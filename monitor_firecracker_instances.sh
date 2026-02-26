#!/bin/bash

INTERVAL=2   # seconds between updates

echo "Firecracker Resource Monitor"
echo "Press Ctrl+C to stop"
echo

while true; do
    clear
    echo "Timestamp: $(date)"
    echo
    printf "%-8s %-8s %-10s\n" "PID" "CPU(%)" "nemory consumption(MB)" 
    echo "-------------------------------------------"

    ps -C firecracker -o pid=,%cpu=,rss= | while read pid cpu rss; do
        rss_mb=$(awk "BEGIN {printf \"%.1f\", $rss/1024}")
        printf "%-8s %-8s %-10s %-10s\n" "$pid" "$cpu" "$rss_mb"
    done

    sleep "$INTERVAL"
done
