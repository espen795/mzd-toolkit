#!/bin/sh
# MZD Toolkit - Complete System Dump v2
# Collects ALL useful info and writes DIRECTLY to USB
# Also works when /tmp is full or has read-only issues

# Source shared library
. "$(dirname "$0")/../lib/common.sh" 2>/dev/null || . ${TOOLKIT_DIR}/lib/common.sh
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup
detect_usb && ensure_usb_rw && TOOLKIT_DIR="$USB_MOUNT/mzd-toolkit" || TOOLKIT_DIR="${TOOLKIT_DIR}"
# v4.7.2 M2/F1: USB health pre-flight before dump
if type usb_health_check >/dev/null 2>&1; then usb_health_check || true; fi
log_to_usb "dump.sh started (USB_MOUNT=${USB_MOUNT:-none})"
# v4.8.1: dump to $LOG_DIR (= $DATA_DIR/logs = mzd-data/logs on USB root)
USB_LOG="${LOG_DIR:-$TOOLKIT_DIR/logs}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
# OUTPUT_DIR env (os-map.sh) — otherwise own dump dir. Unique suffix against collision.
if [ -n "${OUTPUT_DIR:-}" ]; then
    DUMP_DIR="$OUTPUT_DIR"
else
    DUMP_DIR="$USB_LOG/dump-$TIMESTAMP-$$"
fi

echo "========================================"
echo " MZD System Dump v2"
echo "========================================"
echo ""
echo "Timestamp: $TIMESTAMP"
echo ""

# Create directories directly on USB
mkdir -p "$DUMP_DIR" 2>/dev/null
if [ ! -d "$DUMP_DIR" ]; then
    echo "ERROR: cannot create $DUMP_DIR!"
    echo "Check USB mount: ls /tmp/mnt"
    exit 1
fi
echo "Output dir: $DUMP_DIR"
echo ""

# Helper function: write directly to USB file
write_file() {
    local fname="$1"
    shift
    local target="$DUMP_DIR/$fname"
    echo "Collecting: $fname"
    "$@" > "$target" 2>&1
    local size=$(wc -c < "$target" 2>/dev/null || echo "0")
    echo "  -> $fname ($size bytes)"
}

echo "--- 01-basic-info.txt ---"
{
    echo "=== MZD Basic Info ==="
    echo "Date: $(date)"
    echo "Timestamp: $TIMESTAMP"
    echo ""
    echo "=== whoami ==="
    whoami
    echo ""
    echo "=== id ==="
    id
    echo ""
    echo "=== hostname ==="
    hostname
    echo ""
    echo "=== uname -a ==="
    uname -a
    echo ""
    echo "=== /proc/version ==="
    cat /proc/version 2>&1
    echo ""
    echo "=== /jci/version.ini ==="
    cat /jci/version.ini 2>&1
    echo ""
    echo "=== /etc/os-release ==="
    cat /etc/os-release 2>&1
    echo ""
    echo "=== uptime ==="
    uptime 2>&1 || cat /proc/uptime 2>&1
} > "$DUMP_DIR/01-basic-info.txt" 2>&1
echo "  -> 01-basic-info.txt ($(wc -c < "$DUMP_DIR/01-basic-info.txt") bytes)"

echo "--- 02-network.txt ---"
{
    echo "=== MZD Network Info ==="
    echo "Date: $(date)"
    echo ""
    echo "=== ifconfig -a ==="
    ifconfig -a 2>&1
    echo ""
    echo "=== wifi_status (v4.7.2 M1: wpactrl + /sys + ifconfig; iwconfig/iwlist do NOT exist on MZD) ==="
    wifi_status wlan0 2>&1
    echo ""
    echo "=== wl12xx deadlock check (M1b) ==="
    wifi_deadlock_check 2>&1 || true
    echo ""
    echo "=== route -n ==="
    route -n 2>&1
    echo ""
    echo "=== /proc/net/route ==="
    cat /proc/net/route 2>&1
    echo ""
    echo "=== /proc/net/arp ==="
    cat /proc/net/arp 2>&1
    echo ""
    echo "=== /proc/net/wireless ==="
    cat /proc/net/wireless 2>&1
    echo ""
    echo "=== netstat -tln ==="
    netstat -tln 2>&1
    echo ""
    echo "=== netstat -tlnp ==="
    netstat -tlnp 2>&1
    echo ""
    echo "=== netstat -rn ==="
    netstat -rn 2>&1
    echo ""
    echo "=== /etc/resolv.conf ==="
    cat /etc/resolv.conf 2>&1
    echo ""
    echo "=== /etc/hosts ==="
    cat /etc/hosts 2>&1
    echo ""
    echo "=== Ping tests ==="
    GW=$(route -n 2>/dev/null | grep "^0.0.0.0" | awk "{print \$2}")
    echo "Gateway: $GW"
    if [ -n "$GW" ]; then
        ping -c 3 -W 5 "$GW" 2>&1
    fi
    echo ""
    echo "DNS test:"
    ping -c 2 -W 5 8.8.8.8 2>&1
} > "$DUMP_DIR/02-network.txt" 2>&1
echo "  -> 02-network.txt ($(wc -c < "$DUMP_DIR/02-network.txt") bytes)"

echo "--- 03-storage.txt ---"
{
    echo "=== MZD Storage Info ==="
    echo "Date: $(date)"
    echo ""
    echo "=== df -h ==="
    df -h 2>&1
    echo ""
    echo "=== df ==="
    df 2>&1
    echo ""
    echo "=== mount ==="
    mount 2>&1
    echo ""
    echo "=== /proc/mounts ==="
    cat /proc/mounts 2>&1
    echo ""
    echo "=== /proc/partitions ==="
    cat /proc/partitions 2>&1
    echo ""
    echo "=== Block devices ==="
    ls -la /dev/sd* /dev/mmcblk* /dev/mtd* /dev/ubi* 2>&1
    echo ""
    echo "=== USB Mounts detail ==="
    for d in /tmp/mnt/*; do
        if [ -d "$d" ]; then
            echo "--- $d ---"
            echo "Mount info:"
            mount 2>/dev/null | grep "$d"
            echo "Write test:"
            if touch "$d/.test_write" 2>/dev/null; then
                echo "  WRITABLE"
                rm "$d/.test_write" 2>/dev/null
            else
                echo "  READ-ONLY"
            fi
            echo "Contents:"
            ls -la "$d" 2>&1 | head -30
            echo "Disk usage:"
            df -h "$d" 2>&1
            echo ""
        fi
    done
    echo "=== /mnt detail ==="
    ls -la /mnt/ 2>&1
    for d in /mnt/*; do
        if [ -d "$d" ]; then
            echo "--- $d ---"
            ls -la "$d" 2>&1 | head -20
        fi
    done
    echo ""
    echo "=== data_persist ==="
    mount 2>/dev/null | grep data_persist
    if touch /mnt/data_persist/.test_write 2>/dev/null; then
        echo "WRITABLE"
        rm /mnt/data_persist/.test_write 2>/dev/null
    else
        echo "READ-ONLY"
    fi
    df -h /mnt/data_persist 2>&1
    echo "Contents:"
    ls -la /mnt/data_persist/ 2>&1
    echo "dev/bin:"
    ls -la /mnt/data_persist/dev/bin/ 2>&1
} > "$DUMP_DIR/03-storage.txt" 2>&1
echo "  -> 03-storage.txt ($(wc -c < "$DUMP_DIR/03-storage.txt") bytes)"

echo "--- 04-processes.txt ---"
{
    echo "=== MZD Processes ==="
    echo "Date: $(date)"
    echo ""
    echo "=== ps ==="
    ps 2>&1
    echo ""
    echo "=== ps aux ==="
    ps aux 2>&1
    echo ""
    echo "=== /proc/*/cmdline ==="
    for p in /proc/[0-9]*; do
        if [ -d "$p" ]; then
            pid=$(basename "$p")
            cmd=$(cat "$p/cmdline" 2>/dev/null | tr "\0" " ")
            if [ -n "$cmd" ]; then
                echo "PID $pid: $cmd"
            fi
        fi
    done
    echo ""
    echo "=== Process details ==="
    for p in /proc/[0-9]*; do
        if [ -f "$p/stat" ]; then
            pid=$(basename "$p")
            name=$(cat "$p/comm" 2>/dev/null)
            state=$(awk "{print \$3}" "$p/stat" 2>/dev/null)
            ppid=$(awk "{print \$4}" "$p/stat" 2>/dev/null)
            echo "PID: $pid  PPID: $ppid  State: $state  Name: $name"
        fi
    done
} > "$DUMP_DIR/04-processes.txt" 2>&1
echo "  -> 04-processes.txt ($(wc -c < "$DUMP_DIR/04-processes.txt") bytes)"

echo "--- 05-logs.txt ---"
{
    echo "=== MZD Logs ==="
    echo "Date: $(date)"
    echo ""
    echo "=== dmesg (full) ==="
    dmesg 2>&1
    echo ""
    echo "=== dmesg WiFi ==="
    dmesg 2>&1 | grep -i -E "wlan|wifi|sdio|bcmdhd|brcm|802.11"
    echo ""
    echo "=== dmesg USB ==="
    dmesg 2>&1 | grep -i -E "usb|sd[a-z]|mass storage"
    echo ""
    echo "=== dmesg Errors ==="
    dmesg 2>&1 | grep -i -E "error|fail|warn|timeout"
    echo ""
    echo "=== /tmp/*.log ==="
    for f in /tmp/*.log; do
        if [ -f "$f" ]; then
            echo "--- $f ---"
            cat "$f" 2>&1
            echo ""
        fi
    done
    echo "=== MZD logs ==="
    for f in /tmp/mzd-*.log /tmp/mzd-toolkit-*.log; do
        if [ -f "$f" ]; then
            echo "--- $f ---"
            cat "$f" 2>&1
            echo ""
        fi
    done
    echo "=== /var/log ==="
    ls -la /var/log/ 2>&1
    cat /var/log/messages 2>&1 | tail -50
    cat /var/log/syslog 2>&1 | tail -50
} > "$DUMP_DIR/05-logs.txt" 2>&1
echo "  -> 05-logs.txt ($(wc -c < "$DUMP_DIR/05-logs.txt") bytes)"

echo "--- 06-configs.txt ---"
{
    echo "=== MZD Configs ==="
    echo "Date: $(date)"
    echo ""
    echo "=== /etc/ssh/ ==="
    ls -la /etc/ssh/ 2>&1
    echo ""
    echo "=== /etc/ssh/sshd_config ==="
    cat /etc/ssh/sshd_config 2>&1
    echo ""
    echo "=== /etc/passwd ==="
    cat /etc/passwd 2>&1
    echo ""
    echo "=== /etc/group ==="
    cat /etc/group 2>&1
    echo ""
    echo "=== /etc/network/interfaces ==="
    cat /etc/network/interfaces 2>&1
    echo ""
    echo "=== /etc/wpa_supplicant.conf ==="
    cat /etc/wpa_supplicant.conf 2>&1
    echo ""
    echo "=== /etc/resolv.conf ==="
    cat /etc/resolv.conf 2>&1
    echo ""
    echo "=== /jci/scripts/stage_wifi.sh ==="
    cat /jci/scripts/stage_wifi.sh 2>&1
    echo ""
    echo "=== /jci/version.ini ==="
    cat /jci/version.ini 2>&1
    echo ""
    echo "=== /jci/scripts/ listing ==="
    ls -la /jci/scripts/ 2>&1
} > "$DUMP_DIR/06-configs.txt" 2>&1
echo "  -> 06-configs.txt ($(wc -c < "$DUMP_DIR/06-configs.txt") bytes)"

echo "--- 07-hardware.txt ---"
{
    echo "=== MZD Hardware ==="
    echo "Date: $(date)"
    echo ""
    echo "=== /proc/cpuinfo ==="
    cat /proc/cpuinfo 2>&1
    echo ""
    echo "=== /proc/meminfo ==="
    cat /proc/meminfo 2>&1
    echo ""
    echo "=== /proc/modules ==="
    cat /proc/modules 2>&1
    echo ""
    echo "=== /proc/interrupts ==="
    cat /proc/interrupts 2>&1
    echo ""
    echo "=== /proc/ioports ==="
    cat /proc/ioports 2>&1
    echo ""
    echo "=== /sys/class/net ==="
    ls -la /sys/class/net/ 2>&1
    echo ""
    echo "=== /sys/block ==="
    ls -la /sys/block/ 2>&1
    echo ""
    echo "=== lspci ==="
    lspci 2>&1
    echo ""
    echo "=== lsusb ==="
    lsusb 2>&1
} > "$DUMP_DIR/07-hardware.txt" 2>&1
echo "  -> 07-hardware.txt ($(wc -c < "$DUMP_DIR/07-hardware.txt") bytes)"

echo "--- 08-firewall.txt ---"
{
    echo "=== MZD Firewall ==="
    echo "Date: $(date)"
    echo ""
    echo "=== iptables -L -n ==="
    iptables -L -n 2>&1
    echo ""
    echo "=== iptables -L -n -v ==="
    iptables -L -n -v 2>&1
    echo ""
    echo "=== iptables -t nat -L -n ==="
    iptables -t nat -L -n 2>&1
    echo ""
    echo "=== iptables -t mangle -L -n ==="
    iptables -t mangle -L -n 2>&1
    echo ""
    echo "=== /proc/net/ip_tables_names ==="
    cat /proc/net/ip_tables_names 2>&1
} > "$DUMP_DIR/08-firewall.txt" 2>&1
echo "  -> 08-firewall.txt ($(wc -c < "$DUMP_DIR/08-firewall.txt") bytes)"

echo "--- 09-ssh-remote.txt ---"
{
    echo "=== MZD SSH/Remote ==="
    echo "Date: $(date)"
    echo ""
    echo "=== SSH Processen ==="
    ps 2>&1 | grep -E "sshd|dropbear|ssh"
    echo ""
    echo "=== SSH Poorten ==="
    netstat -tln 2>&1 | grep -E ":22|:2222"
    echo ""
    echo "=== SSH Config in data_persist ==="
    ls -la /mnt/data_persist/dev/bin/ 2>&1
    cat /mnt/data_persist/dev/bin/sshd_config 2>&1
    echo ""
    echo "=== SSH Host Keys ==="
    ls -la /mnt/data_persist/dev/bin/ssh_host_* 2>&1
    ls -la /etc/ssh/ssh_host_* 2>&1
    echo ""
    echo "=== Autorun script ==="
    cat /mnt/data_persist/dev/bin/autorun 2>&1
    echo ""
    echo "=== stage_wifi.sh hook check ==="
    grep -n "autorun\|MZD-AIO" /jci/scripts/stage_wifi.sh 2>&1
    echo ""
    echo "=== stage_wifi.sh backup ==="
    ls -la /mnt/data_persist/stage_wifi.sh.bak 2>&1
} > "$DUMP_DIR/09-ssh-remote.txt" 2>&1
echo "  -> 09-ssh-remote.txt ($(wc -c < "$DUMP_DIR/09-ssh-remote.txt") bytes)"

echo "--- 10-environment.txt ---"
{
    echo "=== MZD Environment ==="
    echo "Date: $(date)"
    echo ""
    echo "=== env ==="
    env 2>&1
    echo ""
    echo "=== set ==="
    set 2>&1
    echo ""
    echo "=== PATH ==="
    echo "$PATH"
    echo ""
    echo "=== Available commands ==="
    echo "--- /bin ---"
    ls /bin/ 2>&1
    echo ""
    echo "--- /sbin ---"
    ls /sbin/ 2>&1
    echo ""
    echo "--- /usr/bin ---"
    ls /usr/bin/ 2>&1 | head -100
    echo ""
    echo "--- /usr/sbin ---"
    ls /usr/sbin/ 2>&1 | head -100
    echo ""
    echo "--- /jci/bin ---"
    ls /jci/bin/ 2>&1
} > "$DUMP_DIR/10-environment.txt" 2>&1
echo "  -> 10-environment.txt ($(wc -c < "$DUMP_DIR/10-environment.txt") bytes)"

echo "--- 11-wifi-debug.txt ---"
{
    echo "=== MZD WiFi Debug ==="
    echo "Date: $(date)"
    echo ""
    echo "=== wpa_cli status ==="
    wpactrl status 2>&1
    echo ""
    echo "=== wpa_cli scan ==="
    wpactrl scan 2>&1
    sleep 3
    echo "=== wpa_cli scan_results ==="
    wpactrl scan_results 2>&1
    echo ""
    echo "=== wifi_scan (v4.7.2 M1: wpactrl scan, NO iwlist) ==="
    run_with_timeout "wpactrl scan" 15 2>&1
    sleep 3
    run_with_timeout "wpactrl scan_results" 15 2>&1 | head -50
    echo ""
    echo "=== wl12xx deadlock check (M1b) ==="
    wifi_deadlock_check 2>&1 || true
    echo ""
    echo "=== /sys/class/net/wlan0 ==="
    ls -la /sys/class/net/wlan0/ 2>&1
    echo ""
    echo "=== wlan0 statistics ==="
    cat /sys/class/net/wlan0/statistics/* 2>&1 | head -20
} > "$DUMP_DIR/11-wifi-debug.txt" 2>&1
echo "  -> 11-wifi-debug.txt ($(wc -c < "$DUMP_DIR/11-wifi-debug.txt") bytes)"

# Create summary
{
    echo "========================================"
    echo " MZD SYSTEM DUMP SUMMARY"
    echo "========================================"
    echo "Date: $(date)"
    echo "Timestamp: $TIMESTAMP"
    echo ""
    echo "--- Basic ---"
    echo "User: $(whoami 2>&1)"
    echo "Host: $(hostname 2>&1)"
    echo "Firmware: $(cat /jci/version.ini 2>&1 | head -1)"
    echo "Kernel: $(uname -r 2>&1)"
    echo ""
    echo "--- Network ---"
    IP=$(ifconfig wlan0 2>/dev/null | grep "inet addr" | sed "s/.*inet addr://" | sed "s/ .*//")
    echo "WiFi IP: ${IP:-NOT CONNECTED}"
    echo "MAC: $(ifconfig wlan0 2>/dev/null | grep "HWaddr" | awk "{print \$5}")"
    echo "Gateway: $(route -n 2>/dev/null | grep "^0.0.0.0" | awk "{print \$2}")"
    echo ""
    echo "--- SSH ---"
    if ps 2>/dev/null | grep sshd | grep -v grep > /dev/null; then
        echo "SSH: ACTIVE"
    else
        echo "SSH: INACTIVE"
    fi
    echo "Port 22: $(netstat -tln 2>/dev/null | grep -q ':36000 ' && echo 'OPEN' || echo 'CLOSED')"
    echo ""
    echo "--- Storage ---"
    echo "data_persist: $(df -h /mnt/data_persist 2>&1 | tail -1)"
    echo "Writable: $(touch /mnt/data_persist/.test 2>/dev/null && echo 'YES' && rm /mnt/data_persist/.test || echo 'NO')"
    echo ""
    echo "--- USB ---"
    ls -d /tmp/mnt/* 2>/dev/null | while read d; do
        rw="ro"
        touch "$d/.test" 2>/dev/null && rw="rw" && rm "$d/.test" 2>/dev/null
        echo "$d ($rw)"
    done
    echo ""
    echo "--- WiFi Status (v4.7.2 M1: wifi_status instead of iwconfig) ---"
    wifi_status wlan0 2>&1 | head -12
    echo ""
    echo "--- wl12xx deadlock check (M1b) ---"
    wifi_deadlock_check 2>&1 || true
    echo ""
    echo "--- Processes (total) ---"
    ps 2>&1 | wc -l
    echo ""
    echo "--- Files in this dump ---"
    ls -la "$DUMP_DIR"
    echo ""
    echo "--- File sizes ---"
    wc -c "$DUMP_DIR"/* 2>&1
} > "$DUMP_DIR/00-SUMMARY.txt" 2>&1

echo ""
echo "========================================"
echo " DUMP COMPLEET"
echo "========================================"
echo ""
echo "Output directory: $DUMP_DIR"
echo ""
echo "Files:"
ls -la "$DUMP_DIR"
echo ""
echo "Total size:"
du -sh "$DUMP_DIR" 2>/dev/null
echo ""
echo "File sizes:"
wc -c "$DUMP_DIR"/* 2>/dev/null
echo ""
echo "=== Summary ==="
cat "$DUMP_DIR/00-SUMMARY.txt"
