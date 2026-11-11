# Firmware — versions, layout, rollback

## 1. Version numbering

Mazda CMU firmware versions look like `59.00.502` or `74.00.324A`:

- First field = major platform generation (`59` = the v59 line shipped in
  2017-era cars, `70`/`74` = later generations).
- The full build identifier is embedded in the image, e.g.:

```
MAZ_CMU-150_59.00.502   flavor cmu150_EU   build 2017-05-09
```

- Adjacent builds exist within a line (the v59 image records `prior
  58.78.006`, `next 59.00.503`).
- The suffix letter on v74 builds (e.g. `74.00.324A`) is a regional/variant
  marker (NA vs EU hardware is identical).

The authoritative component list is **`/jci/version.ini`** — it contains every
component's version (`JCI_BLM_*`, `CPP_*`, `GUI_*`, `MMUI_*`, `VUI_*`, …). The
toolkit's `tools/firmware-info.sh` / dump scripts capture it in `SUMMARY.txt`,
which makes it diff-able between firmware generations.

## 2. The v59.00.502 USB-autorun patch — and what it means

Starting with **v59.00.502**, Mazda patched out the USB autorun mechanism that
earlier firmwares had. Consequence:

> You cannot simply drop a `autorun` script on a USB stick and have the CMU run
> it. Autorun must first be **re-enabled via a serial or ID7-based method**.

The established community methods:

- https://github.com/Trevelopment/cmu-autorun — ID7 recovery zip that installs an
  `autorun` script into `/data_persist/dev/bin/`
- https://github.com/mzd-evo/mzd-connect-1-root — root-access research for the
  MZD Connect 1, including the MP3/XSS vector used to unlock ID7 on v59.00.502

Once autorun is in place, the hook chain is:

```
/jci/scripts/stage_wifi.sh  →  /data_persist/dev/bin/autorun
```

(see ARCHITECTURE-CMU.md). This toolkit's `install.sh` **extends** that
`autorun` (with `.orig` backup + fail-counter); it does not create the initial
hook.

## 3. v59 vs v74 — what differs (and why we recommend v59)

Same kernel (3.0.35), same wpa_supplicant (v2.6), same driver backport — but
different WiFi chip firmware and different autorun/USB policy:

| Component | v59 | v74 | Note |
|---|---|---|---|
| wl12xx station firmware (`wl128x-fw-4-sr.bin`) | **Rev 7.3.10.10.136** | **FRev 7.3.10.0.142** | v74 is newer — but on our hardware it produced **more** watchdog crashes, not fewer |
| wl12xx multi-role firmware (`wl128x-fw-4-mr.bin`) | Rev 7.3.10.10.136 | Rev 7.5.7.0.50 | v74 much newer |
| USB autorun | patched out | blocked; serial access is the only way in | v74 removes the USB tweak path entirely |
| SSH | stock sshd on port 36000 | same | see SSH-V59.md |

**WiFi stability:** the wl12xx watchdog panic root cause (WIFI.md) is *worse*
on v74 in practice — the TX-flush/hardware-watchdog recovery loop was observed
on both, and the v74 `sr.bin` (.142) did **not** fix it on this board's NVS
calibration. The toolkit ships `wifi/rollback-firmware-v59.sh` (also reachable
as **Tools → menu option 10**): rollback to v59 is the recommended stable
configuration. The board-specific NVS calibration (`wl1271-nvs.bin`) must always
stay the one belonging to your own unit.

## 4. version.ini component list

`/jci/version.ini` holds one entry per subsystem, for example
`JCI_BLM_*`, `CPP_*`, `GUI_*`, `MMUI_*`, `VUI_*`, plus flags like
`JCI_VR_PRESENT="NO"`. Use it to:

- confirm the exact firmware you are on,
- diff two firmware generations component-by-component (the v59 dump's
  `SUMMARY.txt` is directly diff-able against a v74 extract),
- detect region flavor (`cmu150_EU` etc.).

## 5. Build date strings

Build dates appear both in the image name (`…_59.00.502`, build `2017-05-09`)
and in the kernel banner (`Thu Oct 27 14:55:44 PKT 2016`). When comparing two
dumps, always compare **both** — the kernel banner date and the
`version.ini`/`SUMMARY.txt` build date are independent.

## 6. Rollback procedure

1. Menu → **Tools → 10** (`wifi/rollback-firmware-v59.sh`), or run the script
   directly on the CMU.
2. It restores the v59 WiFi firmware set (`wl128x-fw-4-sr.bin` Rev
   7.3.10.10.136 etc.) while **keeping your board's `wl1271-nvs.bin`**.
3. Reboot the CMU (Mute + Navi, 10 s).
4. Verify with `wifi/check-firmware.sh` (prints FRev + sha256 of the loaded
   firmware) and `dmesg | grep -c "watchdog interrupt"` over a drive.
