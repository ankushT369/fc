#!/bin/bash
set -e

# Config
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

# NAT for internet
# NAT for internet
WAN_IFACE=$(ip route | awk '/default/ {print $5}')
# MAIN NAT rule - you're missing this!
sudo iptables -t nat -A POSTROUTING -s 172.16.0.0/24 -o $WAN_IFACE -j MASQUERADE
# DNS rules
sudo iptables -t nat -A POSTROUTING -p udp --dport 53 -s 172.16.0.0/24 -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -p tcp --dport 53 -s 172.16.0.0/24 -j MASQUERADE

# NO DHCP needed for static IP

# ========== 2. CONFIGURE VM ==========
echo "[2] Configuring VM..."

# Machine config
sudo curl --unix-socket $API_SOCK \
  -X PUT http://localhost/machine-config \
  -H "Content-Type: application/json" \
  -d '{"vcpu_count": 1, "mem_size_mib": 512, "smt": false}'

# Kernel with STATIC IP and DNS
sudo curl --unix-socket $API_SOCK \
  -X PUT http://localhost/boot-source \
  -H "Content-Type: application/json" \
  -d '{
    "kernel_image_path": "/home/ankush/fc-demo/vmlinux-6.1.155",
    "boot_args": "console=ttyS0 root=/dev/vda rw reboot=k panic=1 pci=off ip=172.16.0.10::172.16.0.1:255.255.255.0::eth0:off nameserver=8.8.8.8"
  }'

# Root filesystem (NO cloud-init)
sudo curl --unix-socket $API_SOCK \
  -X PUT http://localhost/drives/rootfs \
  -H "Content-Type: application/json" \
  -d '{
    "drive_id": "rootfs",
    "path_on_host": "/home/ankush/fc-demo/ubuntu-24.04.ext4",
    "is_root_device": true,
    "is_read_only": false
  }'

# Network interface
sudo curl --unix-socket $API_SOCK \
  -X PUT http://localhost/network-interfaces/eth0 \
  -H "Content-Type: application/json" \
  -d '{
    "iface_id": "eth0",
    "host_dev_name": "tap0",
    "guest_mac": "AA:FC:00:00:00:01"
  }'

# ========== 3. START VM ==========
echo "[3] Starting CI VM..."
sudo curl --unix-socket $API_SOCK \
  -X PUT http://localhost/actions \
  -H "Content-Type: application/json" \
  -d '{"action_type": "InstanceStart"}'

echo "✅ VM started with static IP 172.16.0.10"
echo "📋 Will run your CI script from rc.local"

# ========== 4. WAIT FOR COMPLETION ==========
echo "[4] Waiting for CI to complete (30 seconds)..."
sleep 30

# ========== 5. CLEANUP ==========
echo "[5] Cleaning up..."
sudo ip link del $TAP_DEV 2>/dev/null || true

echo "✅ CI run completed!"
