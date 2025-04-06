#!/bin/bash

set -e
set -o pipefail

echo "[INFO] Running ComfyUI bootstrap..."
/bin/bash /workspace/script/bootstraps-script/runpod-comfyui/comfyui-bootstrap.sh

echo "[INFO] Starting system services (SSH, Nginx, Jupyter)..."
/bin/bash /workspace/script/bootstraps-script/runpod-comfyui/start-runpod-services.sh

echo "[INFO] All setup done. Container is ready."
