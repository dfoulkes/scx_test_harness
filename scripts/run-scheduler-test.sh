#!/bin/bash

# Linux Scheduler Test Runner Script
# This script tests different schedulers and runs Gatling load tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

SCHEDULERS=("scx_rusty" "scx_lavd" "scx_bpfland" "scx_layered")
TEST_DURATION=300  # 5 minutes per scheduler
RESULTS_DIR="$PROJECT_ROOT/results/$(date +%Y%m%d_%H%M%S)"
APP_URL="http://localhost:8080"
VMAPP_PATH="/opt/banking-app"
SPRING_BOOT_JAR="${SPRING_BOOT_JAR:-$PROJECT_ROOT/spring-boot-app/target/banking-app.jar}"
VM_SSH_PORT="${VM_SSH_PORT:-2222}"
VM_USER="${VM_USER:-debian}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/scheduler_test_vm}"
RESTORE_SNAPSHOT="${RESTORE_SNAPSHOT:-}"  # Set to snapshot name to restore before tests

mkdir -p "$RESULTS_DIR"

# Check if VM is running
check_vm_running() {
    if ! nc -z localhost "$VM_SSH_PORT" 2>/dev/null; then
        echo "Error: VM is not running or SSH is not accessible on port $VM_SSH_PORT"
        echo "Start the VM with: $SCRIPT_DIR/vm-start.sh"
        exit 1
    fi
    echo "VM is running and accessible"
}

# Deploy application to VM
deploy_app_to_vm() {
    echo "Deploying Spring Boot application to VM..."
    
    if [ ! -f "$SPRING_BOOT_JAR" ]; then
        echo "Error: Spring Boot JAR not found at $SPRING_BOOT_JAR"
        echo "Build it first with: cd spring-boot-app && mvn clean package"
        exit 1
    fi
    
    # Ensure app directory exists
    ssh -p "$VM_SSH_PORT" -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$VM_USER@localhost" "sudo mkdir -p $VMAPP_PATH && sudo chown $VM_USER:$VM_USER $VMAPP_PATH"
    
    # Copy JAR to VM
    scp -P "$VM_SSH_PORT" -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$SPRING_BOOT_JAR" "$VM_USER@localhost:$VMAPP_PATH/banking-app.jar"
    
    echo "Application deployed to VM"
}

# Start application in VM
start_app_in_vm() {
    echo "Starting Spring Boot application in VM..."
    
    # Kill any existing instance and start new one
    # Use -f flag to background SSH immediately
    ssh -f -p "$VM_SSH_PORT" -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$VM_USER@localhost" "pkill -f banking-app.jar || true; sleep 2; cd $VMAPP_PATH && nohup env KAFKA_BOOTSTRAP_SERVERS=localhost:9092 java -jar banking-app.jar > app.log 2>&1 &"
    
    echo "Application started in VM"
}

# Function to check if Spring Boot app is running
wait_for_app() {
    echo "Waiting for Spring Boot application to start..."
    for i in {1..60}; do
        if curl -s "$APP_URL/actuator/health" > /dev/null 2>&1; then
            echo "Application is ready!"
            return 0
        fi
        sleep 2
    done
    echo "Application failed to start!"
    return 1
}

# Function to get current scheduler from VM
get_current_scheduler() {
    "$SCRIPT_DIR/vm-ssh.sh" "if [ -f /sys/kernel/sched_ext/state ]; then cat /sys/kernel/sched_ext/state 2>/dev/null || echo 'unknown'; else echo 'cfs'; fi"
}

# Function to switch scheduler in VM
switch_scheduler() {
    local scheduler=$1
    "$SCRIPT_DIR/vm-scheduler-switch.sh" "$scheduler"
}

# Function to collect system metrics from VM
collect_metrics() {
    local scheduler=$1
    local output_file="$RESULTS_DIR/${scheduler}_metrics.txt"
    
    echo "=== System Metrics for $scheduler ===" > "$output_file"
    echo "Date: $(date)" >> "$output_file"
    echo "" >> "$output_file"
    
    echo "--- CPU Info ---" >> "$output_file"
    "$SCRIPT_DIR/vm-ssh.sh" "lscpu" >> "$output_file"
    echo "" >> "$output_file"
    
    echo "--- Memory Info ---" >> "$output_file"
    "$SCRIPT_DIR/vm-ssh.sh" "free -h" >> "$output_file"
    echo "" >> "$output_file"
    
    echo "--- Scheduler State ---" >> "$output_file"
    get_current_scheduler >> "$output_file"
    echo "" >> "$output_file"
    
    echo "--- sched_ext Schedulers Available ---" >> "$output_file"
    "$SCRIPT_DIR/vm-ssh.sh" "ls -la /usr/local/bin/scx_* 2>/dev/null || echo 'No schedulers found'" >> "$output_file"
}

# =====================================================================
# Main execution starts here
# =====================================================================

echo "==================================="
echo "Linux Scheduler Performance Test"
echo "==================================="
echo "Results will be saved to: $RESULTS_DIR"
echo ""

# Check VM is running
check_vm_running

# Optionally restore from snapshot
if [ -n "$RESTORE_SNAPSHOT" ]; then
    echo "Restoring VM from snapshot: $RESTORE_SNAPSHOT"
    "$SCRIPT_DIR/vm-stop.sh"
    "$SCRIPT_DIR/vm-snapshot.sh" restore "$RESTORE_SNAPSHOT"
    "$SCRIPT_DIR/vm-start.sh"
    check_vm_running
fi

# Deploy and start application
deploy_app_to_vm
start_app_in_vm
wait_for_app

echo ""

# Test each scheduler
for scheduler in "cfs" "${SCHEDULERS[@]}"; do
    echo ""
    echo "==================================="
    echo "Testing scheduler: $scheduler"
    echo "==================================="
    
    # Switch scheduler
    switch_scheduler "$scheduler"
    
    # Collect pre-test metrics
    collect_metrics "$scheduler"
    
    # Wait a bit for scheduler to stabilize
    sleep 10
    
    # Run Gatling test
    echo "Running Gatling load test..."
    mvn gatling:test \
        -DbaseUrl="$APP_URL" \
        -Dgatling.simulationClass=simulations.BankingTransactionSimulation \
        || true
    
    # Copy Gatling results
    if [ -d "target/gatling" ]; then
        latest_result=$(ls -t target/gatling | head -1)
        if [ -n "$latest_result" ]; then
            cp -r "target/gatling/$latest_result" "$RESULTS_DIR/${scheduler}_gatling_results"
        fi
    fi
    
    # Collect post-test metrics
    echo "--- Post-Test Load Average ---" >> "$RESULTS_DIR/${scheduler}_metrics.txt"
    "$SCRIPT_DIR/vm-ssh.sh" "uptime" >> "$RESULTS_DIR/${scheduler}_metrics.txt"
    
    # Collect application logs from VM
    echo "--- Application Logs (last 50 lines) ---" >> "$RESULTS_DIR/${scheduler}_metrics.txt"
    "$SCRIPT_DIR/vm-ssh.sh" "tail -n 50 $VM_APP_PATH/app.log" >> "$RESULTS_DIR/${scheduler}_metrics.txt" || true
    
    echo "Test completed for $scheduler"
    echo "Cooling down..."
    sleep 30
done

echo ""
echo "==================================="
echo "All tests completed!"
echo "==================================="
echo "Results saved to: $RESULTS_DIR"
echo ""
echo "To view results:"
echo "  - Open $RESULTS_DIR/*_gatling_results/index.html in a browser"
echo "  - Check $RESULTS_DIR/*_metrics.txt for system metrics"
