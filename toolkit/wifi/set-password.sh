#!/bin/sh
# ============================================================
# MZD Toolkit - wifi/set-password.sh (v4.8.3)
# Set WiFi password - saves to $SETTINGS_DIR/secrets.conf
# (mzd-data/config on USB root, 0600, gitignored). NEVER plaintext in
# settings.conf and NEVER as argv. PSK is passed at connect via env
# MZD_PSK.
# ============================================================

[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

echo "========================================"
echo " WiFi Set Password (v4.8.3)"
echo "========================================"
echo ""
echo "Network: ${WIFI_SSID:-YOUR_HOTSPOT_SSID}"
echo ""
echo "Enter the password for ${WIFI_SSID:-YOUR_HOTSPOT_SSID} (will not be shown):"
echo -n "Password: "
if command -v stty >/dev/null 2>&1; then
    stty -echo 2>/dev/null
    read PASSWORD
    stty echo 2>/dev/null
    echo ""
else
    read PASSWORD
fi

PWLEN=$(echo -n "$PASSWORD" | wc -c)
if [ "$PWLEN" -lt 8 ]; then
    echo "ERROR: Password too short! ($PWLEN chars, minimum 8 required)"
    unset PASSWORD
    exit 1
fi
echo "Password length: $PWLEN chars (value itself not logged)"
echo ""

# v4.8.0: psk to secrets.conf in $SETTINGS_DIR (mzd-data/config), NEVER plaintext in settings.conf
SECRETS_DIR="${SETTINGS_DIR:-${DATA_DIR:-}/config}"
[ -z "$SECRETS_DIR" ] && SECRETS_DIR="${TOOLKIT_DIR:-.}/config"
mkdir -p "$SECRETS_DIR" 2>/dev/null
SECRETS="$SECRETS_DIR/secrets.conf"
# keep MZD_SSH_PASSWORD if it existed
_SAVED_SSH=""
[ -f "$SECRETS" ] && _SAVED_SSH=$(grep '^MZD_SSH_PASSWORD=' "$SECRETS" 2>/dev/null)
{
    [ -n "$_SAVED_SSH" ] && echo "$_SAVED_SSH"
    echo "# v4.8.0: wifi psk via env MZD_PSK (never argv) — $(date +%s 2>/dev/null || echo set)"
    echo "MZD_PSK=\"$PASSWORD\""
    echo "WIFI_PASSWORD=\"$PASSWORD\""
} > "$SECRETS.tmp.$$" 2>/dev/null && mv "$SECRETS.tmp.$$" "$SECRETS" 2>/dev/null
chmod 600 "$SECRETS" 2>/dev/null
unset PASSWORD
echo "Saved in: $SECRETS (0600, gitignored)"
echo ""

echo "Password saved!"
echo ""
echo "Connect now? (y/n)"
echo -n "Choice: "
read choice
if [ "$choice" = "y" ] || [ "$choice" = "Y" ] || [ "$choice" = "yes" ] || [ "$choice" = "YES" ] || [ "$choice" = "j" ] || [ "$choice" = "J" ] || [ "$choice" = "ja" ] || [ "$choice" = "JA" ]; then
    echo ""
    sh "${TOOLKIT_DIR:-$(dirname "$0")/..}/wifi/quick-connect.sh"
fi
