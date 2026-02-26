#!/bin/bash
set -e

cleanup() {
  echo "🧹 Cleaning up..."

  # sudo pkill firecracker 2>/dev/null || true
  # sudo pkill dnsmasq 2>/dev/null || true

  sudo iptables -t nat -F 2>/dev/null || true
  sudo iptables -F 2>/dev/null || true

  sudo ip link del tap0 2>/dev/null || true

  sudo sysctl -w net.ipv4.ip_forward=0 >/dev/null 2>&1 || true

  echo "✅ Cleanup done"
}

# Run cleanup on:
# - normal exit
# - Ctrl+C
# - error
# - kill signals
trap cleanup EXIT INT TERM ERR

# Kill everything
sudo pkill dnsmasq 2>/dev/null || true
sudo ip link del tap0 2>/dev/null || true
sudo iptables -t nat -F 2>/dev/null || true
sudo iptables -F 2>/dev/null || true

# Network
sudo ip tuntap add tap0 mode tap
sudo ip addr add 172.16.0.1/24 dev tap0
sudo ip link set tap0 up
sudo sysctl -w net.ipv4.ip_forward=1

WAN=$(ip route | awk '/default/ {print $5}')
sudo iptables -t nat -A POSTROUTING -s 172.16.0.0/24 -o $WAN -j MASQUERADE
sudo iptables -A FORWARD -i $WAN -o tap0 -m state --state RELATED,ESTABLISHED -j ACCEPT
sudo iptables -A FORWARD -i tap0 -o $WAN -j ACCEPT

# Start Firecracker
# cd /home/ankush/fc-demo
# sudo ./firecracker --api-sock /run/firecracker.socket &
# sleep 1

# Configure
curl --unix-socket /run/firecracker.socket \
  -X PUT http://localhost/machine-config \
  -H "Content-Type: application/json" \
  -d '{"vcpu_count": 1, "mem_size_mib": 512, "smt": false}'

curl --unix-socket /run/firecracker.socket \
  -X PUT http://localhost/boot-source \
  -H "Content-Type: application/json" \
  -d '{
    "kernel_image_path": "/home/ankush/fc-demo/vmlinux-6.1.155",
    "boot_args": "console=ttyS0 root=/dev/vda rw reboot=k panic=1 pci=off ip=172.16.0.10::172.16.0.1:255.255.255.0::eth0:off"
  }'

curl --unix-socket /run/firecracker.socket \
  -X PUT http://localhost/drives/rootfs \
  -H "Content-Type: application/json" \
  -d '{
    "drive_id": "rootfs",
    "path_on_host": "/home/ankush/fc-demo/ubuntu-24.04.ext4",
    "is_root_device": true,
    "is_read_only": false
  }'

curl --unix-socket /run/firecracker.socket \
  -X PUT http://localhost/network-interfaces/eth0 \
  -H "Content-Type: application/json" \
  -d '{
    "iface_id": "eth0",
    "host_dev_name": "tap0",
    "guest_mac": "AA:FC:00:00:00:01"
  }'

curl --unix-socket /run/firecracker.socket \
  -X PUT http://localhost/actions \
  -H "Content-Type: application/json" \
  -d '{"action_type": "InstanceStart"}'

echo "✅ VM started!"
echo "⏳ Will auto-run CI and shutdown in 30 seconds..."
sleep 1000

# Cleanup
sudo pkill firecracker
sudo ip link del tap0 2>/dev/null || true
echo "✅ Done!"
