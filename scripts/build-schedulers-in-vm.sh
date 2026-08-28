#!/bin/bash

# Build sched_ext schedulers inside the VM
# Must be run AFTER installing the custom kernel

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_KEY="$HOME/.ssh/scheduler_test_vm"
SSH_PORT="${SSH_PORT:-2222}"
VM_USER="${VM_USER:-debian}"

# shellcheck source=lib/scx-common.sh
source "$SCRIPT_DIR/lib/scx-common.sh"

echo "=========================================="
echo "Building Schedulers in VM"
echo "=========================================="
echo ""
echo "scx Ref: $SCX_REF"
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

# Build schedulers in VM. SCX_REF is passed through so the VM builds the same
# pinned upstream ref as the host scripts.
ssh -p $SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@localhost "SCX_REF='$SCX_REF' SCX_REPO='$SCX_REPO' bash -s" <<'REMOTE_SCRIPT'
set -e

SCX_DIR="$HOME/scx"

# Install Rust if not present
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
source "$HOME/.cargo/env" 2>/dev/null || true

# Clone or update scx, then pin
if [ ! -d "$SCX_DIR/.git" ]; then
    echo "Cloning sched_ext repository..."
    git clone "$SCX_REPO" "$SCX_DIR"
else
    echo "Updating existing scx checkout..."
    git -C "$SCX_DIR" fetch --all --tags --prune
fi

echo "Checking out pinned ref: $SCX_REF"
git -C "$SCX_DIR" checkout --detach "$SCX_REF"
echo "scx is at: $(git -C "$SCX_DIR" describe --tags --always)"

# Layout preflight - upstream removed the Makefile/meson build and scheds/c at
# v1.1.0. Fail loudly rather than silently producing nothing.
if [ ! -f "$SCX_DIR/Cargo.toml" ] || [ ! -d "$SCX_DIR/scheds/rust" ]; then
    echo "ERROR: scx layout at ref '$SCX_REF' is not the expected Cargo workspace." >&2
    echo "       Expected $SCX_DIR/Cargo.toml and $SCX_DIR/scheds/rust." >&2
    exit 1
fi

# Build the workspace.
# Parallelism is limited to avoid OOM: a 16GB VM cannot survive LTO linking of
# the full workspace at -j$(nproc).
echo ""
echo "Building scx workspace (cargo)..."
cd "$SCX_DIR"
cargo build --release -j"${CARGO_JOBS:-2}" --workspace

# Install every scheduler that was built
echo ""
echo "Installing schedulers to /usr/local/bin..."
mapfile -t BUILT < <(find "$SCX_DIR/target/release" -maxdepth 1 -type f -executable \
    -name 'scx_*' ! -name '*.d' | sort)

if [ ${#BUILT[@]} -eq 0 ]; then
    echo "ERROR: cargo reported success but no scx_* binaries were produced." >&2
    exit 1
fi

sudo install -m 0755 "${BUILT[@]}" /usr/local/bin/

echo ""
echo "Installed ${#BUILT[@]} schedulers:"
ls -1 /usr/local/bin/scx_* | sed 's|.*/|  |'
REMOTE_SCRIPT

echo ""
echo "=========================================="
echo "Scheduler Build Complete!"
echo "=========================================="
echo ""
echo "Verify with:"
echo "  ./scripts/vm-ssh.sh 'ls -la /usr/local/bin/scx_*'"
