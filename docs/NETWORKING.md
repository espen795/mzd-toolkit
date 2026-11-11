# Networking — eth0/eth1, USB dongles, tethering

Wired and tethered networking on the CMU. Verified on v59.00.502.

## 1. The golden rule: never touch `eth0`

- `eth0` is the i.MX6's internal MAC with **no external PHY** — it is not
  physically connected to anything. Bringing it up/down or reconfiguring it
  **corrupts routing and switch state** on the board.
- All external networking must use **`eth1`** (USB ethernet dongle) or
  **`usb0`** (phone tethering).

## 2. USB ethernet dongles → `eth1`

The CMU has EHCI-only USB 2.0 (no xHCI). Two dongle chipsets are proven:

| Dongle | USB ID | Driver | Notes |
|---|---|---|---|
| **ASIX AX88772** | `0b95:772a` | `asix` — **built into the CMU kernel**, works out of the box | log line: `asix 2-1.3:1.0: eth1: register 'asix' at usb-fsl-ehci.1-1.3, ASIX AX88772 USB 2.0 Ethernet` |
| **Realtek RTL8152** | `0bda:8152` | `cdc_ether` + `new_id` bind (no `r8152` module is shipped or needed) | RTL8152 speaks CDC-Ethernet but is **not in `cdc_ether`'s default device table** |

### RTL8152 bring-up (the reliable sequence)

```sh
# 1. load cdc_ether (bundled in wifi/cdc-modules/)
insmod /data_persist/mzd-toolkit/wifi/cdc-modules/cdc_ether.ko
# 2. bind the dongle manually via sysfs
echo "0bda 8152" > /sys/bus/usb/drivers/cdc_ether/new_id
# 3. wait ~2 s, then configure
ifconfig eth1 192.168.0.2 netmask 255.255.255.0 up
```

Observed behavior: the dongle is detected in USB logs
(`idVendor=0bda, idProduct=8152`) but no interface appears until `cdc_ether`
is loaded **and** the `new_id` bind is done. After a USB-stack reset the bind
is forgotten — the autorun script must redo steps 1–2 on every boot.

⚠️ **Registration can take up to ~60 s** after boot before `eth1` appears —
don't panic, poll `ifconfig -a`.

### IP configuration

Static (toolkit default in `net/autostart-eth1-ssh.sh`):

```sh
ifconfig eth1 192.168.0.2 netmask 255.255.255.0 up
route add default gw 192.168.0.1   # if a gateway is needed
```

DHCP: `net/eth1-dhcp.sh` (runs `udhcpc -i eth1`); `net/eth.sh up|down|status|gw`
for manual control. Use `192.168.0.x` as your generic lab subnet — pick
something that doesn't clash with your home LAN if the CMU is also on WiFi.

## 3. USB tethering from an Android phone → `usb0`

- Put the CMU USB role switch in **host mode**:
  ```sh
  echo 1 > /proc/driver/usbroleswitch/0/mode
  ```
- Enable USB tethering on the phone. Samsung phones expose two USB
  configurations:
  - **`04e8:6863` — RNDIS** → gives a `usb0` interface. Requires the
    `rndis_host` module — use the **v3 build** from DRIVER-COMPILATION.md
    (v1/v2 fail to load).
  - `04e8:6860` — AOA/MTP → **no network interface** (`usb0` does not appear).
- Load order matters: `cdc_ether` **before** `rndis_host`
  (`rndis_host` depends on `cdc_ether`'s `usbnet_generic_cdc_bind` export;
  `usbnet` is already loaded via `asix` on the CMU):

```sh
insmod /data_persist/mzd-toolkit/wifi/cdc-modules/cdc_ether.ko
insmod /tmp/rndis_host-armv7-3.0.35-v3.ko
echo "04e8 6863" > /sys/bus/usb/drivers/rndis_host/new_id
# proven result:
#   usbcore: registered new interface driver rndis_host
#   lsmod: rndis_host / cdc_ether / usbnet
ifconfig usb0 up
udhcpc -i usb0        # the phone assigns 192.168.42.x/24 style addresses
```

- **iOS tethering is not supported** — the kernel lacks the `iph_eth` driver.
- CDC-ECM/NCM Android tethering (`usb-tether.sh`) also works and only needs the
  stock `cdc_ether`/`cdc_ncm` modules.

## 4. Uploading files to the CMU over the network

BusyBox `base64 -d` fails on long single-line heredocs ("truncated base64
input"). Reliable method — echo line by line (76-char wrapped base64):

```sh
# on the PC:
base64 -w76 file.ko > file.b64
# over SSH, per line:
#   echo "<line>" >> /tmp/file.b64
# then on the CMU:
base64 -d /tmp/file.b64 > /tmp/file.ko
```

The toolkit prefers a **chunked upload (~3000 chars per chunk)** to stay well
clear of any line-length limits.

## 5. Firewall

If you run your own sshd, add a single ACCEPT rule — do **not** set
`-P INPUT ACCEPT`:

```sh
iptables -I INPUT --dport 36000 -j ACCEPT    # or your chosen port
```

(The old toolkit versions that set the whole INPUT policy to ACCEPT were a
security regression; current releases only open the one port.)

## 6. Autostart

`net/autostart-eth1-ssh.sh` (called from the autorun hook) does, at every boot:

1. remount the persist paths rw,
2. create the sshd priv-sep dirs,
3. load `cdc_ether` + bind `0bda 8152`,
4. set `eth1` to `192.168.0.2/24`,
5. start sshd on port **36000**.

`net/eth1-dhcp.sh static` switches back to the static address after a DHCP run.
