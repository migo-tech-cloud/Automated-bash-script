## deploy.sh (place at repo root and `chmod +x deploy.sh`)

```bash
#!/usr/bin/env bash
# deploy.sh — Automated deployment script tailored for "Automated-bash-script"
# Assumptions:
#  - Remote host: Ubuntu (apt)
#  - SSH key authentication is set up for the remote user
#  - Repo contains docker-compose.yml (script will prefer compose)
#  - Nginx will proxy public port 80 to the container internal port (e.g., 5000)

set -o errexit
set -o pipefail
set -o nounset

TIMESTAMP() { date +'%Y%m%d_%H%M%S'; }
LOGFILE="deploy_$(TIMESTAMP).log"
exec > >(tee -a "$LOGFILE") 2>&1

info() { printf "[%s] INFO: %s
" "$(date +'%F %T')" "$*"; }
warn() { printf "[%s] WARN: %s
" "$(date +'%F %T')" "$*"; }
error() { printf "[%s] ERROR: %s
" "$(date +'%F %T')" "$*"; }

die() { error "$1"; exit ${2:-1}; }

trap 'error "Script failed at line $LINENO"; exit 50' ERR
trap 'info "Script finished at $(date -u) UTC"' EXIT

usage() {
  cat <<EOF
Usage: $0 [--cleanup] [--help]

Interactive mode prompts for values. For non-interactive use, set environment variables (see README).

Flags:
  --cleanup    Remove remote deploy directory, containers, and nginx config then exit
  --help       Show this message
EOF
  exit 2
}

CLEANUP=false
for arg in "$@"; do
  case "$arg" in
    --cleanup) CLEANUP=true ;;
    --help) usage ;;
    *) usage ;;
  esac
done

# Read input (interactive unless NONINTERACTIVE=true env var is set)
if [ "${NONINTERACTIVE:-false}" = "true" ]; then
  info "Non-interactive mode: reading variables from environment"
  GIT_URL="${GIT_URL:-}"
  GIT_PAT="${GIT_PAT:-}"
  GIT_BRANCH="${GIT_BRANCH:-main}"
  REMOTE_USER="${REMOTE_USER:-}"
  REMOTE_IP="${REMOTE_IP:-}"
  SSH_KEY="${SSH_KEY:-}"
  APP_PORT="${APP_PORT:-}"
  REMOTE_PATH="${REMOTE_PATH:-~/app_deploy}"
else
  read -r -p "Git repository HTTPS URL: " GIT_URL
  read -r -s -p "Personal Access Token (PAT): " GIT_PAT
  echo
  read -r -p "Branch (default: main): " GIT_BRANCH
  GIT_BRANCH=${GIT_BRANCH:-main}
  read -r -p "Remote SSH username: " REMOTE_USER
  read -r -p "Remote public IP: " REMOTE_IP
  read -r -p "Local SSH private key path (e.g. ~/.ssh/id_rsa): " SSH_KEY
  read -r -p "Application internal container port (e.g. 5000): " APP_PORT
  read -r -p "Remote deploy path (default: ~/app_deploy): " REMOTE_PATH
  REMOTE_PATH=${REMOTE_PATH:-~/app_deploy}
fi

# Basic validations
[ -n "${GIT_URL:-}" ] || die "GIT_URL is required" 3
[ -n "${GIT_PAT:-}" ] || die "GIT_PAT is required" 4
[ -n "${REMOTE_USER:-}" ] || die "REMOTE_USER is required" 5
[ -n "${REMOTE_IP:-}" ] || die "REMOTE_IP is required" 6
[ -n "${SSH_KEY:-}" ] || die "SSH_KEY is required" 7
[ -n "${APP_PORT:-}" ] || die "APP_PORT is required" 8

# Expand ~ for paths
case "$SSH_KEY" in ~/*) SSH_KEY="$HOME/${SSH_KEY#~/}" ;; esac
case "$REMOTE_PATH" in ~/*) REMOTE_PATH="$HOME/${REMOTE_PATH#~/}" ;; esac

[ -f "$SSH_KEY" ] || die "SSH key not found at $SSH_KEY" 9

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
REMOTE_TARGET="$REMOTE_USER@$REMOTE_IP"

# Ensure HTTPS URL
if printf '%s' "$GIT_URL" | grep -qE '^https://'; then
  AUTH_GIT_URL=$(printf '%s' "$GIT_URL" | sed -e "s#https://#https://$GIT_PAT:@#")
else
  die "GIT_URL must be HTTPS (e.g. https://github.com/user/repo.git)" 10
fi

REPO_NAME=$(basename "$GIT_URL" .git)
LOCAL_CLONE_DIR="./$REPO_NAME"

info "Local clone dir: $LOCAL_CLONE_DIR"

# CLEANUP mode: remove remote resources and exit
if [ "$CLEANUP" = true ]; then
  info "Running remote cleanup..."
  ssh $SSH_OPTS "$REMOTE_TARGET" bash -s <<'REMOTE_CLEAN' || true
set -eux
REMOTE_PATH="${REMOTE_PATH:-~/app_deploy}"
if [ -d "$REMOTE_PATH" ]; then
  cd "$REMOTE_PATH" || true
  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose down --rmi all || true
  fi
  docker ps -a --filter "name=hng_flask_app" --format '{{.ID}}' | xargs -r docker rm -f || true
  docker ps -a --filter "name=hng_deploy" --format '{{.ID}}' | xargs -r docker rm -f || true
  rm -rf "$REMOTE_PATH"
fi
NGCONF="/etc/nginx/sites-available/hng_deploy"
NGENABLED="/etc/nginx/sites-enabled/hng_deploy"
sudo rm -f "$NGENABLED" "$NGCONF" || true
sudo nginx -t || true
sudo systemctl reload nginx || true
REMOTE_CLEAN
  info "Remote cleanup finished."
  exit 0
fi

# Clone or update locally
info "Cloning or updating repository locally"
if [ -d "$LOCAL_CLONE_DIR/.git" ]; then
  (cd "$LOCAL_CLONE_DIR" && git fetch --all --prune) || die "git fetch failed" 11
  (cd "$LOCAL_CLONE_DIR" && git checkout "$GIT_BRANCH" && git pull origin "$GIT_BRANCH") || die "git checkout/pull failed" 12
else
  info "Cloning $GIT_URL (branch: $GIT_BRANCH)"
  git clone --branch "$GIT_BRANCH" "$AUTH_GIT_URL" "$LOCAL_CLONE_DIR" || die "git clone failed" 13
  (cd "$LOCAL_CLONE_DIR" && git remote set-url origin "$GIT_URL") || true
fi

# Verify docker-compose existence
if [ -f "$LOCAL_CLONE_DIR/docker-compose.yml" ] || [ -f "$LOCAL_CLONE_DIR/docker-compose.yaml" ]; then
  info "docker-compose file found — using docker-compose deployment"
else
  die "docker-compose.yml not found in repo root; script configured to use docker-compose for this repo" 14
fi

# Check SSH connectivity
info "Checking SSH connectivity to $REMOTE_TARGET"
if ssh $SSH_OPTS -o BatchMode=yes "$REMOTE_TARGET" "echo connected" >/dev/null 2>&1; then
  info "SSH OK"
else
  ssh $SSH_OPTS "$REMOTE_TARGET" "echo connected" || die "SSH connection failed" 15
fi

# Remote preparation: install Docker, docker-compose, nginx (Ubuntu/apt)
info "Preparing remote host (install docker, docker-compose, nginx if missing)"
REMOTE_PREP=$(cat <<'REMOTE_PREP_EOF'
set -eux
REMOTE_PATH="__REMOTE_PATH__"
APP_PORT="__APP_PORT__"
mkdir -p "$REMOTE_PATH"
cd "$REMOTE_PATH"
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update -y
  sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common
  if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm -f get-docker.sh
  fi
  if ! command -v docker-compose >/dev/null 2>&1; then
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
  fi
  if ! command -v nginx >/dev/null 2>&1; then
    sudo apt-get install -y nginx
  fi
else
  echo "Non-apt distro detected; manual steps required" >&2
  exit 20
fi
if ! groups "$USER" | grep -q docker; then
  sudo groupadd -f docker || true
  sudo usermod -aG docker "$USER" || true
fi
sudo systemctl enable docker || true
sudo systemctl start docker || true
sudo systemctl enable nginx || true
sudo systemctl start nginx || true
# versions (non-fatal)
docker --version || true
docker-compose --version || true
nginx -v || true
REMOTE_PREP_EOF
)
REMOTE_PREP=${REMOTE_PREP//__REMOTE_PATH__/$REMOTE_PATH}
REMOTE_PREP=${REMOTE_PREP//__APP_PORT__/$APP_PORT}

ssh $SSH_OPTS "$REMOTE_TARGET" 'bash -s' <<REMOTE_RUN
$REMOTE_PREP
REMOTE_RUN

# rsync project
info "Syncing project files to remote"
rsync -avz --delete --exclude '.git' -e "ssh $SSH_OPTS" "$LOCAL_CLONE_DIR/" "$REMOTE_TARGET:$REMOTE_PATH/" || die "rsync failed" 21

# remote deploy (docker-compose)
info "Running docker-compose on remote"
REMOTE_DEPLOY=$(cat <<'REMOTE_DEPLOY_EOF'
set -eux
REMOTE_PATH="__REMOTE_PATH__"
APP_PORT="__APP_PORT__"
cd "$REMOTE_PATH"
if command -v docker-compose >/dev/null 2>&1 && ([ -f docker-compose.yml ] || [ -f docker-compose.yaml ]); then
  docker-compose down --remove-orphans || true
  docker-compose pull || true
  docker-compose up -d --build
else
  echo "docker-compose not available or compose file missing" >&2
  exit 22
fi
sleep 4
docker ps --format 'table {{.Names}}    {{.Status}}' || true
REMOTE_DEPLOY_EOF
)
REMOTE_DEPLOY=${REMOTE_DEPLOY//__REMOTE_PATH__/$REMOTE_PATH}
REMOTE_DEPLOY=${REMOTE_DEPLOY//__APP_PORT__/$APP_PORT}

ssh $SSH_OPTS "$REMOTE_TARGET" 'bash -s' <<REMOTE_EXEC
$REMOTE_DEPLOY
REMOTE_EXEC

# configure nginx
info "Configuring nginx to reverse-proxy port 80 -> $APP_PORT"
REMOTE_NGINX=$(cat <<'NGINX_EOF'
set -eux
APP_PORT="__APP_PORT__"
NGCONF="/etc/nginx/sites-available/hng_deploy"
NGENABLED="/etc/nginx/sites-enabled/hng_deploy"
sudo bash -c "cat > $NGCONF" <<'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:APP_PORT_PLACEHOLDER;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
sudo ln -sf "$NGCONF" "$NGENABLED"
sudo nginx -t
sudo systemctl reload nginx
NGINX_EOF
)
REMOTE_NGINX=${REMOTE_NGINX//APP_PORT_PLACEHOLDER/$APP_PORT}
REMOTE_NGINX=${REMOTE_NGINX//__APP_PORT__/$APP_PORT}

ssh $SSH_OPTS "$REMOTE_TARGET" 'bash -s' <<NGRUN
$REMOTE_NGINX
NGRUN

# validation
info "Validating deployment"
ssh $SSH_OPTS "$REMOTE_TARGET" "sudo systemctl is-active --quiet docker && echo docker_running || echo docker_not_running" || true
CONTAINER_STATUS=$(ssh $SSH_OPTS "$REMOTE_TARGET" "docker ps --filter 'name=hng_flask_app' --format '{{.Names}}:{{.Status}}' || true" || true)
info "Container status: ${CONTAINER_STATUS:-<none>}"
REMOTE_HTTP=$(ssh $SSH_OPTS "$REMOTE_TARGET" "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:$APP_PORT || echo 000" || true)
info "Remote local HTTP code: $REMOTE_HTTP"
PUBLIC_HTTP=$(curl -s -o /dev/null -w '%{http_code}' "http://$REMOTE_IP/" --max-time 10 || echo 000) || true
info "Public HTTP code: $PUBLIC_HTTP"

if [ "$REMOTE_HTTP" = "000" ] || [ "$PUBLIC_HTTP" = "000" ]; then
  warn "Endpoint checks failed — check firewall (security groups), nginx, or container health"
else
  info "Endpoint checks passed. Local->container: $REMOTE_HTTP, Public: $PUBLIC_HTTP"
fi

info "Done. Logs saved to $LOGFILE"
exit 0
