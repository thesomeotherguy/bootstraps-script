#!/bin/bash

set -e
set -o pipefail

echo "[INFO] Ensuring 'git' is installed..."
apt-get update -y && apt-get install -y git

echo "[INFO] Cloning bootstrap repo (clean)..."
rm -rf /workspace/bootstraps-script
git clone https://github.com/thesomeotherguy/bootstraps-script.git /workspace/bootstraps-script

echo "[INFO] Starting system services (SSH, Nginx, Jupyter)..."
/bin/bash /workspace/bootstraps-script/runpod-comfyui/start-runpod-services.sh

echo "[INFO] Running ComfyUI bootstrap..."
/bin/bash /workspace/bootstraps-script/runpod-comfyui/comfyui-bootstrap.sh

echo "[INFO] All setup done. Container is ready."
sleep infinity
