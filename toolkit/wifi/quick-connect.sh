#!/bin/sh
# ============================================================
# MZD Toolkit - wifi/quick-connect.sh (v4.8.0, punt 5.1)
# Quick connect to the SSID from settings.conf (default YOUR_HOTSPOT_SSID).
# Non-interactive. PsK via env MZD_PSK (never argv).
# Exit-code contract: 0 = got IP, 4 = connect failed.
# ============================================================

[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null

# settings: primary $SETTINGS_DIR, fallback toolkit/config
for _sc in "${SETTINGS_DIR:-}/settings.conf" "${TOOLKIT_DIR:-}/config/settings.conf"; do
    [ -n "$_sc" ] && [ -f "$_sc" ] && . "$_sc" 2>/dev/null && break
done
# psk from secrets.conf (via env, never argv)
for _sec in "${SETTINGS_DIR:-}/secrets.conf" "${TOOLKIT_DIR:-}/config/secrets.conf"; do
    [ -n "$_sec" ] && [ -f "$_sec" ] && . "$_sec" 2>/dev/null && break
done

SSID="${WIFI_SSID:-${1:-YOUR_HOTSPOT_SSID}}"
PASSWORD="${MZD_PSK:-${WIFI_PASSWORD:-${2:-}}}"

sh "$(dirname "$0")/driver-info.sh" 2>/dev/null
echo "Quick-connect to: $SSID"
# v4.8.1: message where the output is — connect-nms.sh starts its own run-log,
# so this run-log ends here. See $LOG_DIR/runs/v*-connect-nms-* for details.
echo "(output is in run-log: ${LOG_DIR:-/tmp/toolkit-logs}/runs/v*-connect-nms-*)"
MZD_PSK="$PASSWORD" WIFI_SSID="$SSID" \
    sh "${TOOLKIT_DIR:-$(dirname "$0")/..}/wifi/connect-nms.sh" "$SSID"
exit $?
