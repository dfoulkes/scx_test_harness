#!/bin/bash

# Install pre-built sched_ext schedulers to the VM

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/scheduler-build}"
SSH_KEY="$HOME/.ssh/scheduler_test_vm"
SSH_PORT="${SSH_PORT:-2222}"
VM_USER="${VM_USER:-debian}"

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

# Find built schedulers
echo "Finding built schedulers..."
RUST_SCHEDULERS=$(find "$BUILD_DIR/scx/target/release" -maxdepth 1 -type f -executable -name "scx_*" 2>/dev/null | grep -v "\.d$" || true)
C_SCHEDULERS=$(find "$BUILD_DIR/scx/build/scheds/c" -maxdepth 1 -type f -executable -name "scx_*" 2>/dev/null || true)

if [ -z "$RUST_SCHEDULERS" ] && [ -z "$C_SCHEDULERS" ]; then
    echo "Error: No schedulers found"
    echo "Build them first with: ./scripts/build-schedulers.sh"
    exit 1
fi

echo "Found schedulers:"
echo "$RUST_SCHEDULERS" | while read -r sched; do
    [ -n "$sched" ] && echo "  Rust: $(basename "$sched")"
done
echo "$C_SCHEDULERS" | while read -r sched; do
    [ -n "$sched" ] && echo "  C: $(basename "$sched")"
done
echo ""

# Create temp directory for schedulers
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy schedulers to temp directory
echo "Preparing scheduler binaries..."
echo "$RUST_SCHEDULERS" | while read -r sched; do
    [ -n "$sched" ] && cp "$sched" "$TEMP_DIR/"
done
echo "$C_SCHEDULERS" | while read -r sched; do
    [ -n "$sched" ] && cp "$sched" "$TEMP_DIR/"
done

# Copy to VM
echo "Copying schedulers to VM..."
scp -P $SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$TEMP_DIR"/scx_* $VM_USER@localhost:/tmp/

# Install to /usr/local/bin
echo "Installing schedulers..."
ssh -p $SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@localhost "sudo mv /tmp/scx_* /usr/local/bin/ && sudo chmod +x /usr/local/bin/scx_*"

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
echo "  ./scripts/vm-ssh.sh 'sudo /usr/local/bin/scx_rusty'"
