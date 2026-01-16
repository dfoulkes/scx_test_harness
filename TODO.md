# TODO: Complete Scheduler Testing Setup

## Current Status (Jan 16, 2026 - 12:47 AM)

### ✅ Completed
- Spring Boot banking app with 30 JUnit tests (7-10 seconds execution)
- Kafka made optional for tests
- VM setup script created with automated kernel build
- Custom kernel 6.12.6-schedext built successfully
- Schedulers (scx_rusty, scx_lavd, scx_bpfland, scx_layered) sources ready
- Identified all issues with kernel config and GRUB boot

### ❌ Issues Found
1. **CONFIG_SCHED_CLASS_EXT not enabled**: The `./scripts/config --enable` command failed silently
2. **GRUB not booting custom kernel**: Stock Debian kernel (6.12.63) boots by default instead of custom 6.12.6-schedext

### ✅ Fixes Applied to setup-vm.sh
1. Changed config method: Now directly appends `CONFIG_SCHED_CLASS_EXT=y` to .config file
2. Added `CONFIG_SCHED_DEBUG=y` for better debugging
3. Set GRUB_DEFAULT to specific menu entry for custom kernel
4. Added debhelper package (was missing, causing build failures)
5. Increased resources: 8 CPUs, 16GB RAM, -j6 builds (down from 40min to ~25min)

## Next Steps

### 1. Rebuild VM with Fixed Configuration (25-40 minutes)
```bash
cd /home/dan/source/linux-scheduler-test
killall qemu-system-x86_64 2>/dev/null
rm -f vm/debian-scheduler-test.qcow2 vm/cloud-init.img
./scripts/setup-vm.sh
```

**Expected output**: Script will run for 25-40 minutes building kernel

### 2. Start VM and Verify Custom Kernel
```bash
sg kvm -c "./scripts/vm-start.sh" > /dev/null 2>&1 &
sleep 15

# Verify custom kernel with sched_ext is running
ssh -p 2222 -i ~/.ssh/scheduler_test_vm -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null debian@localhost "uname -r"
# Expected: 6.12.6-schedext (NOT 6.12.63+deb13-amd64)

# Verify sched_ext is available
ssh -p 2222 -i ~/.ssh/scheduler_test_vm -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null debian@localhost "cat /sys/kernel/sched_ext/state"
# Expected: "disabled" or "enabled" (NOT "No such file or directory")

# Verify schedulers are installed
ssh -p 2222 -i ~/.ssh/scheduler_test_vm -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null debian@localhost "ls /usr/local/bin/scx_*"
# Expected: scx_rusty, scx_lavd, scx_bpfland, scx_layered
```

### 3. Test Scheduler Switching
```bash
# Test switching to scx_rusty scheduler
ssh -p 2222 -i ~/.ssh/scheduler_test_vm -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null debian@localhost \
  "sudo scx_rusty &"
  
# Check if it's running
ssh -p 2222 -i ~/.ssh/scheduler_test_vm -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null debian@localhost \
  "cat /sys/kernel/sched_ext/state"
# Expected: "enabled"

# Stop scheduler (Ctrl+C or kill process)
# State should return to "disabled"
```

### 4. Deploy Spring Boot Application
```bash
# Build the app (if not already built)
cd spring-boot-app
mvn clean package

# Copy to VM
scp -P 2222 -i ~/.ssh/scheduler_test_vm \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  target/banking-app-*.jar debian@localhost:/home/debian/banking-app.jar

# Create startup script on VM
ssh -p 2222 -i ~/.ssh/scheduler_test_vm -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null debian@localhost \
  "echo 'java -jar /home/debian/banking-app.jar' > /home/debian/start-app.sh && chmod +x /home/debian/start-app.sh"
```

### 5. Run Performance Tests
```bash
# From host machine
./scripts/run-scheduler-test.sh

# This will:
# - Test with CFS (default) scheduler
# - Test with scx_rusty
# - Test with scx_lavd
# - Test with scx_bpfland
# - Generate comparison reports
```

### 6. Analyze Results
```bash
./scripts/analyze-results.sh

# Check results in:
# - target/gatling/*/index.html (Gatling HTML reports)
# - Compare response times, throughput, error rates
```

## Troubleshooting

### If custom kernel doesn't boot:
```bash
# Check if kernel is installed
ssh ... "dpkg -l | grep linux-image"

# Check GRUB config
ssh ... "cat /etc/default/grub | grep GRUB_DEFAULT"

# Check available kernels
ssh ... "ls -la /boot/vmlinuz*"

# Manually set GRUB default
ssh ... "sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=\"Advanced options for Debian GNU\\/Linux>Debian GNU\\/Linux, with Linux 6.12.6-schedext\"/' /etc/default/grub && sudo update-grub && sudo reboot"
```

### If sched_ext not available:
```bash
# Check if CONFIG_SCHED_CLASS_EXT was enabled during build
ssh ... "zcat /proc/config.gz 2>/dev/null | grep SCHED_CLASS_EXT || cat /boot/config-\$(uname -r) | grep SCHED_CLASS_EXT"
# Expected: CONFIG_SCHED_CLASS_EXT=y

# Check build logs
ssh ... "sudo grep -i 'sched.*ext\|CONFIG_SCHED' /var/log/cloud-init-output.log | head -20"
```

### If schedulers not found:
```bash
# Check if they were built
ssh ... "ls -la /home/debian/scx/build/ || ls -la /home/debian/scx/scheds/rust/target/release/"

# Manually install
ssh ... "cd /home/debian/scx && sudo make install"
```

## Files Modified
- `scripts/setup-vm.sh` - Fixed kernel config and GRUB settings
- `scripts/vm-start.sh` - Updated to 8 CPUs, 16GB RAM

## Key Commands Reference
```bash
# VM Management
./scripts/vm-start.sh          # Start VM
./scripts/vm-stop.sh           # Stop VM
./scripts/vm-ssh.sh            # SSH into VM

# Scheduler Control
sudo scx_rusty &               # Start scx_rusty scheduler
sudo scx_lavd &                # Start scx_lavd scheduler
cat /sys/kernel/sched_ext/state  # Check scheduler state
sudo pkill scx_                # Stop scheduler

# Testing
./scripts/run-scheduler-test.sh  # Run full test suite
```

## Expected Final State
- ✅ VM running custom kernel 6.12.6-schedext
- ✅ `/sys/kernel/sched_ext/state` file exists
- ✅ 4+ sched_ext schedulers in `/usr/local/bin/`
- ✅ Banking app deployed and running
- ✅ Performance test results comparing schedulers
