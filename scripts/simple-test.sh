#!/bin/bash

# Simple test script that doesn't require scheduler switching
# Useful for testing the setup without root access

set -e

echo "==================================="
echo "Running Simple Load Test"
echo "==================================="

APP_URL="${APP_URL:-http://localhost:8080}"

# Check if app is running
echo "Checking if application is running at $APP_URL..."
if ! curl -s "$APP_URL/actuator/health" > /dev/null; then
    echo "Application is not running at $APP_URL"
    echo "Start it with: ./scripts/start-app.sh"
    exit 1
fi

echo "Application is running!"
echo ""

# Run Gatling test
echo "Running Gatling load test..."
mvn gatling:test -DbaseUrl="$APP_URL"

echo ""
echo "Test completed!"
echo "Results are in: target/gatling/"
