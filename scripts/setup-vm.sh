#!/bin/bash

# Setup and provision a Debian VM for scheduler testing
# This script creates a QEMU VM with all necessary dependencies

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
  # Install Rust
  - sudo -u $VM_USER bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'
  - sudo -u $VM_USER bash -c 'echo "source \$HOME/.cargo/env" >> /home/$VM_USER/.bashrc'
  
  # Download and prepare kernel source with sched_ext enabled
  - sudo -u $VM_USER bash -c 'cd /home/$VM_USER && wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.6.tar.xz'
  - sudo -u $VM_USER bash -c 'cd /home/$VM_USER && tar xf linux-6.12.6.tar.xz'
  - sudo -u $VM_USER bash -c 'cd /home/$VM_USER/linux-6.12.6 && git init && git config user.email "builder@localhost" && git config user.name "Builder" && git add -A && git commit -m "Initial commit"'
  - sudo -u $VM_USER bash -c 'cd /home/$VM_USER/linux-6.12.6 && cp /boot/config-\$(uname -r) .config'
  - sudo -u $VM_USER bash -c 'cd /home/$VM_USER/linux-6.12.6 && echo "CONFIG_SCHED_CLASS_EXT=y" >> .config && echo "CONFIG_SCHED_DEBUG=y" >> .config'
  - sudo -u $VM_USER bash -c 'cd /home/$VM_USER/linux-6.12.6 && make olddefconfig'
  
  # Build kernel with 6 parallel jobs
  - sudo -u $VM_USER bash -c 'cd /home/$VM_USER/linux-6.12.6 && make -j6 deb-pkg LOCALVERSION=-schedext KDEB_PKGVERSION=\$(make kernelversion)-1'
  
  # Install custom kernel and update GRUB to boot it by default
  - bash -c 'cd /home/$VM_USER && dpkg -i linux-image-6*.deb linux-headers-6*.deb'
  - sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT="Advanced options for Debian GNU\\/Linux>Debian GNU\\/Linux, with Linux 6.12.6-schedext"/' /etc/default/grub
  - update-grub
  
  # Clone sched_ext repository
  - sudo -u $VM_USER bash -c 'cd /home/$VM_USER && git clone https://github.com/sched-ext/scx.git'
  
  # Build and install C schedulers (need PATH for bpftool)
  - sudo -u $VM_USER bash -c 'cd /home/$VM_USER/scx && source /home/$VM_USER/.cargo/env && export PATH=/usr/sbin:\$PATH && make'
  - bash -c 'cd /home/$VM_USER/scx && make install'
  
  # Build Rust schedulers with 6 parallel jobs
  - sudo -u $VM_USER bash -c 'cd /home/$VM_USER/scx/scheds/rust && source /home/$VM_USER/.cargo/env && export PATH=/usr/sbin:\$PATH && cargo build --release -j6 --workspace'
  
  # Install key Rust schedulers to /usr/local/bin
  - bash -c 'cp /home/$VM_USER/scx/target/release/scx_rusty /home/$VM_USER/scx/target/release/scx_lavd /home/$VM_USER/scx/target/release/scx_bpfland /home/$VM_USER/scx/target/release/scx_layered /usr/local/bin/'
  - bash -c 'chmod +x /usr/local/bin/scx_*'
  
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

# Wait for SSH to become available
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

# Wait for cloud-init to complete with progress updates
echo "Waiting for cloud-init to complete provisioning..."
echo "This takes 25-35 minutes due to kernel build (make -j6 deb-pkg with 8 CPUs)"
echo ""
sleep 10

LAST_LOG_SIZE=0
for i in {1..540}; do  # 90 minutes = 540 iterations of 10 seconds
    # Check if cloud-init is done
    if ssh -p 2222 -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$VM_USER@localhost" "cloud-init status 2>/dev/null | grep -q 'status: done'" 2>/dev/null; then
        echo ""
        echo "Cloud-init completed!"
        break
    fi
    
    # Show progress every 30 seconds
    if [ $((i % 3)) -eq 0 ]; then
        MINUTES=$((i / 6))
        # Get last few lines of cloud-init log to show current activity
        CURRENT_ACTIVITY=$(ssh -p 2222 -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$VM_USER@localhost" "sudo tail -3 /var/log/cloud-init-output.log 2>/dev/null | grep -v '^$' | tail -1" 2>/dev/null || echo "Building...")
        
        # Check log size to detect if build is progressing
        CURRENT_LOG_SIZE=$(ssh -p 2222 -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$VM_USER@localhost" "sudo wc -c < /var/log/cloud-init-output.log 2>/dev/null" 2>/dev/null || echo "0")
        
        if [ "$CURRENT_LOG_SIZE" -gt "$LAST_LOG_SIZE" ]; then
            echo "[$MINUTES min] Active: ${CURRENT_ACTIVITY:0:80}"
            LAST_LOG_SIZE=$CURRENT_LOG_SIZE
        else
            echo "[$MINUTES min] Waiting..."
        fi
    fi
    
    sleep 10
done

echo ""
echo "Verifying sched_ext installation..."
ssh -p 2222 -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$VM_USER@localhost" "command -v scx_rusty && command -v scx_lavd && command -v scx_bpfland && command -v scx_layered" || echo "Warning: Some schedulers may not be installed"

# Create clean snapshot
echo ""
echo "Creating clean snapshot..."
kill $QEMU_PID 2>/dev/null || true
wait $QEMU_PID 2>/dev/null || true
sleep 5

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
echo "Next steps:"
echo "  1. Start VM: $SCRIPT_DIR/vm-start.sh"
echo "  2. Connect: $SCRIPT_DIR/vm-ssh.sh"
echo "  3. Run tests: $SCRIPT_DIR/run-scheduler-test.sh"
