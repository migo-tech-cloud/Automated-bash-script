#!/bin/bash

# === Automated Local Deployment Script ===
# Description: Builds and runs a Flask + Nginx app locally using Docker Compose
# Author: Your Name
# Usage: chmod +x deploy.sh && ./deploy.sh

set -e

APP_NAME="automated-bash-script"
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"

echo "🔧 Starting local deployment for $APP_NAME..." | tee -a "$LOG_FILE"

# Step 1: Ensure Docker is running
if ! docker info > /dev/null 2>&1; then
  echo "❌ Docker is not running. Please start Docker Desktop and re-run this script." | tee -a "$LOG_FILE"
  exit 1
fi

# Step 2: Build and start containers
echo "🚀 Building and starting containers..." | tee -a "$LOG_FILE"
docker-compose up -d --build 2>&1 | tee -a "$LOG_FILE"

# Step 3: Wait a few seconds for containers to initialize
sleep 5

# Step 4: Check running containers
echo "📦 Checking running containers..." | tee -a "$LOG_FILE"
docker ps | tee -a "$LOG_FILE"

# Step 5: Verify Flask container is healthy
if docker ps --filter "name=${APP_NAME}_flask" --filter "status=running" | grep -q "${APP_NAME}_flask"; then
  echo "✅ Flask container is running properly!" | tee -a "$LOG_FILE"
else
  echo "❌ Flask container failed to start. Check logs below:" | tee -a "$LOG_FILE"
  docker logs "${APP_NAME}_flask" | tee -a "$LOG_FILE"
  exit 1
fi

# Step 6: Print local access instructions
echo ""
echo "🎉 Deployment complete!"
echo "🌐 Visit your app at: http://localhost"
echo "📜 Logs saved to: $LOG_FILE"
echo ""

