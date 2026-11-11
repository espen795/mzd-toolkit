# LOCALIZATION

## UI language in this release

All user-facing strings in this public release (menu labels, prompts,
echo/printf messages, error messages, README.txt) are in **English**.

The strings live in these files:

| File | What it contains |
|------|------------------|
| `toolkit/menu.sh` | Master menu + all submenus (WiFi, SSH, Network, Diagnostics, System, Tools, VIM/CAN) |
| `toolkit/menu.lib/common.sh` | UI helpers: header, pause prompt, status lines, `read_choice`, `invalid_choice` |
| `toolkit/install.sh` | Installer output (step messages, shortcuts, result) |
| `toolkit/FIX-ALL.sh` | All-in-one fix script output |
| `toolkit/QUICK-FIX.sh` | Quick-fix script output |
| `toolkit/status.sh` | Running-process status output |
| `toolkit/stop-all.sh` | Stop-all output |
| `toolkit/README.txt` | On-stick readme |

## How to localize

1. Edit the string literals directly in the files above. Only change
   quoted strings — **do not** change variable names, function names,
   file paths, exit codes, or logic.
2. Keep files **UTF-8** encoded (the CMU handles UTF-8 fine for Latin
   scripts; avoid exotic glyphs).
3. The CMU screen is **800x480**. Keep lines short — ideally max ~70
   characters per line. The menu framework wraps long lines, but short
   prompts look much better on the small screen.
4. Technical terms are intentionally kept as-is in all languages:
   `wlan0`, `eth1`, `usb0`, `sshd`, `D-Bus`, `NMS`, `udhcpc`,
   `watchdog`, IP addresses, ports, file paths.
5. Menu confirmations accept both English and Dutch in this release
   (`y|Y|yes|YES` and the legacy `j|J|ja|JA` are both accepted). For a
   localized build, you can keep or drop the Dutch variants in the
   `case` patterns in `menu.sh`.
6. After editing, verify syntax with:
   ```sh
   sh -n toolkit/menu.sh
   sh -n toolkit/menu.lib/common.sh
   sh -n toolkit/install.sh
   sh -n toolkit/FIX-ALL.sh
   sh -n toolkit/QUICK-FIX.sh
   sh -n toolkit/status.sh
   sh -n toolkit/stop-all.sh
   ```

## Notes

- Comments in the scripts are in English too; they are not user-facing
  but keeping them English keeps the public repo clean.
- `YOUR_HOTSPOT_SSID` is a placeholder, not a translatable string —
  replace it in `config/settings.conf`.
