#!/bin/bash

# Stop the QEMU VM gracefully

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VM_DIR="${VM_DIR:-$PROJECT_ROOT/vm}"
PIDFILE="${PIDFILE:-$VM_DIR/qemu.pid}"

if [ ! -f "$PIDFILE" ]; then
    echo "VM is not running (no PID file found)"
    exit 0
fi

pid=$(cat "$PIDFILE")

if ! ps -p "$pid" > /dev/null 2>&1; then
    echo "VM is not running (stale PID file)"
    rm "$PIDFILE"
    exit 0
fi

echo "Stopping VM (PID: $pid)..."

# Try graceful shutdown first via SSH
"$SCRIPT_DIR/vm-ssh.sh" "sudo poweroff" 2>/dev/null || true

# Wait for VM to shut down
for i in {1..30}; do
    if ! ps -p "$pid" > /dev/null 2>&1; then
        echo "VM stopped successfully"
        rm "$PIDFILE"
        exit 0
    fi
    sleep 1
done

# Force kill if still running
echo "VM did not shut down gracefully, force killing..."
kill -9 "$pid" 2>/dev/null || true
rm "$PIDFILE"
echo "VM stopped"
