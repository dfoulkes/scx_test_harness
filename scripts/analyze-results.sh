#!/bin/bash

# Script to analyze and compare scheduler test results

RESULTS_DIR=${1:-"results"}

if [ ! -d "$RESULTS_DIR" ]; then
    echo "Results directory not found: $RESULTS_DIR"
    echo "Usage: $0 [results_directory]"
    exit 1
fi

echo "==================================="
echo "Scheduler Performance Comparison"
echo "==================================="
echo ""

# Find all test result directories
TEST_RUNS=$(ls -d $RESULTS_DIR/*/ 2>/dev/null | tail -1)

if [ -z "$TEST_RUNS" ]; then
    echo "No test results found in $RESULTS_DIR"
    exit 1
fi

cd "$TEST_RUNS"

echo "Test Run: $(basename $TEST_RUNS)"
echo ""

# Compare metrics from each scheduler
for scheduler in cfs scx_simple scx_rusty scx_lavd; do
    if [ -d "${scheduler}_gatling_results" ]; then
        echo "--- $scheduler ---"
        
        # Extract key metrics from Gatling report
        if [ -f "${scheduler}_gatling_results/js/stats.json" ]; then
            echo "Extracting performance metrics..."
            # In a real scenario, you'd parse the JSON for metrics
            echo "See HTML report: ${scheduler}_gatling_results/index.html"
        fi
        
        # Show system metrics
        if [ -f "${scheduler}_metrics.txt" ]; then
            echo ""
            echo "System Load Average:"
            grep -A1 "Post-Test Load Average" "${scheduler}_metrics.txt" || echo "N/A"
        fi
        
        echo ""
    fi
done

echo "==================================="
echo "To view detailed results, open:"
for scheduler in cfs scx_simple scx_rusty scx_lavd; do
    if [ -d "${scheduler}_gatling_results" ]; then
        echo "  - ${scheduler}_gatling_results/index.html"
    fi
done
