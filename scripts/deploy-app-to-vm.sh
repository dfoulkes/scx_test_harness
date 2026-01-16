#!/bin/bash

# Deploy Spring Boot banking app to the VM

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SSH_KEY="$HOME/.ssh/scheduler_test_vm"
SSH_PORT="${SSH_PORT:-2222}"
VM_USER="${VM_USER:-debian}"
APP_JAR="$PROJECT_ROOT/spring-boot-app/target/banking-app.jar"
APP_DIR="/opt/banking-app"

echo "=========================================="
echo "Deploying Banking App to VM"
echo "=========================================="
echo ""

# Check if VM is running
if ! nc -z localhost $SSH_PORT 2>/dev/null; then
    echo "Error: VM is not running on port $SSH_PORT"
    echo "Start it with: ./scripts/vm-start.sh"
    exit 1
fi

# Check if JAR exists
if [ ! -f "$APP_JAR" ]; then
    echo "Error: Banking app JAR not found at $APP_JAR"
    echo "Build it with: cd spring-boot-app && mvn clean package -DskipTests"
    exit 1
fi

echo "Found JAR: $(basename "$APP_JAR") ($(du -h "$APP_JAR" | cut -f1))"
echo ""

echo "Copying JAR to VM..."
scp -P $SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$APP_JAR" \
    $VM_USER@localhost:$APP_DIR/

echo ""
echo "Creating systemd service for banking app..."
ssh -p $SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@localhost "sudo tee /etc/systemd/system/banking-app.service > /dev/null" <<'EOF'
[Unit]
Description=Banking Application
After=network.target kafka.service
Requires=kafka.service

[Service]
Type=simple
User=debian
WorkingDirectory=/opt/banking-app
ExecStart=/usr/bin/java -jar /opt/banking-app/banking-app.jar
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "Enabling and starting banking app service..."
ssh -p $SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@localhost "sudo systemctl daemon-reload && sudo systemctl enable banking-app && sudo systemctl start banking-app"

echo ""
echo "Waiting for app to start..."
sleep 10

echo ""
echo "Checking service status..."
ssh -p $SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    $VM_USER@localhost "sudo systemctl status banking-app --no-pager | head -20"

echo ""
echo "=========================================="
echo "Banking App Deployment Complete!"
echo "=========================================="
echo ""
echo "App is running on http://localhost:8080"
echo "Kafka integration: localhost:9092"
echo ""
echo "Test endpoints:"
echo "  Health: curl http://localhost:8080/actuator/health"
echo "  Accounts: curl http://localhost:8080/api/accounts"
echo "  Create transaction: curl -X POST http://localhost:8080/api/transactions ..."
echo ""
echo "View logs: ./scripts/vm-ssh.sh 'sudo journalctl -u banking-app -f'"
echo "Stop app: ./scripts/vm-ssh.sh 'sudo systemctl stop banking-app'"
