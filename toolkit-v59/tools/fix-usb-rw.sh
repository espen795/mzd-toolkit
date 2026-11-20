#!/bin/sh
# MZD Toolkit - Fix USB Read-Write
# Makes USB stick writable (unmount/remount with rw)

# Source shared library
. "$(dirname "$0")/../lib/common.sh" 2>/dev/null || . ${TOOLKIT_DIR}/lib/common.sh
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup
detect_usb
log_to_usb "fix-usb-rw.sh started (USB_MOUNT=${USB_MOUNT:-none})"

echo "========================================"
echo " USB Read-Write Fix"
echo "========================================"
echo ""

# Find USB mounts
for dev in /tmp/mnt/sd*; do
    if [ -d "$dev" ]; then
        echo "Found: $dev"
        
        # Check current status
        if touch "$dev/.test_write" 2>/dev/null; then
            echo "  Already WRITABLE"
            rm "$dev/.test_write" 2>/dev/null
            continue
        fi
        
        echo "  Nu READ-ONLY - fixen..."
        
        # Unmount
        echo "  Unmount $dev..."
        umount "$dev" 2>&1
        sleep 2
        
        # Find the real device
        # ${USB_MOUNT} -> /dev/sdb1
        REAL_DEV="/dev/$(basename $dev)"
        echo "  Real device: $REAL_DEV"
        
        # Check if device exists
        if [ -b "$REAL_DEV" ]; then
            echo "  Device exists: $REAL_DEV"
            
            # Remount with rw
            echo "  Remount rw..."
            mount -t vfat -o rw,umask=000 "$REAL_DEV" "$dev" 2>&1 || \
            mount -o rw "$REAL_DEV" "$dev" 2>&1 || \
            mount "$REAL_DEV" "$dev" 2>&1
            sleep 2
            
            # Test
            if touch "$dev/.test_write" 2>/dev/null; then
                echo "  SUCCES: $dev is NU SCHRIJFBAAR"
                rm "$dev/.test_write" 2>/dev/null
            else
                echo "  FAILED: cannot make writable"
                
                # Try other mount options
                echo "  Trying other options..."
                umount "$dev" 2>/dev/null
                sleep 1
                mount -t vfat -o rw,uid=0,gid=0,umask=000,dmask=000,fmask=000 "$REAL_DEV" "$dev" 2>&1
                sleep 2
                
                if touch "$dev/.test_write" 2>/dev/null; then
                    echo "  SUCCESS with other options!"
                    rm "$dev/.test_write" 2>/dev/null
                else
                    echo "  Still read-only"
                    
                    # Check filesystem errors
                    echo "  Check filesystem..."
                    fsck -n "$REAL_DEV" 2>&1 | head -10
                    
                    # Force remount
                    echo "  Force remount..."
                    mount -o remount,rw,force "$dev" 2>&1
                    sleep 2
                    
                    if touch "$dev/.test_write" 2>/dev/null; then
                        echo "  SUCCESS after force remount!"
                        rm "$dev/.test_write" 2>/dev/null
                    fi
                fi
            fi
        else
            echo "  Device $REAL_DEV not found!"
            echo "  Available block devices:"
            ls -la /dev/sd* /dev/mmcblk* 2>/dev/null
        fi
        
        echo ""
    fi
done

echo "========================================"
echo " USB Fix complete"
echo "========================================"
echo ""
echo "Test all USB mounts:"
for dev in /tmp/mnt/*; do
    if [ -d "$dev" ]; then
        if touch "$dev/.test_final" 2>/dev/null; then
            echo "  $dev: WRITABLE"
            rm "$dev/.test_final" 2>/dev/null
        else
            echo "  $dev: READ-ONLY"
        fi
    fi
done
