#!/bin/sh
# MZD Toolkit - Backup
# Makes a backup of important files to USB

# Source shared library
. "$(dirname "$0")/../lib/common.sh" 2>/dev/null || . ${TOOLKIT_DIR}/lib/common.sh
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup
# M2 USB health pre-flight (v4.7.2): rw-check + LOST.DIR + best-effort dmesg FAT-check
usb_health_check
_uhc_rc=$?
if [ "$_uhc_rc" -eq 1 ]; then
    TOOLKIT_DIR="${TOOLKIT_DIR:-}"
else
    detect_usb && TOOLKIT_DIR="$USB_MOUNT/mzd-toolkit" || TOOLKIT_DIR="${TOOLKIT_DIR}"
fi
log_to_usb "backup.sh started (USB_MOUNT=${USB_MOUNT:-none})"
BACKUP_DIR="$TOOLKIT_DIR/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/mzd-backup-$TIMESTAMP.tar"

echo "========================================"
echo " MZD Backup"
echo "========================================"
echo ""
echo "Backup to: $BACKUP_FILE"
echo ""

mkdir -p "$BACKUP_DIR"

# List of files to back up
FILES=""
DIRS=""

# Config files
for f in \
    /etc/wpa_supplicant.conf \
    /etc/network/interfaces \
    /etc/resolv.conf \
    /etc/ssh/sshd_config \
    /jci/version.ini \
    /jci/scripts/stage_wifi.sh \
; do
    if [ -f "$f" ]; then
        FILES="$FILES $f"
    fi
done

# Directories
for d in \
    /mnt/data_persist/dev \
    /mnt/data_persist/aio \
; do
    if [ -d "$d" ]; then
        DIRS="$DIRS $d"
    fi
done

echo "Files to back up:"
echo "$FILES" | tr " " "\n" | grep -v "^$"
echo ""
echo "Directories to back up:"
echo "$DIRS" | tr " " "\n" | grep -v "^$"
echo ""

# Maak backup
if command -v tar > /dev/null 2>&1; then
    tar -cf "$BACKUP_FILE" $FILES $DIRS 2>/dev/null
    echo "Backup created: $BACKUP_FILE"
    ls -la "$BACKUP_FILE"
else
    # Without tar: copy individually
    BACKUP_SUBDIR="$BACKUP_DIR/backup-$TIMESTAMP"
    mkdir -p "$BACKUP_SUBDIR"

    for f in $FILES; do
        cp "$f" "$BACKUP_SUBDIR/" 2>/dev/null
    done

    for d in $DIRS; do
        cp -r "$d" "$BACKUP_SUBDIR/" 2>/dev/null
    done

    echo "Backup created: $BACKUP_SUBDIR"
    ls -la "$BACKUP_SUBDIR"
fi

echo ""
echo "Backup complete!"
