#!/bin/bash
echo "=== CI START ==="
echo "IP: $(hostname -I)"

echo "nameserver 8.8.8.8" > /etc/resolv.conf
echo "nameserver 1.1.1.1" >> /etc/resolv.conf

apt-get update
apt-get install -y git

git clone https://github.com/niwasawa/c-hello-world /tmp/test
echo "=== CI DONE ==="
poweroff

