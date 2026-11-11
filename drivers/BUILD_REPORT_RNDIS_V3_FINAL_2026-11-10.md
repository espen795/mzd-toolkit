# RNDIS Host Module Build Report v3 - DEFINITIEF - 2026-11-10

## Status: ✅ **WORKING ON CMU** — `rndis_host` loaded, `new_id` bind accepted

## End result on CMU (proven)
```
$ insmod /tmp/rndis_clean.ko
CLEAN_EXIT=0
$ lsmod | grep rndis
rndis_host 4659 0 - Live 0x7f3d3000
cdc_ether 3062 1 rndis_host, Live 0x7f3cf000
usbnet 12833 3 rndis_host,cdc_ether,asix, Live 0x7f2ac000
$ dmesg | tail
usbcore: registered new interface driver rndis_host
$ echo "04e8 6863" > /sys/bus/usb/drivers/rndis_host/new_id
BIND_EXIT=0   ← SUCCES
```

## Root Causes of v1 failure (all 3 solved)

| # | Error | Root Cause | Fix |
|---|-------|-----------|-----|
| 1 | `Unknown symbol __aeabi_unwind_cpp_pr0` | v1 config had `CONFIG_ARM_UNWIND=y` → `-funwind-tables` → unwind refs. CMU kernel has ARM_UNWIND **OFF** | `CONFIG_ARM_UNWIND` → not set |
| 2 | `Unknown symbol _GLOBAL_OFFSET_TABLE_` | Debian gcc-12 default PIE → implicit `-fPIC` → GOT refs in module. Kernel modules must be non-PIC | `-fno-pic -fno-pie -fno-PIC -fno-PIE` in `Makefile` + `arch/arm/Makefile` |
| 3 | `Unknown symbol usbnet_generic_cdc_bind` | Cascade of #1+#2: usbnet.ko failed too. `usbnet_generic_cdc_bind` is exported by **cdc_ether.ko** (not usbnet) | Load order: cdc_ether BEFORE rndis_host. `depends=usbnet,cdc_ether` |

## Root Cause of v2 "invalid module format" (solved in v3)

v2 modules were 141-152 KB with **debug sections** (`.debug_info`, `.debug_frame`, etc.) because `CONFIG_DEBUG_INFO=y`. The CMU kernel (BusyBox insmod v1.19.2) cannot load modules with debug sections → `invalid module format` (-ENOEXEC).

**Fix:** `CONFIG_DEBUG_INFO` → not set + `CONFIG_FUNCTION_TRACER=y` + `CONFIG_OLD_MCOUNT=y` (for `__mcount_loc` section, like v74 modules).

v3 modules are 9-11 KB (stripped, like v74).

## Final config (critical difference with v1)

```diff
# v1 (failed)               → v3 (working)
CONFIG_PREEMPT_NONE=y       → CONFIG_PREEMPT=y + CONFIG_PREEMPT_RCU=y
CONFIG_ARM_UNWIND=y         → # CONFIG_ARM_UNWIND is not set
# CONFIG_FRAME_POINTER       → CONFIG_FRAME_POINTER=y
CONFIG_DEBUG_INFO=y         → # CONFIG_DEBUG_INFO is not set   ← CRITICAL for v3
# CONFIG_FUNCTION_TRACER    → CONFIG_FUNCTION_TRACER=y         ← for __mcount_loc
CONFIG_OLD_MCOUNT=y         → CONFIG_OLD_MCOUNT=y
# CONFIG_USB_USBNET          → CONFIG_USB_USBNET=m
# CONFIG_USB_NET_CDCETHER    → CONFIG_USB_NET_CDCETHER=m
# CONFIG_USB_NET_RNDIS_HOST  → CONFIG_USB_NET_RNDIS_HOST=m
CONFIG_SMP=y                → CONFIG_SMP=y (from r8152 base, needed for vermagic)
CONFIG_CPU_V7=y             → CONFIG_CPU_V7=y
# CONFIG_MODVERSIONS         → # CONFIG_MODVERSIONS is not set (match CMU)
```

## Final build commands (reproducible)

```bash
# 1. Schone source
rm -rf /tmp/rndis-build
cp -a /tmp/r8152-build/linux-3.0.35 /tmp/rndis-build
cd /tmp/rndis-build

# 2. Start with r8152 .config (has SMP=y, CPU_V7=y, VEXPRESS_CA9X4)
cp /tmp/r8152-build/linux-3.0.35/.config .config

# 3. Patch config
sed -i \
  -e 's/^CONFIG_PREEMPT_NONE=y/# CONFIG_PREEMPT_NONE is not set/' \
  -e 's/^# CONFIG_PREEMPT is not set/CONFIG_PREEMPT=y/' \
  -e 's/^# CONFIG_PREEMPT_RCU is not set/CONFIG_PREEMPT_RCU=y/' \
  -e 's/^CONFIG_ARM_UNWIND=y/# CONFIG_ARM_UNWIND is not set/' \
  -e 's/^CONFIG_DEBUG_INFO=y/# CONFIG_DEBUG_INFO is not set/' \
  -e 's/^# CONFIG_FUNCTION_TRACER is not set/CONFIG_FUNCTION_TRACER=y/' \
  -e 's/^# CONFIG_USB_USBNET is not set/CONFIG_USB_USBNET=m/' \
  .config
cat >> .config << 'EOF'
CONFIG_FRAME_POINTER=y
CONFIG_USB_NET_CDCETHER=m
CONFIG_USB_NET_RNDIS_HOST=m
CONFIG_USB_NET_CDC_NCM=m
CONFIG_DYNAMIC_FTRACE=y
CONFIG_OLD_MCOUNT=y
EOF

# 4. Oldconfig
yes '' | make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- oldconfig

# 5. Compiler compat + arch flags
cp include/linux/compiler-gcc4.h include/linux/compiler-gcc12.h
sed -i 's/-march=armv7-a,/-march=armv7-a+fp,/; s/-Wa$(comma)-march=armv7-a)/-Wa$(comma)-march=armv7-a+fp)/' arch/arm/Makefile

# 6. PIC/PIE fix (CRITICAL for _GLOBAL_OFFSET_TABLE_)
# In top Makefile, voeg toe aan KBUILD_CFLAGS := ...:
#   -fno-pic -fno-pie -fno-PIC -fno-PIE
# In arch/arm/Makefile, voeg toe aan KBUILD_CFLAGS += ...:
#   -fno-pic -fno-pie

# 7. Build
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- prepare modules_prepare
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- M=drivers/net/usb modules

# 8. Verify (MUST all be empty/0 except vermagic)
arm-linux-gnueabihf-readelf -s drivers/net/usb/rndis_host.ko | grep -c 'aeabi_unwind_cpp\|GLOBAL_OFFSET'  # → 0
arm-linux-gnueabihf-readelf -p .modinfo drivers/net/usb/rndis_host.ko | grep vermagic  # → 3.0.35 SMP preempt mod_unload ARMv7
arm-linux-gnueabihf-readelf -S drivers/net/usb/rndis_host.ko | grep -c debug  # → 0
arm-linux-gnueabihf-readelf -S drivers/net/usb/rndis_host.ko | grep -c mcount  # → ≥1
```

## Built v3 modules

| File | Size | SHA256 |
|---------|---------|--------|
| `rndis_host-armv7-3.0.35-v3.ko` | 10.6 KB | `c6b04f983ef3d29db755278f502b3306ec3ded7e3282db9ab061b58693020e09` |
| `cdc_ether-armv7-3.0.35-v3.ko` | 9.2 KB | `51065683c5aae6b736738c7cafcfebb0f058d8f6754c8457bae49cb5f4661f9b` |
| `usbnet-armv7-3.0.35-v3.ko` | 25.4 KB | `11d3081cf719828f9a1239800294519807d8f4b7201f9299ea5251530f4d268f` |

## CMU load sequence (PROVEN WORKING)

```bash
# On CMU (usbnet is already loaded via asix):
# 1. Load v74 cdc_ether (from toolkit) OR our cdc_v3:
insmod /data_persist/mzd-toolkit/wifi/cdc-modules/cdc_ether.ko   # v74 works
# 2. Load our rndis_host v3:
insmod /tmp/rndis_clean.ko    # exit 0!
# 3. Bind Samsung RNDIS:
echo "04e8 6863" > /sys/bus/usb/drivers/rndis_host/new_id   # exit 0!
# 4. Check:
lsmod | grep rndis   # rndis_host loaded
dmesg | grep rndis   # "usbcore: registered new interface driver rndis_host"
```

## Upload method (IMPORTANT)

The CMU's BusyBox `base64 -d` fails on "truncated base64 input" with a heredoc containing 1 long line. **Use echo-per-line:**

```bash
# Generate locally:
base64 -w76 rndis_host-armv7-3.0.35-v3.ko > /tmp/rndis.b64
# Upload via SSH stdin with a script that echoes each line:
# echo "<line>" >> /tmp/r.b64  (per 76-char line)
# base64 -d /tmp/r.b64 > /tmp/rndis.ko
```

## Lessons learned

1. **gcc-12 default PIE** generates `_GLOBAL_OFFSET_TABLE_` refs → always `-fno-pic -fno-pie` for kernel modules
2. **CONFIG_ARM_UNWIND** must match the target kernel (CMU: OFF)
3. **CONFIG_DEBUG_INFO=y** generates debug sections that BusyBox insmod refuses → turn OFF for CMU modules
4. **CONFIG_FUNCTION_TRACER=y** needed for `__mcount_loc` section (v74 modules have this)
5. **Upload corruption**: heredoc with long base64 lines fails on CMU → use echo-per-line or split in chunks
6. **Load order**: `cdc_ether` VÓÓR `rndis_host` (rndis depends op cdc_ether's `usbnet_generic_cdc_bind` export)
