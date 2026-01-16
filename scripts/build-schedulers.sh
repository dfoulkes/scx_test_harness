#!/bin/bash

# Build sched_ext schedulers on the host
# Much faster than building in the VM

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/scheduler-build}"
NUM_JOBS="${NUM_JOBS:-$(nproc)}"

echo "=========================================="
echo "Building sched_ext Schedulers"
echo "=========================================="
echo ""
echo "Build Directory: $BUILD_DIR"
echo "Parallel Jobs: $NUM_JOBS"
echo ""

# Check and install prerequisites
echo "Checking prerequisites..."
MISSING_PACKAGES=()

for pkg in git clang llvm lld pkg-config libelf-dev libbpf-dev; do
    if ! command -v ${pkg%-dev} &> /dev/null && ! dpkg -l | grep -q "^ii  $pkg"; then
        MISSING_PACKAGES+=($pkg)
    fi
done

# Check for Rust
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
    echo "Installing missing packages: ${MISSING_PACKAGES[*]}"
    sudo apt-get update
    sudo apt-get install -y build-essential git clang llvm lld pkg-config \
        libelf-dev zlib1g-dev libbpf-dev linux-tools-common linux-tools-generic
fi

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Clone sched_ext repository if not present
if [ ! -d "scx" ]; then
    echo "Cloning sched_ext repository..."
    git clone https://github.com/sched-ext/scx.git
else
    echo "Using existing sched_ext repository..."
    cd scx
    git pull
    cd ..
fi

cd scx

# Build C schedulers
echo ""
echo "Building C schedulers..."
export PATH=/usr/sbin:$PATH
make -j${NUM_JOBS}

# Build Rust schedulers
echo ""
echo "Building Rust schedulers..."
source "$HOME/.cargo/env" 2>/dev/null || true
cd scheds/rust
cargo build --release -j${NUM_JOBS} --workspace
cd ../..

echo ""
echo "=========================================="
echo "Scheduler Build Complete!"
echo "=========================================="
echo ""
echo "C schedulers built in: $BUILD_DIR/scx/build/scheds/c/"
ls -lh "$BUILD_DIR/scx/build/scheds/c/" 2>/dev/null || echo "  (no C schedulers found)"
echo ""
echo "Rust schedulers built in: $BUILD_DIR/scx/target/release/"
ls -lh "$BUILD_DIR/scx/target/release/scx_"* 2>/dev/null | grep -v "\.d$" || echo "  (no Rust schedulers found)"
echo ""
echo "Next steps:"
echo "  1. Install schedulers to VM with: ./scripts/install-schedulers-to-vm.sh"
