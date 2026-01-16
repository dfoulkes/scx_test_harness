#!/bin/bash

# Start QEMU VM for scheduler testing
# This script launches a Debian VM with appropriate resources and port forwarding

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VM_DIR="${VM_DIR:-$PROJECT_ROOT/vm}"
VM_IMAGE="${VM_IMAGE:-$VM_DIR/debian-scheduler-test.qcow2}"
VM_SNAPSHOT="${VM_SNAPSHOT:-}"
VM_RAM="${VM_RAM:-16G}"
VM_CPUS="${VM_CPUS:-8}"
VM_SSH_PORT="${VM_SSH_PORT:-2222}"
VM_APP_PORT="${VM_APP_PORT:-8080}"
PIDFILE="${PIDFILE:-$VM_DIR/qemu.pid}"

# Check if VM is already running
if [ -f "$PIDFILE" ]; then
    pid=$(cat "$PIDFILE")
    if ps -p "$pid" > /dev/null 2>&1; then
        echo "VM is already running (PID: $pid)"
        echo "Use vm-stop.sh to stop it first"
        exit 1
    else
        echo "Stale PID file found, removing..."
        rm "$PIDFILE"
    fi
fi

# Check if VM image exists
if [ ! -f "$VM_IMAGE" ]; then
    echo "Error: VM image not found at $VM_IMAGE"
    echo "Please run setup-vm.sh first to create the VM"
    exit 1
fi

# Prepare snapshot option
SNAPSHOT_OPTS=""
if [ -n "$VM_SNAPSHOT" ]; then
    if [ -f "$VM_SNAPSHOT" ]; then
        echo "Loading VM from snapshot: $VM_SNAPSHOT"
        SNAPSHOT_OPTS="-loadvm $(basename "$VM_SNAPSHOT" .qcow2)"
    else
        echo "Warning: Snapshot $VM_SNAPSHOT not found, using base image"
    fi
fi

echo "Starting QEMU VM..."
echo "  RAM: $VM_RAM"
echo "  CPUs: $VM_CPUS"
echo "  SSH Port: $VM_SSH_PORT -> 22"
echo "  App Port: $VM_APP_PORT -> 8080"
echo "  Image: $VM_IMAGE"

# Start QEMU with user-mode networking
qemu-system-x86_64 \
    -machine type=q35,accel=kvm \
    -cpu host \
    -smp "$VM_CPUS" \
    -m "$VM_RAM" \
    -drive file="$VM_IMAGE",format=qcow2,if=virtio \
    -netdev user,id=net0,hostfwd=tcp::${VM_SSH_PORT}-:22,hostfwd=tcp::${VM_APP_PORT}-:8080 \
    -device virtio-net-pci,netdev=net0 \
    -display none \
    $SNAPSHOT_OPTS \
    -daemonize \
    -pidfile "$PIDFILE"

echo "VM started (PID: $(cat "$PIDFILE"))"
echo ""
echo "Waiting for VM to boot and SSH to become available..."

# Wait for SSH to be available
for i in {1..60}; do
    if nc -z localhost "$VM_SSH_PORT" 2>/dev/null; then
        echo "SSH is available!"
        sleep 5  # Give it a few more seconds to fully initialize
        echo ""
        echo "VM is ready!"
        echo "  Connect via SSH: $SCRIPT_DIR/vm-ssh.sh"
        echo "  Application will be accessible at: http://localhost:$VM_APP_PORT"
        echo "  Host Kafka accessible from VM at: 10.0.2.2:9092"
        exit 0
    fi
    sleep 2
done

echo "Error: VM failed to start or SSH is not responding"
echo "Check VM logs for details"
exit 1
