#!/bin/sh
# cell-data: manage cellular data session and modem power state
#
# Data path is PPP over SMD (/dev/smd7). BAM DMUX / rmnet is unused on
# this firmware — see docs/modem_data.md.
#
# Usage:
#   cell-data up      — wake modem, enforce LTE prefs, PS attach, pppd up
#   cell-data down    — stop pppd (modem stays online)
#   cell-data status  — show current state
#   cell-data sleep   — put modem in low-power mode (RF off, ~5-10 mA)
#   cell-data wake    — bring modem online, enforce prefs, wait for PS attach
#   cell-data force   — force both WiFi+cellular on, disable watchdog failover
#   cell-data off     — tear cellular down and pin it down (failover disabled)
#   cell-data auto    — re-enable normal failover (undo force/off)
#
# Forced modes (force = pinned up, off = pinned down) prevent the
# watchdog/wpa_cli hooks from touching cellular. Both ride on
# /run/cell-data.force — tmpfs, so a reboot returns to auto.

set -e

QMI_DEV="msmipc://0"
# Mode preference for ensure_rat_prefs. Default is `lte|umts` (commit
# 7df1869 — UMTS fallback is required while LTE attach on Sunrise is
# still broken). Set `CELL_DATA_RAT=lte` in the environment to force
# LTE-only, used by `just diag-capture-lte` to test the B20 UL TX
# hypothesis: if no UL_CCCH frames appear during a 90s LTE-only wake,
# the modem is reading LTE SIBs but never transmitting a Connection
# Request, which points at an RF / UL path problem.
CELL_DATA_RAT="${CELL_DATA_RAT:-lte|umts}"
PPP_IF="ppp0"
PPP_PEER="cellular"
STATE_FILE="/run/cell-data.state"
FORCE_FILE="/run/cell-data.force"
CELL_LOG="/var/log/cellular.log"
PARTNERS_FILE="/etc/cellular/roaming-partners"
MCFG_DIR="/usr/share/cellular-mcfg"
# MCFG-SW files shipped with the rootfs. First one is the one we
# activate (HPLMN-matched); the rest are loaded inactive as fallbacks.
MCFG_PRIMARY="$MCFG_DIR/singtel_sg.mbn"
MCFG_FALLBACK="$MCFG_DIR/row_generic.mbn"

# Bounded budgets — total wake+attach must fit in ~2 minutes.
WAKE_BUDGET=20          # seconds to get modem out of transient states
ATTACH_BUDGET=45        # seconds per automatic-attach attempt
PARTNER_BUDGET=30       # seconds per manual partner-attach attempt
PPP_BUDGET=30           # seconds for pppd to bring ppp0 up with an IP
RESET_SETTLE=10         # seconds to wait after dms reset before polling

log() {
    logger -t cell-data "$@"
    echo "cell-data: $*"
}

modem_mode() {
    qmicli -p -d "$QMI_DEV" --dms-get-operating-mode 2>&1 | \
        sed -n "s/.*Mode: '\([^']*\)'.*/\1/p"
}

# Load the Singtel carrier MCFG-SW into the modem via PDC and
# activate it. The modem ships with zero MCFG-SW configs from our
# side (verified: --pdc-list-configs=software → 0), which puts the
# NAS into a generic fallback that doesn't complete default-EPS-bearer
# activation for our Eskimo IMSI. With the Singtel MCFG active, EMM
# attach succeeds and stays stable (9s+ of EMM-REGISTERED observed,
# where before we got at most 2s). The MCFG is sourced from the
# original vendor modem firmware (~/bq268-edl/dump/modem.bin) and
# shipped in the rootfs under /usr/share/cellular-mcfg.
#
# Activating an MCFG-SW triggers an internal modem reset (equivalent
# to an NAS restart without a full `dms reset`), so this function
# only does work when the desired config isn't already Active.
# Persists in modem NV (modemst1/2) across reboots.
ensure_mcfg() {
    [ -f "$MCFG_PRIMARY" ] || return 0
    local list
    list=$(qmicli -p -d "$QMI_DEV" --pdc-list-configs=software 2>&1 || true)
    # Already loaded + active? No-op. The `pdc-list-configs` output
    # puts `Status: Active` ~3 lines below the Description, so we need
    # enough context — -A4 is safe. Without this, ensure_mcfg would
    # re-activate every wake, which triggers an internal modem reset
    # and drops whatever registration we had.
    if echo "$list" | grep -A4 "Singtel_Commercial" | grep -q "Status: *Active"; then
        return 0
    fi
    # Not loaded at all? Upload both files.
    if ! echo "$list" | grep -q "Singtel_Commercial"; then
        log "loading MCFG $MCFG_PRIMARY"
        qmicli -p -d "$QMI_DEV" --pdc-load-config="$MCFG_PRIMARY" 2>&1 \
            | tail -2 | logger -t cell-data || true
        [ -f "$MCFG_FALLBACK" ] && \
            qmicli -p -d "$QMI_DEV" --pdc-load-config="$MCFG_FALLBACK" 2>&1 \
                | tail -2 | logger -t cell-data || true
        list=$(qmicli -p -d "$QMI_DEV" --pdc-list-configs=software 2>&1 || true)
    fi
    # Activate Singtel by ID (parse from list).
    local id
    id=$(echo "$list" | awk '
        /Singtel_Commercial/ {found=1}
        found && /ID:/ {print $2; exit}
    ')
    [ -z "$id" ] && return 0
    log "activating Singtel MCFG"
    qmicli -p -d "$QMI_DEV" --pdc-activate-config="software,$id" 2>&1 \
        | tail -2 | logger -t cell-data || true
    # Activation triggers modem internal reset; let set_online handle
    # the transient shutting-down state.
    return 0
}

# LTE preferred with UMTS fallback, automatic network selection. Idempotent.
#
# History: we previously enforced `lte,automatic` (LTE-only) to avoid
# latching onto a weak cross-border UMTS Orange France cell in CH. But
# 2026-04-13 DIAG captures showed that in LTE-only mode the modem reads
# SIBs from multiple Swiss LTE cells yet never transmits an ATTACH
# REQUEST — zero EMM_OTA_OUT in 60 s of searching. With `lte|umts` the
# modem attaches cleanly to Orange F (208/01) within 40 s. UMTS coverage
# is strong enough at the bench that the occasional cross-border camp is
# a tolerable tradeoff against never attaching at all. If/when we
# resolve the underlying LTE attach block (likely MCFG or TAI-reject at
# the HSS), we can tighten this back to lte-only.
ensure_rat_prefs() {
    local prefs
    prefs=$(qmicli -p -d "$QMI_DEV" --nas-get-system-selection-preference 2>&1 || true)
    # Modem reports mode preference with an unspecified ordering
    # ('umts, lte' or 'lte, umts'); match either.
    local mode_re
    case "$CELL_DATA_RAT" in
        lte) mode_re="Mode preference: 'lte'" ;;
        umts) mode_re="Mode preference: 'umts'" ;;
        *) mode_re="Mode preference: '(lte, umts|umts, lte)'" ;;
    esac
    if echo "$prefs" | grep -Eq "$mode_re" && \
       echo "$prefs" | grep -q "Network selection preference: 'automatic'" && \
       echo "$prefs" | grep -q "Usage preference: 'data-centric'"; then
        return 0
    fi
    # usage=data-centric: BQ268 is a data-only device. Voice-centric (the
    # Qualcomm default) makes NAS refuse to camp on LTE cells whose CS
    # domain can't be negotiated, which kills attach on MVNO roaming in
    # markets where 2G/3G is decommissioned. Requires the qmicli usage-pref
    # extension (libqmi commit d8995d3).
    log "enforcing ${CELL_DATA_RAT}, automatic network selection, data-centric"
    qmicli -p -d "$QMI_DEV" --nas-set-system-selection-preference="${CELL_DATA_RAT},automatic,usage=data-centric" 2>&1 \
        | logger -t cell-data || true
    return 1
}

# Profile 1 is the LTE-attach PDN (wds-get-lte-attach-pdn-list = [1]).
# With the Singtel_Commercial MCFG-SW active, the modem maintains
# profile 1 at APN='E-IDEAS' pdp-type=ipv4-or-ipv6 — this is the
# Singtel default initial-attach APN that the HSS expects in the
# first PDN-CONNECTIVITY-REQUEST. We do NOT override it.
#
# The 'hicard' APN used by Eskimo Android is an overlay APN applied
# after attach for the actual data session (pppd CGACT sets it). We
# keep that in profile 2 so it's available for CGACT without
# touching the attach profile.
ensure_wds_profile() {
    local list apn2 pdp2
    list=$(qmicli -p -d "$QMI_DEV" --wds-get-profile-list=3gpp 2>&1 || true)
    apn2=$(echo "$list" | sed -n "/\[2\] 3gpp/,/\[3\] 3gpp/ {s/.*APN: '\([^']*\)'.*/\1/p;}" | head -1)
    pdp2=$(echo "$list" | sed -n "/\[2\] 3gpp/,/\[3\] 3gpp/ {s/.*PDP type: '\([^']*\)'.*/\1/p;}" | head -1)
    if [ "$apn2" = "hicard" ] && [ "$pdp2" = "ipv4-or-ipv6" ]; then
        return 0
    fi
    log "rewriting WDS profile 2: apn=hicard, pdp=ipv4v6 (was apn='$apn2' pdp='$pdp2')"
    qmicli -p -d "$QMI_DEV" --wds-modify-profile="3gpp,2,apn=hicard,pdp-type=IPV4V6" 2>&1 \
        | logger -t cell-data || true
    return 0
}

# User-controlled preferred PLMN list. Eskimo's eSIM ships with
# EF_OPLMNwAcT containing only the HPLMN (525/01 Singtel) — zero
# roaming partners — so automatic selection has no steering and can
# latch onto cross-border RATs that happen to be louder (e.g. UMTS
# Orange-FR from inside CH). We populate the modem's user-controlled
# list from /etc/cellular/roaming-partners so automatic selection
# prefers approved roaming networks.
#
# The modem caps the user-controlled list at ~23 entries (SIM
# EF_PLMNwAcT allocation) and silently drops any beyond that. We
# therefore can't write all 154 partners — we prioritize by
# PRIORITY_MCCS (Swiss + immediate neighbours) and fill the rest of
# the 20-slot budget from the full file in file order. Persists in
# modem NV.
PRIORITY_MCCS="228 208 262 222 232 214 268 272 206 234"
PREFERRED_LIMIT=20
ensure_preferred_networks() {
    local have count
    have=$(qmicli -p -d "$QMI_DEV" --nas-get-preferred-networks 2>&1 || true)
    count=$(echo "$have" | sed -n '/Preferred PLMN list/,/PCS digit status/p' \
        | grep -c "Access Technology: 'eutran'")
    # Sanity check: the target list always contains 228/02 Sunrise
    # (top of PRIORITY_MCCS). If it's already there with roughly the
    # right number of entries, this is a no-op.
    if [ "$count" -ge "$PREFERRED_LIMIT" ] && \
       echo "$have" | sed -n '/Preferred PLMN list/,/PCS digit status/p' \
         | grep -B1 "Access Technology: 'eutran'" | grep -B1 "MCC: '228'" \
         | grep -q "MNC: '2'"; then
        return 0
    fi
    if [ ! -f "$PARTNERS_FILE" ]; then
        return 0
    fi
    local args="" n=0 mcc mnc
    # Pass 1: priority MCCs in PRIORITY_MCCS order.
    local pmcc
    for pmcc in $PRIORITY_MCCS; do
        while IFS= read -r line; do
            case "$line" in ''|'#'*) continue ;; esac
            set -- $line
            [ "$1" = "$pmcc" ] || continue
            [ -z "$2" ] && continue
            args="$args,$1$2,eutran"
            n=$((n + 1))
            [ $n -ge "$PREFERRED_LIMIT" ] && break
        done < "$PARTNERS_FILE"
        [ $n -ge "$PREFERRED_LIMIT" ] && break
    done
    # Pass 2: fill remainder from file order, skipping priority MCCs.
    if [ $n -lt "$PREFERRED_LIMIT" ]; then
        while IFS= read -r line; do
            case "$line" in ''|'#'*) continue ;; esac
            set -- $line
            [ -z "$1" ] || [ -z "$2" ] && continue
            case " $PRIORITY_MCCS " in *" $1 "*) continue ;; esac
            args="$args,$1$2,eutran"
            n=$((n + 1))
            [ $n -ge "$PREFERRED_LIMIT" ] && break
        done < "$PARTNERS_FILE"
    fi
    args="${args#,}"
    [ -z "$args" ] && return 0
    log "writing preferred-networks ($n entries, priority first)"
    qmicli -p -d "$QMI_DEV" --nas-set-preferred-networks="$args" 2>&1 \
        | logger -t cell-data || true
    return 0
}

# Drive the modem into 'online' from whatever state it's in. Handles:
#   online                 → no-op
#   low-power / offline    → set online
#   shutting-down          → wait (boot transient)
#   persistent-low-power   → set online
#   anything else / stuck  → reset + settle
# Bounded by WAKE_BUDGET. Returns 1 if we can't reach online.
set_online() {
    local start now mode tried_reset=0
    start=$(date +%s)
    while :; do
        mode=$(modem_mode)
        case "$mode" in
            online)
                return 0 ;;
            low-power|persistent-low-power|offline)
                log "modem $mode → online"
                qmicli -p -d "$QMI_DEV" --dms-set-operating-mode=online 2>&1 \
                    | logger -t cell-data || true
                ;;
            shutting-down|resetting)
                : ;;  # transient — just wait
            "")
                log "modem not responding"
                ;;
            *)
                log "modem in unexpected mode '$mode'"
                ;;
        esac
        sleep 2
        now=$(date +%s)
        if [ $((now - start)) -ge "$WAKE_BUDGET" ]; then
            if [ "$tried_reset" -eq 0 ]; then
                log "wake budget (${WAKE_BUDGET}s) exhausted in mode '$mode', escalating to reset"
                qmicli -p -d "$QMI_DEV" --dms-set-operating-mode=reset 2>&1 \
                    | logger -t cell-data || true
                sleep "$RESET_SETTLE"
                tried_reset=1
                start=$(date +%s)
                continue
            fi
            log "error: modem stuck in '$mode' after reset attempt"
            return 1
        fi
    done
}

wait_ps_attached() {
    local budget="${1:-$ATTACH_BUDGET}" elapsed=0 s
    while [ $elapsed -lt "$budget" ]; do
        s=$(qmicli -p -d "$QMI_DEV" --nas-get-serving-system 2>&1 || true)
        if echo "$s" | grep -q "PS: 'attached'"; then
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    return 1
}

# Log serving PLMN + roaming status to /var/log/cellular.log and syslog.
# Pulled after a successful attach so data-byte correlation is possible.
log_serving() {
    local s mcc mnc rat roaming h hmcc hmnc
    s=$(qmicli -p -d "$QMI_DEV" --nas-get-serving-system 2>&1 || true)
    mcc=$(echo "$s" | awk -F"'" '/MCC:/ {print $2; exit}')
    mnc=$(echo "$s" | awk -F"'" '/MNC:/ {print $2; exit}')
    rat=$(echo "$s" | awk -F"'" '/Radio interfaces/{getline; print $2; exit}')
    roaming=$(echo "$s" | awk -F"'" '/Roaming status:/ {print $2; exit}')
    h=$(qmicli -p -d "$QMI_DEV" --nas-get-home-network 2>&1 || true)
    hmcc=$(echo "$h" | awk -F"'" '/MCC:/ {print $2; exit}')
    hmnc=$(echo "$h" | awk -F"'" '/MNC:/ {print $2; exit}')

    local roaming_bool=false
    if [ "$mcc" != "$hmcc" ] || [ "$mnc" != "$hmnc" ]; then
        roaming_bool=true
    fi

    log "serving plmn=$mcc/$mnc rat=$rat roaming=$roaming_bool (home=$hmcc/$hmnc)"
    mkdir -p "$(dirname "$CELL_LOG")"
    printf '%s plmn=%s/%s rat=%s roaming=%s home=%s/%s qmi_roaming=%s\n' \
        "$(date -Iseconds)" "$mcc" "$mnc" "$rat" "$roaming_bool" \
        "$hmcc" "$hmnc" "$roaming" >> "$CELL_LOG"
}

# Look up MCC/MNC in the approved partners file. Prints the priority
# (lower = preferred) on match, nothing on miss. Comments and blank
# lines are skipped. MNC is compared after stripping leading zeros on
# both sides so "02" matches "2".
partner_priority() {
    local want_mcc="$1" want_mnc="$2" mcc mnc prio rest
    [ -f "$PARTNERS_FILE" ] || return 1
    # Normalise the lookup key
    want_mnc=$(printf '%d' "$want_mnc" 2>/dev/null || echo "$want_mnc")
    while read -r mcc mnc rest; do
        case "$mcc" in ''|\#*) continue ;; esac
        mnc=$(printf '%d' "$mnc" 2>/dev/null || echo "$mnc")
        if [ "$mcc" = "$want_mcc" ] && [ "$mnc" = "$want_mnc" ]; then
            # rest = "COUNTRY OPERATOR PRIORITY" — priority is the last field
            prio=$(echo "$rest" | awk '{print $NF}')
            case "$prio" in ''|*[!0-9]*) prio=100 ;; esac
            echo "$prio"
            return 0
        fi
    done < "$PARTNERS_FILE"
    return 1
}

# Scan LTE, emit "MCC MNC PRIORITY" for each visible network that is in
# the approved partners file, sorted by priority ascending.
#
# qmicli's scan output contains each network 3 times: in the
# availability block, the RAT block, and the PCS block. We dedupe by
# extracting unique MCC/MNC pairs with awk.
approved_lte_candidates() {
    local scan mcc mnc prio
    scan=$(qmicli -p -d "$QMI_DEV" --nas-network-scan=lte 2>&1 || true)
    echo "$scan" | awk '
        /MCC:/ { match($0, /'"'"'[^'"'"']+'"'"'/); mcc=substr($0, RSTART+1, RLENGTH-2); next }
        /MNC:/ {
            match($0, /'"'"'[^'"'"']+'"'"'/); mnc=substr($0, RSTART+1, RLENGTH-2)
            if (mcc != "") {
                key=mcc"-"mnc
                if (!(key in seen)) { seen[key]=1; print mcc, mnc }
                mcc=""
            }
        }
    ' | while read -r mcc mnc; do
        prio=$(partner_priority "$mcc" "$mnc") || continue
        printf '%s\t%s\t%s\n' "$prio" "$mcc" "$mnc"
    done | sort -n | while read -r prio mcc mnc; do
        printf '%s %s %s\n' "$mcc" "$mnc" "$prio"
    done
}

try_partner_attach() {
    local mcc="$1" mnc="$2" mnc_padded target elapsed=0
    # qmicli's --nas-set-system-selection-preference=manual=MCCMNC
    # expects MNC zero-padded to at least 2 digits (EU networks) or
    # 3 (US). printf '%02d' pads shorter values and leaves longer
    # ones unchanged.
    mnc_padded=$(printf '%02d' "$mnc")
    target="${mcc}${mnc_padded}"
    log "trying manual attach to $mcc/$mnc_padded (${target})"
    qmicli -p -d "$QMI_DEV" --nas-set-system-selection-preference="lte|umts,manual=${target}" 2>&1 \
        | logger -t cell-data || true
    while [ $elapsed -lt "$PARTNER_BUDGET" ]; do
        if qmicli -p -d "$QMI_DEV" --nas-get-serving-system 2>&1 | grep -q "PS: 'attached'"; then
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    return 1
}

do_wake() {
    # All three ensure_* are persistent in modem NV and normally no-ops.
    # If any changed state, set_online + reset escalation below picks
    # up the new config.
    ensure_mcfg || true
    ensure_rat_prefs || true
    ensure_wds_profile || true
    ensure_preferred_networks || true

    set_online || return 1

    # Phase 1: automatic attach (fast path when the modem picks a
    # partner on its own — typical for home network and for visits
    # where the strongest signal belongs to an approved partner).
    if wait_ps_attached "$ATTACH_BUDGET"; then
        log_serving
        return 0
    fi

    # Phase 2: scan visible LTE networks and try approved partners in
    # priority order. Prevents accidental attach to non-partner
    # networks (which either refuse registration outright or attach
    # with "WCDMA limited" and block PS traffic).
    log "automatic attach failed after ${ATTACH_BUDGET}s, scanning for approved partners"
    local candidates
    candidates=$(approved_lte_candidates)
    if [ -z "$candidates" ]; then
        log "no approved partners visible on LTE scan"
        return 2
    fi
    log "approved partners visible:"
    printf '%s\n' "$candidates" | while read -r mcc mnc prio; do
        log "  $mcc/$mnc (priority $prio)"
    done

    # Try each in priority order. IFS-split the newline-separated
    # candidate list so this loop runs in the current shell and
    # `return` works from the function scope.
    local OLDIFS="$IFS"
    IFS='
'
    set -f  # disable glob expansion on positional params
    for line in $candidates; do
        set +f
        IFS="$OLDIFS"
        # shellcheck disable=SC2086
        set -- $line
        if try_partner_attach "$1" "$2"; then
            log_serving
            return 0
        fi
        IFS='
'
        set -f
    done
    set +f
    IFS="$OLDIFS"

    log "warning: PS not attached after automatic + partner fallback"
    return 2
}

do_sleep() {
    if [ -f "$STATE_FILE" ]; then
        log "data session active, not sleeping (call 'down' first)"
        return 1
    fi
    local mode
    mode=$(modem_mode)
    if [ "$mode" = "low-power" ] || [ "$mode" = "persistent-low-power" ]; then
        log "modem already in $mode"
        return 0
    fi
    log "putting modem to low-power mode..."
    qmicli -p -d "$QMI_DEV" --dms-set-operating-mode=low-power 2>&1 | logger -t cell-data
    log "modem sleeping (RF off)"
}

ppp_pid() {
    pgrep -f "pppd call $PPP_PEER" 2>/dev/null | head -1
}

do_up() {
    if [ -f "$STATE_FILE" ] && [ -n "$(ppp_pid)" ]; then
        log "already up (pppd pid $(ppp_pid))"
        return 0
    fi
    # Stale state from crashed prior run — clear it.
    rm -f "$STATE_FILE"

    do_wake || {
        log "error: do_wake failed, aborting up"
        return 1
    }

    log "starting pppd call $PPP_PEER..."
    /usr/sbin/pppd call "$PPP_PEER" 2>&1 | logger -t cell-data &

    # Wait for ppp0 to exist with an IP
    local elapsed=0
    while [ $elapsed -lt "$PPP_BUDGET" ]; do
        if ip -4 addr show "$PPP_IF" 2>/dev/null | grep -q 'inet '; then
            echo "up" > "$STATE_FILE"
            local ip
            ip=$(ip -4 addr show "$PPP_IF" | awk '/inet /{print $2; exit}')
            log "data path up on $PPP_IF ($ip)"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    log "error: $PPP_IF did not come up within ${PPP_BUDGET}s"
    # Kill whatever pppd we started so we don't leak it
    local p; p=$(ppp_pid)
    [ -n "$p" ] && kill "$p" 2>/dev/null || true
    return 1
}

do_down() {
    if [ -f "$FORCE_FILE" ]; then
        log "force mode active, ignoring down (use 'cell-data auto' to disable)"
        return 0
    fi

    local p; p=$(ppp_pid)
    if [ -z "$p" ] && [ ! -f "$STATE_FILE" ]; then
        log "already down"
        return 0
    fi

    log "tearing down pppd..."
    if [ -n "$p" ]; then
        kill "$p" 2>/dev/null || true
        local w=0
        while [ $w -lt 10 ] && kill -0 "$p" 2>/dev/null; do
            sleep 1; w=$((w+1))
        done
        kill -9 "$p" 2>/dev/null || true
    fi
    rm -f "$STATE_FILE"
    log "data path down"
}

do_force() {
    touch "$FORCE_FILE"
    log "force mode ON — both interfaces stay up, failover disabled"
    if [ ! -f "$STATE_FILE" ]; then
        do_up
    fi
}

do_off() {
    # do_down refuses while the force file exists, so tear down first
    rm -f "$FORCE_FILE"
    do_down
    touch "$FORCE_FILE"
    log "off mode ON — cellular pinned down, failover disabled"
}

do_auto() {
    rm -f "$FORCE_FILE"
    log "force mode OFF — normal failover resumed"
}

do_status() {
    echo "=== cell-data status ==="
    if [ -f "$FORCE_FILE" ]; then
        echo "  mode: FORCED (watchdog failover disabled)"
    else
        echo "  mode: auto (WiFi primary, cellular failover)"
    fi

    local p; p=$(ppp_pid)
    if [ -n "$p" ]; then
        echo "  data: up (pppd pid $p)"
        ip -4 addr show "$PPP_IF" 2>/dev/null | grep -w inet | sed 's/^/  /'
        ip route show dev "$PPP_IF" 2>/dev/null | sed 's/^/  route: /'
    else
        echo "  data: down"
    fi

    echo "  modem: $(modem_mode)"
    qmicli -p -d "$QMI_DEV" --nas-get-system-selection-preference 2>&1 | \
        grep -E "Mode preference|Network selection|Acquisition order" | sed 's/^[[:space:]]*/  /'
    qmicli -p -d "$QMI_DEV" --nas-get-serving-system 2>&1 | \
        grep -E "Registration|CS:|PS:|Roaming status|PLMN" | sed 's/^[[:space:]]*/  /'
}

case "${1:-status}" in
    up)     do_up ;;
    down)   do_down ;;
    sleep)  do_sleep ;;
    wake)   do_wake ;;
    force)  do_force ;;
    off)    do_off ;;
    auto)   do_auto ;;
    status) do_status ;;
    *)      echo "Usage: cell-data {up|down|sleep|wake|force|off|auto|status}" >&2; exit 1 ;;
esac
