# 🚀 Automated Deployment Bash Script — HNG DevOps Stage 1

This project automates the deployment of a Dockerized Flask app locally, simulating a production-grade DevOps workflow.  
It includes automated build, container orchestration, Nginx reverse proxy, and health checks — all triggered by a single Bash script.

---

## 🧠 Features
- Automated Docker build and container startup
- Nginx reverse proxy for local routing
- Health and log verification
- Idempotent re-runs
- Single-command setup (`./deploy.sh`)

---

## 🧩 Project Structure
```bash
Automated-bash-script/
├── app.py
├── requirements.txt
├── Dockerfile
├── nginx.conf
├── docker-compose.yml
├── deploy.sh
└── README.md
