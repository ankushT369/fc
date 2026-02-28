#!/bin/bash
set -euo pipefail

ROOTFS_IMG="$HOME/boneci/setup/ubuntu-24.04.ext4"
MNT="$HOME/rootfs"

echo "====================================="
echo " STEP 1: Mount rootfs"
echo "====================================="

sudo mkdir -p "$MNT"
sudo mount -o loop "$ROOTFS_IMG" "$MNT"

echo "====================================="
echo " STEP 2: Create /init.sh"
echo "====================================="

sudo tee "$MNT/init.sh" >/dev/null <<'EOF'
#!/bin/bash
set -euxo pipefail

# Fix DNS
printf "nameserver 8.8.8.8\nnameserver 1.1.1.1\n" > /etc/resolv.conf

echo "=== CI START ==="
echo "IP: $(hostname -I || true)"

export DEBIAN_FRONTEND=noninteractive

apt-get update -o Acquire::Retries=3 -o Acquire::http::Timeout=10
apt-get install -y git ca-certificates

git clone https://github.com/niwasawa/c-hello-world /tmp/test

echo "=== CI DONE ==="

sync
sleep 1
poweroff
EOF

sudo chmod +x "$MNT/init.sh"

echo "====================================="
echo " STEP 3: Create /etc/rc.local"
echo "====================================="

sudo tee "$MNT/etc/rc.local" >/dev/null <<'EOF'
#!/bin/bash
/bin/bash /init.sh
exit 0
EOF

sudo chmod +x "$MNT/etc/rc.local"

echo "====================================="
echo " STEP 4: Create rc-local.service"
echo "====================================="

sudo tee "$MNT/etc/systemd/system/rc-local.service" >/dev/null <<'EOF'
[Unit]
Description=/etc/rc.local Compatibility
ConditionFileIsExecutable=/etc/rc.local
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/etc/rc.local
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo mkdir -p "$MNT/etc/systemd/system/multi-user.target.wants"
sudo ln -sf /etc/systemd/system/rc-local.service \
  "$MNT/etc/systemd/system/multi-user.target.wants/rc-local.service"

echo "====================================="
echo " STEP 5: Disable apt timers"
echo "====================================="

sudo mount -t proc none "$MNT/proc"
sudo mount -t sysfs none "$MNT/sys"
sudo mount --bind /dev "$MNT/dev"

sudo chroot "$MNT" systemctl mask apt-daily.service apt-daily.timer apt-daily-upgrade.timer dpkg-db-backup.timer || true

sudo umount "$MNT/proc" "$MNT/sys" "$MNT/dev"

echo "====================================="
echo " STEP 6: Unmount rootfs"
echo "====================================="

sudo umount "$MNT"

echo "====================================="
echo " ALL DONE — rootfs is ready."
echo "====================================="
