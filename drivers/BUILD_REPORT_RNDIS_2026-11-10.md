# RNDIS Host Module Build Report - 2026-11-10

## Status: ✅ SUCCESVOL

## Built modules

| File | Size | SHA256 |
|---------|---------|--------|
| `rndis_host-armv7-3.0.35.ko` | 154 KB | `b77837148ae92c96d00c0f3f978bb79e3ff261fda23bf10e0a3909e73c349096` |
| `usbnet-armv7-3.0.35.ko` | 226 KB | `91a777f5ee6c85ec66ff426786f1b87c726e6161b1c0f05bb4019b295156fb5e` |
| `cdc_ether-armv7-3.0.35.ko` | 143 KB | `c97a06842d2ab70e2e95e8187a08ca2772b9ffc7d90abc9e2a327a22b4798ead` |

## Vermagic (matches CMU exactly)
```
3.0.35 SMP preempt mod_unload ARMv7
```
CMU kernel: `Linux version 3.0.35 (bsp@jci) (gcc version 4.5.2) #1 SMP PREEMPT Thu Oct 27 14:55:44 PKT 2016`

## Dependencies
- `rndis_host.ko` → `usbnet, cdc_ether`
- `cdc_ether.ko` → `usbnet`
- `usbnet.ko` → (none)

**IMPORTANT:** On the CMU `usbnet` is ALREADY loaded (see /proc/modules: `usbnet 12833 1 asix`), so only `cdc_ether.ko` and `rndis_host.ko` need to be loaded.

## Build environment
- Kernel source: `/tmp/rndis-build` (kopie van `/tmp/r8152-build/linux-3.0.35`)
- Cross-compiler: `arm-linux-gnueabihf-gcc` (Debian 12.2.0-14)
- Config: Mazda linux-config-mazda + modifications

## Important fixes during build
1. **`include/linux/compiler-gcc12.h`** created as a copy of `compiler-gcc4.h` (kernel 3.0 does not know gcc12)
2. **`arch/arm/Makefile`** patched: `-march=armv7-a` → `-march=armv7-a+fp` (gcc 12 requires FPU spec with hard-float ABI)
3. Config: `CONFIG_USB_NET_RNDIS_HOST=m`, `CONFIG_USB_USBNET=m`, `CONFIG_EXPERIMENTAL=y`, `CONFIG_SMP=y`, `CONFIG_PREEMPT=y`, `CONFIG_CPU_V7=y`

## Working build commands
```bash
cd /tmp/rndis-build
cp /tmp/r8152-build/linux-3.0.35/.config .config
sed -i 's/# CONFIG_USB_USBNET is not set/CONFIG_USB_USBNET=m/' .config
sed -i 's/# CONFIG_USB_NET_RNDIS_HOST is not set/CONFIG_USB_NET_RNDIS_HOST=m/' .config
sed -i 's/CONFIG_PREEMPT_NONE=y/# CONFIG_PREEMPT_NONE is not set/' .config
sed -i 's/# CONFIG_PREEMPT is not set/CONFIG_PREEMPT=y/' .config
yes "" | make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- oldconfig
cp include/linux/compiler-gcc4.h include/linux/compiler-gcc12.h
# patch arch/arm/Makefile: armv7-a → armv7-a+fp
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- prepare modules_prepare
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- M=drivers/net/usb modules
```

## Test on CMU (still to be executed)
```bash
# Upload via base64 (rndis_host + cdc_ether needed, usbnet is already loaded)
cat cdc_ether-armv7-3.0.35.ko | base64 -w0 > /tmp/cdc_ether.b64
cat rndis_host-armv7-3.0.35.ko | base64 -w0 > /tmp/rndis.b64
# Via SSH (<CMU_IP>:36000, user root, pwd from the toolkit secrets config):
echo '<cdc_ether_base64>' | base64 -d > /tmp/cdc_ether.ko
echo '<rndis_base64>' | base64 -d > /tmp/rndis_host.ko
insmod /tmp/cdc_ether.ko
insmod /tmp/rndis_host.ko
lsmod | grep rndis
# Bind Samsung RNDIS device (04e8:6863):
echo "04e8 6863" > /sys/bus/usb/drivers/rndis_host/new_id
ls /sys/class/net/
dmesg | tail -20
```
