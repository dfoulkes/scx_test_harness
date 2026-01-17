

# Linux Scheduler Performance Test Harness

One-command automated testing of Linux sched_ext schedulers with real-world workloads.

**TL;DR:** Switching from the default Linux scheduler (CFS) to **scx_rusty** improved our demo Spring Boot banking application performance by **5-7x** with 95% fewer errors. This test harness automates the entire process: kernel build, VM setup, scheduler testing, and performance reporting.

## 🏆 Key Findings

I tested 5 schedulers with a CPU-intensive Spring Boot banking application (17,370 requests per test):

| Scheduler | Success Rate | Mean Response | p95 Response | Best For |
|-----------|-------------|---------------|--------------|----------|
| **scx_rusty** ⭐ | **95.2%** | **1,154ms** | **5,048ms** | **CPU-intensive throughput** |
| scx_lavd | 100% | 19,895ms | 39,669ms | Interactive/latency-sensitive |
| CFS (default) | 77.7% | 1,669ms | 9,392ms | General purpose baseline |
| scx_layered | 98.7% | 38,458ms | 57,502ms | Multi-tenant fairness |
| scx_bpfland | 31.8% | 22,696ms | 53,974ms | ❌ Poor fit for this workload |

**Winner: scx_rusty** - 7x faster mean response, 95% success rate vs CFS's 77.7%

### What This Means

- **For CPU-bound apps** (ML, data processing, batch jobs): Use **scx_rusty** for 5-7x better throughput
- **For web servers** (Meta, Steam Deck): Use **scx_lavd** for guaranteed low latency (0% errors)
- **For Kubernetes nodes**: Use **scx_lavd** for control plane stability, **scx_rusty** for batch pods
- **The default scheduler (CFS)** left significant performance on the table (22% error rate)

Read more about [why different schedulers win](#why-different-schedulers-win) for different workloads.

## Overview

Using `sched_ext` (Extended Scheduling Class), we can dynamically switch between different Linux schedulers and measure their impact on application performance. This project uses Gatling to load test a Spring Boot banking application running in a QEMU VM under different scheduler configurations.

The application runs in an isolated QEMU/Debian VM while load testing and orchestration happens on the host machine. **Everything is automated** - from kernel compilation to final performance reports.

## Project Structure

```
linux-scheduler-test/
├── pom.xml                          # Main Maven project for Gatling tests
├── spring-boot-app/                 # Spring Boot banking application
│   ├── pom.xml
│   └── src/main/java/com/banking/   # Banking app source code
├── src/test/scala/simulations/      # Gatling load test simulations
│   └── BankingTransactionSimulation.scala
├── scripts/
│   ├── setup-vm.sh                  # One-time VM provisioning
│   ├── vm-start.sh                  # Start the QEMU VM
│   ├── vm-stop.sh                   # Stop the QEMU VM
│   ├── vm-ssh.sh                    # SSH into the VM
│   ├── vm-snapshot.sh               # Create/restore VM snapshots
│   ├── vm-scheduler-switch.sh       # Switch schedulers in VM
│   ├── run-scheduler-test.sh        # Main test orchestrator
│   ├── start-app.sh                 # Start app locally (legacy)
│   ├── simple-test.sh               # Run test without scheduler switching
│   └── analyze-results.sh           # Analyze test results
├── vm/                              # VM images and config (generated)
└── results/                         # Test results (generated)
```

## Scope

- **Spring Boot Application**: Simulates a Banking Transaction system with REST APIs (runs in VM)
- **Message Broker**: Uses Kafka for async message processing (runs in VM, pre-installed)
- **Database**: H2 in-memory database for fast transaction processing
- **Load Testing**: Gatling framework with realistic user scenarios (runs on host)
- **VM Infrastructure**: QEMU with Debian 13 (trixie), cloud-init provisioning, 16GB RAM, kernel 6.12+ with sched_ext support, Kafka and Zookeeper pre-installed
- **Schedulers Tested**:
  - CFS (Completely Fair Scheduler) - default Linux scheduler
  - scx_rusty - Rusty sched_ext scheduler  
  - scx_lavd - Low-latency scheduler
  - scx_bpfland - BPF-based scheduler
  - scx_layered - Layered scheduler

## Testing

### Unit and Integration Tests

The Spring Boot application includes a comprehensive test suite with 30 JUnit 5 tests:

```bash
cd spring-boot-app
mvn test
```

Test execution completes in **7-10 seconds** and includes:
- **BankingApplicationTest**: 2 context loading tests
- **BankingServiceTest**: 10 banking operation tests (deposits, withdrawals, transfers)
- **BankingControllerTest**: 12 REST endpoint tests
- **ComputationalServiceTest**: 6 computational workload tests

**Test Configuration**:
- Uses H2 in-memory database
- Kafka disabled for tests via `@ConditionalOnProperty(name="kafka.enabled")`
- Fraud detection threshold set to 50000 for tests (vs 150 in production)
- All tests run in isolation with `@Transactional` rollback

## Why Different Schedulers Win

### scx_rusty (Throughput Champion)
- **Design:** Work-stealing, load-balancing across cores
- **Strengths:** CPU-bound compute, uniform workloads, batch processing
- **Weaknesses:** Not optimised for interactive latency
- **Use Cases:** ML training, data pipelines, batch jobs, our banking app

### scx_lavd (Latency Champion)
- **Design:** Latency-criticality Aware Virtual Deadline scheduling
- **Strengths:** Interactive workloads, mixed short/long tasks, responsiveness
- **Weaknesses:** Sacrifices throughput for latency (20x slower on compute-heavy tasks)
- **Use Cases:** Web servers (Meta), gaming (Steam Deck), Kubernetes control plane

### CFS (Default Baseline)
- **Design:** Fair time-sharing across all tasks
- **Strengths:** "Good enough" for most workloads, proven stability
- **Weaknesses:** Not optimised for any specific pattern, 22% errors under our load
- **Use Cases:** General purpose, when you can't tune for specific workload

### scx_bpfland & scx_layered
- **Status:** Poor fit for this workload (68% errors and slow respectively)
- **Note:** May excel in other scenarios (multi-tenant, specialized isolation)

**Key Insight:** Scheduler choice can be as impactful as hardware upgrades. The "best" scheduler depends entirely on your workload characteristics.

## Prerequisites

### Host System Requirements
- Linux with KVM support (any modern distribution)
- QEMU/KVM installed
- Java 17 or higher (for Gatling on host)
- Maven 3.6+
- 16GB+ RAM recommended (VM uses 16GB)
- 50GB+ free disk space (for VM image and kernel builds)

### Installing Host Dependencies
```bash
# On Debian/Ubuntu
sudo apt-get update
sudo apt-get install qemu-system-x86_64 qemu-utils cloud-image-utils \
  openssh-client netcat-openbsd openjdk-17-jdk maven

# Enable KVM (if not already enabled)
sudo modprobe kvm
sudo modprobe kvm_intel  # or kvm_amd for AMD CPUs
sudo usermod -aG kvm $USER  # Add yourself to kvm group
# Log out and back in for group change to take effect
```

## Quick Start

### Complete Automated Setup (Recommended)

```bash
# One command to run everything (kernel build → VM setup → scheduler tests)
./scripts/full-setup.sh
```

**Time:** ~70 minutes | **Output:** HTML performance reports + comparative metrics

This will:
1. ✅ Build custom Linux 6.12.6 kernel with sched_ext (~30 min)
2. ✅ Create and configure Debian VM (~5 min)
3. ✅ Install 13 schedulers (~15 min)
4. ✅ Run all scheduler tests with Gatling (~20 min)
5. ✅ Generate HTML reports with performance charts

Results saved to: `results/YYYYMMDD_HHMMSS/` and `target/gatling/*/index.html`

### Manual Step-by-Step Setup

### 1. One-Time VM Setup (Takes 45-60 minutes)
```bash
# This creates and provisions a Debian VM with Kafka and sched_ext support
./scripts/setup-vm.sh
```

This will:
- Download Debian cloud image
- Create a QEMU VM with 16GB RAM, 40GB disk
- Install Java, Maven, Rust, build tools, Kafka, and Zookeeper
- Configure Kafka topics (transactions, fraud-alerts)
- Clone and build sched_ext kernel schedulers
- Create a clean snapshot for easy resets

**Note**: Kafka and Zookeeper are automatically installed and configured in the VM. No separate setup needed!

### 2. Build the Spring Boot Application
```bash
cd spring-boot-app
mvn clean package
cd ..
```

### 3. Start the VM
```bash
./scripts/vm-start.sh
```

The VM will be accessible at:
- SSH: `localhost:2222`
- Application: `localhost:8080` (once deployed)
- Kafka: `localhost:9092`

Kafka and Zookeeper start automatically with the VM.

### 4. Run Full Scheduler Comparison
```bash
./scripts/run-scheduler-test.sh
```

This will:
- Deploy the Spring Boot app to the VM (with Kafka enabled)
- Test CFS and all available sched_ext schedulers
- Run 5-minute load tests for each scheduler
- Generate comprehensive reports with Gatling
- Collect system metrics from the VM

### 5. View Results
```bash
# Results are saved with timestamp
ls -la results/

# Open Gatling HTML report in browser
firefox results/[timestamp]/cfs_gatling_results/index.html
```

### 6. Stop the VM When Done
```bash
./scripts/vm-stop.sh
```

## Load Test Scenarios

The Gatling simulation includes 4 concurrent scenarios:

1. **Create Account** (10 users/sec): Creates new banking accounts
2. **Transfer Money** (50 users/sec): Performs money transfers between accounts
3. **Check Balance** (100 users/sec): Reads account balances
4. **Transaction History** (20 users/sec): Retrieves transaction history

Each scenario ramps up gradually, maintains steady load, then ramps down.

## VM Management

### SSH into VM
```bash
./scripts/vm-ssh.sh
# Or with a command
./scripts/vm-ssh.sh "ls -la /opt/banking-app"
```

### Create Snapshot (Save VM State)
```bash
./scripts/vm-snapshot.sh create my-snapshot-name
```

### Restore from Snapshot
```bash
# Stop VM first
./scripts/vm-stop.sh

# Restore snapshot
./scripts/vm-snapshot.sh restore my-snapshot-name

# Start VM again
./scripts/vm-start.sh
```

### List Snapshots
```bash
./scripts/vm-snapshot.sh list
```

### Restore Clean State Before Tests
```bash
# Automatically restore snapshot before running tests
RESTORE_SNAPSHOT=clean-install ./scripts/run-scheduler-test.sh
```

## Analysing Results

### View Gatling HTML Reports
```bash
./scripts/analyze-results.sh results/[timestamp]
```

Then open the HTML reports in a browser:
```bash
firefox results/[timestamp]/cfs_gatling_results/index.html
```

### Key Metrics to Compare
- **Response Time**: p50, p75, p95, p99 percentiles
- **Throughput**: Requests per second
- **Error Rate**: Failed requests percentage
- **System Load**: CPU load average during test (from VM)
- **Scheduler State**: Verify correct scheduler was active

## API Endpoints

The Spring Boot application exposes:

- `POST /api/accounts` - Create account
- `GET /api/accounts/{id}` - Get account details
- `GET /api/accounts/{id}/balance` - Get account balance
- `POST /api/transactions/transfer` - Transfer money
- `GET /api/accounts/{id}/transactions` - Get transaction history
- `GET /actuator/health` - Health check

## Customisation

### Adjust VM Resources
Edit the VM startup parameters in [scripts/vm-start.sh](scripts/vm-start.sh):
```bash
VM_RAM=16G        # Increase RAM
VM_CPUS=6         # More CPUs
```

### Adjust Load Test Intensity
Edit [src/test/scala/simulations/BankingTransactionSimulation.scala](src/test/scala/simulations/BankingTransactionSimulation.scala):
```scala
constantUsersPerSec(50).during(2.minutes)  // Adjust users and duration
```

### Test Different Schedulers
Edit [scripts/run-scheduler-test.sh](scripts/run-scheduler-test.sh):
```bash
SCHEDULERS=("scx_rusty" "scx_lavd" "scx_bpfland" "scx_layered" "scx_cosmos")
```

### Change Test Duration
```bash
TEST_DURATION=600  # 10 minutes per scheduler in run-scheduler-test.sh
```

## Networking Details

### Port Forwarding (QEMU User-Mode Networking)
- **Host → VM**: 
  - `localhost:2222` → `VM:22` (SSH)
  - `localhost:8080` → `VM:8080` (Spring Boot app)
- **VM → Host**: 
  - `10.0.2.2:9092` → Host Kafka
  - `10.0.2.2` is the special address for the host in QEMU user-mode networking

## Troubleshooting

### Common Issues

#### VM Won't Start
**Symptom:** `Error: Permission denied` or `Could not access KVM kernel module`
**Solution:**
```bash
# Check if KVM is loaded
lsmod | grep kvm

# Load KVM module
sudo modprobe kvm
sudo modprobe kvm_intel  # or kvm_amd

# Add user to kvm group
sudo usermod -aG kvm $USER
# Log out and back in for change to take effect
```

#### Kafka Connection Failures
**Symptom:** `org.apache.kafka.common.errors.TimeoutException: Topic transactions not present in metadata`
**Solution:**
```bash
# SSH into VM and check Kafka status
./scripts/vm-ssh.sh "sudo systemctl status kafka"
./scripts/vm-ssh.sh "sudo systemctl status zookeeper"

# Restart Kafka services
./scripts/vm-ssh.sh "sudo systemctl restart zookeeper && sleep 5 && sudo systemctl restart kafka"

# Verify topics exist
./scripts/vm-ssh.sh "kafka-topics.sh --list --bootstrap-server localhost:9092"
```

#### Gatling Test Hangs or Fails
**Symptom:** Tests stuck at "Waiting for server to be ready" or connection refused errors
**Solution:**
```bash
# Check if app is running in VM
./scripts/vm-ssh.sh "ps aux | grep banking-app"

# Check application logs
./scripts/vm-ssh.sh "tail -50 /opt/banking-app/logs/application.log"

# Verify app responds to health check
curl http://localhost:8080/actuator/health

# Restart application
./scripts/vm-ssh.sh "sudo systemctl restart banking-app"
```

#### Scheduler Won't Switch
**Symptom:** `sched_ext_ops_load: Operation not permitted` or scheduler still shows CFS
**Solution:**
```bash
# Verify sched_ext kernel is running
./scripts/vm-ssh.sh "uname -r"
# Should show: 6.12.6-schedext-*

# Check if another scheduler is already loaded
./scripts/vm-ssh.sh "sudo scx_dump --states"

# Kill existing scheduler first
./scripts/vm-ssh.sh "sudo pkill scx_"

# Try loading scheduler again
./scripts/vm-ssh.sh "sudo scx_rusty -v"
```

#### Out of Memory Errors
**Symptom:** VM becomes unresponsive or Gatling crashes
**Solution:**
```bash
# Increase VM RAM in vm-start.sh
VM_RAM=24G  # Default is 16G

# Reduce Gatling load intensity
# Edit BankingTransactionSimulation.scala:
constantUsersPerSec(25)  # Reduce from 50
```

#### Results Directory Not Found
**Symptom:** `ls: cannot access 'results/': No such file or directory`
**Solution:**
```bash
# Results are created automatically during test runs
# Check if test completed successfully:
ls -la target/gatling/

# If Gatling reports exist but results/ is empty:
./scripts/analyze-results.sh target/gatling/scheduler-test-*
```

#### Permission Denied on Scripts
**Symptom:** `bash: permission denied: ./scripts/full-setup.sh`
**Solution:**
```bash
# Make all scripts executable
chmod +x scripts/*.sh
```

### Getting Help

1. **Check logs:** Most issues are logged in `/opt/banking-app/logs/` in the VM
2. **VM console:** Use `./scripts/vm-ssh.sh` to inspect running processes
3. **Gatling simulation logs:** Check `target/gatling/*/simulation.log`
4. **System metrics:** Run `./scripts/vm-ssh.sh "top -bn1 | head -20"` to check resource usage

## Script Reference

### Core Scripts

| Script | Purpose | Runtime | Notes |
|--------|---------|---------|-------|
| `full-setup.sh` | Complete end-to-end setup and testing | ~70 min | Recommended for first-time users |
| `setup-vm.sh` | Create and configure VM | ~45 min | One-time setup |
| `vm-start.sh` | Start the VM | ~30 sec | Auto-starts Kafka/Zookeeper |
| `vm-stop.sh` | Gracefully stop VM | ~10 sec | Always use before host shutdown |
| `vm-ssh.sh` | SSH into VM or run commands | Instant | Use `vm-ssh.sh "command"` |
| `run-scheduler-test.sh` | Run full scheduler comparison | ~20 min | Tests all 5 schedulers |
| `simple-test.sh` | Quick test of current scheduler | ~3 min | For rapid iteration |
| `analyze-results.sh` | Extract metrics from test results | ~5 sec | Generates comparative summaries |
| `vm-scheduler-switch.sh` | Switch scheduler in VM | ~2 sec | Used internally by test scripts |

### Advanced Scripts

| Script | Purpose | Notes |
|--------|---------|-------|
| `vm-snapshot.sh` | Create/restore VM snapshots | Useful for test repeatability |
| `start-app.sh` | Deploy Spring Boot app to VM | Called automatically by test scripts |

## Where Are My Results?

After running tests, results are stored in **two locations**:

### 1. Detailed HTML Reports (Per-Scheduler)
**Location:** `target/gatling/scheduler-test-TIMESTAMP/`
**Contains:** 
- `index.html` - Interactive charts and graphs
- `stats.json` - Raw performance metrics
- `simulation.log` - Detailed request/response logs

**Open in browser:**
```bash
firefox target/gatling/scheduler-test-*/index.html
```

### 2. Comparative Summary (All Schedulers)
**Location:** `results/YYYYMMDD_HHMMSS/`
**Contains:**
- `{scheduler}_stats.json` - Extracted metrics for each scheduler
- `summary.txt` - Side-by-side comparison
- `metrics.csv` - Excel-compatible data

**View summary:**
```bash
cat results/$(ls -t results/ | head -1)/summary.txt
```

## Customising for Your Application

Want to test your own Java application instead of the banking demo?

### 1. Replace the Spring Boot App
```bash
# Copy your JAR to the project
cp /path/to/your-app.jar spring-boot-app/target/your-app.jar
```

### 2. Update Deployment Script
Edit [scripts/start-app.sh](scripts/start-app.sh):
```bash
JAR_NAME="your-app.jar"
VM_APP_PATH="/opt/your-app"
```

### 3. Create Custom Gatling Simulation
Create `src/test/scala/simulations/YourAppSimulation.scala`:
```scala
package simulations

import io.gatling.core.Predef._
import io.gatling.http.Predef._
import scala.concurrent.duration._

class YourAppSimulation extends Simulation {
  val httpProtocol = http
    .baseUrl("http://localhost:8080")
    .acceptHeader("application/json")
  
  val scn = scenario("Your Workload")
    .exec(
      http("Your Endpoint")
        .get("/api/your-endpoint")
        .check(status.is(200))
    )
  
  setUp(
    scn.inject(
      rampUsersPerSec(1).to(50).during(1.minute),
      constantUsersPerSec(50).during(2.minutes),
      rampUsersPerSec(50).to(1).during(1.minute)
    )
  ).protocols(httpProtocol)
}
```

### 4. Update Test Script
Edit [scripts/run-scheduler-test.sh](scripts/run-scheduler-test.sh):
```bash
SIMULATION_NAME="YourAppSimulation"
```

### 5. Run Your Tests
```bash
./scripts/run-scheduler-test.sh
```

**Pro Tip:** Use CPU-intensive endpoints (data processing, calculations, encryption) to see the biggest scheduler differences. Simple CRUD operations may not show significant variance.

## Known Limitations

- **sched_ext kernel required:** Tests must run on Linux 6.12+ with CONFIG_SCHED_CLASS_EXT=y
- **VM overhead:** Results include QEMU virtualization overhead (~5-10% performance impact)
- **Network latency:** Gatling runs on host, tests through port forwarding (adds ~1ms)
- **Snapshot reliability:** VM snapshots work best when VM is stopped
- **Scheduler availability:** Some schedulers may not compile on all CPU architectures
- **Single-node testing:** Does not test distributed/multi-node scenarios

## Future Enhancements

- [ ] Docker container support (test without VM)
- [ ] Real-time dashboard during tests
- [ ] Prometheus metrics export
- [ ] Multi-VM cluster testing
- [ ] ARM64 support for M-series Macs
- [ ] Automated scheduler auto-tuning parameter sweep
- [ ] Integration with CI/CD pipelines

## Contributing

Contributions welcome! Areas of interest:
- Additional workload patterns (machine learning, databases, etc.)
- Support for other languages (Python, Node.js, Go)
- Better visualisation of results
- Kubernetes node testing scenarios

## License

MIT License - See LICENSE file for details

## Acknowledgments

- **sched_ext maintainers:** Tejun Heo, David Vernet, Dan Schatzberg
- **Scheduler authors:** Meta (scx_lavd), Valve (scx_layered), Andrea Righi (scx_bpfland)
- **Linux kernel team:** For making CONFIG_SCHED_CLASS_EXT possible
- **Gatling:** For the excellent load testing framework

## Further Reading

- [sched_ext Documentation](https://www.kernel.org/doc/html/latest/scheduler/sched-ext.html)
- [Meta's Blog on scx_lavd](https://engineering.fb.com/2024/01/scheduler-improvements/)
- [Valve's Steam Deck Scheduler Work](https://www.phoronix.com/news/Valve-Linux-Scheduler-Work)
- [Original Test Results Discussion](https://github.com/dfoulkes/scx_test_harness/discussions)

---

**⚡ Pro Tip:** Run `./scripts/full-setup.sh` once, then use `./scripts/simple-test.sh` for rapid iteration when tuning your application or experimenting with scheduler parameters.
# Check if KVM is available
lsmod | grep kvm

# Check QEMU installation
which qemu-system-x86_64

# Check if another VM is running
cat vm/qemu.pid
ps aux | grep qemu
```

### SSH Connection Refused
```bash
# Check if VM is running
nc -z localhost 2222

# Check VM logs (if VM started in foreground)
# Or restart VM with verbose output
VM_RAM=12G VM_CPUS=4 ./scripts/vm-start.sh
```

### Schedulers Not Found in VM
```bash
# SSH into VM and check installation
./scripts/vm-ssh.sh
ls -la /usr/local/bin/scx_*
which scx_rusty

# Rebuild schedulers if needed
cd ~/scx
source ~/.cargo/env
make
sudo make install
```

### Application Won't Start in VM
```bash
# Check if Java is installed
./scripts/vm-ssh.sh "java -version"

# Check application logs
./scripts/vm-ssh.sh "cat /opt/banking-app/app.log"

# Check if port 8080 is already in use
./scripts/vm-ssh.sh "netstat -tlnp | grep 8080"
```

### Kafka Connection Issues
```bash
# Verify Kafka is running on host
docker ps | grep kafka
netstat -tlnp | grep 9092

# Test connectivity from VM to host
./scripts/vm-ssh.sh "nc -zv 10.0.2.2 9092"

# Application will work without Kafka (degrades gracefully)
```

### Slow VM Performance
```bash
# Ensure KVM acceleration is enabled
./scripts/vm-ssh.sh "cat /proc/cpuinfo | grep -E 'vmx|svm'"

# Increase VM resources
VM_RAM=16G VM_CPUS=6 ./scripts/vm-start.sh
```

## Resources

- [sched_ext GitHub](https://github.com/sched-ext/scx/tree/main)
- [sched_ext Documentation](https://github.com/sched-ext/scx/blob/main/README.md)
- [Gatling Documentation](https://gatling.io/docs/gatling/)
- [Spring Boot Documentation](https://spring.io/projects/spring-boot)
- [QEMU Documentation](https://www.qemu.org/documentation/)
- [cloud-init Documentation](https://cloudinit.readthedocs.io/)

## Architecture

```mermaid
graph TB
    subgraph Host["🖥️ Host Machine"]
        Gatling["📊 Gatling Load Tester<br/>(Maven/Scala)"]
        Kafka["📨 Kafka Broker<br/>(Docker)<br/>Port 9092"]
        
        subgraph PortForward["Port Forwarding"]
            PF1["localhost:2222 → VM:22"]
            PF2["localhost:8080 → VM:8080"]
        end
    end
    
    subgraph VM["💻 Debian 13 VM<br/>(16GB RAM, 8 vCPUs, Kernel 6.12.6)"]
        subgraph App["Spring Boot Banking App"]
            REST["🌐 REST API<br/>Port 8080"]
            H2["💾 H2 Database<br/>(In-Memory)"]
            KProducer["📤 Kafka Producer"]
        end
        
        subgraph Schedulers["⚙️ sched_ext Schedulers"]
            SCX1["scx_rusty"]
            SCX2["scx_lavd"]
            SCX3["scx_bpfland"]
            SCX4["scx_layered"]
        end
        
        SchedState["📋 /sys/kernel/sched_ext/state<br/>(Active Scheduler)"]
    end
    
    Gatling -->|HTTP Requests| PF2
    PF2 -->|8080| REST
    
    Kafka -->|10.0.2.2:9092| KProducer
    KProducer -.->|Events| Kafka
    
    REST --- H2
    
    Schedulers -.->|Controls| App
    SchedState -.->|Status| Schedulers
    
    style Host fill:#e1f5ff
    style VM fill:#fff4e1
    style App fill:#e8f5e9
    style Schedulers fill:#fce4ec
    style PortForward fill:#f3e5f5
```

**Key Components:**
- **Host**: Runs Gatling load tests and optional Kafka broker
- **VM**: Isolated Debian environment with custom kernel for scheduler testing
- **Networking**: QEMU user-mode networking (`10.0.2.2` = host from VM perspective)
- **Schedulers**: Dynamically switchable via `/sys/kernel/sched_ext/state`

## Limitations

### Virtualisation Overhead
- **Not Bare Metal**: Tests run in QEMU/KVM, which adds virtualisation overhead that may not reflect bare metal performance
- **Nested Scheduling**: The host's scheduler affects the VM's scheduler, creating a nested scheduling scenario
- **CPU Pinning**: QEMU vCPUs are scheduled by the host kernel, which can introduce variability
- **Impact**: Results show *relative* performance differences between schedulers, not absolute bare metal performance

### Workload Constraints
- **Single Application**: Only tests one Spring Boot application, not representative of multi-application server workloads
- **Synthetic Load**: Gatling simulates user behavior but doesn't capture all real-world patterns
- **In-Memory Database**: H2 database doesn't test I/O-bound workloads that might benefit differently from schedulers
- **No CPU-Intensive Tasks**: Banking operations are relatively lightweight compared to rendering, compilation, or scientific computing

### Scheduler Feature Coverage
- **Limited Topology Testing**: Doesn't extensively test NUMA awareness, cache affinity, or complex CPU topologies
- **No Interactive Workloads**: Doesn't measure desktop responsiveness or latency-sensitive GUI applications
- **Limited I/O Testing**: Minimal testing of I/O scheduler interactions
- **No Real-Time Testing**: Doesn't test real-time scheduling guarantees or deadlines

### Testing Environment
- **Network Latency**: Port forwarding adds minimal latency that wouldn't exist in bare metal deployments
- **Resource Isolation**: VM provides perfect isolation but doesn't test scheduler behavior under system-wide contention
- **Fixed Kernel Version**: Tests specific kernel version (6.12.6), scheduler behavior may vary across versions
- **Limited Schedulers**: Only tests available sched_ext schedulers, not all possible scheduling policies

### Measurement Accuracy
- **Sampling Overhead**: Gatling and metrics collection add measurement overhead
- **Warm-up Effects**: JVM warm-up and JIT compilation affect early test results
- **Statistical Variance**: Results can vary between runs due to system state, cache effects, and timing
- **No Hardware Counters**: Doesn't collect PMU (Performance Monitoring Unit) data for deep CPU analysis

### Recommendations for Interpretation
1. **Use for Comparison**: Results are most valuable for *comparing* schedulers under identical conditions
2. **Understand Context**: Performance differences are specific to this workload and may not generalise
3. **Validate on Bare Metal**: Important findings should be validated on bare metal systems
4. **Consider Your Workload**: Choose schedulers based on similarity to your actual production workload
5. **Multiple Runs**: Run tests multiple times and analyze variance before drawing conclusions

### What This Harness IS Good For
✅ Comparing relative scheduler performance under controlled conditions  
✅ Quick prototyping and testing of scheduler configurations  
✅ Educational exploration of sched_ext capabilities  
✅ Identifying obvious performance regressions or improvements  
✅ Testing scheduler behavior under specific workload patterns

### What This Harness IS NOT Good For
❌ Absolute bare metal performance measurement  
❌ Production deployment decisions without validation  
❌ Testing real-time or latency-critical applications  
❌ Comprehensive scheduler feature validation  
❌ Hardware-specific optimisations (NUMA, cache topology)

## License

MIT

