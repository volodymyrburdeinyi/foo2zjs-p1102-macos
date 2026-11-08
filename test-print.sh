#!/bin/sh
# Prints a 2-page PDF through the installed queue, the same path any macOS app uses,
# and waits for the job to leave the queue. Check the paper: two pages, "Page 1 of 2" and "Page 2 of 2".
set -eu

QUEUE=HP_LaserJet_Professional_P1102
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf 'P1102 driver test\n\nPage 1 of 2\n\fP1102 driver test\n\nPage 2 of 2\n' > "$TMP/test.txt"
cupsfilter -i text/plain -m application/pdf "$TMP/test.txt" > "$TMP/test.pdf" 2>/dev/null

job=$(lp -d "$QUEUE" -t "p1102-test-print" "$TMP/test.pdf" | awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^'"$QUEUE"'-[0-9]+$/) print $i }')
echo "Sent $job"

i=0
while lpstat -o "$QUEUE" | grep -q "^$job "; do
    i=$((i + 1))
    if [ "$i" -ge 60 ]; then
        echo "Job still queued after 60 s. Printer state:" >&2
        lpstat -l -p "$QUEUE" | head -3 >&2
        exit 1
    fi
    sleep 1
done
echo "$job finished. Printer state:"
lpstat -l -p "$QUEUE" | head -2
