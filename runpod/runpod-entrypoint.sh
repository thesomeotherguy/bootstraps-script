#!/bin/bash

set -e
set -o pipefail

echo "[INFO] Cloning bootstrap repo if not already present..."
if [ ! -d /workspace/bootstraps-script ]; then
    git clone https://github.com/thesomeotherguy/bootstraps-script.git /workspace/bootstraps-script
fi

echo "[INFO] Starting system services (SSH, Nginx, Jupyter)..."
/bin/bash /workspace/bootstraps-script/runpod/start-runpod-services.sh

echo "[INFO] Running ComfyUI bootstrap..."
/bin/bash /workspace/bootstraps-script/runpod/comfyui-bootstrap.sh

echo "[INFO] All setup done. Container is ready."
sleep infinity
