#!/bin/bash

# Build sched_ext schedulers on Arch Linux
# Optimized for host system builds

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/scheduler-build}"
NUM_JOBS="${NUM_JOBS:-$(nproc)}"

# shellcheck source=lib/scx-common.sh
source "$SCRIPT_DIR/lib/scx-common.sh"

echo "=========================================="
echo "Building sched_ext Schedulers (Arch Linux)"
echo "=========================================="
echo ""
echo "Build Directory: $BUILD_DIR"
echo "Parallel Jobs:   $NUM_JOBS"
echo "scx Ref:         $SCX_REF"
echo ""

# Check and install prerequisites (Arch package names)
echo "Checking prerequisites..."
MISSING_PACKAGES=()

declare -A ARCH_PACKAGES=(
    ["git"]="git"
    ["clang"]="clang"
    ["llvm"]="llvm"
    ["lld"]="lld"
    ["pkg-config"]="pkgconf"
    ["libelf"]="libelf"
    ["libbpf"]="libbpf"
    ["zlib"]="zlib"
    ["openssl"]="openssl"
    ["make"]="make"
)

for pkg in "${!ARCH_PACKAGES[@]}"; do
    if ! pacman -Q "${ARCH_PACKAGES[$pkg]}" &> /dev/null; then
        MISSING_PACKAGES+=("${ARCH_PACKAGES[$pkg]}")
    fi
done

# Check for Rust
if ! command -v cargo &> /dev/null; then
    echo "Installing Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi

if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
    echo "Installing missing packages: ${MISSING_PACKAGES[*]}"
    sudo pacman -S --needed --noconfirm base-devel "${MISSING_PACKAGES[@]}"
fi

mkdir -p "$BUILD_DIR"

# Fetch scx at the pinned ref, then verify the layout is what we expect
scx_fetch "$BUILD_DIR/scx"
scx_preflight "$BUILD_DIR/scx"

# Single cargo workspace build - upstream dropped make/meson at v1.1.0 and
# deleted scheds/c entirely, so there is nothing else to build.
scx_build "$BUILD_DIR/scx" "$NUM_JOBS"

echo ""
echo "=========================================="
echo "Scheduler Build Complete!"
echo "=========================================="
echo ""
echo "Schedulers built in: $BUILD_DIR/scx/target/release/"
BUILT=$(scx_built_binaries "$BUILD_DIR/scx")
if [ -z "$BUILT" ]; then
    echo "ERROR: cargo reported success but no scx_* binaries were produced." >&2
    exit 1
fi
echo "$BUILT" | sed 's|.*/|  |'
echo ""
echo "Built $(echo "$BUILT" | wc -l) schedulers."
echo ""
echo "To run scx_lavd:"
echo "  sudo $BUILD_DIR/scx/target/release/scx_lavd -v"
echo ""
echo "To install to the VM:"
echo "  $SCRIPT_DIR/install-schedulers-to-vm.sh"
