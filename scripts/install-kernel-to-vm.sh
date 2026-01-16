#!/bin/bash

# Install custom kernel packages to the VM
# Set SKIP_PROMPT=1 to run non-interactively

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/kernel-build}"
SSH_KEY="$HOME/.ssh/scheduler_test_vm"
SSH_PORT="${SSH_PORT:-2222}"

echo "=========================================="
echo "Installing Custom Kernel to VM"
echo "=========================================="
echo ""

# Check if VM is running
if ! nc -z localhost $SSH_PORT 2>/dev/null; then
    echo "Error: VM is not running on port $SSH_PORT"
    echo "Start it with: ./scripts/vm-start.sh"
    exit 1
fi

# Check if kernel packages exist
KERNEL_IMAGE=$(ls "$BUILD_DIR"/linux-image-6*.deb 2>/dev/null | grep -v dbg | head -1)
KERNEL_HEADERS=$(ls "$BUILD_DIR"/linux-headers-6*.deb 2>/dev/null | head -1)

if [ -z "$KERNEL_IMAGE" ] || [ -z "$KERNEL_HEADERS" ]; then
    echo "Error: Kernel packages not found in $BUILD_DIR"
    echo "Build them first with: ./scripts/build-kernel.sh"
    exit 1
fi

echo "Found kernel packages:"
echo "  Image: $(basename "$KERNEL_IMAGE")"
echo "  Headers: $(basename "$KERNEL_HEADERS")"
echo ""

echo "Copying kernel packages to VM..."
scp -P $SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$KERNEL_IMAGE" \
    "$KERNEL_HEADERS" \
    debian@localhost:/home/debian/

echo "Installing kernel packages..."
ssh -p $SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    debian@localhost "sudo dpkg -i /home/debian/$(basename "$KERNEL_IMAGE") /home/debian/$(basename "$KERNEL_HEADERS")"

echo "Configuring GRUB to boot custom kernel by default..."
ssh -p $SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    debian@localhost 'sudo sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=\"1>2\"/" /etc/default/grub && sudo update-grub'

echo "Rebooting VM to load custom kernel..."
ssh -p $SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    debian@localhost "sudo reboot" || true

echo ""
echo "=========================================="
echo "Kernel Installation Complete!"
echo "=========================================="
echo ""
echo "Reboot the VM to use the new kernel:"
echo "  ssh -p $SSH_PORT -i $SSH_KEY -o StrictHostKeyChecking=no debian@localhost \"sudo reboot\""
echo ""
echo "After reboot, verify with:"
echo "  ssh -p $SSH_PORT -i $SSH_KEY -o StrictHostKeyChecking=no debian@localhost \"uname -r && cat /sys/kernel/sched_ext/state\""
