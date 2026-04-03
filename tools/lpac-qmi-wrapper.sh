#!/bin/sh
# lpac-qmi-wrapper: APDU backend for lpac using qmi-send-apdu daemon
#
# Launches a persistent qmi-send-apdu process (which maintains a single
# QMI UIM session over AF_MSM_IPC), then runs lpac with the stdio APDU
# driver and translates between lpac's JSON protocol and the daemon's
# line-based protocol.
#
# The daemon automatically truncates ISD-R AIDs to bypass the modem's
# 7-byte AID filter (see docs/esim_provision.md).
#
# Usage: lpac-qmi-wrapper [lpac args...]
# Environment:
#   DEBUG - set to 1 for verbose logging to stderr

# Work around c-ares DNS resolver timeout on musl/Alpine: c-ares doesn't
# reliably read /etc/resolv.conf, so extract nameservers and pass them
# explicitly via the CURL_DNS_SERVERS environment variable.
if [ -z "$CURL_DNS_SERVERS" ] && [ -f /etc/resolv.conf ]; then
    _dns=$(sed -n 's/^nameserver[[:space:]]*//p' /etc/resolv.conf | tr '\n' ',' | sed 's/,$//')
    [ -n "$_dns" ] && export CURL_DNS_SERVERS="$_dns"
fi

DEBUG="${DEBUG:-0}"

TMPDIR="${TMPDIR:-/tmp}"
FIFO_IN="$TMPDIR/lpac-in.$$"
DAEMON_IN="$TMPDIR/daemon-in.$$"
DAEMON_OUT="$TMPDIR/daemon-out.$$"
CHANNEL_ID=""
LPAC_PID=""
SENTINEL_PID=""
DAEMON_PID=""

cleanup() {
    [ -n "$LPAC_PID" ] && kill "$LPAC_PID" 2>/dev/null || true
    [ -n "$SENTINEL_PID" ] && kill "$SENTINEL_PID" 2>/dev/null || true
    [ -n "$DAEMON_PID" ] && kill "$DAEMON_PID" 2>/dev/null || true
    rm -f "$FIFO_IN" "$DAEMON_IN" "$DAEMON_OUT"
}
trap cleanup EXIT INT TERM

debug() {
    [ "$DEBUG" = "1" ] && printf 'WRAP: %s\n' "$*" >&2 || true
}

info() {
    printf '%s\n' "$*" >&2
}

# Extract a JSON string value by key (simple sed, no jq needed)
jval() {
    sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

# --- Daemon communication ---

# Send command to daemon and read response
daemon_cmd() {
    debug "DAEMON << $1"
    printf '%s\n' "$1" >&4
    IFS= read -r resp <&5
    debug "DAEMON >> $resp"
    printf '%s' "$resp"
}

open_channel() {
    local resp
    resp=$(daemon_cmd "OPEN $1")
    case "$resp" in
        OK\ *)
            # "OK channel_id [FCI_hex]"
            printf '%s' "$resp" | cut -d' ' -f2
            ;;
        *)
            info "open_channel error: $resp"
            return 1
            ;;
    esac
}

send_apdu() {
    local resp
    resp=$(daemon_cmd "APDU $CHANNEL_ID $1")
    case "$resp" in
        OK\ *)
            # "OK response_hex"
            printf '%s' "$resp" | cut -d' ' -f2-
            ;;
        *)
            info "send_apdu error: $resp"
            return 1
            ;;
    esac
}

close_channel() {
    daemon_cmd "CLOSE $1" >/dev/null
}

# --- Main ---

export LPAC_APDU=stdio
export LPAC_HTTP=curl

# Start the qmi-send-apdu daemon
mkfifo "$DAEMON_IN" "$DAEMON_OUT" "$FIFO_IN"

qmi-send-apdu daemon < "$DAEMON_IN" > "$DAEMON_OUT" &
DAEMON_PID=$!

# Open daemon FIFOs as fd 4 (write) and fd 5 (read)
exec 4>"$DAEMON_IN"
exec 5<"$DAEMON_OUT"

# Keep the lpac FIFO write-end open with a sleeping sentinel process.
sleep 86400 > "$FIFO_IN" &
SENTINEL_PID=$!

# Launch lpac: stdin from FIFO, stdout piped to our while-loop
lpac "$@" < "$FIFO_IN" 2>/dev/null | {
    # Open write end of FIFO as fd 3
    exec 3>"$FIFO_IN"

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        debug "<<< $line"

        req_type=$(printf '%s' "$line" | jval type)

        case "$req_type" in
            lpa)
                # Final result — pass through to our stdout
                printf '%s\n' "$line"
                ;;
            progress)
                printf '%s\n' "$line" >&2
                ;;
            apdu)
                func=$(printf '%s' "$line" | jval func)
                param=$(printf '%s' "$line" | jval param)

                case "$func" in
                    connect)
                        info "eUICC: connect"
                        printf '{"type":"apdu","payload":{"ecode":0}}\n' >&3
                        ;;
                    disconnect)
                        info "eUICC: disconnect"
                        printf '{"type":"apdu","payload":{"ecode":0}}\n' >&3
                        ;;
                    logic_channel_open)
                        info "eUICC: open channel AID=$param"
                        if cid=$(open_channel "$param"); then
                            CHANNEL_ID="$cid"
                            info "eUICC: channel $cid opened"
                            printf '{"type":"apdu","payload":{"ecode":%s}}\n' "$cid" >&3
                        else
                            printf '{"type":"apdu","payload":{"ecode":-1}}\n' >&3
                        fi
                        ;;
                    logic_channel_close)
                        info "eUICC: close channel $param"
                        close_channel "$param"
                        printf '{"type":"apdu","payload":{"ecode":0}}\n' >&3
                        ;;
                    transmit)
                        debug "TX: $param"
                        if data=$(send_apdu "$param"); then
                            debug "RX: $data"
                            printf '{"type":"apdu","payload":{"ecode":0,"data":"%s"}}\n' "$data" >&3
                        else
                            printf '{"type":"apdu","payload":{"ecode":-1}}\n' >&3
                        fi
                        ;;
                    *)
                        info "Unknown APDU func: $func"
                        printf '{"type":"apdu","payload":{"ecode":-1}}\n' >&3
                        ;;
                esac
                ;;
            *)
                printf '%s\n' "$line"
                ;;
        esac
    done

    exec 3>&-
}

RC=$?
# Clean up
exec 4>&- 5<&-
kill "$SENTINEL_PID" 2>/dev/null || true
kill "$DAEMON_PID" 2>/dev/null || true
SENTINEL_PID=""
DAEMON_PID=""
exit $RC
