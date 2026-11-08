#!/bin/sh
# Removes the printer queue and everything install.sh put under /Library/Printers.
set -eu

QUEUE=HP_LaserJet_Professional_P1102

if [ "$(id -u)" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

lpadmin -x "$QUEUE" 2>/dev/null || true
rm -rf /Library/Printers/foo2zjs
rm -f /Library/Printers/PPDs/Contents/Resources/HP-LaserJet_Pro_P1102-foo2zjs-macos.ppd
echo "Removed the printer and the driver files"
