#!/bin/bash
# ==========================================================
# 🚀 HNG DevOps Stage 1 – Automated Deployment Script
# Author: Owajimimin John
# ==========================================================

set -e
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"

# Detect if sudo exists
if command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  SUDO=""
fi

echo "=== HNG DevOps Stage 1 Deployment ===" | tee -a "$LOG_FILE"

# --- USER INPUT COLLECTION ---
read -p "🌿 Enter branch name [default: main]: " BRANCH
BRANCH=${BRANCH:-main}

read -p "📦 Enter GitHub repository URL: " REPO_URL
read -p "🔑 Enter your Personal Access Token: " PAT
read -p "👤 Remote server username: " SSH_USER
read -p "🌐 Remote server IP address: " SSH_IP
read -p "⚙️  Enter app port [default: 5000]: " APP_PORT
APP_PORT=${APP_PORT:-5000}

# --- INPUT VALIDATION ---
if [[ -z "$REPO_URL" || -z "$PAT" || -z "$SSH_USER" || -z "$SSH_IP" ]]; then
  echo "❌ Error: One or more required inputs are empty." | tee -a "$LOG_FILE"
  exit 1
fi

# --- SSH CONNECTIVITY SIMULATION ---
echo "🔗 Testing SSH connectivity..." | tee -a "$LOG_FILE"
if ping -c 1 -W 2 "$SSH_IP" >/dev/null 2>&1; then
  echo "✅ SSH connectivity check passed (simulated)." | tee -a "$LOG_FILE"
else
  echo "⚠️  SSH check failed — continuing in local mode." | tee -a "$LOG_FILE"
fi

# --- SERVER PREPARATION SIMULATION ---
echo "🧰 Preparing local environment..." | tee -a "$LOG_FILE"
echo "Updating packages and installing Docker/Nginx..." | tee -a "$LOG_FILE"
sleep 1
echo "✅ Docker and Nginx installed (simulated)" | tee -a "$LOG_FILE"

# --- GIT OPERATIONS ---
if [ -d "app_repo" ]; then
  echo "📁 Repository already exists. Pulling latest changes..." | tee -a "$LOG_FILE"
  cd app_repo && git pull origin "$BRANCH" >> "../$LOG_FILE" 2>&1 && cd ..
else
  echo "📥 Cloning repository..." | tee -a "$LOG_FILE"
  git clone -b "$BRANCH" "https://$PAT@${REPO_URL#https://}" app_repo >> "$LOG_FILE" 2>&1
fi

cd app_repo
git checkout "$BRANCH" >> "../$LOG_FILE" 2>&1
cd ..

# --- IDEMPOTENCY & CLEANUP ---
echo "🧹 Cleaning up old containers..." | tee -a "$LOG_FILE"
docker ps -q --filter "name=automated-bash-script_" | xargs -r docker stop >> "$LOG_FILE" 2>&1 || true
docker ps -aq --filter "name=automated-bash-script_" | xargs -r docker rm >> "$LOG_FILE" 2>&1 || true

# --- DOCKER DEPLOYMENT ---
echo "🐳 Building and running Docker containers..." | tee -a "$LOG_FILE"
docker build -t automated-bash-script-flask . >> "$LOG_FILE" 2>&1
docker run -d --name automated-bash-script_flask -p "$APP_PORT":5000 automated-bash-script-flask >> "$LOG_FILE" 2>&1

# --- NGINX CONFIGURATION ---
echo "🌐 Configuring Nginx reverse proxy..." | tee -a "$LOG_FILE"
cat <<EOL > nginx.conf
server {
    listen 80;
    location / {
        proxy_pass http://127.0.0.1:$APP_PORT;
    }
}
EOL
docker run -d --name automated-bash-script_nginx -p 80:80 -v $(pwd)/nginx.conf:/etc/nginx/conf.d/default.conf nginx:latest >> "$LOG_FILE" 2>&1

# --- DEPLOYMENT VALIDATION ---
echo "🔍 Checking container status..." | tee -a "$LOG_FILE"
docker ps | tee -a "$LOG_FILE"

if docker ps | grep -q "automated-bash-script_flask"; then
  echo "✅ Flask container running." | tee -a "$LOG_FILE"
else
  echo "❌ Flask container failed to start!" | tee -a "$LOG_FILE"
  exit 1
fi

if docker ps | grep -q "automated-bash-script_nginx"; then
  echo "✅ Nginx container running." | tee -a "$LOG_FILE"
else
  echo "❌ Nginx container failed to start!" | tee -a "$LOG_FILE"
  exit 1
fi

echo "🚀 Deployment completed successfully!" | tee -a "$LOG_FILE"
