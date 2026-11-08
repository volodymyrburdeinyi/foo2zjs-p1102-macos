#!/bin/sh
# Installs the built driver under /Library/Printers and adds the USB printer queue.
set -eu

QUEUE=HP_LaserJet_Professional_P1102
PPD=/Library/Printers/PPDs/Contents/Resources/HP-LaserJet_Pro_P1102-foo2zjs-macos.ppd
HERE=$(cd "$(dirname "$0")" && pwd)

if [ "$(id -u)" -ne 0 ]; then
    exec sudo "$0" "$@"
fi
[ -x "$HERE/stage/Library/Printers/foo2zjs/bin/gs" ] || { echo "Run ./build.sh first" >&2; exit 1; }

# CUPS checks that filters and their directories are root-owned and not group/world writable.
ditto "$HERE/stage/Library/Printers" /Library/Printers
chown -R root:wheel /Library/Printers/foo2zjs "$PPD"
chmod -R go-w /Library/Printers/foo2zjs
chmod 644 "$PPD"

if lpstat -v "$QUEUE" >/dev/null 2>&1; then
    echo "Driver files updated; printer $QUEUE already exists and was left as is"
    exit 0
fi

URI=$(lpinfo -v | awk '$2 ~ /^usb:\/\/.*P1102/ { print $2; exit }')
[ -n "$URI" ] || { echo "Printer not found on USB; driver files are installed, connect it and re-run" >&2; exit 1; }

lpadmin -p "$QUEUE" -E -v "$URI" -P "$PPD" \
    -D "HP LaserJet Professional P1102" -L "USB" -o printer-is-shared=false
lpadmin -d "$QUEUE"
echo "Installed queue $QUEUE on $URI"
