#!/bin/bash
# ==========================================================
# 🚀 HNG DevOps Stage 1 – Automated Deployment Script
# Author: Owajimimin John
# ==========================================================

set -e
LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"

# --- Cross-platform sudo detection (works on Windows, Linux, Mac) ---
if command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  SUDO=""
fi

# --- Prompt for user inputs ---
read -p "🌿 Enter branch name [default: main]: " BRANCH
BRANCH=${BRANCH:-main}

read -p "👤 Remote server username: " USERNAME
read -p "🌐 Remote server IP address: " SERVER_IP
read -p "🔑 SSH key path: " SSH_KEY
read -p "🚪 Application port: " APP_PORT

# --- GitHub inputs ---
read -p "📦 Enter GitHub repository URL (HTTPS): " REPO_URL
read -p "🔐 Enter your GitHub Personal Access Token (PAT): " PAT

echo "============================================================" | tee -a "$LOG_FILE"
echo "🚀 Starting deployment at $(date)" | tee -a "$LOG_FILE"
echo "============================================================" | tee -a "$LOG_FILE"

# --- Clone or update repo ---
if [ -d "app_repo" ]; then
  echo "📁 Repository already exists. Pulling latest changes..." | tee -a "$LOG_FILE"
  cd app_repo && git pull >> "$LOG_FILE" 2>&1 && cd ..
else
  echo "📥 Cloning repository..." | tee -a "$LOG_FILE"
  git clone -b "$BRANCH" "https://$PAT@${REPO_URL#https://}" app_repo >> "$LOG_FILE" 2>&1
fi

# --- Verify project structure ---
cd app_repo
if [ ! -f "Dockerfile" ] && [ ! -f "docker-compose.yml" ]; then
  echo "❌ No Dockerfile or docker-compose.yml found!" | tee -a "$LOG_FILE"
  exit 2
fi
cd ..

# --- Build and run Docker containers ---
echo "🐳 Building and deploying containers..." | tee -a "$LOG_FILE"
docker compose down >> "$LOG_FILE" 2>&1 || true
docker compose up -d --build >> "$LOG_FILE" 2>&1

# --- Check running containers ---
echo "🔍 Checking container status..." | tee -a "$LOG_FILE"
docker ps | tee -a "$LOG_FILE"

# --- Configure Nginx reverse proxy ---
echo "🌐 Configuring Nginx reverse proxy..." | tee -a "$LOG_FILE"
$SUDO docker exec -i automated-bash-script_nginx bash -c "
cat > /etc/nginx/conf.d/flask_app.conf <<EOF
server {
    listen 80;
    location / {
        proxy_pass http://automated-bash-script-flask:5000;
    }
}
EOF
" >> "$LOG_FILE" 2>&1

$SUDO docker exec automated-bash-script_nginx nginx -t >> "$LOG_FILE" 2>&1
$SUDO docker exec automated-bash-script_nginx nginx -s reload >> "$LOG_FILE" 2>&1
echo "✅ Nginx reloaded successfully." | tee -a "$LOG_FILE"

# --- Validate app deployment ---
echo "🧪 Validating application..." | tee -a "$LOG_FILE"
sleep 5
if curl -s http://127.0.0.1:"$APP_PORT" | grep -q "Hello"; then
  echo "🎉 Deployment successful! App running at: http://127.0.0.1" | tee -a "$LOG_FILE"
else
  echo "⚠️  App did not respond correctly. Check logs." | tee -a "$LOG_FILE"
fi

echo "============================================================" | tee -a "$LOG_FILE"
echo "✅ Deployment complete! Log saved to: $LOG_FILE"
echo "============================================================"

