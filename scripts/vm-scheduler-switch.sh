#!/bin/bash

# Switch scheduler inside the VM
# Usage: ./vm-scheduler-switch.sh <scheduler-name>
#        scheduler-name: cfs, scx_rusty, scx_lavd, scx_bpfland, scx_layered

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$1" ]; then
    echo "Usage: $0 <scheduler-name>"
    echo "Available schedulers: cfs, scx_rusty, scx_lavd, scx_bpfland, scx_layered"
    exit 1
fi

SCHEDULER="$1"

echo "Switching to scheduler: $SCHEDULER in VM"

if [ "$SCHEDULER" = "cfs" ]; then
    # Switch back to CFS by killing all sched_ext schedulers
    "$SCRIPT_DIR/vm-ssh.sh" "sudo pkill -9 scx_ 2>/dev/null || true"
    sleep 2
    echo "Switched to CFS (default scheduler)"
else
    # Stop any running sched_ext scheduler
    "$SCRIPT_DIR/vm-ssh.sh" "sudo pkill -9 scx_ 2>/dev/null || true"
    sleep 2
    
    # Check if scheduler binary exists
    if ! "$SCRIPT_DIR/vm-ssh.sh" "command -v $SCHEDULER" > /dev/null 2>&1; then
        echo "Error: Scheduler $SCHEDULER not found in VM"
        echo "Make sure sched_ext schedulers are installed"
        exit 1
    fi
    
    # Start new scheduler in background
    "$SCRIPT_DIR/vm-ssh.sh" "sudo nohup $SCHEDULER > /tmp/${SCHEDULER}.log 2>&1 &"
    sleep 5
    
    echo "Started $SCHEDULER"
fi

# Verify scheduler state
CURRENT_STATE=$("$SCRIPT_DIR/vm-ssh.sh" "if [ -f /sys/kernel/sched_ext/state ]; then cat /sys/kernel/sched_ext/state 2>/dev/null || echo 'unknown'; else echo 'cfs'; fi")
echo "Current scheduler state: $CURRENT_STATE"
