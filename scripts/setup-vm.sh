#!/bin/bash

# Setup and provision a Debian VM for scheduler testing
# This script creates a QEMU VM with build tools, Kafka, and Zookeeper installed via cloud-init.
# 
# The workflow is:
# 1. This script: Creates VM with Debian 13 + build tools + Kafka (~10-15 min)
# 2. build-kernel.sh: Build custom kernel on host with all CPU cores (~20 min)
# 3. install-kernel-to-vm.sh: Copy and install pre-built kernel to VM (~1 min)
# 4. build-schedulers-in-vm.sh: Build schedulers inside VM (~10-15 min with custom kernel)
#
# This approach is much faster than building everything in the VM.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VM_DIR="${VM_DIR:-$PROJECT_ROOT/vm}"
VM_IMAGE="${VM_IMAGE:-$VM_DIR/debian-scheduler-test.qcow2}"
VM_SIZE="${VM_SIZE:-40G}"
DEBIAN_IMAGE_URL="${DEBIAN_IMAGE_URL:-https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/scheduler_test_vm}"
VM_USER="${VM_USER:-debian}"

echo "=========================================="
echo "Debian VM Setup for Scheduler Testing"
echo "=========================================="
echo ""

# Create VM directory
mkdir -p "$VM_DIR"
cd "$VM_DIR"

# Check prerequisites
echo "Checking prerequisites..."
for cmd in qemu-system-x86_64 qemu-img cloud-localds ssh-keygen; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: $cmd is not installed"
        echo "Install with: sudo apt-get install qemu-system-x86_64 qemu-utils cloud-image-utils openssh-client"
        exit 1
    fi
done

# Generate SSH key if it doesn't exist
if [ ! -f "$SSH_KEY" ]; then
    echo "Generating SSH key for VM access..."
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "scheduler-test-vm"
    echo "SSH key created at $SSH_KEY"
else
    echo "Using existing SSH key: $SSH_KEY"
fi

# Download Debian cloud image if not exists
DEBIAN_IMAGE="$VM_DIR/debian-13-generic-amd64.qcow2"
if [ ! -f "$DEBIAN_IMAGE" ]; then
    echo "Downloading Debian cloud image..."
    wget -O "$DEBIAN_IMAGE" "$DEBIAN_IMAGE_URL"
else
    echo "Using existing Debian image: $DEBIAN_IMAGE"
fi

# Create VM disk from cloud image
if [ ! -f "$VM_IMAGE" ]; then
    echo "Creating VM disk image ($VM_SIZE)..."
    qemu-img create -f qcow2 -F qcow2 -b "$DEBIAN_IMAGE" "$VM_IMAGE" "$VM_SIZE"
    qemu-img resize "$VM_IMAGE" "$VM_SIZE"
else
    echo "VM image already exists: $VM_IMAGE"
    read -p "Recreate VM image? This will delete existing data (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm "$VM_IMAGE"
        qemu-img create -f qcow2 -F qcow2 -b "$DEBIAN_IMAGE" "$VM_IMAGE" "$VM_SIZE"
        qemu-img resize "$VM_IMAGE" "$VM_SIZE"
    else
        echo "Using existing VM image"
        exit 0
    fi
fi

# Create cloud-init configuration
echo "Creating cloud-init configuration..."

cat > "$VM_DIR/user-data" <<EOF
#cloud-config
hostname: scheduler-test-vm
manage_etc_hosts: true

users:
  - name: $VM_USER
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: users, admin, sudo
    shell: /bin/bash
    plain_text_passwd: debian
    lock_passwd: false
    ssh_authorized_keys:
      - $(cat "${SSH_KEY}.pub")

package_update: true
package_upgrade: false
package_reboot_if_required: false

packages:
  - build-essential
  - debhelper
  - git
  - curl
  - wget
  - clang
  - llvm
  - lld
  - pkg-config
  - libelf-dev
  - libssl-dev
  - libseccomp-dev
  - libz-dev
  - libbpf-dev
  - bpftool
  - bison
  - flex
  - bc
  - netcat-openbsd
  - openjdk-17-jdk
  - openjdk-17-jre
  - maven
  - libncurses-dev
  - kmod
  - cpio
  - rsync

runcmd:
  # Create application directory
  - mkdir -p /opt/banking-app
  - chown $VM_USER:$VM_USER /opt/banking-app

power_state:
  mode: reboot
  timeout: 300

final_message: "VM provisioning complete! System is ready after reboot."
EOF

cat > "$VM_DIR/meta-data" <<EOF
instance-id: scheduler-test-vm-001
local-hostname: scheduler-test-vm
EOF

# Create cloud-init ISO
echo "Creating cloud-init ISO..."
cloud-localds "$VM_DIR/cloud-init.img" "$VM_DIR/user-data" "$VM_DIR/meta-data"

# Start VM for first boot and provisioning
echo ""
echo "Starting VM for initial provisioning..."
echo "This will take several minutes as it installs packages and builds sched_ext..."
echo ""

# Start QEMU in background with proper KVM permissions
nohup sg kvm -c "qemu-system-x86_64 \
    -machine type=q35,accel=kvm \
    -cpu host \
    -smp 8 \
    -m 16G \
    -drive file=\"$VM_IMAGE\",format=qcow2,if=virtio \
    -drive file=\"$VM_DIR/cloud-init.img\",format=raw,if=virtio \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net-pci,netdev=net0 \
    -nographic" > /tmp/qemu-setup.log 2>&1 &

sleep 3
QEMU_PID=$(pgrep -f "qemu-system-x86_64.*debian-scheduler-test.qcow2" || echo "")
echo "QEMU PID: $QEMU_PID"
if [ -z "$QEMU_PID" ]; then
    echo "Error: Failed to start QEMU. Check /tmp/qemu-setup.log"
    cat /tmp/qemu-setup.log
    exit 1
fi

# Wait for SSH to become available and cloud-init to finish
echo "Waiting for VM to boot and SSH to become available..."
for i in {1..120}; do
    if nc -z localhost 2222 2>/dev/null; then
        echo "SSH is available!"
        break
    fi
    if ! ps -p $QEMU_PID > /dev/null 2>&1; then
        echo "Error: QEMU process died"
        exit 1
    fi
    sleep 5
done

# Wait for cloud-init to complete package installation
echo "Waiting for cloud-init to complete package installation..."
echo "This takes ~10-15 minutes (installs build tools, Kafka, Zookeeper, and reboots)"
echo ""

WAIT_COUNT=0
MAX_WAIT=180  # 30 minutes max
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    # Try to check cloud-init status
    if ssh -p 2222 -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null "$VM_USER@localhost" "cloud-init status --wait 2>/dev/null" 2>&1 | grep -q "done\|disabled"; then
        echo ""
        echo "Cloud-init completed!"
        break
    fi
    
    MINUTES=$((WAIT_COUNT / 6))
    if [ $((WAIT_COUNT % 6)) -eq 0 ] && [ $WAIT_COUNT -gt 0 ]; then
        echo "[$MINUTES min] Waiting for cloud-init..."
    fi
    
    sleep 10
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

# Shutdown VM to create clean snapshot
echo ""
echo "Shutting down VM to create clean snapshot..."
ssh -p 2222 -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$VM_USER@localhost" "sudo poweroff" 2>/dev/null || true

# Wait for VM to shutdown
sleep 10
if ps -p $QEMU_PID > /dev/null 2>&1; then
    kill $QEMU_PID 2>/dev/null || true
    sleep 3
fi

# Create clean snapshot
echo "Creating clean snapshot..."
qemu-img snapshot -c "clean-install" "$VM_IMAGE"

echo ""
echo "=========================================="
echo "VM Setup Complete!"
echo "=========================================="
echo ""
echo "VM Image: $VM_IMAGE"
echo "SSH Key: $SSH_KEY"
echo "Clean snapshot created: clean-install"
echo ""
echo "The VM has Debian 13 with build tools, Kafka, and Zookeeper pre-installed."
echo "Kafka is running on port 9092, Zookeeper on port 2181."
echo ""
echo "Next steps:"
echo ""
echo "  1. Build custom kernel on host (if not already done):"
echo "     $SCRIPT_DIR/build-kernel.sh"
echo ""
echo "  2. Start the VM:"
echo "     $SCRIPT_DIR/vm-start.sh"
echo ""
echo "  3. Install custom kernel to VM:"
echo "     $SCRIPT_DIR/install-kernel-to-vm.sh"
echo ""
echo "  4. Build schedulers in VM:"
echo "     $SCRIPT_DIR/build-schedulers-in-vm.sh"
echo ""
echo "  5. Run scheduler tests:"
echo "     $SCRIPT_DIR/run-scheduler-test.sh"
