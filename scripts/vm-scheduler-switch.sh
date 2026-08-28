#!/bin/bash

# Switch scheduler inside the VM
# Usage: ./vm-scheduler-switch.sh <scheduler-name>
#        scheduler-name: cfs, or any scx_* binary installed in the VM
#
# Verifies that the scheduler actually attached. A sched_ext scheduler can log
# "started" and then die on the first fork (see scx_rusty on kernels >= 7.1.5,
# upstream PR #3721), which would otherwise silently leave the VM on CFS and
# quietly invalidate the benchmark run.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/scx-common.sh
source "$SCRIPT_DIR/lib/scx-common.sh"

if [ -z "$1" ]; then
    echo "Usage: $0 <scheduler-name>"
    echo ""
    echo "Available: cfs, ${SCX_ALL_SCHEDS[*]}"
    exit 1
fi

SCHEDULER="$1"
SETTLE_SECONDS="${SETTLE_SECONDS:-5}"

echo "Switching to scheduler: $SCHEDULER in VM"

# Stop any running sched_ext scheduler and wait for the kernel to detach
"$SCRIPT_DIR/vm-ssh.sh" "sudo pkill -9 'scx_' 2>/dev/null || true"
sleep 2

if [ "$SCHEDULER" = "cfs" ]; then
    STATE=$("$SCRIPT_DIR/vm-ssh.sh" "cat /sys/kernel/sched_ext/state 2>/dev/null || echo 'no-sched-ext'" | tr -d '\r')
    if [ "$STATE" = "enabled" ]; then
        echo "ERROR: asked for CFS but sched_ext still reports '$STATE'" >&2
        exit 1
    fi
    echo "Switched to CFS (state: $STATE)"
    exit 0
fi

# Check the scheduler binary exists in the VM
if ! "$SCRIPT_DIR/vm-ssh.sh" "command -v $SCHEDULER" > /dev/null 2>&1; then
    echo "ERROR: Scheduler $SCHEDULER not found in VM" >&2
    echo "       Install with: $SCRIPT_DIR/install-schedulers-to-vm.sh" >&2
    exit 1
fi

# Start the scheduler detached
"$SCRIPT_DIR/vm-ssh.sh" "sudo nohup $SCHEDULER > /tmp/${SCHEDULER}.log 2>&1 &"
sleep "$SETTLE_SECONDS"

# Verify it actually attached, and is still alive after settling
STATE=$("$SCRIPT_DIR/vm-ssh.sh" "cat /sys/kernel/sched_ext/state 2>/dev/null || echo 'no-sched-ext'" | tr -d '\r')
ALIVE=$("$SCRIPT_DIR/vm-ssh.sh" "pgrep -c -x '$SCHEDULER' 2>/dev/null || echo 0" | tr -d '\r')

if [ "$STATE" != "enabled" ] || [ "$ALIVE" -eq 0 ]; then
    echo "" >&2
    echo "ERROR: $SCHEDULER failed to attach." >&2
    echo "       sched_ext state: $STATE" >&2
    echo "       processes alive: $ALIVE" >&2
    echo "       --- last 30 lines of /tmp/${SCHEDULER}.log ---" >&2
    "$SCRIPT_DIR/vm-ssh.sh" "tail -n 30 /tmp/${SCHEDULER}.log 2>/dev/null || echo '(no log)'" >&2
    exit 1
fi

echo "Started $SCHEDULER (state: $STATE, processes: $ALIVE)"
