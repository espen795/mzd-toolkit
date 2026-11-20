#!/bin/sh
# ============================================================
# MZD Toolkit - WiFi Compatibility Layer (lib/wifi-compat.sh)
# v4.7.2 M1 + M1b (gate a1b9ce9)
#
# WHY: on the MZD (kernel 3.0.35, busybox) iwconfig, iwlist do NOT exist
# ("not found" proven in logs/from-mzd/
# wifi-debug-19700101-000557.txt section 2 and dump 11-wifi-debug.txt).
# wpa_cli works ONLY with explicit "-i wlan0".
#
# Chain (all proven in MZD logs):
#   wifi_status():  wpa_cli -i wlan0 status
#                 -> /sys/class/net/wlan0/operstate + statistics/*
#                 -> ifconfig wlan0
#                 -> /proc/net/wireless
#   wifi_scan():    wpa_cli -i wlan0 scan (behind run_with_timeout)
#                 -> sleep -> wpa_cli -i wlan0 scan_results
#   wifi_deadlock_check(): dmesg grep for wl12xx deadlock signature
#                 -> detection + recovery hint ONLY, NEVER auto-recovery
#                    (brick-risk)
#
# Do NOT source this directly if you already loaded common.sh:
# common.sh sources this file automatically (1 line, see common.sh).
# Standalone: . lib/wifi-compat.sh
#
# Works on: Mazda CMU v59/v74, BusyBox sh, kernel 3.0.35 (POSIX only)
# ============================================================

WIFI_COMPAT_LOADED=1

# ============================================================
# wpactrl <wpa_cli args…> - v4.7.5 M2 (gate 0046b92)
# MZD: wpa_cli -i wlan0 fails ("Failed to connect to non-global
# ctrl_ifname: wlan0") because the ctrl socket is per-interface.
# We detect the socket path at runtime (NOT hardcoded - the exact
# path of the NMS supplicant is not proven in logs):
#   /var/run/wpa_supplicant-wlan0/wlan0  (per-interface dir)
#   /var/run/wpa_supplicant/wlan0       (global dir)
#   /var/run/wpa_supplicant-wlan0        (global socket in dir)
# Fallback: -i wlan0 (works as own supplicant with /tmp/wpa.conf)
# ============================================================
wpactrl() {
    _if="${WLAN_IFACE:-wlan0}"
    _d=""
    for _c in "/var/run/wpa_supplicant-$_if" /var/run/wpa_supplicant; do
        [ -S "$_c/$_if" ] && _d="$_c" && break
        [ -S "$_c" ] && _d="$_c" && break
    done
    if [ -n "$_d" ]; then
        wpa_cli -p "$_d" -i "$_if" "$@"
    else
        wpa_cli -i "$_if" "$@"
    fi
}

# ------------------------------------------------------------
# Env overrides (for off-auto unit tests with fixtures)
# ------------------------------------------------------------
WLAN_IFACE="${WLAN_IFACE:-wlan0}"
SYS_CLASS_NET="${SYS_CLASS_NET:-/sys/class/net}"
PROC_NET_WIRELESS="${PROC_NET_WIRELESS:-/proc/net/wireless}"
DMESG_CMD="${DMESG_CMD:-dmesg}"

# run_with_timeout comes from lib/common.sh; if this file is
# loaded standalone (without common.sh), define a local fallback
# so wifi_scan() NEVER lets the scan run unbounded.
if ! command -v run_with_timeout > /dev/null 2>&1; then
    run_with_timeout() {
        _cmd="$1"
        _secs="${2:-30}"
        if command -v timeout > /dev/null 2>&1; then
            timeout "$_secs" sh -c "$_cmd"
            return $?
        fi
        sh -c "$_cmd" &
        _pid=$!
        ( sleep "$_secs"; kill "$_pid" 2>/dev/null ) &
        _wd=$!
        wait "$_pid" 2>/dev/null
        _rc=$?
        kill "$_wd" 2>/dev/null
        wait "$_wd" 2>/dev/null
        [ "$_rc" -eq 143 ] && return 124
        return "$_rc"
    }
fi

# ============================================================
# wifi_status [iface] - print link/wpa/IP status.
#   Exit code: 0 = connected (wpa_state=COMPLETED)
#              1 = not connected / wpa_cli unavailable
# ============================================================
wifi_status() {
    _if="${1:-$WLAN_IFACE}"

    echo "=== wpactrl status ==="
    if command -v wpa_cli > /dev/null 2>&1; then
        wpactrl status 2>&1
    else
        echo "wpa_cli not available on this system"
    fi
    echo ""

    echo "=== /sys/class/net/$_if ==="
    echo "operstate:  $(cat "$SYS_CLASS_NET/$_if/operstate" 2>/dev/null || echo unknown)"
    echo "carrier:    $(cat "$SYS_CLASS_NET/$_if/carrier" 2>/dev/null || echo unknown)"
    echo "address:    $(cat "$SYS_CLASS_NET/$_if/address" 2>/dev/null || echo unknown)"
    echo "rx_packets: $(cat "$SYS_CLASS_NET/$_if/statistics/rx_packets" 2>/dev/null || echo '?')"
    echo "tx_packets: $(cat "$SYS_CLASS_NET/$_if/statistics/tx_packets" 2>/dev/null || echo '?')"
    echo "rx_bytes:   $(cat "$SYS_CLASS_NET/$_if/statistics/rx_bytes" 2>/dev/null || echo '?')"
    echo "tx_bytes:   $(cat "$SYS_CLASS_NET/$_if/statistics/tx_bytes" 2>/dev/null || echo '?')"
    echo ""

    echo "=== ifconfig $_if ==="
    ifconfig "$_if" 2>&1 || echo "$_if not found"
    echo ""

    echo "=== $PROC_NET_WIRELESS ==="
    if [ -f "$PROC_NET_WIRELESS" ]; then
        # always show header; interface line if present
        head -2 "$PROC_NET_WIRELESS" 2>/dev/null
        grep "$_if:" "$PROC_NET_WIRELESS" 2>/dev/null || echo "(no $_if line - not associated)"
    else
        echo "$PROC_NET_WIRELESS not readable"
    fi

    # Exit code: 0 only if wpa_state=COMPLETED
    if command -v wpa_cli > /dev/null 2>&1; then
        _st=$(wpactrl status 2>/dev/null | grep "^wpa_state=" | cut -d= -f2)
        if [ "$_st" = "COMPLETED" ]; then
            return 0
        fi
    fi
    return 1
}

# ============================================================
# wifi_scan [iface] [wait_secs] - start scan and print results.
#   NO iwlist (does not exist on MZD). All via wpa_cli -i wlan0,
#   scan itself behind run_with_timeout (max 15s).
#   Exit code: 0 = scan ran, 1 = wpa_cli missing
# ============================================================
wifi_scan() {
    _if="${1:-$WLAN_IFACE}"
    _wait="${2:-5}"

    if ! command -v wpa_cli > /dev/null 2>&1; then
        echo "wpa_cli not available - scan impossible (start wpa_supplicant first)"
        return 1
    fi

    echo "=== wpactrl scan (timeout 15s) ==="
    run_with_timeout "wpactrl scan" 15
    echo "waiting ${_wait}s for scan results..."
    sleep "$_wait"
    echo ""
    echo "=== wpactrl scan_results (timeout 15s) ==="
    run_with_timeout "wpactrl scan_results" 15
    return 0
}

# ============================================================
# wifi_deadlock_check - M1b: detect wl12xx watchdog deadlock
#   signature in dmesg (re-confirmed in logs 2026-11-01, t=281-316:
#   probe timeouts, 4x "Unable to flush TX buffers", "removing
#   interface", re-boot).
#   Detection + recovery hint ONLY. NO auto-recovery (brick-risk).
#   Exit code: 1 = deadlock signature found, 0 = clean
# ============================================================
wifi_deadlock_check() {
    _dmesg_out=$($DMESG_CMD 2>/dev/null)
    if [ -z "$_dmesg_out" ]; then
        echo "dmesg empty or not readable - deadlock check inconclusive"
        return 0
    fi

    # v4.7.5: also match FW panic pc: 0x... (proven pc: 0x21b8e in wifi-debug-002743.txt:864,876,887)
    _hits=$(printf '%s\n' "$_dmesg_out" | grep -c -E "removing interface|Unable to flush|probe.*timed out|watchdog interrupt|pc: 0x[0-9a-fA-F]+")
    if [ "$_hits" -gt 0 ]; then
        echo "!!! WL12XX DEADLOCK SIGNATURE DETECTED ($_hits lines in dmesg) !!!"
        printf '%s\n' "$_dmesg_out" | grep -E "removing interface|Unable to flush|probe.*timed out|watchdog interrupt|pc: 0x[0-9a-fA-F]+" | tail -10
        echo ""
        echo "Recovery hint (run MANUALLY - no auto-recovery due to brick-risk):"
        echo "  rmmod wl12xx_sdio wl12xx 2>/dev/null; sleep 2"
        echo "  insmod /lib/modules/\$(uname -r)/kernel/drivers/net/wireless/ti/wl12xx/wl12xx_sdio.ko 2>/dev/null || modprobe wl12xx_sdio"
        echo "  ifconfig $WLAN_IFACE up 2>/dev/null"
        echo "  If that does not help: reboot the CMU."
        echo "  See wifi/fix-watchdog.sh for the monitor loop."
        return 1
    fi
    echo "No wl12xx deadlock signature in dmesg."
    return 0
}
