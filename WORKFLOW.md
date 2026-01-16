# Scheduler Testing Workflow

## Overview
This project tests different Linux CPU schedulers (sched_ext) with a Spring Boot banking application under load.

## Complete Setup Process

### 1. Build Custom Kernel on Host (22 minutes)
```bash
./scripts/build-kernel.sh
```
- Downloads Linux 6.12.6 source
- Enables CONFIG_SCHED_CLASS_EXT and DEBUG_INFO_BTF
- Builds with all available CPU cores (~32 threads on 7950x3d)
- Outputs: `kernel-build/*.deb` packages

### 2. Create VM with Kafka (10-15 minutes)
```bash
./scripts/setup-vm.sh
```
- Creates Debian 13 VM (16GB RAM, 8 CPUs, 40GB disk)
- Installs build tools, Kafka, and Zookeeper via cloud-init
- Configures Kafka topics for banking app (transactions, fraud-alerts)
- Creates clean snapshot after installation
- **Note:** Kafka runs on port 9092, Zookeeper on port 2181
- **Note:** Does NOT build kernel or schedulers (done separately for speed)

### 3. Start VM
```bash
./scripts/vm-start.sh
```
- Starts QEMU with KVM acceleration
- Port forwards: 2222→22 (SSH), 8080→8080 (App), 9092→9092 (Kafka)
- VM boots in ~30 seconds
- Kafka and Zookeeper start automatically

### 4. Install Custom Kernel to VM (1-2 minutes)
```bash
./scripts/install-kernel-to-vm.sh
```
- Copies pre-built kernel packages from host
- Installs via `dpkg -i`
- Updates GRUB to boot custom kernel by default (`GRUB_DEFAULT="1>2"`)
- Reboots VM into custom kernel

### 5. Build Schedulers in VM (10-15 minutes)
```bash
./scripts/build-schedulers-in-vm.sh
```
- Installs Rust if needed
- Clones sched_ext repository
- Builds C schedulers with `make`
- Builds Rust schedulers with `cargo build --release -j4`
  - **Important:** Uses `-j4` to avoid OOM with 16GB RAM
- Installs 24 schedulers to `/usr/local/bin/`

### 6. Verify Setup
```bash
ssh -p 2222 -i ~/.ssh/scheduler_test_vm debian@localhost 'uname -r && cat /sys/kernel/sched_ext/state && systemctl is-active kafka && ls -1 /usr/local/bin/scx_*'
```
Expected output:
- Kernel: `6.12.6-schedext-g2d8ba96ff834`
- sched_ext state: `disabled` (ready to use)
- Kafka status: `active`
- 24 schedulers listed

### 7. Run Tests
```bash
./scripts/run-scheduler-test.sh
```
- Runs Spring Boot banking app
- Tests with different schedulers
- Generates performance comparison

## Available Schedulers

- **C schedulers:** scx_simple, scx_qmap, scx_central, scx_userland, scx_nest, scx_flatcg, scx_pair, scx_prev, scx_sdt
- **Rust schedulers:** scx_bpfland, scx_rusty, scx_lavd, scx_layered, scx_rlfifo, scx_rustland, scx_chaos, scx_cosmos, scx_beerland, scx_flash, scx_mitosis, scx_tickless, scx_wd40, scx_p2dq, scx_arena_selftests

## Key Lessons Learned

### 1. Build on Host, Not in VM
- **Problem:** Building kernel in VM took 40-90 minutes
- **Solution:** Build on host with all CPU cores (22 minutes)
- **Benefit:** 50-75% faster, uses host's full power

### 2. Simplified Cloud-Init
- **Problem:** Complex cloud-init builds timed out or hung SSH
- **Solution:** Minimal cloud-init (only installs packages, no builds)
- **Benefit:** Reliable provisioning, easier debugging

### 3. GRUB Default Configuration
- **Problem:** VM booted default kernel after reboot
- **Solution:** Set `GRUB_DEFAULT="1>2"` to boot custom kernel from Advanced menu
- **Benefit:** Consistent kernel selection after reboots

### 4. Memory-Conscious Rust Builds
- **Problem:** Parallel Rust builds with 8 jobs caused OOM kills
- **Solution:** Use `cargo build -j4` to limit parallelism
- **Benefit:** Reliable builds without memory pressure

### 5. Schedulers Must Build in VM
- **Problem:** Building schedulers on host failed (BPF arena requires kernel 6.12+ headers)
- **Solution:** Build schedulers inside VM after custom kernel installed
- **Benefit:** Correct kernel headers available for BPF compilation

## Helper Scripts

### VM Management
- `./scripts/vm-start.sh` - Start the VM
- `./scripts/vm-stop.sh` - Stop the VM
- `./scripts/vm-ssh.sh` - SSH into the VM

### Building
- `./scripts/build-kernel.sh` - Build kernel on host
- `./scripts/install-kernel-to-vm.sh` - Install kernel to VM
- `./scripts/build-schedulers-in-vm.sh` - Build schedulers in VM

### Testing
- `./scripts/run-scheduler-test.sh` - Run scheduler comparison tests
- `./scripts/simple-test.sh` - Quick test of a single scheduler

## Troubleshooting

### VM Won't Boot Custom Kernel
```bash
# Check GRUB configuration
ssh -p 2222 -i ~/.ssh/scheduler_test_vm debian@localhost "grep GRUB_DEFAULT /etc/default/grub"

# Should show: GRUB_DEFAULT="1>2"
# If not, run install-kernel-to-vm.sh again
```

### SSH Connection Refused
```bash
# Check if VM is running
ps aux | grep qemu | grep debian-scheduler-test

# Check if port is accessible
nc -zv localhost 2222

# Wait for cloud-init to complete (first boot only)
# May take 5-10 minutes during initial provisioning
```

### Scheduler Build Fails with OOM
```bash
# Inside VM, rebuild with fewer parallel jobs
source ~/.cargo/env
cd ~/scx
cargo clean
cargo build --release -j2  # Use even fewer jobs if needed
```

### Check sched_ext Status
```bash
ssh -p 2222 -i ~/.ssh/scheduler_test_vm debian@localhost 'cat /sys/kernel/sched_ext/state'
# Should show: disabled (ready to use)

# Test a scheduler
ssh -p 2222 -i ~/.ssh/scheduler_test_vm debian@localhost 'sudo timeout 5 scx_simple -v'
```

### Kafka Not Running
```bash
# Check Kafka status
ssh -p 2222 -i ~/.ssh/scheduler_test_vm debian@localhost 'systemctl status kafka'

# Check Zookeeper status (required for Kafka)
ssh -p 2222 -i ~/.ssh/scheduler_test_vm debian@localhost 'systemctl status zookeeper'

# Restart services if needed
ssh -p 2222 -i ~/.ssh/scheduler_test_vm debian@localhost 'sudo systemctl restart zookeeper && sleep 10 && sudo systemctl restart kafka'

# Verify Kafka topics
ssh -p 2222 -i ~/.ssh/scheduler_test_vm debian@localhost '/usr/bin/kafka-topics --list --bootstrap-server localhost:9092'
# Should show: transactions, fraud-alerts
```

## Performance Metrics

| Step | Time | Notes |
|------|------|-------|
| Build kernel on host | ~22 min | Uses all CPU cores (32 on 7950x3d) |
| Create VM with cloud-init | ~5-10 min | Package installation + reboot |
| Install kernel to VM | ~1 min | Copy + dpkg + GRUB update |
| Build schedulers in VM | ~10-15 min | Rust compilation with -j4 |
| **Total Setup** | **~40-50 min** | One-time setup |
| Spring Boot tests | ~7-10 sec | 30 JUnit tests |
| VM boot time | ~30 sec | After initial provisioning |

## System Requirements

- **Host:** Ubuntu 22.04 (WSL2), KVM support
- **CPU:** Multi-core recommended (tested on AMD Ryzen 7950x3d)
- **RAM:** 16GB+ for host (VM uses 16GB)
- **Disk:** ~10GB for kernel source, ~5GB for VM image
- **Network:** Internet for package downloads

## Repository Structure
```
.
├── scripts/
│   ├── build-kernel.sh              # Build custom kernel on host
│   ├── setup-vm.sh                  # Create and provision VM
│   ├── install-kernel-to-vm.sh      # Install kernel to VM
│   ├── build-schedulers-in-vm.sh    # Build schedulers in VM
│   ├── vm-start.sh                  # Start VM
│   ├── vm-stop.sh                   # Stop VM
│   ├── vm-ssh.sh                    # SSH into VM
│   └── run-scheduler-test.sh        # Run scheduler tests
├── spring-boot-app/                 # Banking application
│   └── src/test/                    # JUnit 5 tests (30 tests)
├── kernel-build/                    # Kernel build output (.deb packages)
└── vm/                              # VM images and cloud-init config
```

## Next Steps

1. Build Spring Boot app: `mvn clean package -DskipTests`
2. Copy app to VM: `scp -P 2222 -i ~/.ssh/scheduler_test_vm spring-boot-app/target/*.jar debian@localhost:/opt/banking-app/`
3. Run scheduler comparison tests
4. Analyze results and generate performance reports
