# Cross-compiling kernel modules for the CMU (kernel 3.0.35, ARMv7)

Merged, proven recipe from the RNDIS host and RTL8152 builds. Target:
**Linux 3.0.35, ARMv7 (i.MX6), `arm-linux-gnueabihf-gcc` (gcc 12)**.

## 1. Why cross-compile

The CMU kernel (3.0.35) predates many USB drivers: `r8152` only exists since
kernel 3.12+, and `rndis_host`/`cdc_ether` builds that ship with the CMU
can't be re-bound to Samsung's RNDIS PID without our own module. So we build
`.ko` files on a PC and `insmod` them on the car.

## 2. Hard requirements learned the hard way

The CMU kernel identity (must match exactly in `vermagic`):

```
Linux version 3.0.35 (bsp@jci) (gcc version 4.5.2) #1 SMP PREEMPT Thu Oct 27 14:55:44 PKT 2016
→ vermagic: "3.0.35 SMP preempt mod_unload ARMv7"
```

### Failure modes and their fixes (v1/v2 → v3)

| # | Symptom on `insmod` | Root cause | Fix |
|---|---|---|---|
| 1 | `Unknown symbol __aeabi_unwind_cpp_pr0` | Build config had `CONFIG_ARM_UNWIND=y` → `-funwind-tables` → unwind symbol refs. The CMU kernel has ARM_UNWIND **off** | `# CONFIG_ARM_UNWIND is not set` |
| 2 | `Unknown symbol _GLOBAL_OFFSET_TABLE_` | gcc 12 defaults to PIE → `-fPIC` implied → GOT references. Kernel modules must be non-PIC | add `-fno-pic -fno-pie -fno-PIC -fno-PIE` to `KBUILD_CFLAGS` in the top `Makefile` **and** `arch/arm/Makefile` |
| 3 | `Unknown symbol usbnet_generic_cdc_bind` | Cascade of #1+#2 (usbnet failed too); that symbol is exported by **`cdc_ether`**, not usbnet | load order: `cdc_ether` **before** `rndis_host` (`depends=usbnet,cdc_ether`) |
| 4 | `invalid module format` (-ENOEXEC) | `CONFIG_DEBUG_INFO=y` produced `.debug_*` sections; the CMU's **BusyBox insmod v1.19.2 rejects modules with debug sections** | `# CONFIG_DEBUG_INFO is not set`; keep `CONFIG_FUNCTION_TRACER=y` + `CONFIG_OLD_MCOUNT=y` so the `__mcount_loc` section exists like v74 modules |

v3 modules come out at **9–11 KB** (stripped, like the v74 stock modules);
v1/v2 were 141–152 KB with debug sections.

### Required .config diff (from a known-good base config)

```diff
# v1 (failed)                → v3 (works)
CONFIG_PREEMPT_NONE=y         → CONFIG_PREEMPT=y + CONFIG_PREEMPT_RCU=y
CONFIG_ARM_UNWIND=y           → # CONFIG_ARM_UNWIND is not set
# CONFIG_FRAME_POINTER        → CONFIG_FRAME_POINTER=y
CONFIG_DEBUG_INFO=y           → # CONFIG_DEBUG_INFO is not set      ← critical
# CONFIG_FUNCTION_TRACER      → CONFIG_FUNCTION_TRACER=y           ← for __mcount_loc
CONFIG_OLD_MCOUNT=y           → CONFIG_OLD_MCOUNT=y
# CONFIG_USB_USBNET           → CONFIG_USB_USBNET=m
# CONFIG_USB_NET_CDCETHER     → CONFIG_USB_NET_CDCETHER=m
# CONFIG_USB_NET_RNDIS_HOST   → CONFIG_USB_NET_RNDIS_HOST=m
CONFIG_SMP=y                  → CONFIG_SMP=y     (needed for vermagic)
CONFIG_CPU_V7=y               → CONFIG_CPU_V7=y
# CONFIG_MODVERSIONS          → # CONFIG_MODVERSIONS is not set   (match CMU)
```

### Toolchain quirks (gcc 12 vs kernel 3.0)

- `include/linux/compiler-gcc12.h` doesn't exist in 3.0.35:
  `cp include/linux/compiler-gcc4.h include/linux/compiler-gcc12.h`
- Hard-float ABI requires an explicit FPU spec; gcc 12 rejects plain
  `-march=armv7-a`:
  ```sh
  sed -i 's/-march=armv7-a,/-march=armv7-a+fp,/;
          s/-Wa$(comma)-march=armv7-a)/-Wa$(comma)-march=armv7-a+fp)/' arch/arm/Makefile
  ```

## 3. Reproducible build

```sh
# 0. toolchain
apt install gcc-arm-linux-gnueabihf   # Debian 12 → gcc 12.2

# 1. clean tree
rm -rf /tmp/mod-build
cp -a linux-3.0.35 /tmp/mod-build && cd /tmp/mod-build
cp /path/to/known-good/.config .config      # base with SMP=y, CPU_V7=y

# 2. patch config (see diff above)
sed -i \
  -e 's/^CONFIG_PREEMPT_NONE=y/# CONFIG_PREEMPT_NONE is not set/' \
  -e 's/^# CONFIG_PREEMPT is not set/CONFIG_PREEMPT=y/' \
  -e 's/^# CONFIG_PREEMPT_RCU is not set/CONFIG_PREEMPT_RCU=y/' \
  -e 's/^CONFIG_ARM_UNWIND=y/# CONFIG_ARM_UNWIND is not set/' \
  -e 's/^CONFIG_DEBUG_INFO=y/# CONFIG_DEBUG_INFO is not set/' \
  -e 's/^# CONFIG_FUNCTION_TRACER is not set/CONFIG_FUNCTION_TRACER=y/' \
  -e 's/^# CONFIG_USB_USBNET is not set/CONFIG_USB_USBNET=m/' \
  .config
cat >> .config <<'EOF'
CONFIG_FRAME_POINTER=y
CONFIG_USB_NET_CDCETHER=m
CONFIG_USB_NET_RNDIS_HOST=m
CONFIG_USB_NET_CDC_NCM=m
CONFIG_DYNAMIC_FTRACE=y
CONFIG_OLD_MCOUNT=y
EOF

# 3. non-interactive oldconfig
yes '' | make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- oldconfig

# 4. gcc-12 compat + arch flags
cp include/linux/compiler-gcc4.h include/linux/compiler-gcc12.h
sed -i 's/-march=armv7-a,/-march=armv7-a+fp,/; s/-Wa$(comma)-march=armv7-a)/-Wa$(comma)-march=armv7-a+fp)/' arch/arm/Makefile
# add -fno-pic -fno-pie -fno-PIC -fno-PIE to KBUILD_CFLAGS in ./Makefile
# and -fno-pic -fno-pie to KBUILD_CFLAGS in arch/arm/Makefile

# 5. build
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- prepare modules_prepare
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- M=drivers/net/usb modules

# 6. VERIFY before shipping (all must pass)
arm-linux-gnueabihf-readelf -s  drivers/net/usb/rndis_host.ko | grep -c 'aeabi_unwind_cpp\|GLOBAL_OFFSET'   # → 0
arm-linux-gnueabihf-readelf -p .modinfo drivers/net/usb/rndis_host.ko | grep vermagic   # → 3.0.35 SMP preempt mod_unload ARMv7
arm-linux-gnueabihf-readelf -S  drivers/net/usb/rndis_host.ko | grep -c debug            # → 0
arm-linux-gnueabihf-readelf -S  drivers/net/usb/rndis_host.ko | grep -c mcount           # → ≥1
```

Built artifacts (v3, proven on the CMU):

| File | Size | SHA256 |
|---|---|---|
| `rndis_host-armv7-3.0.35-v3.ko` | 10.6 KB | `c6b04f983ef3d29db755278f502b3306ec3ded7e3282db9ab061b58693020e09` |
| `cdc_ether-armv7-3.0.35-v3.ko` | 9.2 KB | `51065683c5aae6b736738c7cafcfebb0f058d8f6754c8457bae49cb5f4661f9b` |
| `usbnet-armv7-3.0.35-v3.ko` | 25.4 KB | `11d3081cf719828f9a1239800294519807d8f4b7201f9299ea5251530f4d268f` |

## 4. Proven load sequence on the CMU

```sh
insmod /data_persist/mzd-toolkit/wifi/cdc-modules/cdc_ether.ko   # exit 0
insmod /tmp/rndis_host-armv7-3.0.35-v3.ko                        # exit 0
lsmod | grep rndis      # rndis_host / cdc_ether / usbnet Live
echo "04e8 6863" > /sys/bus/usb/drivers/rndis_host/new_id         # exit 0 → usb0 appears
```

(`usbnet` is already loaded on the CMU via `asix`, so only `cdc_ether` +
`rndis_host` need loading.)

## 5. Uploading .ko files to the CMU

BusyBox `base64 -d` chokes on one long heredoc line ("truncated base64 input").
Use **echo-per-line** with 76-char wrapped base64, or the toolkit's ~3000-char
chunked upload:

```sh
# PC:
base64 -w76 rndis_host-armv7-3.0.35-v3.ko > /tmp/r.b64
# over SSH, for each line L in r.b64:   echo "L" >> /tmp/r.b64
# CMU:
base64 -d /tmp/r.b64 > /tmp/rndis_host.ko
```

## 6. RTL8152 notes

The `r8152` driver is absent from kernel 3.0.35 (added in 3.12). Options:

1. **`cdc_ether` + `new_id` bind** (see NETWORKING.md) - the RTL8152 partially
   implements CDC-Ethernet, so `cdc_ether` drives it without `r8152` at all.
   This is the proven path used by the toolkit; **no `r8152` module is shipped
   in this repo**.
2. **Cross-compile `r8152` yourself** from a newer kernel source with the gcc-12
   recipe above (untested for `r8152`; if the module reports `Unknown symbol` /
   `Invalid module format`, fall back to the `cdc_ether` bind or an ASIX dongle).
3. Cross-compile attempts with gcc 9/4.8/4.9 all failed (missing
   `compiler-gccN.h`, Docker rate limits, EOL repos) - use the gcc-12 recipe
   above instead.

## 7. Lessons learned (checklist)

1. gcc-12 defaults to PIE → always `-fno-pic -fno-pie` for kernel modules.
2. `CONFIG_ARM_UNWIND` must match the target kernel (CMU: **off**).
3. `CONFIG_DEBUG_INFO` must be **off** — BusyBox insmod rejects `.debug_*` sections.
4. `CONFIG_FUNCTION_TRACER=y` + `CONFIG_OLD_MCOUNT=y` for the `__mcount_loc` section.
5. `vermagic` must be exactly `3.0.35 SMP preempt mod_unload ARMv7`.
6. Load order: `usbnet` → `cdc_ether` → `rndis_host`.
7. Upload via line-by-line base64 or ~3000-char chunks, never one giant heredoc.
8. Always `readelf`-verify symbols/sections/vermagic **before** shipping to the car.
