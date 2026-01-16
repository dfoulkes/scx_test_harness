#!/bin/bash

# Create or restore VM snapshots
# Usage: ./vm-snapshot.sh create <snapshot-name>
#        ./vm-snapshot.sh restore <snapshot-name>
#        ./vm-snapshot.sh list

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VM_DIR="${VM_DIR:-$PROJECT_ROOT/vm}"
VM_IMAGE="${VM_IMAGE:-$VM_DIR/debian-scheduler-test.qcow2}"

if [ ! -f "$VM_IMAGE" ]; then
    echo "Error: VM image not found at $VM_IMAGE"
    exit 1
fi

case "$1" in
    create)
        if [ -z "$2" ]; then
            echo "Usage: $0 create <snapshot-name>"
            exit 1
        fi
        SNAPSHOT_NAME="$2"
        echo "Creating snapshot: $SNAPSHOT_NAME"
        qemu-img snapshot -c "$SNAPSHOT_NAME" "$VM_IMAGE"
        echo "Snapshot created successfully"
        ;;
    
    restore)
        if [ -z "$2" ]; then
            echo "Usage: $0 restore <snapshot-name>"
            exit 1
        fi
        SNAPSHOT_NAME="$2"
        echo "Restoring snapshot: $SNAPSHOT_NAME"
        
        # Check if VM is running
        if [ -f "$VM_DIR/qemu.pid" ]; then
            pid=$(cat "$VM_DIR/qemu.pid")
            if ps -p "$pid" > /dev/null 2>&1; then
                echo "Error: VM is running. Stop it first with vm-stop.sh"
                exit 1
            fi
        fi
        
        qemu-img snapshot -a "$SNAPSHOT_NAME" "$VM_IMAGE"
        echo "Snapshot restored successfully"
        ;;
    
    list)
        echo "Available snapshots for $VM_IMAGE:"
        qemu-img snapshot -l "$VM_IMAGE"
        ;;
    
    delete)
        if [ -z "$2" ]; then
            echo "Usage: $0 delete <snapshot-name>"
            exit 1
        fi
        SNAPSHOT_NAME="$2"
        echo "Deleting snapshot: $SNAPSHOT_NAME"
        qemu-img snapshot -d "$SNAPSHOT_NAME" "$VM_IMAGE"
        echo "Snapshot deleted successfully"
        ;;
    
    *)
        echo "Usage: $0 {create|restore|list|delete} [snapshot-name]"
        echo ""
        echo "Commands:"
        echo "  create <name>   - Create a new snapshot"
        echo "  restore <name>  - Restore from a snapshot"
        echo "  list           - List all snapshots"
        echo "  delete <name>  - Delete a snapshot"
        exit 1
        ;;
esac
