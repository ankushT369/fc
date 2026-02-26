#!/usr/bin/env bash
set -euo pipefail

# ===== MUST BE ROOT =====
if [ "$EUID" -ne 0 ]; then
  echo "Run this script as root"
  exit 1
fi

# ===== ARCH & RELEASE =====
ARCH="$(uname -m)"
RELEASE_URL="https://github.com/firecracker-microvm/firecracker/releases"
LATEST_VERSION="$(basename "$(curl -fsSLI -o /dev/null -w %{url_effective} ${RELEASE_URL}/latest)")"
CI_VERSION="${LATEST_VERSION%.*}"

# ===== GET LATEST KERNEL KEY =====
LATEST_KERNEL_KEY="$(
  curl -fsSL "http://spec.ccfc.min.s3.amazonaws.com/?prefix=firecracker-ci/${CI_VERSION}/${ARCH}/vmlinux-&list-type=2" \
  | grep -oP "(?<=<Key>)(firecracker-ci/${CI_VERSION}/${ARCH}/vmlinux-[0-9]+\.[0-9]+\.[0-9]+)(?=</Key>)" \
  | sort -V | tail -1
)"

# ===== DOWNLOAD KERNEL =====
wget -q "https://s3.amazonaws.com/spec.ccfc.min/${LATEST_KERNEL_KEY}"

# ===== GET LATEST UBUNTU ROOTFS KEY =====
LATEST_UBUNTU_KEY="$(
  curl -fsSL "http://spec.ccfc.min.s3.amazonaws.com/?prefix=firecracker-ci/${CI_VERSION}/${ARCH}/ubuntu-&list-type=2" \
  | grep -oP "(?<=<Key>)(firecracker-ci/${CI_VERSION}/${ARCH}/ubuntu-[0-9]+\.[0-9]+\.squashfs)(?=</Key>)" \
  | sort -V | tail -1
)"

UBUNTU_VERSION="$(basename "${LATEST_UBUNTU_KEY}" .squashfs | grep -oE '[0-9]+\.[0-9]+')"

# ===== DOWNLOAD ROOTFS =====
wget -q -O ubuntu-${UBUNTU_VERSION}.squashfs.upstream \
  "https://s3.amazonaws.com/spec.ccfc.min/${LATEST_UBUNTU_KEY}"

# ===== EXTRACT ROOTFS =====
rm -rf squashfs-root
unsquashfs ubuntu-${UBUNTU_VERSION}.squashfs.upstream

# ===== CREATE SSH KEY =====
rm -f id_rsa id_rsa.pub
ssh-keygen -t rsa -b 3072 -f id_rsa -N ""

mkdir -p squashfs-root/root/.ssh
cp id_rsa.pub squashfs-root/root/.ssh/authorized_keys
chmod 600 squashfs-root/root/.ssh/authorized_keys
chown -R root:root squashfs-root

mv id_rsa ubuntu-${UBUNTU_VERSION}.id_rsa

# ===== CREATE EXT4 IMAGE =====
truncate -s 1G ubuntu-${UBUNTU_VERSION}.ext4
mkfs.ext4 -F -d squashfs-root ubuntu-${UBUNTU_VERSION}.ext4

# ===== VERIFY =====
echo
echo "Artifacts created:"
KERNEL="$(ls vmlinux-* | tail -1)"
[ -f "$KERNEL" ] && echo "Kernel:  $KERNEL" || echo "ERROR: kernel missing"

ROOTFS="$(ls ubuntu-*.ext4 | tail -1)"
e2fsck -fn "$ROOTFS" &>/dev/null && echo "Rootfs:  $ROOTFS" || echo "ERROR: invalid rootfs"

KEY="$(ls ubuntu-*.id_rsa | tail -1)"
[ -f "$KEY" ] && echo "SSH Key: $KEY" || echo "ERROR: ssh key missing"

echo
echo "DONE ✅"
