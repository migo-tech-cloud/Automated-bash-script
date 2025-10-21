# Automated-bash-script
# Automated Deployment — `deploy.sh`


## Overview


`deploy.sh` automates the setup and deployment of a Dockerized application to a remote Linux server over SSH. It:


- Collects user input (Git repo, PAT, branch, SSH details, ports)
- Clones or updates the repo (using the PAT)
- Prepares the remote host (installs Docker, Docker Compose, Nginx)
- Transfers files and deploys containers (docker or docker-compose)
- Creates/updates an Nginx reverse proxy configuration
- Validates the deployment
- Logs all actions to `deploy_YYYYMMDD_HHMMSS.log`
- Is idempotent and includes a `--cleanup` option


> POSIX-compatible Bash script. Make it executable before use: `chmod +x deploy.sh`.


## Quick start


1. Ensure you have SSH access to the remote server and an SSH key.
2. Place `deploy.sh` where you want to run it locally and make it executable:


```bash
chmod +x deploy.sh
./deploy.sh
