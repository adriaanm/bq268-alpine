#!/bin/sh
# esim-provision: Download and activate an eSIM profile on the BQ268
#
# Usage:
#   esim-provision 'LPA:1$smdp.example.com$ACTIVATION-CODE'
#   esim-provision -f /path/to/activation-code.txt
#   esim-provision   (prompts for input)
#
# The activation code format is: LPA:1$smdp-address$matching-id[$confirmation-code]
# This is what you get when scanning an eSIM QR code.
#
# Prerequisites:
#   - WiFi connected (for SM-DP+ communication)
#   - eUICC adapter inserted and detected by modem
#   - lpac and qmi-send-apdu installed
set -e

WRAPPER="qmi-send-apdu lpac"

# --- Parse arguments ---

ACTIVATION_CODE=""
CODE_FILE=""

usage() {
    cat >&2 <<'EOF'
Usage: esim-provision [OPTIONS] [ACTIVATION_CODE]

Download and activate an eSIM profile.

Arguments:
  ACTIVATION_CODE   LPA:1$smdp-address$matching-id (from QR code)

Options:
  -f FILE    Read activation code from file
  -s SLOT    UIM slot number (default: 1)
  -h         Show this help

The activation code format from a QR code is:
  LPA:1$smdp.example.com$ACTIVATION-CODE-HERE

If no code is given, you will be prompted to enter one.
EOF
    exit 1
}

SLOT=1
while [ $# -gt 0 ]; do
    case "$1" in
        -f) CODE_FILE="$2"; shift 2 ;;
        -s) SLOT="$2"; shift 2 ;;
        -h|--help) usage ;;
        -*) echo "Unknown option: $1" >&2; usage ;;
        *)  ACTIVATION_CODE="$1"; shift ;;
    esac
done

export LPAC_QMI_SLOT="$SLOT"

# --- Get activation code ---

if [ -n "$CODE_FILE" ]; then
    if [ ! -f "$CODE_FILE" ]; then
        echo "ERROR: File not found: $CODE_FILE" >&2
        exit 1
    fi
    ACTIVATION_CODE=$(cat "$CODE_FILE" | tr -d '\n\r ')
fi

if [ -z "$ACTIVATION_CODE" ]; then
    printf 'Enter eSIM activation code (LPA:1$...): '
    read -r ACTIVATION_CODE
fi

if [ -z "$ACTIVATION_CODE" ]; then
    echo "ERROR: No activation code provided" >&2
    exit 1
fi

# --- Parse activation code ---

# Format: LPA:1$smdp-address$matching-id[$confirmation-code]
case "$ACTIVATION_CODE" in
    LPA:1\$*)
        # Strip the LPA:1$ prefix
        rest="${ACTIVATION_CODE#LPA:1\$}"
        ;;
    *)
        echo "ERROR: Invalid format. Expected LPA:1\$smdp-address\$matching-id" >&2
        echo "  Got: $ACTIVATION_CODE" >&2
        exit 1
        ;;
esac

# Split on $ delimiter
SMDP=$(printf '%s' "$rest" | cut -d'$' -f1)
MATCHING_ID=$(printf '%s' "$rest" | cut -d'$' -f2)
CONFIRM_CODE=$(printf '%s' "$rest" | cut -d'$' -f3)

if [ -z "$SMDP" ]; then
    echo "ERROR: Could not parse SM-DP+ address from activation code" >&2
    exit 1
fi

echo "=== eSIM Provisioning ==="
echo "SM-DP+ server: $SMDP"
echo "Matching ID:   ${MATCHING_ID:-(none)}"
[ -n "$CONFIRM_CODE" ] && echo "Confirm code:  (provided)"
echo "UIM slot:      $SLOT"
echo ""

# --- Check prerequisites ---

echo "Checking prerequisites..."

# Check WiFi
if ! ip link show wlan0 2>/dev/null | grep -q 'state UP'; then
    echo "WARNING: wlan0 does not appear to be up" >&2
    echo "  eSIM download requires internet connectivity" >&2
    printf 'Continue anyway? [y/N] '
    read -r yn
    case "$yn" in [yY]*) ;; *) exit 1 ;; esac
else
    echo "  WiFi: up"
fi

# Check DNS/connectivity (use TCP connect — SM-DP+ servers often block ICMP)
if ! wget -q --spider -T5 "https://$SMDP" >/dev/null 2>&1; then
    # BusyBox wget may fail on TLS — try a plain DNS lookup as fallback
    if ! nslookup "$SMDP" >/dev/null 2>&1; then
        echo "WARNING: Cannot resolve $SMDP" >&2
        echo "  Check WiFi and DNS configuration" >&2
        printf 'Continue anyway? [y/N] '
        read -r yn
        case "$yn" in [yY]*) ;; *) exit 1 ;; esac
    else
        echo "  Network: $SMDP resolves (HTTPS check skipped)"
    fi
else
    echo "  Network: $SMDP reachable"
fi

# Check eUICC via qmicli
echo "  Checking eUICC (UIM slot $SLOT)..."
if ! qmicli -d msmipc://0 --uim-get-card-status >/dev/null 2>&1; then
    echo "ERROR: Cannot communicate with modem UIM service" >&2
    echo "  Is the modem running? Check: rc-service modem status" >&2
    exit 1
fi
echo "  Modem UIM: accessible"

# Quick card status check
CARD_STATUS=$(qmicli -d msmipc://0 --uim-get-card-status 2>&1)
if echo "$CARD_STATUS" | grep -q "Card state: 'present'"; then
    echo "  Card: present"
else
    echo "WARNING: No card detected in UIM status" >&2
    echo "  The eUICC adapter may not be inserted" >&2
    printf 'Continue anyway? [y/N] '
    read -r yn
    case "$yn" in [yY]*) ;; *) exit 1 ;; esac
fi

echo ""

# --- Check existing profiles ---

echo "Querying eUICC for existing profiles..."
if PROFILES=$($WRAPPER profile list 2>/dev/null); then
    # Check if there are already enabled profiles
    if printf '%s' "$PROFILES" | grep -q '"profileState":"enabled"'; then
        echo "NOTE: There is already an enabled profile on this eUICC" >&2
        echo "  The new profile will be downloaded but may not auto-enable" >&2
    fi
    echo "  Existing profiles:"
    printf '%s' "$PROFILES" | sed -n 's/.*"profileName":"\([^"]*\)".*/    - \1/p'
else
    echo "  (Could not query profiles — eUICC may not be accessible yet)"
fi
echo ""

# --- Download profile ---

echo "Downloading eSIM profile..."
echo "  This may take 30-60 seconds."
echo ""

DL_ARGS="-s $SMDP"
[ -n "$MATCHING_ID" ] && DL_ARGS="$DL_ARGS -m $MATCHING_ID"
[ -n "$CONFIRM_CODE" ] && DL_ARGS="$DL_ARGS -c $CONFIRM_CODE"

# shellcheck disable=SC2086
if ! DL_RESULT=$($WRAPPER profile download $DL_ARGS 2>&1); then
    echo "ERROR: Profile download failed" >&2
    echo "$DL_RESULT" >&2
    exit 1
fi

echo "$DL_RESULT"

# Check result
if printf '%s' "$DL_RESULT" | grep -q '"code":0'; then
    echo ""
    echo "Profile downloaded successfully."
else
    echo ""
    echo "ERROR: Download may have failed. Check output above." >&2
    exit 1
fi

# --- Enable profile ---

echo ""
echo "Listing profiles to find the new one..."
PROFILES=$($WRAPPER profile list 2>/dev/null) || true

# Find disabled profiles (the new one should be disabled)
NEW_ICCID=$(printf '%s' "$PROFILES" | grep -o '"iccid":"[^"]*"' | tail -1 | sed 's/"iccid":"//;s/"//')

if [ -n "$NEW_ICCID" ]; then
    echo "Enabling profile $NEW_ICCID..."
    if $WRAPPER profile enable "$NEW_ICCID" 2>&1; then
        echo "Profile enabled."
    else
        echo "WARNING: Could not auto-enable profile" >&2
        echo "  Try manually: qmi-send-apdu lpac profile enable $NEW_ICCID" >&2
    fi
fi

# --- Process notifications ---

echo ""
echo "Processing pending notifications..."
$WRAPPER notification process 2>&1 || echo "  (notification processing skipped)"

# --- Power cycle UIM to load new profile ---

echo ""
echo "Power cycling UIM to load new profile..."
qmicli -d msmipc://0 --uim-sim-power-off=1 2>/dev/null
sleep 2
qmicli -d msmipc://0 --uim-sim-power-on=1 2>/dev/null
echo "  UIM power cycled."

echo ""
echo "=== Done ==="
echo "eSIM profile provisioned. Restart the modem to register on the network:"
echo "  rc-service modem restart"
