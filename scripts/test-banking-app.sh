#!/bin/bash

# Test the banking application with scheduler benchmarks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_URL="http://localhost:8080"

echo "=========================================="
echo "Banking App Scheduler Test"
echo "=========================================="
echo ""

# Test 1: Health check
echo "1. Health Check:"
curl -s "${BASE_URL}/actuator/health" | jq -r '.status'
echo ""

# Test 2: Create test accounts
echo "2. Creating test accounts..."
ACCOUNT1=$(curl -s -X POST "${BASE_URL}/api/accounts" \
  -H "Content-Type: application/json" \
  -d '{"accountNumber": "ACC001", "balance": 1000.00}' | jq -r '.id')
echo "   Created account: $ACCOUNT1"

ACCOUNT2=$(curl -s -X POST "${BASE_URL}/api/accounts" \
  -H "Content-Type: application/json" \
  -d '{"accountNumber": "ACC002", "balance": 2000.00}' | jq -r '.id')
echo "   Created account: $ACCOUNT2"
echo ""

# Test 3: Create transactions
echo "3. Creating test transactions..."
for i in {1..5}; do
  RESPONSE=$(curl -s -X POST "${BASE_URL}/api/transactions" \
    -H "Content-Type: application/json" \
    -d "{\"fromAccountId\": $ACCOUNT1, \"toAccountId\": $ACCOUNT2, \"amount\": 10.00}")
  echo "   Transaction $i: $(echo $RESPONSE | jq -r '.status // "COMPLETED"')"
done
echo ""

# Test 4: Query accounts
echo "4. Account balances:"
curl -s "${BASE_URL}/api/accounts/${ACCOUNT1}" | jq '{accountNumber, balance}'
curl -s "${BASE_URL}/api/accounts/${ACCOUNT2}" | jq '{accountNumber, balance}'
echo ""

# Test 5: Load test with different schedulers
echo "5. Scheduler Performance Test"
echo "=========================================="
echo ""

SCHEDULERS=("EEVDF" "scx_simple" "scx_rusty")

for SCHEDULER in "${SCHEDULERS[@]}"; do
  echo "Testing with: $SCHEDULER"
  echo "---"
  
  # Switch scheduler
  if [ "$SCHEDULER" = "EEVDF" ]; then
    echo "Using default EEVDF scheduler (sched_ext disabled)"
    ssh -p 2222 -i ~/.ssh/scheduler_test_vm -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      debian@localhost "pgrep scx_ | xargs -r sudo kill 2>/dev/null || true" 2>/dev/null
    sleep 2
  else
    echo "Switching to $SCHEDULER..."
    ssh -p 2222 -i ~/.ssh/scheduler_test_vm -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      debian@localhost "pgrep scx_ | xargs -r sudo kill 2>/dev/null || true; sudo $SCHEDULER &" 2>/dev/null &
    sleep 3
  fi
  
  # Run benchmark
  echo "Running transaction benchmark (10 requests)..."
  START=$(date +%s%N)
  
  for i in {1..10}; do
    curl -s -X POST "${BASE_URL}/api/transactions" \
      -H "Content-Type: application/json" \
      -d "{\"fromAccountId\": $ACCOUNT1, \"toAccountId\": $ACCOUNT2, \"amount\": 1.00}" > /dev/null
  done
  
  END=$(date +%s%N)
  DURATION=$(( (END - START) / 1000000 ))
  
  echo "Completed in: ${DURATION}ms"
  echo "Average: $((DURATION / 10))ms per transaction"
  echo ""
done

echo "=========================================="
echo "Test Complete!"
echo "=========================================="
echo ""
echo "View Kafka messages:"
echo "  ./scripts/vm-ssh.sh '/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic transactions --from-beginning --max-messages 5'"
