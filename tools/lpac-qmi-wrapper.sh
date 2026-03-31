#!/bin/sh
# lpac-qmi-wrapper: APDU backend for lpac using qmicli over msmipc://
#
# Launches lpac with the stdio APDU driver, reads JSON requests from lpac's
# stdout, translates them into qmicli UIM commands, and writes JSON responses
# back to lpac's stdin via a named pipe.
#
# Usage: lpac-qmi-wrapper [lpac args...]
# Environment:
#   LPAC_QMI_DEVICE  - QMI device (default: msmipc://0)
#   LPAC_QMI_SLOT    - UIM slot number (default: 1)
#   DEBUG            - set to 1 for verbose logging to stderr

QMI_DEVICE="${LPAC_QMI_DEVICE:-msmipc://0}"
SLOT="${LPAC_QMI_SLOT:-1}"
DEBUG="${DEBUG:-0}"

TMPDIR="${TMPDIR:-/tmp}"
FIFO_IN="$TMPDIR/lpac-in.$$"
CHANNEL_ID=""
LPAC_PID=""
SENTINEL_PID=""

cleanup() {
    [ -n "$LPAC_PID" ] && kill "$LPAC_PID" 2>/dev/null || true
    [ -n "$SENTINEL_PID" ] && kill "$SENTINEL_PID" 2>/dev/null || true
    rm -f "$FIFO_IN"
}
trap cleanup EXIT INT TERM

debug() {
    [ "$DEBUG" = "1" ] && printf 'WRAP: %s\n' "$*" >&2 || true
}

info() {
    printf '%s\n' "$*" >&2
}

# --- QMI helpers ---

send_apdu() {
    local out
    out=$(qmicli -d "$QMI_DEVICE" "--uim-send-apdu=$SLOT,$CHANNEL_ID,$1" 2>&1) || {
        info "qmicli send-apdu error: $out"
        return 1
    }
    printf '%s' "$out" | sed 's/.*completed: //' | tr -d ':' | tr -d '\n'
}

open_channel() {
    local out
    out=$(qmicli -d "$QMI_DEVICE" "--uim-open-logical-channel=$SLOT,$1" 2>&1) || {
        info "qmicli open-channel error: $out"
        return 1
    }
    printf '%s' "$out" | sed 's/.*completed: //' | tr -d ' \n'
}

close_channel() {
    qmicli -d "$QMI_DEVICE" "--uim-close-logical-channel=$SLOT,$1" >/dev/null 2>&1 || true
}

# Extract a JSON string value by key (simple sed, no jq needed)
jval() {
    sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

# --- Main ---

export LPAC_APDU=stdio
export LPAC_HTTP=curl

mkfifo "$FIFO_IN"

# Keep the FIFO write-end open with a sleeping sentinel process.
# This prevents lpac from seeing EOF if the main loop hasn't opened fd 3 yet,
# and critically, it unblocks lpac's open() on the FIFO read-end.
sleep 86400 > "$FIFO_IN" &
SENTINEL_PID=$!

# Launch lpac: stdin from FIFO, stdout piped to our while-loop
lpac "$@" < "$FIFO_IN" 2>/dev/null | {
    # Open write end of FIFO as fd 3 (sentinel already keeps it open)
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
                        info "eUICC: connect (slot $SLOT via $QMI_DEVICE)"
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
# Clean up sentinel
kill "$SENTINEL_PID" 2>/dev/null || true
SENTINEL_PID=""
exit $RC
