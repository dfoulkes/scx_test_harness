# Multi-Threaded Distributed Computing Architecture

## Overview

The banking application uses **heavy multi-threaded parallel computation** to create massive thread contention and force the scheduler to make complex thread ordering decisions.

## Testing

The application includes **30 comprehensive JUnit 5 tests** that complete in **7-10 seconds**:

- **BankingApplicationTest**: 2 tests for context loading
- **BankingServiceTest**: 10 tests for banking operations
- **BankingControllerTest**: 12 tests for REST endpoints
- **ComputationalServiceTest**: 6 tests for computational workloads

**Test Configuration** (`application-test.properties`):
```properties
kafka.enabled=false                    # Kafka disabled for tests
fraud.detection.threshold=50000        # Lenient threshold (vs 150 in prod)
spring.kafka.bootstrap-servers=        # No Kafka connection
```

**Kafka is Optional**: The application uses `@ConditionalOnProperty(name="kafka.enabled")` on `KafkaProducerService` and `KafkaConsumerService`, so Kafka components are only loaded when explicitly enabled. The `BankingService` uses `@Autowired(required=false)` for the Kafka producer with null checks.

## Thread Pool Configuration

### Thread Pools Created:
- **computationExecutor**: 16-32 threads for computational tasks
- **parallelExecutor**: 24-48 threads for parallel operations  
- **Built-in thread pool**: 24 fixed threads for distributed tasks

**Total concurrent threads: 64-100+ competing threads**

## Parallel Operations

### 1. Fraud Detection (8 Competing Threads per Request)
```
Request → Spawns 8 parallel threads
├─ Thread 1: SHA-256 hashing (2000 iterations)
├─ Thread 2: SHA-256 hashing (2000 iterations)
├─ Thread 3: SHA-256 hashing (2000 iterations)
├─ Thread 4: SHA-256 hashing (2000 iterations)
├─ Thread 5: SHA-256 hashing (2000 iterations)
├─ Thread 6: SHA-256 hashing (2000 iterations)
├─ Thread 7: SHA-256 hashing (2000 iterations)
├─ Thread 8: SHA-256 hashing (2000 iterations)
├─ Thread 9: Anomaly detection (heavy math)
├─ Thread 10: Risk calculation (nested loops)
└─ Thread 11: ML inference (matrix multiplication)

All threads synchronize at completion → 11 threads per request
```

### 2. Risk Assessment (16 Competing Threads per Request)
```
Request → Splits 15,000 Monte Carlo simulations across 16 threads
├─ Thread 1: 937 simulations × 100 steps each
├─ Thread 2: 937 simulations × 100 steps each
├─ Thread 3: 937 simulations × 100 steps each
...
└─ Thread 16: 937 simulations × 100 steps each

Thread synchronization + array merging + sorting
```

### 3. Portfolio Optimization (8 Competing Threads per Request)
```
Request → Runs 8 parallel portfolio optimizations
├─ Thread 1: 2000 gradient descent iterations
├─ Thread 2: 2000 gradient descent iterations
├─ Thread 3: 2000 gradient descent iterations
...
└─ Thread 8: 2000 gradient descent iterations

Compare results → pick best portfolio
```

### 4. Distributed Prime Search (12 Competing Threads per Request)
```
Request → Splits range into 12 segments
├─ Thread 1: Prime search in range [start, start+8333]
├─ Thread 2: Prime search in range [start+8333, start+16666]
...
└─ Thread 12: Prime search in range [end-8333, end]

Merge results from all threads
```

## Thread Contention Characteristics

### Scheduler Stress Points:

1. **Thread Creation Burst**: Each request spawns 8-16 threads simultaneously
2. **Synchronization Points**: All threads must complete before response
3. **CPU-Bound**: Pure computation, no I/O blocking
4. **Competing Resources**: Multiple requests create 100+ competing threads
5. **Context Switching**: Heavy scheduler overhead with thread switching
6. **Cache Thrashing**: Different threads working on different data

### Load Test Thread Count:

At peak load (all scenarios running):
- 15 req/sec × 11 threads = 165 fraud detection threads
- 10 req/sec × 16 threads = 160 Monte Carlo threads  
- 8 req/sec × 8 threads = 64 portfolio optimization threads
- 8 req/sec × 12 threads = 96 prime search threads
- 20 req/sec transfers with fraud = 220 additional threads

**Total peak concurrent threads: ~700+ threads competing for CPU time**

## Scheduler Testing Impact

### What This Tests:

1. **Thread Scheduling Fairness**: How well scheduler distributes CPU among 700+ threads
2. **Context Switch Overhead**: Frequent switching between competing threads
3. **Priority Inversion**: Handling of thread priorities under load
4. **Load Balancing**: Distribution of threads across CPU cores
5. **Thread Starvation**: Prevention of thread starvation under heavy load
6. **Cache Locality**: How well scheduler maintains cache locality
7. **Throughput vs Latency**: Tradeoffs different schedulers make

### Expected Scheduler Differences:

- **CFS (Completely Fair Scheduler)**: Fair distribution, moderate latency
- **scx_rusty**: Optimized for multi-core, better load balancing
- **scx_lavd**: Low-latency focus, faster thread wakeup
- **scx_bpfland**: Custom scheduling policies, flexible behavior
- **scx_layered**: Layered priorities, complex workload handling

## API Endpoints

### Multi-Threaded Endpoints:

```bash
# Fraud check: 11 parallel threads per request
GET /api/accounts/{id}/fraud-check?amount=5000

# Risk analysis: 16 parallel threads per request  
GET /api/accounts/{id}/risk-analysis

# Portfolio optimization: 8 parallel threads per request
GET /api/accounts/{id}/portfolio-optimization

# Prime search: 12 parallel threads per request
GET /api/accounts/{id}/distributed-prime-search?rangeSize=100000

# Transfer: 11+ parallel threads (includes fraud detection)
POST /api/transactions/transfer
```

## Performance Metrics

### What to Measure:

1. **Response Time Distribution**: p50, p75, p95, p99 under thread contention
2. **Thread Context Switches**: Scheduler efficiency (from `/proc/pid/status`)
3. **CPU Utilization**: Should be 100% across all cores
4. **Thread Wait Time**: How long threads wait for CPU
5. **Throughput**: Requests completed per second
6. **Fairness**: Standard deviation of thread execution times

### Collect Metrics:

```bash
# In VM during test
vmstat 1 60  # Context switches per second
mpstat -P ALL 1 60  # Per-CPU utilization
perf record -a -g -- sleep 60  # Performance profiling
cat /proc/schedstat  # Scheduler statistics
```

## Key Differences from Previous Version:

| Aspect | Before | Now |
|--------|--------|-----|
| Threads per request | 1 | 8-16 |
| Concurrent threads | ~50 | 700+ |
| Thread contention | Low | **Extreme** |
| Synchronization | None | Heavy |
| Context switches | Minimal | **Massive** |
| Scheduler stress | Low | **Maximum** |

This architecture will clearly show which scheduler handles massive thread contention most efficiently!
