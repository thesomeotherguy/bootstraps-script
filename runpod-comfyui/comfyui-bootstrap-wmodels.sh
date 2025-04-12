#!/bin/bash

set -e  # Exit on error
set -o pipefail

echo "[INFO] Setting working directory permissions and switching to /internalworkspace"
mkdir -p /internalworkspace
cd /internalworkspace
chmod -R 755 /internalworkspace

echo "[INFO] Updating and installing essential tools..."
apt-get update -y
apt-get install -y wget nano curl git cmake zstd tmux ncdu

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
uv pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu126
uv pip install -r ComfyUI/requirements.txt
uv pip install -r ComfyUI/custom_nodes/comfyui-manager/requirements.txt
uv pip install /workspace/.script/bootstraps-script/pip-wheels/dlib/dlib-19.24.6-cp312-cp312-linux_x86_64.whl
uv pip install /workspace/.script/bootstraps-script/pip-wheels/dlib/insightface/insightface-0.7.3-cp312-cp312-linux_x86_64.whl

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
echo "[INFO] Removing default internal directories if they exist..."
rm -rf /internalworkspace/ComfyUI/input
rm -rf /internalworkspace/ComfyUI/output
rm -rf /internalworkspace/ComfyUI/user/default/workflows

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

# Optional CLI login (if needed), please type:
# echo $HUGGINGFACE_TOKEN
# It's set on .env or orchestrator like RunPod before deploying pods

echo "[INFO] Enabling hf_transfer for faster Hugging Face downloads..."
export HF_HUB_ENABLE_HF_TRANSFER=1
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

echo "[INFO] Copying backup and upload scripts..."
cd /internalworkspace
cp /workspace/.script/bootstraps-script/runpod-comfyui/comfyui-venv-backup.sh /internalworkspace/comfyui-venv-backup.sh
chmod +x comfyui-venv-backup.sh
cp /workspace/.script/bootstraps-script/runpod-comfyui/comfyui-venv-backup-upload.py /internalworkspace/comfyui-venv-backup-upload.py
cd /workspace
cp /workspace/.script/bootstraps-script/runpod-comfyui/workspace-backup.sh /workspace/workspace-backup.sh
chmod +x workspace-backup.sh
cp /workspace/.script/bootstraps-script/runpod-comfyui/show-comfyui-console.sh /workspace/show-comfyui-console.sh
chmod +x show-comfyui-console.sh # basically just `tmux attach -t comfyui`

echo "[INFO] Configuring tmux for mouse support..."
# Define the tmux config file path explicitly for clarity
TMUX_CONF_FILE="/root/.tmux.conf"
# Check if the mouse setting already exists to avoid duplicates
# -q: quiet (no output), -x: match whole line exactly, -F: treat pattern as fixed string
# Redirect grep error output (e.g., file not found) to /dev/null
if ! grep -qxF 'set -g mouse on' "$TMUX_CONF_FILE" 2>/dev/null; then
    # Ensure the directory exists (though /root should always exist)
    mkdir -p "$(dirname "$TMUX_CONF_FILE")"
    # Append the setting to the file
    echo 'set -g mouse on' >> "$TMUX_CONF_FILE"
    echo "[INFO] Added 'set -g mouse on' to $TMUX_CONF_FILE"
else
    echo "[INFO] 'set -g mouse on' already exists in $TMUX_CONF_FILE."
fi

echo "[INFO] Configuring terminal to auto-attach FIRST terminal to tmux session 'comfyui'..."
# Remove any previous auto-attach attempts from .bashrc if script runs multiple times
# Using '#' as delimiter for sed to avoid conflict with paths if they were used
sed -i '\%# START TMUX AUTO ATTACH%,\%# END TMUX AUTO ATTACH%d' /root/.bashrc
# Add the new logic
# Using 'EOF' ensures no variable expansion happens *now*, only when .bashrc is read later
cat << 'EOF' >> /root/.bashrc
# START TMUX AUTO ATTACH
# Auto-attach to tmux session 'comfyui' if it exists, we're not in tmux, AND no other client is attached
if command -v tmux &> /dev/null && tmux has-session -t comfyui 2>/dev/null; then
  # Check if we are NOT already inside tmux
  if [ -z "$TMUX" ]; then
    # Check if there are currently NO clients attached to the session
    # The command substitution $() is correct here
    if [ -z "$(tmux list-clients -t comfyui 2>/dev/null)" ]; then
      echo "Attempting to attach first terminal to tmux session 'comfyui'..."
      # This attach command is correct
      tmux attach -t comfyui
      # Note: The echo below will only appear after successful detach/exit
      echo "Detached from tmux session 'comfyui'."
    fi # End client check
  fi # End TMUX check
fi # End command/session check
# END TMUX AUTO ATTACH
EOF

echo "[INFO] Bootstrap completed. Deactivating virtual environment..."
deactivate

echo "[DONE] All setup tasks completed successfully."
