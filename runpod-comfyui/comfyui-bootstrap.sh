#!/bin/bash

set -e  # Exit on error
set -o pipefail

echo "[INFO] Setting working directory permissions and switching to /internalworkspace"
mkdir -p /internalworkspace
cd /internalworkspace
chmod -R 755 /internalworkspace

echo "[INFO] Updating and installing essential tools..."
apt-get update -y
apt-get install -y wget nano curl git cmake zstd

echo "[INFO] Installing 'uv' (Python packaging tool)..."
wget -qO- https://astral.sh/uv/install.sh | bash

echo "[INFO] Updating PATH for uv..."
export PATH="$HOME/.local/bin:$PATH"
hash -r

echo "[INFO] Installing Python 3.12 using uv and setting up virtual environment..."
uv python install 3.12
uv venv --python 3.12
source .venv/bin/activate

echo "[INFO] Aliasing pip to 'uv pip' and modifying pip behavior inside venv..."
mkdir -p .venv/lib/python3.12/site-packages/pip
cat << 'EOF' > .venv/lib/python3.12/site-packages/pip/__main__.py
import sys, subprocess, os.path
if __package__ is None and not getattr(sys, 'frozen', False):
    path = os.path.realpath(os.path.abspath(__file__))
    sys.path.insert(0, os.path.dirname(os.path.dirname(path)))
if __name__ == '__main__':
    ls=['uv', 'pip'] + sys.argv[1:]
    subprocess.check_call(ls)
EOF
chmod +x .venv/lib/python3.12/site-packages/pip/__main__.py

echo "[INFO] Installing Hugging Face CLI and setting up authentication..."
uv pip install --upgrade huggingface_hub
uv pip install 'huggingface_hub[cli]' 'huggingface_hub[hf_transfer]'
git config --global credential.helper store

echo "[INFO] Cloning ComfyUI repository..."
git clone https://github.com/comfyanonymous/ComfyUI.git

echo "[INFO] Installing ComfyUI Manager plugin..."
cd /internalworkspace/ComfyUI/custom_nodes
git clone https://github.com/ltdrdata/ComfyUI-Manager comfyui-manager

echo "[INFO] Installing Python dependencies..."
cd /internalworkspace
source .venv/bin/activate
uv pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu126
uv pip install -r ComfyUI/requirements.txt
uv pip install -r ComfyUI/custom_nodes/comfyui-manager/requirements.txt
uv pip install dlib insightface
uv pip uninstall onnxruntime onnxruntime-gpu
uv pip install onnxruntime-gpu --extra-index-url https://aiinfra.pkgs.visualstudio.com/PublicPackages/_packaging/onnxruntime-cuda-12/pypi/simple/

echo "[INFO] Creating run script in /workspace..."
mkdir -p /workspace
cat << 'EOF' > /workspace/run_gpu.sh
#!/bin/bash
cd /internalworkspace
source .venv/bin/activate
cd ComfyUI
python main.py --listen --preview-method auto
EOF
chmod +x /workspace/run_gpu.sh

echo "[INFO] Creating input/output symlinks in /workspace..."
ln -sfn /internalworkspace/ComfyUI/input /workspace/input
ln -sfn /internalworkspace/ComfyUI/output /workspace/output
mkdir -p /internalworkspace/ComfyUI/user/default/workflows
ln -sfn /internalworkspace/ComfyUI/user/default/workflows /workspace/workflows

# Optional CLI login (if needed)
# echo $HUGGINGFACE_TOKEN | huggingface-cli login --token --stdin
# About Hugging Face token
# It's set on .env or orchestrator like RunPod before deploying pods

echo "[INFO] Enabling hf_transfer for faster Hugging Face downloads (temporary)..."
export HF_HUB_ENABLE_HF_TRANSFER=1
echo "[INFO] Making hf_transfer persistent across reboots/shells..."
echo 'export HF_HUB_ENABLE_HF_TRANSFER=1' >> ~/.bashrc

echo "[INFO] Creating script to download model from Hugging Face..."
cat << 'EOF' > /internalworkspace/download-hf.py
from huggingface_hub import snapshot_download
import os

repo_id = "thesomeotherguy/for-runpod-deploy"
token = os.getenv("HUGGINGFACE_TOKEN")
local_dir = "./for-runpod-deploy"
repo_type = "model"

snapshot_download(
    repo_id=repo_id,
    repo_type=repo_type,
    token=token,
    local_dir=local_dir,
    ignore_patterns=["*.py", "*.md", "*.sh", "*.tar.zst", "*.zst"],
)

print(f"[INFO] Repo downloaded directly to: {local_dir}")
EOF

echo "[INFO] Downloading private Hugging Face model using hf_transfer..."
python /internalworkspace/download-hf.py

echo "[INFO] Organizing model directory..."
rm -rf /internalworkspace/ComfyUI/models
mv /internalworkspace/for-runpod-deploy/comfyui-models-folder /internalworkspace/ComfyUI/models
rm -rf /internalworkspace/for-runpod-deploy/comfyui-models-folder

echo "[INFO] Bootstrap completed. Deactivating virtual environment..."
deactivate

echo "[DONE] All setup tasks completed successfully."
