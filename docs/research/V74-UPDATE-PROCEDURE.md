# Safe update procedure to v74.00.324A -- Mazda MZD Connect (CMU-150)

**Source:** community-verified procedure (Mazda3Revolution user "ASH8", thread "CONNECT Update Firmware"), adopted 2026-11-16.
**Status:** treated as the authoritative procedure for v74.00.324A updates.
**Verified update file:** `cmu150_EU_74.00.324A_update.up` (2.3 GB, MD5 verified: `9b841bc807a5010a8652bb3b9e894f91`)

---

## 1. What is v74.00.324A?

- **Final and last firmware** for the Gen 6 Mazda MZD Connect (CMU-150). No new standalone updates are coming.
- Contains ALL code of v55, v56, v58, v59, v70 -- 140+ cumulative bugfixes since v56.
- **Since 2023, v70.00.100 is NO LONGER needed as an intermediate step.** If your current firmware is >= 56.00.100 (e.g. v59.00.502A), go directly to v74.00.324A.
- It is a **ONE-FILE update** -- the failsafe is embedded in the `.up` file and installs automatically. No separate `failsafe.up` or `reinstall.up` file is needed for v74.

---

## 2. Critical preconditions (MUST DOs 1-7)

| # | Requirement | Details |
|---|---|---|
| 1 | **Car battery strong** | Max 4 years old, or connect a 12V charger during the update. Weak battery = brick risk. Test for free at an auto parts store. Or: drive 20 min during the day without loads (lights, music, fan), then update immediately. Alternative: second 12V battery in parallel with jumper cables (red-red, black-black). |
| 2 | **Press the pedals every <20 min** | Brake (automatic) or clutch (manual). Set a countdown timer to 18 min. If the CMU powers off during flashing = brick. |
| 3 | **USB flash drive <=16GB FAT32** (NOT exFAT!) | Freshly formatted. Only the `.up` file on it, no other files/folders/images. Do NOT use a micro-SD in an adapter. 2017+ models also accept 32GB. Use USB drives with an LED indicator. Recommended: Kingston DataTraveler 8GB. Use the **TOP USB port**, leave the bottom one empty. |
| 4 | **Parking brake ON** | Including eBrake. |
| 5 | **Remove the navigation SD card** | Only while the car is OFF. Reinsert the SD card only AFTER the update is 100% complete. Bootloop after update = SD card was still in the car during the update. |
| 6 | **Key fob in the car** | Leave it in the console. |
| 7 | **Engine NOT running** | Engine on = PCM talks to IC and CMU -> can block read/write -> stall or brick. Mazda dealer instructions say the same. |

## 3. Additional preparation

- **Remove ALL USB cables, Bluetooth and WiFi connections** from phones BEFORE starting.
- **Remove the Mazda pairing** from your phone, turn Bluetooth OFF on all paired phones.
- **Radio ON, low volume** -- you must be able to hear it.
- **Remove dashcam and other USB devices.**
- **Do NOT download directly to USB** -- download to a PC desktop first, then copy/paste the `.up` to a clean USB stick.
- **Windows: check for hidden files** -- Control Panel -> File Explorer Options -> View -> Show hidden files. Delete EVERYTHING except the `.up` file from the USB drive (including "System Volume Information" if present).
- **Mac users:** Macs can drop hidden files (.DS_Store, ._AppleDouble) onto USB so the CMU cannot see the file. Use BlueHarvest to remove them.
- **PC only** -- Windows 10/11 Pro 64-bit with Intel/AMD. No ARM (no Android/iOS). No Mac for download/install.

## 4. Pre-update in the car: Test Screen + clear DTCs

1. Start the car, enter **Test Screen mode** (3-button procedure, see the PDF in the update package).
2. **CLEAR ALL DTCs** (Diagnostic Trouble Codes). You will probably see `B108E04 Display-System Internal Failure` -- this is normal (sensor too sensitive to voltage fluctuations), just clear it.
3. Exit Test Screen.
4. Optional: **Factory Reset** of the existing firmware (Settings -> System -> Reset, engine must be running) -- some users need this before Test Screen works.

## 5. Update procedure (step by step)

1. Car OFF, remove SD card, parking brake on, engine off, key fob in the car.
2. Insert the USB flash drive (only the `.up` file) into the **TOP** USB port.
3. Put the car in **ACC (accessory mode)** -- press Start/Stop once without a pedal.
4. Go to Test Screen -> search for the update file via **#99** (USB search).
5. Select **"Reinstallation Package"** (`cmu150_EU_74.00.324A_update.up`).
6. **Start the update. Once started: NEVER stop, NEVER remove the USB until 100% complete.**

### During the update:

| What you see | What it means |
|---|---|
| Black/empty screen for +15 min at the start | **NORMAL** -- do not panic, do not stop. Audio also goes off. |
| Progress bar "stuck" at 23% or 89% | Not stuck -- let it run. |
| LED on the USB drive blinking | CMU is reading/writing -- good sign. |
| LED on the USB drive NOT blinking + "make sure USB inserted" | Update stalled. Pull the USB out and plug it straight back in. The update restarts automatically. Keep pressing the pedals! |
| "INSTALL NOT SUCCESSFUL -- update package missing" | Same as above: USB out, straight back in. |
| "Validation Failed / Failed to validate package certificate" | USB drive too large (>16GB on 2014-2016 cars) or the drive has hidden files. Use a different USB drive. |

- **Total install time: 38-55 minutes** (depending on region, version, USB speed).
- **Press the pedals every 18-20 minutes** (countdown timer!).

## 6. End of the update

At the end you will see a black screen with:

```
***Version 74.00.324 Software Install was Successful
Please Turn ACC off and on again for changes to take effect***
```

Then:
1. Press Start/Stop once (no pedal) -> goes to IGNITION mode (all gauges on, engine not running).
2. Press Start/Stop again -> everything OFF.
3. **Reinsert the navigation SD card** (M-logo first into the slot), car OFF.
4. Wait a minute, turn the car back ON.
5. **Recommended: Factory Reset** (Settings -> System -> Reset, engine running, SD card out). This is a clean start with the new CMU.

## 7. Warnings and pitfalls

### AIO tweaks / customizations
- v74.00.324A **automatically removes** AIO tweaks and customizations in most cases.
- Since late 2024 someone has managed to install AIO on v74 -- this leads to WiFi problems, Bluetooth issues, AndroidAuto/CarPlay crashes, and can no longer be undone.
- **Do not attempt any form of tweaks.**

### Bootloop/restart after a v74 update
- Caused by the navigation SD card being in the car during the update.
- Fix: remove the SD card, do a Factory Reset (engine on, SD card out).

### Screen problems
- A cracked/aging screen (spider cracks, faded) can block Test Screen -> update cannot start. Replace the screen if needed.

### Commander knob problems
- See the community forum for details.

## 8. What a v74 update wipes vs. what survives (toolkit-relevant)

| Item | Effect of the v74 `.up` update |
|---|---|
| Rootfs (`/`, `/jci`, `/etc`, `/usr`) on eMMC | **fully overwritten** |
| `/data_persist/dev/bin/autorun` hook | **deleted by `neutralizeid7` during every update** -- must be re-installed afterwards |
| sshd config / sshd patch in the rootfs | **overwritten** -- stock v74 sshd (port 36000) reads `AuthorizedKeysFile /config-mfg/authorized_keys` and only accepts the factory key |
| `/data_persist` keys (`/data_persist/dev/authorized_keys` etc.) | **survive** (data partition is not wiped) |
| `/config-mfg` (NOR flash, incl. factory `authorized_keys`, `passwd`, `mfg-version.ini`) | **survives** -- NOR is never touched by a `.up` update |
| AIO/tweaks/customizations | **removed automatically** |
| CarPlay/Android Auto retrofit | **overwritten by the native v74 CarPlay stack** if you already had working CP/AA -- you do NOT need to remove the AUX hub/cables first; the hardware conversion is optional and can be done AFTER the firmware update |

### MD5 / integrity checks (do these before starting)

1. Verify the `.up` file against the published checksum before putting it on USB:
   `cmu150_EU_74.00.324A_update.up` -> MD5 `9b841bc807a5010a8652bb3b9e894f91` (the package also contains a `HASH Value 150_EU_74.00.324A.txt` with MD5 + SHA-1, and a Windows checksum utility).
2. Only put the verified `.up` on a freshly formatted FAT32 USB stick (see preconditions).
3. **No factory reset is required before the update** -- it is only recommended afterwards (step 6.5) as a clean start.

### Post-update re-root (toolkit users)

If the car had toolkit modifications before the update (autorun hook, SSH keys in `/data_persist`), the v74 update will have removed the autorun hook and the rootfs sshd patch. Re-establish access as described in **`docs/V74-ACCESS.md`**: the serial `cmu` login works on v74 (uid 0), stock SSH on port 36000 only accepts the NOR key, so deploy your own sshd + keys from `/data_persist` and hook the bring-up into `/jci/scripts/start_network.sh` (the stage scripts are empty but still executed on v74).

## 9. After the update

- **CarPlay/Android Auto:** if you already had working CP/AA, you do NOT need to remove the AUX hub/cables -- the new firmware simply overwrites. The CP/AA hardware conversion is optional and can be done AFTER the firmware update.
- **Navigation maps:** separate update via the Mazda Toolbox app (NNG) on a PC. Only original SD cards are accepted (VIN check). Cost: per map update.
- **Android Auto app:** make sure you have the latest version on your phone BEFORE installing CP/AA. Update iOS too.

## 10. Corrections vs. older/community information

The community source explicitly asks to ignore ALL other sources (YouTube, Reddit, other forums, AI) -- only this procedure and the PDFs in the update package apply. Specific changes since 2023:

- v70.00.100 as a mandatory intermediate step -- **no longer needed since 2023**
- A separate `failsafe.up` / `reinstall.up` file -- **not needed for v74**, the failsafe is inside the `.up`
- "Plug and play" mentality -- this is a serious procedure with brick risk

## 11. Update package contents

| File | Size | MD5/SHA | Status |
|---|---|---|---|
| `cmu150_EU_74.00.324A_update.up` | 2,432,208,800 bytes (2.3 GB) | MD5 `9b841bc807a5010a8652bb3b9e894f91` | **DOWNLOADED + VERIFIED** |
| `HASH Value 150_EU_74.00.324A.txt` | 152 bytes | -- | contains MD5 + SHA-1 of the .up |
| `MAZDA 'MZD' REFLASH PROCEDURE 74.00.324A.pdf` | 919 KB | -- | official Mazda dealer procedure |
| `CHANGELOG.pdf` | 386 KB | -- | v74 changes |
| `MD5_and_SHA_Checksum_Utility.exe` | 83 KB | -- | Windows checksum tool |
| `rufus-4.15.exe` | 2 MB | -- | USB format tool (FAT32) |
| Various .jpg/.txt | -- | -- | USB drive setup photos, warnings, troubleshooting |

## 12. Download tips

- The file host can be slow during peak hours -- download off-peak.
- Browser pop-ups about "corrupted/virus" are false alarms -- the files are clean.
- Browser problems: use incognito mode, create a free account, or temporarily disable antivirus (Windows Defender: Control Panel -> System and Security -> Windows Defender Firewall -> Turn off).
