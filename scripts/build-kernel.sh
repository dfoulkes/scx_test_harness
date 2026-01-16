#!/bin/bash

# Build custom Linux kernel with sched_ext support on the host
# This is much faster than building in the VM

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/kernel-build}"
KERNEL_VERSION="${KERNEL_VERSION:-6.12.6}"
NUM_JOBS="${NUM_JOBS:-$(nproc)}"

echo "=========================================="
echo "Building Custom Kernel with sched_ext"
echo "=========================================="
echo ""
echo "Kernel Version: $KERNEL_VERSION"
echo "Build Directory: $BUILD_DIR"
echo "Parallel Jobs: $NUM_JOBS"
echo ""

# Check and install prerequisites
echo "Checking prerequisites..."
MISSING_PACKAGES=()

for cmd in wget tar make gcc flex bison bc libelf-dev libssl-dev; do
    case $cmd in
        libelf-dev|libssl-dev)
            if ! dpkg -l | grep -q "^ii  ${cmd%-dev}1"; then
                MISSING_PACKAGES+=($cmd)
            fi
            ;;
        *)
            if ! command -v $cmd &> /dev/null; then
                MISSING_PACKAGES+=($cmd)
            fi
            ;;
    esac
done

if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
    echo "Installing missing packages: ${MISSING_PACKAGES[*]}"
    sudo apt-get update
    sudo apt-get install -y build-essential flex bison bc libelf-dev libssl-dev debhelper rsync dwarves
fi

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Download kernel source if not already present
if [ ! -f "linux-${KERNEL_VERSION}.tar.xz" ]; then
    echo "Downloading Linux ${KERNEL_VERSION}..."
    wget "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz"
fi

# Extract if not already extracted
if [ ! -d "linux-${KERNEL_VERSION}" ]; then
    echo "Extracting kernel source..."
    tar xf "linux-${KERNEL_VERSION}.tar.xz"
fi

cd "linux-${KERNEL_VERSION}"

# Initialize git repo (required for deb-pkg)
if [ ! -d ".git" ]; then
    echo "Initializing git repository..."
    git init
    git config user.email "builder@localhost"
    git config user.name "Builder"
    git add -A
    git commit -m "Initial commit"
fi

# Get Debian kernel config from VM if available
if [ ! -f ".config" ]; then
    echo "Fetching Debian kernel config from VM..."
    SSH_KEY="${SSH_KEY:-$HOME/.ssh/scheduler_test_vm}"
    VM_USER="${VM_USER:-debian}"
    
    if ssh -p 2222 -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$VM_USER@localhost" "test -f /boot/config-\$(uname -r)" 2>/dev/null; then
        echo "Downloading config from running VM..."
        scp -P 2222 -i "$SSH_KEY" -o StrictHostKeyChecking=no "$VM_USER@localhost:/boot/config-\$(uname -r)" .config
        # Remove any WSL or distro-specific LOCALVERSION settings
        sed -i '/^CONFIG_LOCALVERSION=/d' .config
    else
        echo "VM not available, using kernel defconfig..."
        make defconfig
    fi
fi

# Enable sched_ext dependencies first
echo "Enabling CONFIG_SCHED_CLASS_EXT dependencies..."
./scripts/config --enable CONFIG_BPF_SYSCALL
./scripts/config --enable CONFIG_BPF_JIT

# Enable DEBUG_INFO and DEBUG_INFO_BTF (required for sched_ext)
./scripts/config --disable CONFIG_DEBUG_INFO_NONE
./scripts/config --enable CONFIG_DEBUG_INFO
./scripts/config --enable CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
./scripts/config --disable CONFIG_DEBUG_INFO_SPLIT
./scripts/config --disable CONFIG_DEBUG_INFO_REDUCED
./scripts/config --enable CONFIG_DEBUG_INFO_BTF

# Enable sched_ext using scripts/config
echo "Enabling CONFIG_SCHED_CLASS_EXT..."
./scripts/config --enable CONFIG_SCHED_CLASS_EXT
./scripts/config --enable CONFIG_SCHED_DEBUG

# Update config with dependencies
echo "Running make olddefconfig..."
make olddefconfig

# Verify sched_ext is enabled
if ! grep -q "CONFIG_SCHED_CLASS_EXT=y" .config; then
    echo "Error: CONFIG_SCHED_CLASS_EXT was not enabled"
    exit 1
fi

echo "CONFIG_SCHED_CLASS_EXT is enabled!"
echo ""

# Build kernel packages
echo "Building kernel packages with $NUM_JOBS parallel jobs..."
echo "This will take 5-15 minutes depending on your CPU..."
echo ""

make -j${NUM_JOBS} deb-pkg LOCALVERSION=-schedext KDEB_PKGVERSION=$(make kernelversion)-1

echo ""
echo "=========================================="
echo "Kernel Build Complete!"
echo "=========================================="
echo ""
echo "Kernel packages built in: $BUILD_DIR"
ls -lh "$BUILD_DIR"/*.deb
echo ""
echo "Next steps:"
echo "  1. Copy packages to VM with: ./scripts/install-kernel-to-vm.sh"
echo "  2. Or manually: scp -P 2222 -i ~/.ssh/scheduler_test_vm $BUILD_DIR/linux-*.deb debian@localhost:~/"
