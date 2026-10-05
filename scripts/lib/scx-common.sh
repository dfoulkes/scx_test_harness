#!/bin/bash
# Shared helpers for fetching and building sched_ext (scx).
#
# Sourced by the build-schedulers-*.sh scripts so the upstream pin and the
# layout preflight live in exactly one place.
#
# Upstream history that this file exists to absorb:
#   * v1.1.0 (2026-03-07) removed the top-level Makefile and meson build.
#     The project is now a pure Cargo workspace rooted at the repo top level.
#   * v1.1.0 also deleted scheds/c entirely. There are no C schedulers.
#   * scheds/rust has never had its own Cargo.toml; cargo walks up to the
#     workspace root, so builds are driven from the repo root.

SCX_REPO="${SCX_REPO:-https://github.com/sched-ext/scx.git}"

# Pin to a released tag by default. Unpinned `main` is what silently broke this
# harness for five months: the scripts kept pulling a tree whose build system
# had been deleted underneath them. Override with SCX_REF=main to track tip.
SCX_REF="${SCX_REF:-v1.1.3}"

# Schedulers built by the workspace at scx v1.1.3.
# Sources live in scheds/rust/ and scheds/experimental/ - note that scx_flow
# and scx_mlfq are in the latter, so listing scheds/rust alone under-reports.
SCX_ALL_SCHEDS=(
    scx_beerland
    scx_bpfland
    scx_cake
    scx_chaos
    scx_cosmos
    scx_flash
    scx_flow
    scx_forge
    scx_lavd
    scx_layered
    scx_mitosis
    scx_mlfq
    scx_p2dq
    scx_pandemonium
    scx_rlfifo
    scx_rustland
    scx_rusty
    scx_tickless
)

# Built by the same workspace but NOT schedulers - do not install or offer
# these as something the test runner can switch to.
#   scx_arena_selftests : scx_arena library selftests
#   scx_characterize    : workload characterization tool (perf wrapper)
SCX_NON_SCHEDULERS=(
    scx_arena_selftests
    scx_characterize
)

# Fail loudly and specifically if upstream has moved the ground again.
scx_preflight() {
    local repo_root="$1"
    local failed=0

    if [ ! -f "$repo_root/Cargo.toml" ]; then
        echo "ERROR: $repo_root/Cargo.toml not found." >&2
        echo "       scx is expected to be a Cargo workspace rooted here." >&2
        failed=1
    fi

    if [ ! -d "$repo_root/scheds/rust" ]; then
        echo "ERROR: $repo_root/scheds/rust not found." >&2
        echo "       Upstream has moved the scheduler sources." >&2
        failed=1
    fi

    if [ -f "$repo_root/Makefile" ] || [ -f "$repo_root/meson.build" ]; then
        echo "NOTE:  $repo_root has a Makefile/meson.build - you are on a ref" >&2
        echo "       older than v1.1.0. This harness builds via cargo only." >&2
    fi

    if [ "$failed" -ne 0 ]; then
        echo "" >&2
        echo "The scx layout at ref '$SCX_REF' is not what this harness expects." >&2
        echo "Check https://github.com/sched-ext/scx for build changes, then" >&2
        echo "update scripts/lib/scx-common.sh. Refusing to continue." >&2
        return 1
    fi

    return 0
}

# Clone (or update) scx and check out the pinned ref.
scx_fetch() {
    local dest="$1"

    if [ ! -d "$dest/.git" ]; then
        echo "Cloning scx from $SCX_REPO..."
        git clone "$SCX_REPO" "$dest"
    else
        echo "Updating existing scx checkout..."
        git -C "$dest" fetch --all --tags --prune
    fi

    echo "Checking out pinned ref: $SCX_REF"
    if ! git -C "$dest" checkout --detach "$SCX_REF" 2>/dev/null; then
        echo "ERROR: ref '$SCX_REF' not found in $SCX_REPO." >&2
        echo "       Available recent tags:" >&2
        git -C "$dest" tag --sort=-creatordate | head -5 | sed 's/^/         /' >&2
        return 1
    fi

    echo "scx is at: $(git -C "$dest" describe --tags --always)"
}

# Build the whole workspace. Schedulers land in <repo_root>/target/release/.
scx_build() {
    local repo_root="$1"
    local jobs="${2:-$(nproc)}"

    # shellcheck disable=SC1091
    source "$HOME/.cargo/env" 2>/dev/null || true

    echo "Building scx workspace (cargo, $jobs jobs)..."
    ( cd "$repo_root" && cargo build --release -j"$jobs" --workspace )
}

# List the scheduler binaries that actually got built, excluding the tools and
# selftests the workspace also produces under the same scx_* prefix.
scx_built_binaries() {
    local repo_root="$1"
    local -a prune=()
    local tool

    for tool in "${SCX_NON_SCHEDULERS[@]}"; do
        prune+=( ! -name "$tool" )
    done

    find "$repo_root/target/release" -maxdepth 1 -type f -executable -name 'scx_*' \
        ! -name '*.d' "${prune[@]}" 2>/dev/null | sort
}
