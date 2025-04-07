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

echo "[INFO] Installing Hugging Face CLI and setting up authentication..."
uv pip install --upgrade huggingface_hub
uv pip install 'huggingface_hub[cli]' 'huggingface_hub[hf_transfer]'
git config --global credential.helper store

# Optional CLI login (if needed)
# echo $HUGGINGFACE_TOKEN | huggingface-cli login --token --stdin
# About Hugging Face token
# It's set on .env or orchestrator like RunPod before deploying pods

echo "[INFO] Enabling hf_transfer for faster Hugging Face downloads..."
export HF_HUB_ENABLE_HF_TRANSFER=1
echo 'export HF_HUB_ENABLE_HF_TRANSFER=1' >> ~/.bashrc

echo "[INFO] Python script to download single file from Hugging Face..."
cat << 'EOF' > /internalworkspace/download-single-hf.py
from huggingface_hub import hf_hub_download
import os

repo_id = "thesomeotherguy/for-runpod-deploy"
filename = "comfyui-venv.tar.zst"
token = os.getenv("HUGGINGFACE_TOKEN")

file_path = hf_hub_download(
    repo_id=repo_id,
    filename=filename,
    token=token,
    local_dir="/internalworkspace",
)

print(f"[INFO] File downloaded to: {file_path}")
EOF

echo "[INFO] Running download script..."
python /internalworkspace/download-single-hf.py

deactivate
cd /internalworkspace
rm -rf /internalworkspace/.venv

###########################################
echo "[INFO] Extracting comfyui.tar.zst ..."
cd /internalworkspace
# Extract the archive (preserving structure but not permissions)
tar --no-same-owner -I 'zstd -T0' -xf comfyui-venv.tar.zst -C /internalworkspace/
# Set ownership to root
echo "[INFO] Set ownership of extracted ComfyUI + venv to root..."
chown -R root:root /internalworkspace/ComfyUI /internalworkspace/.venv
# Set appropriate permissions
echo "[INFO] Set appropriate permissions of extracted ComfyUI + venv ..."
find /internalworkspace/ComfyUI /internalworkspace/.venv -type d -exec chmod 755 {} \;
find /internalworkspace/ComfyUI /internalworkspace/.venv -type f -exec chmod 644 {} \;
# Make scripts executable
echo "[INFO] Make scripts of extracted ComfyUI + venv folders executable..."
find /internalworkspace/ComfyUI -name "*.sh" -exec chmod +x {} \;
find /internalworkspace/ComfyUI -name "*.py" -exec chmod +x {} \;
# Make Python binaries in venv executable
echo "[INFO] Make Python binaries of extracted venv folders executable ..."
find /internalworkspace/.venv/bin -type f -exec chmod +x {} \;
###########################################

echo "[INFO] Cleaning up..."
rm comfyui-venv.tar.zst

source .venv/bin/activate

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

echo "[INFO] Reconfiguring ComfyUI directory symlinks..."

# 1. Ensure all necessary directories exist
echo "[INFO] Ensuring target data directories exist in /workspace..."
mkdir -p /workspace/input
mkdir -p /workspace/output
mkdir -p /workspace/workflows

echo "[INFO] Ensuring parent directories for links exist in /internalworkspace..."
mkdir -p /internalworkspace/ComfyUI/user/default

# 2. Remove potentially conflicting original directories/files within /internalworkspace
echo "[INFO] Removing default internal directories if they exist (safe even if they don't)..."
rm -rf /internalworkspace/ComfyUI/input
rm -rf /internalworkspace/ComfyUI/output
rm -rf /internalworkspace/ComfyUI/user/default/workflows # This is safe

# 3. Create all symbolic links
echo "[INFO] Creating symlinks from /internalworkspace pointing to /workspace..."
ln -sfn /workspace/input /internalworkspace/ComfyUI/input
ln -sfn /workspace/output /internalworkspace/ComfyUI/output
ln -sfn /workspace/workflows /internalworkspace/ComfyUI/user/default/workflows

echo "[INFO] Symlink configuration complete."

# Optional: Verification step
echo "[INFO] Verifying symlinks and target directories:"
ls -ld \
    /internalworkspace/ComfyUI/input \
    /internalworkspace/ComfyUI/output \
    /internalworkspace/ComfyUI/user/default/workflows \
    /workspace/input \
    /workspace/output \
    /workspace/workflows

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

# echo "[INFO] Downloading private Hugging Face model using hf_transfer..."
# python /internalworkspace/download-hf.py

# echo "[INFO] Organizing model directory..."
# rm -rf /internalworkspace/ComfyUI/models
# mv /internalworkspace/for-runpod-deploy/comfyui-models-folder /internalworkspace/ComfyUI/models

echo "[INFO] Bootstrap completed. Deactivating virtual environment..."
deactivate

echo "[DONE] All setup tasks completed successfully."
