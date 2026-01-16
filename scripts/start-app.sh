#!/bin/bash

# Quick start script for the Spring Boot application

set -e

cd "$(dirname "$0")/.."

echo "Building Spring Boot Application..."
cd spring-boot-app
mvn clean package -DskipTests

echo ""
echo "Starting Spring Boot Application..."
java -jar target/banking-app.jar
