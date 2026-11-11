#!/bin/sh

# Source gedeelde library (met fallback) - review M5
[ "${TOOLKIT_LIB_LOADED:-0}" = "1" ] || . "$(dirname "$0")/../lib/common.sh" 2>/dev/null
type bootstrap_paths >/dev/null 2>&1 && bootstrap_paths 2>/dev/null
trap_cleanup 2>/dev/null
# MZD Toolkit - Stop SSH

echo "Stopping SSH server..."
killall sshd 2>/dev/null
sleep 1

if ps 2>/dev/null | grep sshd | grep -v grep > /dev/null; then
    echo "ERROR: SSH still running"
    ps | grep sshd
else
    echo "SSH server stopped."
fi
