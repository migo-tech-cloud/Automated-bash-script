# Automated-bash-script

A simple Flask application and an automated deployment script for the HNG DevOps Stage 1 task.

This repo contains:
- `app.py` — simple Flask app
- `requirements.txt` — Python dependencies
- `Dockerfile` and `docker-compose.yml` — container definitions
- `deploy.sh` — automated deployment script (added by assistant)

## Quick usage

1. Make sure your local repo contains the application files (`app.py`, `requirements.txt`, `Dockerfile`, `docker-compose.yml`).
2. Make the deploy script executable:

```bash
chmod +x deploy.sh