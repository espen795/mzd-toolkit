# RNDIS Host Module Build Report v2 - 2026-11-10

## Status: ✅ BUILT — symbols fixed, ready for CMU test

## Root Causes of the previous (v1) failure

| Error | Root Cause | Fix in v2 |
|-------|-----------|-----------|
| `Unknown symbol __aeabi_unwind_cpp_pr0` | v1 build had `CONFIG_ARM_UNWIND=y` (from r8152 config) → generated unwind tables → ref to `__aeabi_unwind_cpp_pr0` which CMU kernel does not have (CMU has `CONFIG_ARM_UNWIND` OFF) | `CONFIG_ARM_UNWIND` turned off in .config |
| `Unknown symbol _GLOBAL_OFFSET_TABLE_` | Debian gcc-12 default = PIE/PIC (implicit `-fPIC`) → generates GOT refs. Kernel modules must be `-fno-pic -fno-pie` | `-fno-pic -fno-pie -fno-PIC -fno-PIE` added to `KBUILD_CFLAGS` in top `Makefile` AND `arch/arm/Makefile` |
| `Unknown symbol usbnet_generic_cdc_bind` | Comes from cascade: usbnet.ko also failed (see above) so rndis_host could not resolve the symbol | Solved by building usbnet correctly; `usbnet_generic_cdc_bind` is exported by **cdc_ether.ko** (not usbnet!) → `depends=usbnet,cdc_ether` is correct |

## Config diff v1 → v2 (critical changes)

```diff
# v1 (failed)                     →  v2 (working)
CONFIG_PREEMPT_NONE=y             →  CONFIG_PREEMPT=y + CONFIG_PREEMPT_RCU=y
CONFIG_ARM_UNWIND=y               →  # CONFIG_ARM_UNWIND is not set
# CONFIG_FRAME_POINTER is not set →  CONFIG_FRAME_POINTER=y
# CONFIG_USB_USBNET is not set    →  CONFIG_USB_USBNET=m
(nieuw)                           →  CONFIG_USB_NET_RNDIS_HOST=m
(nieuw)                           →  CONFIG_USB_NET_CDCETHER=m
(nieuw)                           →  CONFIG_USB_NET_CDC_NCM=m
CONFIG_SMP=y                      →  CONFIG_SMP=y (kept from r8152 base)
CONFIG_CPU_V7=y                   →  CONFIG_CPU_V7=y (kept)
# CONFIG_MODVERSIONS is not set   →  # CONFIG_MODVERSIONS is not set (behouden, match CMU)
```

**IMPORTANT:** v2 starts from the **r8152 .config** (which had SMP=y, CPU_V7=y, VEXPRESS — needed for SMP vermagic) with the USB/PREEMPT/FRAME_POINTER/ARM_UNWIND fixes from the mazda config.

## Build flags fix (PIC/PIE)

In top `Makefile`:
```makefile
KBUILD_CFLAGS   := -Wall ... \
		   -fno-delete-null-pointer-checks \
		   -fno-pic -fno-pie -fno-PIC -fno-PIE
```

In `arch/arm/Makefile`:
```makefile
KBUILD_CFLAGS	+=$(CFLAGS_ABI) ... -msoft-float -Uarm -fno-pic -fno-pie
```

## Build commands (reproducible)

```bash
# 1. Schone kopie van kernel source
rm -rf /tmp/rndis-build
cp -a /tmp/r8152-build/linux-3.0.35 /tmp/rndis-build
cd /tmp/rndis-build

# 2. Start with r8152 config (has SMP=y, CPU_V7=y, VEXPRESS)
cp /tmp/r8152-build/linux-3.0.35/.config .config

# 3. Patch critical options
sed -i \
  -e 's/^CONFIG_PREEMPT_NONE=y/# CONFIG_PREEMPT_NONE is not set/' \
  -e 's/^# CONFIG_PREEMPT is not set/CONFIG_PREEMPT=y/' \
  -e 's/^# CONFIG_PREEMPT_RCU is not set/CONFIG_PREEMPT_RCU=y/' \
  -e 's/^CONFIG_ARM_UNWIND=y/# CONFIG_ARM_UNWIND is not set/' \
  -e 's/^# CONFIG_USB_USBNET is not set/CONFIG_USB_USBNET=m/' \
  .config
# Voeg toe (als ze ontbreken):
cat >> .config << 'EOF'
CONFIG_FRAME_POINTER=y
CONFIG_USB_NET_CDCETHER=m
CONFIG_USB_NET_RNDIS_HOST=m
CONFIG_USB_NET_CDC_NCM=m
EOF

# 4. Oldconfig (default answers)
yes '' | make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- oldconfig

# 5. Compiler compat: gcc12 header
cp include/linux/compiler-gcc4.h include/linux/compiler-gcc12.h

# 6. Arch flags: armv7-a+fp for hard-float gcc12
sed -i 's/-march=armv7-a,/-march=armv7-a+fp,/; s/-Wa$(comma)-march=armv7-a)/-Wa$(comma)-march=armv7-a+fp)/' arch/arm/Makefile

# 7. PIC/PIE fix in top Makefile
#    Voeg toe aan KBUILD_CFLAGS := ... : -fno-pic -fno-pie -fno-PIC -fno-PIE
# 8. PIC/PIE fix in arch/arm/Makefile
#    Voeg toe aan KBUILD_CFLAGS += ... : -fno-pic -fno-pie

# 9. Prepare
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- prepare modules_prepare

# 10. Build modules
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- M=drivers/net/usb modules
```

## Built modules (v2)

| File | Size | SHA256 |
|---------|---------|--------|
| `rndis_host-armv7-3.0.35-v2.ko` | 152 KB | `bfe571a97480102d55396179f2116ad3290abc006a5fe0663e21cbc7409018f8` |
| `usbnet-armv7-3.0.35-v2.ko` | 223 KB | `b4c1fbb603f91033854512e715032f1824adffa90ef765e10389a4badaf87e9a` |
| `cdc_ether-armv7-3.0.35-v2.ko` | 141 KB | `e87e6f056511a9bbee3bdb3b38796603e278b684025d7886ab328b219e814183` |

## Verification results

### ✅ No more `__aeabi_unwind_cpp_pr0`
```
arm-linux-gnueabihf-readelf -s rndis_host.ko | grep aeabi → (empty)
arm-linux-gnueabihf-readelf -s usbnet.ko | grep aeabi → only __aeabi_uidiv, __aeabi_uidivmod (these ARE in CMU kernel, same as v74 modules)
```

### ✅ No more `_GLOBAL_OFFSET_TABLE_`
```
arm-linux-gnueabihf-readelf -s *.ko | grep GLOBAL_OFFSET → (empty for all 3)
```

### ✅ Vermagic matches CMU exactly
```
3.0.35 SMP preempt mod_unload ARMv7
```

### ✅ Depends correct
- `rndis_host.ko` → `depends=usbnet,cdc_ether`
- `cdc_ether.ko` → `depends=usbnet`
- `usbnet.ko` → `depends=` (none)

### ✅ `usbnet_generic_cdc_bind` resolved via cdc_ether
- `usbnet_generic_cdc_bind` is exported by `cdc_ether.ko` (`__ksymtab_usbnet_generic_cdc_bind`)
- `rndis_host.ko` has it as UND → resolved when insmod cdc_ether BEFORE rndis_host

## CMU load order (IMPORTANT)

On the CMU `usbnet` is ALREADY loaded (asix). Load only:

```bash
# 1. Upload via base64 (see connect script)
# 2. On CMU:
insmod /tmp/cdc_ether_v2.ko    # FIRST (exports usbnet_generic_cdc_bind)
insmod /tmp/rndis_host_v2.ko   # THEN (depends on cdc_ether + usbnet)
lsmod | grep -E 'rndis|cdc_ether'
# Bind Samsung RNDIS (04e8:6863):
echo "04e8 6863" > /sys/bus/usb/drivers/rndis_host/new_id
ls /sys/class/net/
dmesg | tail -20
```

**NOTE:** If usbnet is already loaded with a different build, cdc_ether cannot bind to our usbnet symbols. In that case: use the **v74 cdc_ether.ko** (from toolkit/wifi/cdc-modules/) together with our **rndis_host-v2.ko**, OR load our usbnet-v2 first (if the loaded usbnet can be removed: `rmmod usbnet` if asix is not in use).
