#!/bin/bash
set -e

# -------------------------
# CONFIG
# -------------------------
TAP_DEV="tap0"
SUBNET="172.16.0.0/24"
HOST_IP="172.16.0.1"
VM_IP="172.16.0.10"
FC_NAT_CHAIN="FC_NAT"
FC_FWD_CHAIN="FC_FWD"
FC_SOCK="/run/firecracker.socket"

WAN_IFACE=$(ip route | awk '/default/ {print $5}')

# -------------------------
# CLEANUP
# -------------------------
cleanup() {
  echo "[-] Cleaning Firecracker networking..."

  sudo ip link del "$TAP_DEV" 2>/dev/null || true

  sudo iptables -t nat -D POSTROUTING -j "$FC_NAT_CHAIN" 2>/dev/null || true
  sudo iptables -D FORWARD -j "$FC_FWD_CHAIN" 2>/dev/null || true

  sudo iptables -t nat -F "$FC_NAT_CHAIN" 2>/dev/null || true
  sudo iptables -F "$FC_FWD_CHAIN" 2>/dev/null || true

  sudo iptables -t nat -X "$FC_NAT_CHAIN" 2>/dev/null || true
  sudo iptables -X "$FC_FWD_CHAIN" 2>/dev/null || true

  sudo rm -f "$FC_SOCK"

  echo "[✔] Cleanup done"
}

trap cleanup EXIT INT TERM ERR

# -------------------------
# NETWORK SETUP
# -------------------------
echo "[-] Setting up TAP device..."

sudo ip tuntap add "$TAP_DEV" mode tap
sudo ip addr add "$HOST_IP/24" dev "$TAP_DEV"
sudo ip link set "$TAP_DEV" up

sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

# -------------------------
# IPTABLES (SAFE WAY)
# -------------------------
echo "[-] Configuring iptables (isolated)..."

sudo iptables -t nat -N "$FC_NAT_CHAIN" 2>/dev/null || true
sudo iptables -N "$FC_FWD_CHAIN" 2>/dev/null || true

sudo iptables -t nat -C POSTROUTING -j "$FC_NAT_CHAIN" 2>/dev/null || \
sudo iptables -t nat -A POSTROUTING -j "$FC_NAT_CHAIN"

sudo iptables -C FORWARD -j "$FC_FWD_CHAIN" 2>/dev/null || \
sudo iptables -A FORWARD -j "$FC_FWD_CHAIN"

sudo iptables -t nat -A "$FC_NAT_CHAIN" -s "$SUBNET" -o "$WAN_IFACE" -j MASQUERADE

sudo iptables -A "$FC_FWD_CHAIN" -i "$WAN_IFACE" -o "$TAP_DEV" \
  -m state --state RELATED,ESTABLISHED -j ACCEPT

sudo iptables -A "$FC_FWD_CHAIN" -i "$TAP_DEV" -o "$WAN_IFACE" -j ACCEPT

# -------------------------
# FIRECRACKER START
# -------------------------
# echo "[-] Starting Firecracker..."
#
# sudo ./firecracker --api-sock "$FC_SOCK" &
# sleep 1

# -------------------------
# FIRECRACKER CONFIG
# -------------------------
echo "[-] Configuring VM..."

curl --unix-socket "$FC_SOCK" -X PUT http://localhost/machine-config \
  -H "Content-Type: application/json" \
  -d '{
    "vcpu_count": 1,
    "mem_size_mib": 512,
    "smt": false
  }'

curl --unix-socket "$FC_SOCK" -X PUT http://localhost/boot-source \
  -H "Content-Type: application/json" \
  -d "{
    \"kernel_image_path\": \"/home/ankush/fc-demo/vmlinux-6.1.155\",
    \"boot_args\": \"console=ttyS0 root=/dev/vda rw reboot=k panic=1 pci=off ip=${VM_IP}::${HOST_IP}:255.255.255.0::eth0:off\"
  }"

curl --unix-socket "$FC_SOCK" -X PUT http://localhost/drives/rootfs \
  -H "Content-Type: application/json" \
  -d '{
    "drive_id": "rootfs",
    "path_on_host": "/home/ankush/fc-demo/ubuntu-24.04.ext4",
    "is_root_device": true,
    "is_read_only": false
  }'

curl --unix-socket "$FC_SOCK" -X PUT http://localhost/network-interfaces/eth0 \
  -H "Content-Type: application/json" \
  -d "{
    \"iface_id\": \"eth0\",
    \"host_dev_name\": \"${TAP_DEV}\",
    \"guest_mac\": \"AA:FC:00:00:00:01\"
  }"

curl --unix-socket "$FC_SOCK" -X PUT http://localhost/actions \
  -H "Content-Type: application/json" \
  -d '{"action_type":"InstanceStart"}'

echo "[✔] VM started!"
echo "[-] Waiting for CI to finish..."
sleep 1000
