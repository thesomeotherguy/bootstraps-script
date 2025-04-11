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

echo "[INFO] Installing Python 3.12 using uv and setting up virtual environment, only for huggingface_hub HF backup download..."
uv python install 3.12
uv venv --python 3.12
source .venv/bin/activate

echo "[INFO] Installing huggingface_hub CLI and HF Transfer..."
uv pip install --upgrade huggingface_hub
uv pip install 'huggingface_hub[cli]' 'huggingface_hub[hf_transfer]'
git config --global credential.helper store

# Optional CLI login (if needed), please type:
# echo $HUGGINGFACE_TOKEN
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

echo "[INFO] Running download comfyui-venv.tar.zst script..."
python /internalworkspace/download-single-hf.py

echo "[INFO] Creating script to download models from Hugging Face..."
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

echo "[INFO] Deactivate and remove initial huggingface_hub virtual environment..."
deactivate
cd /internalworkspace
rm -rf /internalworkspace/.venv
      
###########################################
echo "[INFO] Placing ComfyUI webapp and replacing virtual environment by extracting comfyui-venv.tar.zst ..."
cd /internalworkspace
tar --no-same-owner -I 'zstd -T0' -xf comfyui-venv.tar.zst -C /internalworkspace/

echo "[INFO] Set ownership of extracted ComfyUI + venv to root..."
chown -R root:root /internalworkspace/ComfyUI /internalworkspace/.venv

echo "[INFO] Set directory and file permissions..."
# Applies to ComfyUI and .venv directories
find /internalworkspace/ComfyUI /internalworkspace/.venv -type d -exec chmod 755 {} \;
# Applies to files inside ComfyUI and .venv
find /internalworkspace/ComfyUI /internalworkspace/.venv -type f -exec chmod 644 {} \;

echo "[INFO] Make scripts/binaries executable..."
# Shell scripts in ComfyUI directories
find /internalworkspace/ComfyUI -name "*.sh" -exec chmod +x {} \;
# Binaries/scripts in .venv directories
find /internalworkspace/.venv/bin -type f -exec chmod +x {} \;

# Reset Git state to match the repo state (fixes file permissions/modes)
echo "[INFO] Forcing clean git state in ComfyUI repository..."
cd /internalworkspace/ComfyUI || { echo "[ERROR] Failed to cd into /internalworkspace/ComfyUI"; exit 1; }
git reset --hard HEAD
cd /internalworkspace || { echo "[ERROR] Failed to cd back to /internalworkspace"; exit 1; }

echo "[INFO] Forcing clean git state in ComfyUI custom node repositories (and submodules)..."
find /internalworkspace/ComfyUI/custom_nodes -type d -name .git -execdir git reset --hard HEAD \; || echo "[WARN] Attempted git reset; some may have failed."
echo "[INFO] Git repositories cleaned."
###########################################

echo "[INFO] Cleaning up..."
rm comfyui-venv.tar.zst

echo "[INFO] Organizing model directory..."
rm -rf /internalworkspace/ComfyUI/models
mv /internalworkspace/for-runpod-deploy/comfyui-models-folder /internalworkspace/ComfyUI/models

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

echo "[DONE] All setup tasks completed successfully."
