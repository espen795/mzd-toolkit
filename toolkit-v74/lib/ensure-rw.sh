#!/bin/sh
# ============================================================
# MZD Toolkit - lib/ensure-rw.sh
# RO -> RW helper for the v74 rootfs.
#
# On v74 the root mount (ext4 on /dev/mmcblk0p2) is READ-ONLY by
# default with errors=remount-ro. The old `mount -o remount,rw /`
# (without sync) fails there with
#   "can't create /etc/passwd: Read-only file system".
# The firmware itself uses `mount -o remount,rw,sync /` (found as a
# literal string in the v74 rootfs image) -- that is the correct way.
#
# Usage (source this file, then call the function BEFORE any write
# to the rootfs):
#   . "$(dirname "$0")/../lib/ensure-rw.sh"        # local
#   . /data_persist/mzd-toolkit/lib/ensure-rw.sh   # on the CMU
#   ensure_root_rw || echo "rootfs stays RO - only /tmp + /data_persist work"
#
# Functions:
#   rootfs_is_rw    -> return 0 if /.rwtest can be written
#   ensure_root_rw  -> try to make / rw; return 0 = rw, 1 = stays RO
#   root_rw_status  -> "rw" or "ro" (for logs)
# ============================================================
ENSURE_RW_LOADED=1
export ENSURE_RW_LOADED

# rootfs_is_rw - real write test on / (not a mount-grep, which lies)
rootfs_is_rw() {
    if touch /.rwtest 2>/dev/null; then
        rm -f /.rwtest 2>/dev/null
        return 0
    fi
    return 1
}

# root_rw_status - "rw" or "ro"
root_rw_status() {
    if rootfs_is_rw; then echo "rw"; else echo "ro"; fi
}

# _ensure_rw_log - logs to $LOG_DIR/toolkit.log if present, else /tmp
_ensure_rw_log() {
    _f=""
    if [ -n "${LOG_DIR:-}" ] && { [ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR" 2>/dev/null; }; then
        if touch "$LOG_DIR/.rwtest" 2>/dev/null; then rm -f "$LOG_DIR/.rwtest"; _f="$LOG_DIR/toolkit.log"; fi
    fi
    [ -z "$_f" ] && _f="/tmp/toolkit.log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)] ensure-rw: $*" >> "$_f" 2>/dev/null
    return 0
}

# ensure_root_rw - make / writable.
#   1. already rw? -> done
#   2. mount -o remount,rw,sync /     (v74 firmware method -- sync is the key)
#   3. fallback: mount -o remount,rw /
#   4. fallback: explicit device from /proc/mounts (/dev/mmcblk0p2 on v74)
#   Always verify with touch /.rwtest.
#   Return: 0 = / writable, 1 = stays read-only (logged clearly).
# Named _ensure_root_rw_v74 so lib/common.sh can wrap the public
# ensure_root_rw() without recursion.
_ensure_root_rw_v74() {
    if rootfs_is_rw; then
        return 0
    fi

    # 1. v74 method: remount with sync (firmware does exactly this)
    if mount -o remount,rw,sync / 2>/dev/null; then
        if rootfs_is_rw; then
            _ensure_rw_log "/ -> rw OK via 'remount,rw,sync' (v74 method)"
            return 0
        fi
    fi
    # show the error visibly (not silently 2>/dev/null) if it fails
    mount -o remount,rw,sync / 2>&1 | grep -v "^$" || true

    # 2. fallback without sync
    if mount -o remount,rw / 2>/dev/null; then
        if rootfs_is_rw; then
            _ensure_rw_log "/ -> rw OK via 'remount,rw' (fallback)"
            return 0
        fi
    fi

    # 3. fallback: explicit device (v74: / is ext4 on /dev/mmcblk0p2)
    _rootdev=$(awk '$2=="/" && $1!="rootfs" {print $1; exit}' /proc/mounts 2>/dev/null)
    if [ -n "$_rootdev" ] && [ "$_rootdev" != "rootfs" ]; then
        if mount -o remount,rw,sync "$_rootdev" / 2>/dev/null || mount -o remount,rw "$_rootdev" / 2>/dev/null; then
            if rootfs_is_rw; then
                _ensure_rw_log "/ -> rw OK via device $_rootdev"
                return 0
            fi
        fi
    fi

    # 4. force attempt (only if force is supported)
    mount -o remount,rw,force / 2>/dev/null
    if rootfs_is_rw; then
        _ensure_rw_log "/ -> rw OK via 'remount,rw,force'"
        return 0
    fi

    _ensure_rw_log "FAIL: / stays READ-ONLY after all remount attempts (rootdev=${_rootdev:-rootfs}) - only /tmp and /data_persist are writable"
    return 1
}

# Public entry point
ensure_root_rw() { _ensure_root_rw_v74; }
