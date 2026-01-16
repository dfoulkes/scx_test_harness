#!/bin/bash

# Install and configure Kafka in the VM
# This script should be run after the VM is created and accessible via SSH

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/scheduler_test_vm}"
VM_USER="${VM_USER:-debian}"
VM_SSH_PORT="${VM_SSH_PORT:-2222}"

echo "=========================================="
echo "Installing Kafka to VM"
echo "=========================================="
echo ""

# Check if VM is accessible
echo "Checking VM connectivity..."
if ! ssh -p $VM_SSH_PORT -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$VM_USER@localhost" "echo 'VM is accessible'" 2>/dev/null; then
    echo "Error: Cannot connect to VM"
    echo "Make sure the VM is running with: $SCRIPT_DIR/vm-start.sh"
    exit 1
fi

echo "VM is accessible"
echo ""

# Download and install Kafka
echo "Downloading Kafka..."
ssh -p $VM_SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no "$VM_USER@localhost" << 'ENDSSH'
set -e

# Check if Kafka is already installed
if [ -d "/opt/kafka" ]; then
    echo "Kafka already installed at /opt/kafka"
else
    echo "Downloading Kafka 3.9.0..."
    cd /tmp
    wget -q https://downloads.apache.org/kafka/3.9.0/kafka_2.13-3.9.0.tgz
    echo "Extracting Kafka..."
    tar xzf kafka_2.13-3.9.0.tgz
    sudo mv kafka_2.13-3.9.0 /opt/kafka
    rm kafka_2.13-3.9.0.tgz
    echo "Kafka installed to /opt/kafka"
fi

# Create log directory
sudo mkdir -p /opt/kafka/logs
sudo chown -R debian:debian /opt/kafka

# Create Zookeeper systemd service
echo "Creating Zookeeper systemd service..."
sudo tee /etc/systemd/system/zookeeper.service > /dev/null << 'EOF'
[Unit]
Description=Apache Zookeeper
After=network.target

[Service]
Type=simple
User=debian
Environment="LOG_DIR=/opt/kafka/logs"
ExecStart=/opt/kafka/bin/zookeeper-server-start.sh /opt/kafka/config/zookeeper.properties
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Create Kafka systemd service
echo "Creating Kafka systemd service..."
sudo tee /etc/systemd/system/kafka.service > /dev/null << 'EOF'
[Unit]
Description=Apache Kafka
After=zookeeper.service
Requires=zookeeper.service

[Service]
Type=simple
User=debian
Environment="LOG_DIR=/opt/kafka/logs"
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
echo "Reloading systemd..."
sudo systemctl daemon-reload

# Enable services
echo "Enabling Zookeeper and Kafka services..."
sudo systemctl enable zookeeper
sudo systemctl enable kafka

# Start services
echo "Starting Zookeeper..."
sudo systemctl start zookeeper
echo "Waiting for Zookeeper to start..."
sleep 10

echo "Starting Kafka..."
sudo systemctl start kafka
echo "Waiting for Kafka to start..."
sleep 10

# Check service status
echo ""
echo "Checking service status..."
sudo systemctl is-active zookeeper && echo "Zookeeper: ACTIVE" || echo "Zookeeper: FAILED"
sudo systemctl is-active kafka && echo "Kafka: ACTIVE" || echo "Kafka: FAILED"

ENDSSH

echo ""
echo "Creating Kafka topics for banking app..."
ssh -p $VM_SSH_PORT -i "$SSH_KEY" -o StrictHostKeyChecking=no "$VM_USER@localhost" << 'ENDSSH'
set -e

# Wait a bit more for Kafka to be fully ready
sleep 5

# Create topics
echo "Creating 'transactions' topic..."
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists \
    --bootstrap-server localhost:9092 \
    --replication-factor 1 \
    --partitions 3 \
    --topic transactions 2>/dev/null || echo "Topic may already exist"

echo "Creating 'fraud-alerts' topic..."
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists \
    --bootstrap-server localhost:9092 \
    --replication-factor 1 \
    --partitions 1 \
    --topic fraud-alerts 2>/dev/null || echo "Topic may already exist"

echo ""
echo "Listing topics:"
/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092

ENDSSH

echo ""
echo "=========================================="
echo "Kafka Installation Complete!"
echo "=========================================="
echo ""
echo "Zookeeper: running on port 2181"
echo "Kafka: running on port 9092"
echo "Topics created: transactions, fraud-alerts"
echo ""
echo "Services are configured to start automatically on boot"
