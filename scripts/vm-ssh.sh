#!/bin/bash

# SSH wrapper for connecting to the QEMU VM
# Usage: ./vm-ssh.sh [command]

set -e

VM_SSH_PORT="${VM_SSH_PORT:-2222}"
VM_USER="${VM_USER:-debian}"
VM_HOST="${VM_HOST:-localhost}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/scheduler_test_vm}"

# If no command provided, open interactive shell
if [ $# -eq 0 ]; then
    ssh -p "$VM_SSH_PORT" -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$VM_USER@$VM_HOST"
else
    # Execute command and return
    ssh -p "$VM_SSH_PORT" -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$VM_USER@$VM_HOST" "$@"
fi
