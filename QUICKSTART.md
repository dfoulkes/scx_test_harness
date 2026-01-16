# Quick Start Guide

## Initial Setup (One Time Only)

### 1. Install Host Dependencies
```bash
sudo apt-get update
sudo apt-get install qemu-system-x86_64 qemu-utils cloud-image-utils \
  openssh-client netcat-openbsd openjdk-17-jdk maven
```

### 2. Setup VM (30-60 minutes)
```bash
./scripts/setup-vm.sh
```
This creates a Debian 13 VM with kernel 6.12+, sched_ext schedulers, and all dependencies.

### 3. Build and Test Spring Boot App
```bash
# Run tests (completes in 7-10 seconds)
cd spring-boot-app && mvn test

# Build JAR
mvn clean package && cd ..
```

## Daily Workflow

### Start VM
```bash
./scripts/vm-start.sh
```

### Run Tests
```bash
# Full scheduler comparison
./scripts/run-scheduler-test.sh

# Or with clean snapshot restore
RESTORE_SNAPSHOT=clean-install ./scripts/run-scheduler-test.sh
```

### View Results
```bash
ls -la results/
firefox results/[timestamp]/cfs_gatling_results/index.html
```

### Stop VM
```bash
./scripts/vm-stop.sh
```

## VM Management Commands

```bash
# SSH into VM
./scripts/vm-ssh.sh

# Execute command in VM
./scripts/vm-ssh.sh "ls -la /opt/banking-app"

# Switch scheduler manually
./scripts/vm-scheduler-switch.sh scx_rusty

# Create snapshot
./scripts/vm-snapshot.sh create my-snapshot

# Restore snapshot (VM must be stopped)
./scripts/vm-stop.sh
./scripts/vm-snapshot.sh restore clean-install
./scripts/vm-start.sh

# List snapshots
./scripts/vm-snapshot.sh list
```

## Optional: Kafka

```bash
# Start Kafka on host (optional - app works without it)
docker run -d --name kafka -p 9092:9092 apache/kafka:latest

# Stop Kafka
docker stop kafka && docker rm kafka
```

**Note**: Kafka is completely optional. The application uses `@ConditionalOnProperty(name="kafka.enabled")` to conditionally load Kafka components. Tests run with `kafka.enabled=false`.

## Testing

### Run Unit Tests
```bash
cd spring-boot-app
mvn test
```

30 tests complete in 7-10 seconds:
- Context loading and dependency injection
- Banking operations (deposit, withdraw, transfer)
- REST API endpoints
- Computational workloads

### Test Configuration
- `spring-boot-app/src/test/resources/application-test.properties`
- Kafka disabled: `kafka.enabled=false`
- Lenient fraud detection: `fraud.detection.threshold=50000`
- H2 in-memory database

## Troubleshooting

### VM won't boot
```bash
# Check KVM
lsmod | grep kvm

# Check for stale processes
ps aux | grep qemu
rm vm/qemu.pid  # if needed
```

### Can't SSH to VM
```bash
# Wait longer (VM takes time to boot)
nc -z localhost 2222

# Check if VM is running
cat vm/qemu.pid
ps -p $(cat vm/qemu.pid)
```

### Application not responding
```bash
# Check logs in VM
./scripts/vm-ssh.sh "cat /opt/banking-app/app.log"

# Manually restart app
./scripts/vm-ssh.sh "pkill -f banking-app.jar"
./scripts/vm-ssh.sh "cd /opt/banking-app && nohup java -jar banking-app.jar > app.log 2>&1 &"
```

## Schedulers Tested

- **cfs** - Default Linux Completely Fair Scheduler
- **scx_rusty** - Rusty scheduler (good for multi-core)
- **scx_lavd** - Low-latency scheduler
- **scx_bpfland** - BPF-based scheduler
- **scx_layered** - Layered scheduler

## Architecture

```
Host (Gatling) ──HTTP──> localhost:8080 ──forward──> VM:8080 (Spring Boot)
Host (Kafka)   <──TCP──  10.0.2.2:9092  <──connect── VM (App)
Host (SSH)     ──SSH──> localhost:2222 ──forward──> VM:22
```
