#!/bin/bash

# Build sched_ext schedulers inside the VM
# Must be run AFTER installing the custom kernel

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_KEY="$HOME/.ssh/scheduler_test_vm"
SSH_PORT="${SSH_PORT:-2222}"
VM_USER="${VM_USER:-debian}"

echo "=========================================="
echo "Building Schedulers in VM"
echo "=========================================="
echo ""

# Check if VM is running
if ! nc -z localhost $SSH_PORT 2>/dev/null; then
    echo "Error: VM is not running on port $SSH_PORT"
    echo "Start it with: ./scripts/vm-start.sh"
    exit 1
fi

# Check kernel version
echo "Checking VM kernel version..."
KERNEL_VERSION=$(ssh -p $SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@localhost "uname -r" 2>/dev/null)

if [[ ! "$KERNEL_VERSION" =~ schedext ]]; then
    echo "Warning: VM is not running custom kernel (current: $KERNEL_VERSION)"
    echo "Install custom kernel first with: ./scripts/install-kernel-to-vm.sh"
    if [ "$SKIP_PROMPT" != "1" ]; then
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "Continuing anyway (SKIP_PROMPT=1)"
    fi
fi

echo "Building schedulers on VM kernel: $KERNEL_VERSION"
echo ""

# Build schedulers in VM
ssh -p $SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@localhost "bash -s" <<'REMOTE_SCRIPT'
set -e

# Install Rust if not present
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

# Clone scx if not present
if [ ! -d "$HOME/scx" ]; then
    echo "Cloning sched_ext repository..."
    git clone https://github.com/sched-ext/scx.git "$HOME/scx"
fi

cd "$HOME/scx"
git pull || true

# Build C schedulers
echo ""
echo "Building C schedulers..."
source "$HOME/.cargo/env"
export PATH=/usr/sbin:$PATH
make -j$(nproc)

# Install C schedulers
echo "Installing C schedulers..."
sudo make install

# Build Rust schedulers
echo ""
echo "Building Rust schedulers..."
cd scheds/rust
# Limit parallelism to avoid OOM (16GB VM has limited memory for LTO builds)
# Using -j2 instead of -j$(nproc) to prevent SIGKILL during link-time optimization
cargo build --release -j2 --workspace

# Install Rust schedulers
echo "Installing Rust schedulers..."
sudo cp ../../target/release/scx_rusty \
    ../../target/release/scx_lavd \
    ../../target/release/scx_bpfland \
    ../../target/release/scx_layered \
    /usr/local/bin/ 2>/dev/null || true
sudo chmod +x /usr/local/bin/scx_* 2>/dev/null || true

echo ""
echo "Installed schedulers:"
ls -1 /usr/local/bin/scx_* 2>/dev/null || echo "  (no schedulers found)"
REMOTE_SCRIPT

echo ""
echo "=========================================="
echo "Scheduler Build Complete!"
echo "=========================================="
echo ""
echo "Verify with:"
echo "  ./scripts/vm-ssh.sh 'ls -la /usr/local/bin/scx_*'"
