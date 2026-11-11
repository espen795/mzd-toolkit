#!/bin/sh
# MZD Toolkit - SSH auth setup (v4.7.5 M3, gate 0046b92)
# NO passwords anymore. Stock MZD sshd (port 36000) is publickey-only
# via /config-mfg/authorized_keys and password 'jci' NEVER works
# (PasswordAuthentication no, proven in 06-configs.txt). /config-mfg is
# squashfs ro 100% full -> NEVER touch. Key goes via deploy-key.sh +
# autorun to /mnt/data_persist/dev/bin/authorized_keys.

echo "========================================"
echo " SSH pubkey deploy (v4.7.5 - no passwords)"
echo "========================================"
echo "Alias for ssh/deploy-key.sh ..."
sh "$(dirname "$0")/deploy-key.sh"
exit $?
