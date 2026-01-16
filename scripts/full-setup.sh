#!/bin/bash

# Complete end-to-end setup script for scheduler testing environment
# This script orchestrates the entire setup process from scratch
# NON-INTERACTIVE VERSION - runs fully automated

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=============================================="
echo "Full Scheduler Testing Environment Setup"
echo "=============================================="
echo ""
echo "This will create a complete testing environment:"
echo "  1. Build custom kernel on host (if needed)"
echo "  2. Create and provision VM"
echo "  3. Install custom kernel to VM"
echo "  4. Build schedulers in VM"
echo "  5. Install Kafka in VM"
echo "  6. Verify complete setup"
echo ""
echo "Running in NON-INTERACTIVE mode..."
echo ""

# Track start time
START_TIME=$(date +%s)

# Step 1: Build kernel on host
echo ""
echo "=========================================="
echo "STEP 1/6: Building Custom Kernel on Host"
echo "=========================================="
echo ""
if compgen -G "$PROJECT_ROOT/kernel-build/linux-image-"*".deb" > /dev/null; then
    echo "Kernel packages already exist in kernel-build/, skipping rebuild"
else
    "$SCRIPT_DIR/build-kernel.sh"
fi

# Step 2: Create VM
echo ""
echo "=========================================="
echo "STEP 2/6: Creating and Provisioning VM"
echo "=========================================="
echo ""
if [ -f "$PROJECT_ROOT/vm/debian-scheduler-test.qcow2" ]; then
    echo "WARNING: VM image already exists, will be recreated"
    rm -f "$PROJECT_ROOT/vm/debian-scheduler-test.qcow2"
fi
"$SCRIPT_DIR/setup-vm.sh"

# Step 3: Start VM
echo ""
echo "=========================================="
echo "STEP 3/6: Starting VM"
echo "=========================================="
echo ""
sg kvm -c "$SCRIPT_DIR/vm-start.sh"

# Wait a bit for VM to be fully ready
echo "Waiting for VM to be fully ready..."
sleep 10

# Step 4: Install custom kernel to VM
echo ""
echo "=========================================="
echo "STEP 4/6: Installing Custom Kernel to VM"
echo "=========================================="
echo ""
SKIP_PROMPT=1 "$SCRIPT_DIR/install-kernel-to-vm.sh"

# VM will reboot, wait for it
echo "Waiting for VM to reboot with new kernel..."
sleep 30

# Check if VM is back up
for i in {1..30}; do
    if ssh -p 2222 -i ~/.ssh/scheduler_test_vm -o ConnectTimeout=5 -o StrictHostKeyChecking=no debian@localhost "echo 'VM ready'" 2>/dev/null | grep -q "VM ready"; then
        echo "VM is back online"
        break
    fi
    echo "Waiting for VM... ($i/30)"
    sleep 2
done

# Verify custom kernel
KERNEL_VERSION=$(ssh -p 2222 -i ~/.ssh/scheduler_test_vm -o StrictHostKeyChecking=no debian@localhost "uname -r" 2>/dev/null)
echo "Current kernel: $KERNEL_VERSION"
if [[ ! $KERNEL_VERSION =~ schedext ]]; then
    echo "WARNING: Custom kernel may not be active!"
fi

# Step 5: Build schedulers in VM
echo ""
echo "=========================================="
echo "STEP 5/6: Building Schedulers in VM"
echo "=========================================="
echo ""
SKIP_PROMPT=1 "$SCRIPT_DIR/build-schedulers-in-vm.sh"

# Step 6: Install Kafka
echo ""
echo "=========================================="
echo "STEP 6/6: Installing Kafka in VM"
echo "=========================================="
echo ""
"$SCRIPT_DIR/install-kafka-to-vm.sh"

# Final verification
echo ""
echo "=========================================="
echo "VERIFICATION"
echo "=========================================="
echo ""

echo "Checking system status..."
ssh -p 2222 -i ~/.ssh/scheduler_test_vm -o StrictHostKeyChecking=no debian@localhost << 'ENDSSH'
echo "Kernel version:"
uname -r

echo ""
echo "sched_ext status:"
cat /sys/kernel/sched_ext/state 2>/dev/null || echo "sched_ext not available"

echo ""
echo "Schedulers installed:"
ls -1 /usr/local/bin/scx_* 2>/dev/null | wc -l

echo ""
echo "Kafka status:"
systemctl is-active kafka && echo "Kafka: RUNNING" || echo "Kafka: NOT RUNNING"

echo ""
echo "Zookeeper status:"
systemctl is-active zookeeper && echo "Zookeeper: RUNNING" || echo "Zookeeper: NOT RUNNING"

echo ""
echo "Kafka topics:"
/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092 2>/dev/null || echo "Cannot list topics"
ENDSSH

# Calculate total time
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
MINUTES=$((TOTAL_TIME / 60))
SECONDS=$((TOTAL_TIME % 60))

echo ""
echo "=========================================="
echo "SETUP COMPLETE!"
echo "=========================================="
echo ""
echo "Total time: ${MINUTES}m ${SECONDS}s"
echo ""
echo "The VM is ready for testing!"
echo ""
echo "Next steps:"
echo "  1. Build Spring Boot app: cd spring-boot-app && mvn clean package"
echo "  2. Deploy app to VM"
echo "  3. Run scheduler tests"
echo ""
echo "To SSH into VM: $SCRIPT_DIR/vm-ssh.sh"
echo "To stop VM: $SCRIPT_DIR/vm-stop.sh"
echo ""
