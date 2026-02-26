#!/bin/bash
set -euo pipefail

# path config
FIRECRACKER_BIN="/home/ankush/projects/firecracker/build/cargo_target/debug/firecracker"
KERNEL="/home/ankush/fc-demo/vmlinux-6.1.155"
ROOTFS="/home/ankush/fc-demo/ubuntu-24.04.ext4"

INST="${1:-1}"

log() {
    # Fixed timestamp format
    printf "[%s] %s\n" "$(date '+%H:%M:%S')" "$1"
}

log "Launching $INST Firecracker microVM(s)"

for ((i=1; i<=INST; i++)); do
    echo "\n"
    log "[VM $i] Starting Firecracker"
    log "[VM $i] API socket: /run/firecracker-$i.socket"

    sudo rm -f "/run/firecracker-$i.socket"
    log "[VM $i] Removed old socket"

    # Use absolute path for log files
    log "[VM $i] Starting Firecracker process"
    sudo "$FIRECRACKER_BIN" \
        --api-sock "/run/firecracker-$i.socket" \
        </dev/null \
        >"/tmp/firecracker-$i.log" 2>&1 &

    FC_PID=$!
    log "[VM $i] Firecracker PID: $FC_PID"
    
    # Check if process is still running
    sleep 0.5
    if ! kill -0 $FC_PID 2>/dev/null; then
        log "[VM $i] ERROR: Firecracker process died"
        log "[VM $i] Check /tmp/firecracker-$i.log for details"
        exit 1
    fi

    # Wait for socket with timeout
    wait_count=0
    log "[VM $i] Waiting for socket creation..."
    while [[ ! -S "/run/firecracker-$i.socket" ]] && [[ $wait_count -lt 50 ]]; do
        sleep 0.1
        ((wait_count++))
    done

    if [[ ! -S "/run/firecracker-$i.socket" ]]; then
        log "[VM $i] ERROR: Socket not created after 5 seconds"
        log "[VM $i] Process status: $(ps -p $FC_PID -o pid= 2>/dev/null || echo 'Not running')"
        exit 1
    fi
    
    log "[VM $i] Socket created successfully"

    log "[VM $i] Configuring machine"
    if ! sudo curl --fail --unix-socket "/run/firecracker-$i.socket" -s \
        -X PUT http://localhost/machine-config \
        -H "Content-Type: application/json" \
        -d '{
              "vcpu_count": 1,
              "mem_size_mib": 512,
              "smt": false
            }' >/dev/null; then
        log "[VM $i] ERROR: Failed to configure machine"
        exit 1
    fi

    log "[VM $i] Attaching kernel"
    if ! sudo curl --fail --unix-socket "/run/firecracker-$i.socket" -s \
        -X PUT http://localhost/boot-source \
        -H "Content-Type: application/json" \
        -d "{
              \"kernel_image_path\": \"$KERNEL\",
              \"boot_args\": \"console=ttyS0 root=/dev/vda rw reboot=k panic=1 pci=off\"
            }" >/dev/null; then
        log "[VM $i] ERROR: Failed to attach kernel"
        exit 1
    fi

    log "[VM $i] Attaching root filesystem"
    if ! sudo curl --fail --unix-socket "/run/firecracker-$i.socket" -s \
        -X PUT http://localhost/drives/rootfs \
        -H "Content-Type: application/json" \
        -d "{
              \"drive_id\": \"rootfs\",
              \"path_on_host\": \"$ROOTFS\",
              \"is_root_device\": true,
              \"is_read_only\": false
            }" >/dev/null; then
        log "[VM $i] ERROR: Failed to attach root filesystem"
        exit 1
    fi

  #   sudo curl --fail --unix-socket "/run/firecracker.socket" -s \
  # -X PUT http://localhost/network-interfaces/eth0 \
  # -H "Content-Type: application/json" \
  # -d '{
  #       "iface_id": "eth0",
  #       "host_dev_name": "tap0",
  #       "guest_mac": "AA:FC:00:00:00:01"
  #     }'


    log "[VM $i] Starting microVM"
    if ! sudo curl --fail --unix-socket "/run/firecracker-$i.socket" -s \
        -X PUT http://localhost/actions \
        -H "Content-Type: application/json" \
        -d '{ "action_type": "InstanceStart" }' >/dev/null; then
        log "[VM $i] ERROR: Failed to start microVM"
        exit 1
    fi

    log "[VM $i] MicroVM started"
done

log "All microVMs launched successfully"
