#!/bin/bash

set -euo pipefail

echo "[INFO] Stopping Firecracker microVMs..."

# 1. Show running Firecracker processes (if any)
FC_PIDS=$(pgrep -x firecracker || true)

if [[ -z "$FC_PIDS" ]]; then
    echo "[INFO] No running Firecracker processes found"
else
    echo "[INFO] Found Firecracker PIDs:"
    for pid in $FC_PIDS; do
        echo "  - PID $pid ($(ps -p $pid -o cmd=))"
    done

    echo "[INFO] Killing Firecracker processes..."
    sudo kill $FC_PIDS
fi

# 2. Kill any stuck launcher scripts
LAUNCHERS=$(pgrep -f run_multiple_firecracker.sh || true)
if [[ -n "$LAUNCHERS" ]]; then
    echo "[INFO] Killing launcher scripts..."
    pkill -f run_multiple_firecracker.sh
fi

# 3. Remove leftover API sockets
if ls /run/firecracker-*.socket &>/dev/null; then
    echo "[INFO] Removing Firecracker API sockets"
    sudo rm -f /run/firecracker-*.socket
else
    echo "[INFO] No Firecracker sockets found"
fi

# 4. Final verification
sleep 0.5
if pgrep -x firecracker &>/dev/null; then
    echo "[WARN] Some Firecracker processes are still running!"
    pgrep -a firecracker
else
    echo "[INFO] All Firecracker microVMs stopped cleanly"
fi

