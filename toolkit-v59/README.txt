========================================
 MZD TOOLKIT v4.8.0
 Complete toolkit for Mazda MZD Connect
========================================

INSTALLATION (v4.7.5 - from release archive):
------------------------------------------------
The MZD has NO unzip (but it has tar+gzip). Therefore use ONLY the tar.gz:

1. Download mzd-toolkit-v4.7.5.tar.gz on a PC (the .zip is for PC ONLY!)
2. Copy mzd-toolkit-v4.7.5.tar.gz (+ SHA256SUMS) to a FAT32 USB stick
3. Start the car with the USB inserted
4. Open the terminal (via your root exploit)
5. Extract ON THE CAR (tar is present, unzip is NOT):
     tar -xzf /tmp/mnt/sdb1/mzd-toolkit-v4.7.5.tar.gz -C /tmp/mnt/sdb1/
6. Run:
     sh /tmp/mnt/sdb1/mzd-toolkit/install.sh
   (or: sh /tmp/mnt/sda1/mzd-toolkit/install.sh - check with ls /tmp/mnt)

   Verify checksum (recommended - USB sticks get corrupt):
     cd /tmp/mnt/sdb1 && sha256sum -c SHA256SUMS

INSTALLATION (from this source folder, without archive):
----------------------------------------------------
1. Copy this whole folder (mzd-toolkit) to a FAT32 USB stick
2. Start the car with the USB inserted
3. Open the terminal (via your root exploit)
4. Run:
     sh /tmp/mnt/sdb1/mzd-toolkit/install.sh
   (or: sh /tmp/mnt/sda1/mzd-toolkit/install.sh - check with ls /tmp/mnt)

5. Restart the car - everything starts automatically

USAGE:
--------
After installation you can start the menu with:
  sh /mnt/data_persist/dev/bin/menu.sh

Or directly from USB:
  sh /tmp/mnt/sdb1/mzd-toolkit/menu.sh

MENU STRUCTURE:
---------------
Main menu:
  1. WiFi Menu      - Connect, scan, fix, disconnect
  2. SSH Menu       - Start, stop, status, test
  3. System Info    - All system info scripts
  4. Tools Menu     - Install, backup, cleanup
  5. Everything to USB - Complete system dump

FILE OVERVIEW:
--------------------
menu.sh              - Master CLI menu (start here!)
install.sh           - Install script (one-time)

wifi/
  connect.sh         - Connect to YOUR_HOTSPOT_SSID
  status.sh          - WiFi status
  scan.sh            - Scan networks
  fix.sh             - WiFi repair (full reset)
  disconnect.sh      - Disable WiFi

ssh/
  start.sh           - Start SSH server
  stop.sh            - Stop SSH server
  status.sh          - SSH status
  test.sh            - Test SSH connection
  autorun            - Auto-start at boot
  sshd_config        - SSH configuration

system/
  info.sh            - Quick system info (on screen)
  network.sh         - Network diagnostics
  storage.sh         - Storage/mounts info
  process.sh         - Process list
  logs.sh            - Collect logs
  dmesg.sh           - Kernel messages
  hardware.sh        - Hardware info
  dump.sh            - COMPLETE DUMP to USB (everything!)

tools/
  install-ssh.sh     - Install SSH permanently
  fix-warning.sh     - Remove startup warning
  backup.sh          - Backup to USB
  cleanup.sh         - Cleanup temp files

config/
  settings.conf      - Settings (SSID, etc)

IMPORTANT COMMANDS (without menu):
--------------------------------------
WiFi connect:
  sh /mnt/sdb1/mzd-toolkit/wifi/connect.sh

SSH start:
  sh /mnt/sdb1/mzd-toolkit/ssh/start.sh

SSH status:
  sh /mnt/sdb1/mzd-toolkit/ssh/status.sh

System dump (EVERYTHING to USB):
  sh /mnt/sdb1/mzd-toolkit/system/dump.sh

Quick info:
  sh /mnt/sdb1/mzd-toolkit/system/info.sh

CONNECTING FROM YOUR COMPUTER (v4.7.5 = pubkey-only, no passwords):
---------------------------------------------------------------------
  ssh -p 36000 cmu@<mazda-ip> -i <path-to>/id_mzd    # stock sshd (secondary)
  ssh -p 22 cmu@<mazda-ip> -i <path-to>/id_mzd        # own sshd (primary)

Generate key pair (one-time, on the PC):
  sh toolkit/ssh/deploy-key.sh      # -> toolkit/ssh/id_mzd + id_mzd.pub
Copy the .pub to the USB; at boot the autorun puts it in
/mnt/data_persist/dev/bin/authorized_keys (NEVER /config-mfg - read-only!).

Find the IP with:
  sh /mnt/sdb1/mzd-toolkit/wifi/status.sh

TROUBLESHOOTING:
----------------
WiFi not working (v4.7.5: via NMS, NEVER own wpa_supplicant):
  sh /mnt/sdb1/mzd-toolkit/wifi/fix-powersave.sh
  sh /mnt/sdb1/mzd-toolkit/wifi/connect-nms.sh "SSID" "PASSWORD"

SSH refused (publickey refused?):
  sh /mnt/sdb1/mzd-toolkit/ssh/status.sh
  sh /mnt/sdb1/mzd-toolkit/ssh/test.sh
  # check: cat /mnt/data_persist/dev/bin/authorized_keys  (must contain id_mzd.pub)
  # check which port listens: netstat -tln | grep -E ':(22|36000) '
  # firewall: ONLY open specific port (iptables -I INPUT -p tcp --dport 22 -j ACCEPT),
  # NEVER iptables -P INPUT ACCEPT (security regression, fixed in v4.7.5)

Nothing works:
  sh /mnt/sdb1/mzd-toolkit/system/dump.sh
  (check the logs in /mnt/sdb1/mzd-toolkit/logs/)

View logs:
  cat /tmp/mzd-autorun.log
  ls /mnt/sdb1/mzd-toolkit/logs/

IMPORTANT:
-----------
- No shift key needed! All scripts use only numbers
- USB mount is usually /tmp/mnt/sdb1 (check with ls /tmp/mnt)
- The toolkit does a USB health pre-flight (rw-check + LOST.DIR detection):
  on LOST.DIR or FAT-fs errors you get a warning - reformatting the USB
  is then recommended (proven corruption after USB disconnect)
- Release archive: use mzd-toolkit-v4.7.5.tar.gz on the car (tar -xzf),
  the .zip is for the PC ONLY - the MZD has no unzip
- D-Bus on the MZD: ONLY service bus unix:path=/tmp/dbus_service_socket
  (no --system); jci_dbus_send in lib/common.sh handles this automatically
- wpa_cli: always via wpactrl (lib/wifi-compat.sh) - runtime socket detection
- /mnt/data_persist is writable and permanent
- /tmp is RAM (disappears at reboot)
- The OS itself is read-only

AUTHOR: the toolkit
DATE:   29 October 2026
