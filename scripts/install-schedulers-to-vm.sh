#!/bin/bash

# Install pre-built sched_ext schedulers to the VM

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/scheduler-build}"
SSH_KEY="$HOME/.ssh/scheduler_test_vm"
SSH_PORT="${SSH_PORT:-2222}"
VM_USER="${VM_USER:-debian}"

# shellcheck source=lib/scx-common.sh
source "$SCRIPT_DIR/lib/scx-common.sh"

echo "=========================================="
echo "Installing Schedulers to VM"
echo "=========================================="
echo ""

# Check if VM is running
if ! nc -z localhost $SSH_PORT 2>/dev/null; then
    echo "Error: VM is not running on port $SSH_PORT"
    echo "Start it with: ./scripts/vm-start.sh"
    exit 1
fi

# Check if schedulers exist
if [ ! -d "$BUILD_DIR/scx" ]; then
    echo "Error: Schedulers not found in $BUILD_DIR/scx"
    echo "Build them first with: ./scripts/build-schedulers.sh"
    exit 1
fi

# Find built schedulers.
# Note: upstream deleted scheds/c at v1.1.0 - there are no C schedulers any
# more, and everything lands in the single cargo workspace target dir.
echo "Finding built schedulers..."
SCHEDULERS=$(scx_built_binaries "$BUILD_DIR/scx")

if [ -z "$SCHEDULERS" ]; then
    echo "Error: No schedulers found in $BUILD_DIR/scx/target/release"
    echo "Build them first with: ./scripts/build-schedulers.sh"
    exit 1
fi

echo "Found $(echo "$SCHEDULERS" | wc -l) schedulers:"
echo "$SCHEDULERS" | sed 's|.*/|  |'
echo ""

# Create temp directory for schedulers
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy schedulers to temp directory
echo "Preparing scheduler binaries..."
echo "$SCHEDULERS" | while read -r sched; do
    [ -n "$sched" ] && cp "$sched" "$TEMP_DIR/"
done

# Copy to VM
echo "Copying schedulers to VM..."
scp -P $SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$TEMP_DIR"/scx_* $VM_USER@localhost:/tmp/

# Install to /usr/local/bin
echo "Installing schedulers..."
ssh -p $SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@localhost "sudo install -m 0755 /tmp/scx_* /usr/local/bin/ && rm -f /tmp/scx_*"

echo ""
echo "=========================================="
echo "Scheduler Installation Complete!"
echo "=========================================="
echo ""
echo "Installed schedulers:"
ssh -p $SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@localhost "ls -1 /usr/local/bin/scx_*"
echo ""
echo "Test a scheduler with:"
echo "  ./scripts/vm-scheduler-switch.sh scx_lavd"
