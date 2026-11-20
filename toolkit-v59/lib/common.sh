#!/bin/sh
# ============================================================
# MZD Toolkit - Common Library (lib/common.sh)
# Shared functions for ALL mzd-toolkit scripts.
# Source this at the top of every script:
#   . "$(dirname "$0")/../lib/common.sh"   (lokaal)
#   . ${TOOLKIT_DIR}/lib/common.sh  (op de auto/USB)
# ============================================================

# ------------------------------------------------------------
# Globale variabelen
# ------------------------------------------------------------
TOOLKIT_VERSION="4.8.21"    # v59 compat flags (ssh-rsa/ssh-dss) for modern OpenSSH clients
USB_MOUNT="${USB_MOUNT:-}"          # set by detect_usb()/bootstrap_paths()
TOOLKIT_LIB_LOADED=1

# Resolve toolkit root (waar lib/ in zit) - POSIX compatibel
_common_dir="$(dirname "$0")"
if [ -n "${TOOLKIT_DIR:-}" ] && [ -f "$TOOLKIT_DIR/lib/common.sh" ]; then
    :
elif [ -f "$_common_dir/lib/common.sh" ]; then
    TOOLKIT_DIR="$(cd "$_common_dir" 2>/dev/null && pwd)"
elif [ -f "$_common_dir/../lib/common.sh" ]; then
    TOOLKIT_DIR="$(cd "$_common_dir/.." 2>/dev/null && pwd)"
else
    for _d in /data_persist/mzd-toolkit /mnt/data_persist/mzd-toolkit /tmp/mnt/data_persist/mzd-toolkit; do
        if [ -f "$_d/lib/common.sh" ]; then
            TOOLKIT_DIR="$_d"
            break
        fi
    done
    [ -z "$TOOLKIT_DIR" ] && TOOLKIT_DIR=""
fi
# TOOLKIT_ROOT = deprecated alias van TOOLKIT_DIR (design §2.1)
TOOLKIT_ROOT="${TOOLKIT_DIR:-}"

# v4.7.2 M1: wifi-compat layer (wifi_status/wifi_scan/wifi_deadlock_check)
# In a sourced file $0 is the OUTER script; use TOOLKIT_DIR + env override.
WIFI_COMPAT_LOADED="${WIFI_COMPAT_LOADED:-0}"
if [ "$WIFI_COMPAT_LOADED" != "1" ]; then
    for _wc in "$TOOLKIT_DIR/lib/wifi-compat.sh" "${TOOLKIT_DIR:-/nonexistent}/lib/wifi-compat.sh"; do
        [ -n "$TOOLKIT_DIR" ] && [ -f "$_wc" ] && . "$_wc" 2>/dev/null && break
    done
fi

# ------------------------------------------------------------
# v4.8.0: settings + secrets — primary in $SETTINGS_DIR (= $DATA_DIR/config op
# USB root), fallback to $TOOLKIT_DIR/config (old sticks). Secrets are
# NEVER written by the lib and never in git (only .example tracked).
# -----------------------------------------------------------
_settings_loaded=0
for _sc in "$SETTINGS_DIR/settings.conf" "$TOOLKIT_DIR/config/settings.conf"; do
    [ -n "$_sc" ] && [ -f "$_sc" ] && . "$_sc" 2>/dev/null && _settings_loaded=1 && break
done
for _sec in "$SETTINGS_DIR/secrets.conf" "$TOOLKIT_DIR/config/secrets.conf"; do
    if [ -n "$_sec" ] && [ -f "$_sec" ]; then
        . "$_sec" 2>/dev/null
        chmod 600 "$_sec" 2>/dev/null
        break
    fi
done

# ============================================================
# v4.8.0 W1: detect_usb() v2 + bootstrap_paths() + run-logging
# Design §2.1/§2.3 (gate 1f0fb9a). MZD_MNT_ROOT is a TEST-ONLY env
# override (off-car fixtures); unset on the car -> no effect.
# ============================================================
MNT_ROOT="${MZD_MNT_ROOT:-}"   # test-only prefix; leeg op de CMU
# NOTE: MZD_MNT_ROOT is read per call (see detect_usb), so that
# test fixtures can set it after sourcing.

# boot8() - eerste 8 chars van boot_id (klok is leeg op CMU -> 19700101)
boot8() {
    _b=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null | cut -c1-8)
    echo "${_b:-0}"
}

# next_seq() - persistent run-counter in $STATE_DIR/run.seq (tmp+mv)
next_seq() {
    _sd="${STATE_DIR:-/tmp/toolkit-state}"
    mkdir -p "$_sd" 2>/dev/null
    _f="$_sd/run.seq"
    _n=$(cat "$_f" 2>/dev/null)
    case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
    _n=$((_n+1))
    echo "$_n" > "$_f.tmp.$$" 2>/dev/null && mv "$_f.tmp.$$" "$_f" 2>/dev/null
    echo "$_n"
}

# detect_usb() - vind USB mount path en zet $USB_MOUNT
#   v4.8.9: Only mounts that ACTUALLY contain the toolkit or mzd-data (empty
#   leftover dirs such as /tmp/mnt/sdb1 after stick removal are ignored).
detect_usb() {
    MNT_ROOT="${MZD_MNT_ROOT:-}"   # call-time (test-override)
    USB_MOUNT=""
    for dev in "$MNT_ROOT/tmp/mnt/sdb1" "$MNT_ROOT/tmp/mnt/sda1" "$MNT_ROOT/tmp/mnt/sdc1" "$MNT_ROOT/tmp/mnt/sdd1" "$MNT_ROOT/mnt/sdb1" "$MNT_ROOT/mnt/sda1"; do
        if [ -d "$dev" ] && { [ -f "$dev/mzd-toolkit/menu.sh" ] || [ -f "$dev/menu.sh" ] || [ -d "$dev/mzd-data" ]; }; then
            USB_MOUNT="$dev"; return 0
        fi
    done
    # glob met toolkit-filter (sd_nav = nav-kaart, uitsluiten)
    for dev in "$MNT_ROOT"/tmp/mnt/sd* "$MNT_ROOT"/mnt/sd*; do
        [ -d "$dev" ] || continue
        case "$dev" in *nav*) continue ;; esac
        if [ -f "$dev/mzd-toolkit/menu.sh" ] || [ -f "$dev/menu.sh" ] || [ -d "$dev/mzd-data" ]; then
            USB_MOUNT="$dev"; return 0
        fi
    done
    return 1
}

# bootstrap_paths() - v4.8.0 W1 (design §2.1): zet ALLE pad-variabelen.
# Volgorde: exported USB_MOUNT -> run.env cache -> detect_usb -> PERSIST fallback -> exports.
# v4.8.7: without a USB stick the toolkit works from /mnt/data_persist/mzd-toolkit
# (install.sh kopieert de hele toolkit daarheen — "USB-vrij" modus).
bootstrap_paths() {
    # v4.8.9: If TOOLKIT_DIR already runs under data_persist and contains menu.sh, secure persist paths directly
    if [ -n "${TOOLKIT_DIR:-}" ] && [ -f "$TOOLKIT_DIR/menu.sh" ]; then
        case "$TOOLKIT_DIR" in
            *data_persist*)
                for PP in /data_persist /mnt/data_persist /tmp/mnt/data_persist; do
                    if [ -f "$PP/mzd-toolkit/menu.sh" ]; then
                        USB_MOUNT=""
                        TOOLKIT_DIR="$PP/mzd-toolkit"
                        TOOLKIT_ROOT="$TOOLKIT_DIR"
                        DATA_DIR="$PP/mzd-data"
                        LOG_DIR="$DATA_DIR/logs"
                        STATE_DIR="$DATA_DIR/state"
                        SETTINGS_DIR="$DATA_DIR/config"
                        BACKUP_DIR="$DATA_DIR/backups"
                        export USB_MOUNT TOOLKIT_DIR TOOLKIT_ROOT DATA_DIR LOG_DIR STATE_DIR SETTINGS_DIR BACKUP_DIR
                        mkdir -p "$SETTINGS_DIR" "$STATE_DIR" "$LOG_DIR/runs" "$BACKUP_DIR" 2>/dev/null
                        return 0
                    fi
                done
                ;;
        esac
    fi

    # 1. parent exporteerde al USB_MOUNT?
    if [ -z "$USB_MOUNT" ]; then
        # 2. run.env cache (only if we already know a mount via detect)
        detect_usb || true
    fi
    [ -n "$USB_MOUNT" ] || detect_usb || true
    # read run.env cache (if it exists) - but detect result wins
    if [ -n "$USB_MOUNT" ] && [ -f "$USB_MOUNT/mzd-data/config/run.env" ]; then
        . "$USB_MOUNT/mzd-data/config/run.env" 2>/dev/null
        # sanity: cache mount must exist
        [ -d "${USB_MOUNT:-/nonexistent}" ] || detect_usb || true
    fi
    # v4.8.7/4.8.8/4.8.9 PERSIST fallback: no USB or USB has no toolkit -> toolkit on data_persist.
    # v4.8.8: autodetecteer WELK pad data_persist is (mounts verschillen per boot:
    # /mnt/data_persist, /data_persist or /tmp/mnt/data_persist - see 03-storage.txt)
    if [ -z "$USB_MOUNT" ] || [ ! -d "$USB_MOUNT" ] || [ ! -f "$USB_MOUNT/mzd-toolkit/menu.sh" ]; then
        for PP in /data_persist /mnt/data_persist /tmp/mnt/data_persist; do
            if [ -f "$PP/mzd-toolkit/menu.sh" ]; then
                USB_MOUNT=""
                TOOLKIT_DIR="$PP/mzd-toolkit"
                TOOLKIT_ROOT="$TOOLKIT_DIR"
                DATA_DIR="$PP/mzd-data"
                LOG_DIR="$DATA_DIR/logs"
                STATE_DIR="$DATA_DIR/state"
                SETTINGS_DIR="$DATA_DIR/config"
                BACKUP_DIR="$DATA_DIR/backups"
                export USB_MOUNT TOOLKIT_DIR TOOLKIT_ROOT DATA_DIR LOG_DIR STATE_DIR SETTINGS_DIR BACKUP_DIR
                mkdir -p "$SETTINGS_DIR" "$STATE_DIR" "$LOG_DIR/runs" "$BACKUP_DIR" 2>/dev/null
                return 0
            fi
        done
    fi
    [ -n "$USB_MOUNT" ] || return 1
    # 3. exports - TOOLKIT_DIR wins if the toolkit is really on the USB
    if [ -f "$USB_MOUNT/mzd-toolkit/menu.sh" ]; then
        TOOLKIT_DIR="$USB_MOUNT/mzd-toolkit"
    else
        TOOLKIT_DIR="${TOOLKIT_DIR:-$USB_MOUNT/mzd-toolkit}"
        [ -d "$TOOLKIT_DIR" ] || TOOLKIT_DIR="$USB_MOUNT/mzd-toolkit"
    fi
    TOOLKIT_ROOT="$TOOLKIT_DIR"   # deprecated alias
    DATA_DIR="$USB_MOUNT/mzd-data"
    LOG_DIR="$DATA_DIR/logs"
    STATE_DIR="$DATA_DIR/state"
    SETTINGS_DIR="$DATA_DIR/config"
    BACKUP_DIR="$DATA_DIR/backups"
    export USB_MOUNT TOOLKIT_DIR TOOLKIT_ROOT DATA_DIR LOG_DIR STATE_DIR SETTINGS_DIR BACKUP_DIR
    # 4. best-effort run.env cache write
    if touch "$USB_MOUNT/.rwtest_bootstrap" 2>/dev/null; then
        rm -f "$USB_MOUNT/.rwtest_bootstrap" 2>/dev/null
        mkdir -p "$SETTINGS_DIR" 2>/dev/null
        cat > "$SETTINGS_DIR/run.env" 2>/dev/null <<EOF
USB_MOUNT="$USB_MOUNT"
TOOLKIT_DIR="$TOOLKIT_DIR"
DATA_DIR="$DATA_DIR"
BOOT8="$(boot8)"
EOF
    fi
    return 0
}

# run_log_init() - v4.8.0 W1 (design §2.3): run-dir + meta.env + exec redirect.
# stdout/stderr to run dir; stdin is NOT touched (menu read works).
run_log_init() {
    [ "${MZD_RUNLOG:-1}" = "0" ] && return 0
    LOG_DIR="${LOG_DIR:-/tmp/toolkit-logs}"
    STATE_DIR="${STATE_DIR:-/tmp/toolkit-state}"
    TOOLKIT_VERSION="${TOOLKIT_VERSION:-0.0.0}"
    _script=$(basename "$0" 2>/dev/null || echo script)
    _script="${_script%.sh}"
    RUN_ID="v${TOOLKIT_VERSION}-${_script}-b$(boot8)-r$(next_seq)"
    RUN_DIR="$LOG_DIR/runs/$RUN_ID"
    mkdir -p "$RUN_DIR" 2>/dev/null || { RUN_DIR=""; return 0; }
    export RUN_ID RUN_DIR
    # meta.env - mask args (never psk/password in logs)
    {
        echo "toolkit_version=$TOOLKIT_VERSION"
        echo "script=$_script"
        _masked=""
        for _a in "$@"; do
            case "$_a" in
                *psk=*|*password=*|*passwd=*) _masked="$_masked ***" ;;
                *) _masked="$_masked $_a" ;;
            esac
        done
        echo "args=${_masked# }"
        echo "usb_mount=${USB_MOUNT:-}"
        echo "toolkit_dir=${TOOLKIT_DIR:-}"
        echo "boot_id=$(boot8)"
        echo "start_epoch=$(date +%s 2>/dev/null || echo 0)"
    } > "$RUN_DIR/meta.env" 2>/dev/null
    # v4.8.3: LIVE output in the menu + run log at the same time.
    # Problem v4.8.0-4.8.2: exec >>stdout.log redirects ALL output to file,
    # so in the interactive menu you saw "nothing" until the script was done.
    # Solution: if stdout is a TTY (menu session), route via mkfifo+tee:
    # script output -> pipe -> tee -> stdout.log EN originele terminal (fd 3).
    # Without TTY (autorun/ssh) it behaves as before v4.8.3 (file only).
    if [ -t 1 ] && command -v tee >/dev/null 2>&1 && command -v mkfifo >/dev/null 2>&1; then
        _pipe="$RUN_DIR/.outpipe.$$"
        if mkfifo "$_pipe" 2>/dev/null; then
            exec 3>&1                      # save original terminal on fd 3
            ( tee -a "$RUN_DIR/stdout.log" < "$_pipe" >&3 2>"$RUN_DIR/stderr.log" ) &
            _teepid=$!
            echo "$_teepid" > "$RUN_DIR/.teepid" 2>/dev/null
            exec > "$_pipe" 2>&1
            return 0
        fi
    fi
    exec >>"$RUN_DIR/stdout.log" 2>>"$RUN_DIR/stderr.log"
    return 0
}

# script_end_log(rc) - exit.code + meta.env end + scrub secrets uit stdout.log
script_end_log() {
    _rc="${1:-0}"
    [ -n "${RUN_DIR:-}" ] && [ -d "$RUN_DIR" ] || return 0
    # v4.8.3: in TTY-tee mode close the pipe first so tee ends
    if [ -f "$RUN_DIR/.teepid" ]; then
        _tp=$(cat "$RUN_DIR/.teepid" 2>/dev/null)
        exec >&- 2>/dev/null
        [ -n "$_tp" ] && kill "$_tp" 2>/dev/null
        rm -f "$RUN_DIR/.teepid" "$RUN_DIR/.outpipe."* 2>/dev/null
        exec >&3 2>/dev/null; exec 3>&- 2>/dev/null
    fi
    echo "$_rc" > "$RUN_DIR/exit.code" 2>/dev/null
    echo "end_epoch=$(date +%s 2>/dev/null || echo 0) exit_code=$_rc" >> "$RUN_DIR/meta.env" 2>/dev/null
    # scrub: psk=/password tokens uit stdout.log (zoom_out blocker)
    if [ -f "$RUN_DIR/stdout.log" ]; then
        sed -i -e 's/\(psk=\)[^ "]*/\1***/g' -e 's/\(password=\)[^ "]*/\1***/g' -e 's/\(passwd=\)[^ "]*/\1***/g' "$RUN_DIR/stdout.log" 2>/dev/null
    fi
    return 0
}

# ============================================================
# 1. detect_usb() - OLD version below is NO LONGER used;
#    v4.8.0 version is at the top (see MNT_ROOT block). This placeholder
#    neutralizes the old definition so there is no duplicate definition.
# ============================================================

# ============================================================
# 2. ensure_usb_rw() - if USB detected but read-only,
#    roep tools/fix-usb-rw.sh aan. Return 0 als rw, 1 als fail.
# ============================================================
ensure_usb_rw() {
    detect_usb || return 1
    [ -n "$USB_MOUNT" ] || return 1

    # Test of al schrijfbaar
    if touch "$USB_MOUNT/.rwtest_common" 2>/dev/null; then
        rm -f "$USB_MOUNT/.rwtest_common" 2>/dev/null
        return 0
    fi

    # Try remount ourselves (fast)
    mount -o remount,rw "$USB_MOUNT" 2>/dev/null
    if touch "$USB_MOUNT/.rwtest_common" 2>/dev/null; then
        rm -f "$USB_MOUNT/.rwtest_common" 2>/dev/null
        return 0
    fi

    # Call fix-usb-rw.sh if available
    _fix_script=""
    for c in "$TOOLKIT_DIR/tools/fix-usb-rw.sh"; do
        [ -n "$TOOLKIT_DIR" ] && [ -f "$c" ] && _fix_script="$c" && break
    done
    if [ -n "$_fix_script" ]; then
        sh "$_fix_script" > /dev/null 2>&1
    else
        # Inline fallback: unmount + remount vfat rw
        _dev="/dev/$(basename "$USB_MOUNT")"
        [ -b "$_dev" ] || _dev="$USB_MOUNT"
        umount "$USB_MOUNT" 2>/dev/null
        sleep 1
        mount -t vfat -o rw,umask=000 "$_dev" "$USB_MOUNT" 2>/dev/null \
            || mount -o rw "$_dev" "$USB_MOUNT" 2>/dev/null \
            || mount "$_dev" "$USB_MOUNT" 2>/dev/null
        sleep 1
    fi

    # Final check
    if touch "$USB_MOUNT/.rwtest_common" 2>/dev/null; then
        rm -f "$USB_MOUNT/.rwtest_common" 2>/dev/null
        return 0
    fi
    return 1
}

# ============================================================
# 2b. usb_health_check() - USB health pre-flight (v4.7.2, M2).
#     Thin wrapper around detect_usb()/ensure_usb_rw() - NO duplicate.
#     Return codes:
#       0 = healthy (or no USB detected)
#       1 = hard fail: USB detected but mount rw failed
#       2 = warning: rw OK but LOST.DIR and/or FAT-fs errors detected
#     Evidence: logs/from-mzd/.../05-logs.txt (16x "FAT-fs (sdb1): Directory
#     bread(...) failed" na USB disconnect t=81s) + 03-storage.txt (LOST.DIR
#     in ${USB_MOUNT}). dmesg-check is BEST-EFFORT: MZD boot met loglevel=3,
#     ringbuffer is small - errors may already be gone (no guarantee).
# ============================================================
usb_health_check() {
    if ! detect_usb; then
        # No USB mount found - nothing to check
        return 0
    fi
    [ -n "$USB_MOUNT" ] || return 0

    _uhc_issues=0

    # 1. Mount rw check (hergebruik ensure_usb_rw - touch-test + remount + fix-usb-rw)
    if ensure_usb_rw; then
        :
    else
        echo "ERROR: USB detected on $USB_MOUNT but NOT writable (rw check failed)"
        log_to_usb "usb_health_check: rw-check FAILED op $USB_MOUNT"
        return 1
    fi

    # 2. LOST.DIR in USB root = hard evidence of FAT corruption (03-storage.txt)
    if [ -d "$USB_MOUNT/LOST.DIR" ]; then
        echo "WARNING: LOST.DIR found in $USB_MOUNT - USB corrupt, reformat recommended"
        log_to_usb "usb_health_check: LOST.DIR present on $USB_MOUNT (FAT corruption)"
        _uhc_issues=$((_uhc_issues + 1))
    fi

    # 3. dmesg check op FAT-fs read errors - BEST-EFFORT (loglevel=3, kleine ringbuffer)
    if command -v dmesg > /dev/null 2>&1; then
        _uhc_fat=$(dmesg 2>/dev/null | grep -c "FAT-fs.*failed")
        case "$_uhc_fat" in
            ''|*[!0-9]*) _uhc_fat=0 ;;
        esac
        if [ "$_uhc_fat" -gt 0 ]; then
            echo "WARNING: $_uhc_fat FAT-fs read errors in dmesg (best-effort, loglevel=3) - USB possibly corrupt"
            log_to_usb "usb_health_check: $_uhc_fat FAT-fs failed entries in dmesg on $USB_MOUNT"
            _uhc_issues=$((_uhc_issues + 1))
        fi
    fi

    [ "$_uhc_issues" -gt 0 ] && return 2
    return 0
}

# ============================================================
# 3. log_to_usb(msg) - v4.8.0: logs to $LOG_DIR/toolkit.log
#    (= $DATA_DIR/logs/toolkit.log op USB root — overleeft delete van
#    mzd-toolkit/). Fallback: /tmp/toolkit.log if USB not rw.
#    Categorie-mappen: $LOG_DIR/v$TOOLKIT_VERSION-$MZD_LOG_CATEGORY/b$BOOT8/
# ============================================================
log_to_usb() {
    _msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    _logdir=""
    _logfile=""

    if [ -z "$USB_MOUNT" ]; then
        detect_usb || true
    fi

    LOG_DIR="${LOG_DIR:-}"
    if [ -z "$LOG_DIR" ] && [ -n "$USB_MOUNT" ]; then
        LOG_DIR="$USB_MOUNT/mzd-data/logs"
    fi

    if [ -n "$LOG_DIR" ] && { [ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR" 2>/dev/null; }; then
        if touch "$LOG_DIR/.rwtest" 2>/dev/null; then
            rm -f "$LOG_DIR/.rwtest" 2>/dev/null
            _logfile="$LOG_DIR/toolkit.log"
        fi
    fi

    # Fallback if USB not available/rw
    if [ -z "$_logfile" ]; then
        _logfile="/tmp/toolkit.log"
    fi

    echo "$_msg" >> "$_logfile" 2>/dev/null
    # Also to stdout in debug mode
    [ "${TOOLKIT_DEBUG:-0}" = "1" ] && echo "$_msg"
    return 0
}

# log_to_category(msg) - v4.8.0: logs to category dir with version in name
#   $LOG_DIR/v$TOOLKIT_VERSION-$MZD_LOG_CATEGORY/b$BOOT8/<script>.log
#   MZD_LOG_CATEGORY default = livelogs (dump scripts set logdumb)
log_to_category() {
    _cat="${MZD_LOG_CATEGORY:-livelogs}"
    _base="${LOG_DIR:-/tmp/toolkit-logs}"
    _dir="$_base/v${TOOLKIT_VERSION:-0.0.0}-$_cat/b$(boot8)"
    mkdir -p "$_dir" 2>/dev/null || _dir="/tmp/toolkit-logs"
    _f="$_dir/$(basename "$0" 2>/dev/null || echo script).log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$_f" 2>/dev/null
    return 0
}

# ============================================================
# 3b. ensure_root_rw() - v4.8.14 (hardware testing): remount / rw + VERIFY.
#     Evidence from logs (03-storage.txt + remount-rw runs r21/r24/r26):
#     rootfs layer is rw but /dev/ffx01p1 underneath is mounted ro; after
#     "mount -o remount,rw /" / is WRITABLE (os_unlock: / -> rw OK in
#     toolkit.log). BUT: if the remount fails (e.g. kernel cmdline ro),
#     writes fail silently with 2>/dev/null. Therefore: remount WITHOUT
#     stderr suppression + touch test on /etc/.rwtest.
#     Return: 0 = / is writable, 1 = remount or write failed.
# ============================================================
ensure_root_rw() {
    # Al schrijfbaar?
    if touch /etc/.rwtest_ensure 2>/dev/null; then
        rm -f /etc/.rwtest_ensure 2>/dev/null
        return 0
    fi
    # Remount without 2>/dev/null so the error message is visible in logs
    if mount 2>/dev/null | grep -q " on / type "; then
        mount -o remount,rw / 2>&1 | grep -v "^$" || true
    fi
    # Second attempt with explicit device (from /proc/mounts: /dev/ffx01p1 on /)
    _rootdev=$(awk '$2=="/" && $1!="rootfs" {print $1; exit}' /proc/mounts 2>/dev/null)
    if [ -n "$_rootdev" ] && [ "$_rootdev" != "rootfs" ]; then
        mount -o remount,rw "$_rootdev" / 2>&1 | grep -v "^$" || true
    fi
    # Verifieer met echte write-test
    if touch /etc/.rwtest_ensure 2>/dev/null; then
        rm -f /etc/.rwtest_ensure 2>/dev/null
        log_to_usb "ensure_root_rw: / is WRITABLE after remount"
        return 0
    fi
    log_to_usb "ensure_root_rw: FAIL - / blijft read-only na remount (rootdev=${_rootdev:-rootfs})"
    return 1
}

# ============================================================
# 4. os_unlock() - non-interactive remount rw:
#    /, /jci, /etc, /usr, /var, /mnt/data_persist
#    No prompt. Logs result via log_to_usb.
# ============================================================
os_unlock() {
    _unlock_parts="/ /jci /etc /usr /var /mnt/data_persist /opt /home"
    _ok=0; _fail=0
    for _p in $_unlock_parts; do
        [ -d "$_p" ] || continue
        # Only if it is a mountpoint
        if mount 2>/dev/null | grep -q " on $_p "; then
            if mount -o remount,rw "$_p" 2>/dev/null; then
                _ok=$((_ok + 1))
                log_to_usb "os_unlock: $_p -> rw OK"
            else
                # Second attempt with force
                mount -o remount,rw,force "$_p" 2>/dev/null && _ok=$((_ok + 1)) || {
                    _fail=$((_fail + 1))
                    log_to_usb "os_unlock: $_p -> rw FAIL"
                }
            fi
        fi
    done
    log_to_usb "os_unlock DONE: $_ok rw, $_fail failed"
    [ "$_fail" -eq 0 ]
}

# ============================================================
# 5. os_lock() - remount everything read-only again
# ============================================================
os_lock() {
    _lock_parts="/ /jci /etc /usr /var /mnt/data_persist /opt /home"
    for _p in $_lock_parts; do
        [ -d "$_p" ] || continue
        if mount 2>/dev/null | grep -q " on $_p "; then
            mount -o remount,ro "$_p" 2>/dev/null \
                && log_to_usb "os_lock: $_p -> ro OK" \
                || log_to_usb "os_lock: $_p -> ro FAIL"
        fi
    done
    sync 2>/dev/null
    log_to_usb "os_lock DONE"
    return 0
}

# ============================================================
# 6. safe_write(path, content) - os_unlock if needed,
#    schrijft file, logt via log_to_usb
# ============================================================
safe_write() {
    _path="$1"
    _content="$2"
    [ -n "$_path" ] || return 1

    # Try direct first
    if printf '%s\n' "$_content" > "$_path" 2>/dev/null; then
        log_to_usb "safe_write: $_path OK (direct)"
        return 0
    fi

    # Otherwise unlock and try again
    log_to_usb "safe_write: $_path direct failed, os_unlock..."
    os_unlock
    if printf '%s\n' "$_content" > "$_path" 2>/dev/null; then
        log_to_usb "safe_write: $_path OK (na unlock)"
        return 0
    fi

    log_to_usb "safe_write: $_path FAILED"
    return 1
}

# ============================================================
# 7. trap_cleanup() - v4.8.0 W1 (design §2.3, goldfish blocker fix):
#    ONE chained EXIT trap that PRESERVES the exit code ($_rc), plus
#    INT->130 / TERM->143. Run-logging via run_log_init.
#    ONLY call from a main script - the lib itself sets no traps.
# ============================================================
STOP_DIR="/tmp/toolkit-stop"
PID_DIR="/tmp/toolkit-pids"

trap_cleanup() {
    # Register PID so stop_all() can kill us
    register_pid "$$" "$(basename "$0" 2>/dev/null || echo script)"
    # v4.8.0: run-logging init (always on for main scripts; MZD_RUNLOG=0 off)
    run_log_init
    trap '_rc=$?; script_end_log "$_rc"; unregister_pid "$$"; exit "$_rc"' EXIT
    trap '_rc=130; script_end_log "$_rc"; unregister_pid "$$"; exit 130' INT
    trap '_rc=143; script_end_log "$_rc"; unregister_pid "$$"; exit 143' TERM
}

# ============================================================
# 7b. register_pid(pid, name) - sla PID op in /tmp/toolkit-pids/
# ============================================================
register_pid() {
    _pid="$1"; _name="${2:-script}"
    mkdir -p "$PID_DIR" 2>/dev/null
    echo "$_name" > "$PID_DIR/$_pid" 2>/dev/null
}

# ============================================================
# 7c. unregister_pid(pid) - verwijder PID file
# ============================================================
unregister_pid() {
    rm -f "$PID_DIR/$1" 2>/dev/null
}

# ============================================================
# 7d. check_stop() - return 0 if script MUST stop
#     Stop door: touch /tmp/toolkit-stop/STOP
#     of:       touch ${TOOLKIT_DIR}/STOP (vanaf USB)
#     Check in every loop: while ! check_stop; do ... done
# ============================================================
check_stop() {
    if [ -f "$STOP_DIR/STOP" ] || [ -f "${DATA_DIR:-/nonexistent}/STOP" ] || { [ -n "${TOOLKIT_DIR:-}" ] && [ -f "$TOOLKIT_DIR/STOP" ]; }; then
        log_to_usb "STOP file found - script stops"
        return 0
    fi
    return 1
}

# ============================================================
# 7e. stop_all() - kill ALLE lopende toolkit scripts
#     Usage: sh lib/stop-all.sh  OR from the menu
# ============================================================
stop_all() {
    echo "Stopping all running toolkit scripts..."
    # Via PID files
    if [ -d "$PID_DIR" ]; then
        for pf in "$PID_DIR"/*; do
            [ -f "$pf" ] || continue
            pid=$(basename "$pf")
            name=$(cat "$pf" 2>/dev/null)
            if kill -0 "$pid" 2>/dev/null; then
                echo "  kill $pid ($name)"
                kill "$pid" 2>/dev/null
                sleep 1
                kill -9 "$pid" 2>/dev/null
                log_to_usb "stop_all: gekilled $pid ($name)"
            fi
            rm -f "$pf"
        done
    fi
    # Fallback: kill op proces naam
    for proc in mzd-watchdog watchdog monitor vehicle-data fix-watchdog; do
        pids=$(pgrep -f "$proc" 2>/dev/null)
        for pid in $pids; do
            [ "$pid" != "$$" ] && kill -9 "$pid" 2>/dev/null && echo "  kill -9 $pid ($proc)"
        done
    done
    # Cleanup STOP file
    rm -f "$STOP_DIR/STOP" 2>/dev/null
    echo "DONE. All scripts stopped."
}

# ============================================================
# 7f. make_stop() - create STOP file (to stop loops)
# ============================================================
make_stop() {
    mkdir -p "$STOP_DIR"
    touch "$STOP_DIR/STOP"
    echo "STOP file created - all loops stop within 1 iteration"
}

# ============================================================
# 8. run_with_timeout(cmd, secs) - runs cmd with timeout.
#    v4.7.5 M2 (gate 0046b92): busybox-proof. BusyBox timeout slikt
#    "timeout N cmd" ERROR ("can't execute '15'" - proven in
#    wifi-debug-002743.txt section 6), so we first test which mode works
#    en cachen dat in _TOOLKIT_TIMEOUT_MODE.
#    Return: exit code van cmd, of 124 bij timeout
# ============================================================
run_with_timeout() {
    _cmd="$1"
    _secs="${2:-30}"

    if [ -z "${_TOOLKIT_TIMEOUT_MODE:-}" ]; then
        if command -v timeout > /dev/null 2>&1 && timeout 1 true 2>/dev/null; then
            _TOOLKIT_TIMEOUT_MODE=gnu
        elif command -v timeout > /dev/null 2>&1 && timeout -t 1 true 2>/dev/null; then
            _TOOLKIT_TIMEOUT_MODE=gnu-t
        else
            _TOOLKIT_TIMEOUT_MODE=bg
        fi
    fi

    case "$_TOOLKIT_TIMEOUT_MODE" in
        gnu)   timeout "$_secs" sh -c "$_cmd"; return $? ;;
        gnu-t) timeout -t "$_secs" sh -c "$_cmd"; return $? ;;
        bg)
            # Fallback: background + kill na N seconden (busybox compatibel)
            sh -c "$_cmd" &
            _pid=$!
            ( sleep "$_secs"; kill "$_pid" 2>/dev/null; command -v pkill >/dev/null 2>&1 && pkill -f "$_cmd" 2>/dev/null ) &
            _watchdog=$!
            wait "$_pid" 2>/dev/null
            _rc=$?
            kill "$_watchdog" 2>/dev/null
            wait "$_watchdog" 2>/dev/null
            # If we got here via kill, return 124
            [ "$_rc" -eq 143 ] && return 124
            return "$_rc" ;;
    esac
}

# ============================================================
# 9. require_root() - check for uid 0, exit 1 if not root
# ============================================================
require_root() {
    if [ "$(id -u 2>/dev/null)" != "0" ]; then
        echo "ERROR: This script must run as root (uid 0). Current uid: $(id -u 2>/dev/null)"
        log_to_usb "require_root: FAIL (uid=$(id -u 2>/dev/null))"
        return 1
    fi
    log_to_usb "require_root: OK (uid=0)"
    return 0
}

# ============================================================
# 10. JCI D-Bus service bus + engine/ignition check (v4.7.3)
#     MZD runs NO standard system bus (/var/run/dbus/system_bus_socket
#     does not exist). All com.jci.* services are on:
#       unix:path=/tmp/dbus_service_socket   (service bus, vehicle data)
#       unix:path=/tmp/dbus_hmi_socket       (HMI/GUI bus)
#     See docs/ANALYSIS-2026-11-01-logs-vim-canbus.md - --system gave empty logs.
# ============================================================
JCI_SERVICE_BUS_ADDR="${JCI_SERVICE_BUS_ADDR:-unix:path=/tmp/dbus_service_socket}"
JCI_HMI_BUS_ADDR="${JCI_HMI_BUS_ADDR:-unix:path=/tmp/dbus_hmi_socket}"

# jci_dbus_send [args...] - dbus-send op de JCI service bus.
# v4.7.5 M1 (gate 0046b92): NO --system fallback anymore - the MZD has
# ONLY /tmp/dbus_service_socket; --system gave empty logs (ERR(1), 0 services).
# On missing socket: explicit error + return 1.
jci_dbus_send() {
    if [ -S /tmp/dbus_service_socket ]; then
        dbus-send --address="$JCI_SERVICE_BUS_ADDR" "$@"
        return $?
    fi
    echo "ERROR: /tmp/dbus_service_socket missing - MZD has no system bus, no fallback" >&2
    log_to_usb "jci_dbus_send: socket missing -> return 1"
    return 1
}

# jci_dbus_monitor [match...] - dbus-monitor op de JCI service bus (zelfde regel)
jci_dbus_monitor() {
    if [ -S /tmp/dbus_service_socket ]; then
        dbus-monitor --address="$JCI_SERVICE_BUS_ADDR" "$@"
        return $?
    fi
    echo "ERROR: /tmp/dbus_service_socket missing - MZD has no system bus, no fallback" >&2
    log_to_usb "jci_dbus_monitor: socket missing -> return 1"
    return 1
}

# engine_on() - return 0 if ignition ON (engine/contact on), 1 otherwise.
#   BCM GetIgnitionStatus returnt byte (y): 1 = ON, 0 = OFF.
#   WITHOUT engine the CAN frames and VIM/vehicle D-Bus data are empty or static
#   -> debug test info logging is pointless then.
engine_on() {
    _out=$(jci_dbus_send --print-reply --dest=com.jci.vbs.bcm /com/jci/vbs/bcm com.jci.vbs.bcm.GetIgnitionStatus 2>/dev/null)
    echo "$_out" | grep -q "byte 1" && return 0
    echo "$_out" | grep -qE "boolean true|uint32 1|int32 1" && return 0
    return 1
}

# warn_engine() - print status/warning; NEVER blocks (return 0).
#   Roep aan bovenaan VIM/CAN debug scripts (can-monitor, vim-dump-all, ...)
warn_engine() {
    if engine_on; then
        echo "Motor/contact: AAN (ignition ON) - CAN/VIM data is live"
    else
        echo "================================================"
        echo " WARNING: engine/contact OFF (ignition OFF)"
        echo " CAN bus frames + VIM debug data are empty/static."
        echo " Turn the ENGINE ON for meaningful debug test logging."
        echo "================================================"
    fi
    return 0
}

# ============================================================
# Helper: source guard - check if common.sh is loaded
# ============================================================
_common_loaded() {
    [ "${TOOLKIT_LIB_LOADED:-0}" = "1" ]
}

# ============================================================
# v4.8.18: SSH v59-compat flags - modern OpenSSH clients refuse
# ssh-rsa/ssh-dss host keys standaard ("no matching host key type").
# v59 sshd (2016 build) offers ONLY ssh-rsa + ssh-dss.
# Usage: ssh $MZD_SSH_OPTS -p 36000 cmu@<IP>
# ============================================================
MZD_SSH_OPTS="-o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedAlgorithms=+ssh-rsa"
