#!/bin/sh

# Source shared library (with fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Remount Read-Write
# Makes filesystems read-write where possible

echo "========================================"
echo " Remount Read-Write"
echo "========================================"
echo ""

echo "Current mount status:"
mount 2>/dev/null | head -20
echo ""

echo "--- Step 1: Remount / as rw ---"
mount -o remount,rw / 2>&1
sleep 1

echo "--- Step 2: Remount /jci as rw ---"
mount -o remount,rw /jci 2>&1
sleep 1

echo "--- Step 3: Remount /etc as rw ---"
mount -o remount,rw /etc 2>&1
sleep 1

echo "--- Step 4: Remount /usr as rw ---"
mount -o remount,rw /usr 2>&1
sleep 1

echo "--- Step 5: Remount /var as rw ---"
mount -o remount,rw /var 2>&1
sleep 1

echo ""
echo "--- Test writability ---"

echo "Test / :"
if touch /.test_write 2>/dev/null; then
    echo "  / is WRITABLE"
    rm /.test_write 2>/dev/null
else
    echo "  / is READ-ONLY"
fi

echo "Test /jci :"
if touch /jci/.test_write 2>/dev/null; then
    echo "  /jci is WRITABLE"
    rm /jci/.test_write 2>/dev/null
else
    echo "  /jci is READ-ONLY"
fi

echo "Test /etc :"
if touch /etc/.test_write 2>/dev/null; then
    echo "  /etc is WRITABLE"
    rm /etc/.test_write 2>/dev/null
else
    echo "  /etc is READ-ONLY"
fi

echo "Test /usr :"
if touch /usr/.test_write 2>/dev/null; then
    echo "  /usr is WRITABLE"
    rm /usr/.test_write 2>/dev/null
else
    echo "  /usr is READ-ONLY"
fi

echo "Test /var :"
if touch /var/.test_write 2>/dev/null; then
    echo "  /var is WRITABLE"
    rm /var/.test_write 2>/dev/null
else
    echo "  /var is READ-ONLY"
fi

echo "Test /mnt/data_persist :"
if touch /mnt/data_persist/.test_write 2>/dev/null; then
    echo "  /mnt/data_persist is WRITABLE"
    rm /mnt/data_persist/.test_write 2>/dev/null
else
    echo "  /mnt/data_persist is READ-ONLY"
fi

echo "Test /tmp :"
if touch /tmp/.test_write 2>/dev/null; then
    echo "  /tmp is WRITABLE (always, it is RAM)"
    rm /tmp/.test_write 2>/dev/null
else
    echo "  /tmp is READ-ONLY"
fi

echo ""
echo "--- Make USB mounts rw ---"
for dev in /tmp/mnt/sd*; do
    if [ -d "$dev" ]; then
        echo "USB device: $dev"
        # Try remount rw
        mount -o remount,rw "$dev" 2>&1
        sleep 1
        # Test
        if touch "$dev/.test_write" 2>/dev/null; then
            echo "  $dev is NOW WRITABLE"
            rm "$dev/.test_write" 2>/dev/null
        else
            echo "  $dev is READ-ONLY (FAT32 mount, try unmount/remount)"
            # Unmount and remount with rw flags
            umount "$dev" 2>/dev/null
            sleep 1
            mount -t vfat -o rw,umask=000 "$dev" 2>/dev/null || mount -o rw "$dev" 2>/dev/null
            sleep 1
            if touch "$dev/.test_write" 2>/dev/null; then
                echo "  $dev is NOW WRITABLE after remount"
                rm "$dev/.test_write" 2>/dev/null
            else
                echo "  $dev STAYS read-only (could be a FAT32 mount issue)"
            fi
        fi
    fi
done

echo ""
echo "========================================"
echo " Remount complete"
echo "========================================"
echo ""
echo "New mount status:"
mount 2>/dev/null | grep -E "rw|ro" | head -20
