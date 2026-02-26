#!/bin/bash
set -e

# ========== CONFIG ==========
KERNEL="/home/ankush/fc-demo/vmlinux-6.1.155"
ROOTFS="/home/ankush/fc-demo/ubuntu-24.04.ext4"
API_SOCK="/run/firecracker.socket"
TAP_DEV="tap0"

# ========== 1. NETWORK SETUP ==========
echo "[1] Setting up network..."
sudo ip tuntap add $TAP_DEV mode tap 2>/dev/null || true
sudo ip addr add 172.16.0.1/24 dev $TAP_DEV 2>/dev/null || true
sudo ip link set $TAP_DEV up
sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

# Enable internet access
WAN_IFACE=$(ip route | awk '/default/ {print $5}')
sudo iptables -t nat -A POSTROUTING -s 172.16.0.0/24 -o $WAN_IFACE -j MASQUERADE 2>/dev/null || true

# ========== 2. START FIRECRACKER ==========
# echo "[2] Starting Firecracker..."
# cd /home/ankush/fc-demo
# sudo ./firecracker --api-sock $API_SOCK &
# FC_PID=$!
# sleep 1

# ========== 3. CONFIGURE VM ==========
echo "[3] Configuring VM..."

# Machine
sudo curl --unix-socket $API_SOCK \
  -X PUT http://localhost/machine-config \
  -H "Content-Type: application/json" \
  -d '{"vcpu_count": 1, "mem_size_mib": 256, "smt": false}'

# Kernel with STATIC IP
sudo curl --unix-socket $API_SOCK \
  -X PUT http://localhost/boot-source \
  -H "Content-Type: application/json" \
  -d '{
    "kernel_image_path": "/home/ankush/fc-demo/vmlinux-6.1.155",
    "boot_args": "console=ttyS0 root=/dev/vda rw reboot=k panic=1 pci=off ip=172.16.0.10::172.16.0.1:255.255.255.0::eth0:off nameserver=8.8.8.8"
  }'

# Root filesystem
sudo curl --unix-socket $API_SOCK \
  -X PUT http://localhost/drives/rootfs \
  -H "Content-Type: application/json" \
  -d '{
    "drive_id": "rootfs",
    "path_on_host": "/home/ankush/fc-demo/ubuntu-24.04.ext4",
    "is_root_device": true,
    "is_read_only": false
  }'

# Network
sudo curl --unix-socket $API_SOCK \
  -X PUT http://localhost/network-interfaces/eth0 \
  -H "Content-Type: application/json" \
  -d '{
    "iface_id": "eth0",
    "host_dev_name": "tap0",
    "guest_mac": "AA:FC:00:00:00:01"
  }'

# ========== 4. START VM ==========
echo "[4] Starting CI VM..."
sudo curl --unix-socket $API_SOCK \
  -X PUT http://localhost/actions \
  -H "Content-Type: application/json" \
  -d '{"action_type": "InstanceStart"}'

echo "✅ VM started! IP: 172.16.0.10"
echo "📝 CI script is running automatically..."

# ========== 5. WAIT FOR COMPLETION ==========
echo "[5] Waiting for CI to finish (30 seconds)..."
sleep 30

# ========== 6. CLEANUP ==========
echo "[6] Cleaning up..."
sudo kill $FC_PID 2>/dev/null || true
sudo ip link del $TAP_DEV 2>/dev/null || true
sudo rm -f $API_SOCK 2>/dev/null || true

echo "✅ CI run completed!"
