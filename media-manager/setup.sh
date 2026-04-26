#!/bin/bash

# Check if required environment variable exists
if [ -z "$LXC_PASSWORD" ]; then
    echo "ERROR: LXC_PASSWORD environment variable is not set"
    echo "Please set the environment variable before running this script"
    echo "Example: export LXC_PASSWORD='your_secure_password'"
    exit 1
fi

# This automatically finds the latest debian-12 template filename
TEMPLATE=$(ls /var/lib/vz/template/cache/ | grep "debian-12" | head -n 1)

# 1. Create the container (using the command above)
pct create 101 local:vztmpl/$TEMPLATE \
  --hostname media-manager \
  --password $LXC_PASSWORD \
  --unprivileged 0 \
  --features nesting=1 \
  --cores 4 \
  --memory 2048 \
  --swap 1024 \
  --rootfs local-lvm:50 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.1.101/24,gw=192.168.1.1,firewall=1 \
  --onboot 1 \
  --start 1

# 2. Wait 10 seconds for the container to initialize
sleep 10

# 3. Mount the 16TB Physical Drive
pct set 101 -mp0 /mnt/storage,mp=/mnt/media

# 4. Configure DNS for internet accessibility
pct exec 101 -- bash -c "echo 'nameserver 8.8.8.8' >> /etc/resolv.conf"
pct exec 101 -- bash -c "echo 'nameserver 1.1.1.1' >> /etc/resolv.conf"

# 4.1. Test network connectivity to Google
echo "Testing network connectivity to Google..."
pct exec 101 -- bash -c "ping -c 3 google.com"
if [ $? -eq 0 ]; then
    echo "Network connectivity test passed - LXC 101 can reach Google"
else
    echo "ERROR: Network connectivity test failed - LXC 101 cannot reach Google"
    echo "Please check network configuration before proceeding"
    exit 1
fi

# 5. Update and Install Docker inside the LXC
cat docker_install.sh | pct exec 101 -- bash
echo "LXC 101 created, 16TB drive linked, and Docker installed."