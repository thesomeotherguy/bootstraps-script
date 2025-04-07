#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "[INFO] Starting ComfyUI backup process..."

# Navigate to the correct base directory
cd /internalworkspace || { echo "[ERROR] Failed to change directory to /internalworkspace"; exit 1; }

echo "[INFO] Creating backup archive 'comfyui-venv.tar.zst'..."
echo "[INFO] Including: ComfyUI, .venv"
echo "[INFO] Excluding: ComfyUI/input, ComfyUI/output, ComfyUI/user/default/workflows, ComfyUI/models (except ComfyUI/models/config)"

# Create the compressed tar archive
# Exclude specified directories within ComfyUI.
# Explicitly include ComfyUI/models/config even though ComfyUI/models is excluded during traversal.
tar \
  --exclude='ComfyUI/input' \
  --exclude='ComfyUI/output' \
  --exclude='ComfyUI/user/default/workflows' \
  --exclude='ComfyUI/models' \
  --no-same-owner \
  -I 'zstd -T0' \
  -cf comfyui-venv.tar.zst \
  ComfyUI \
  .venv \
  ComfyUI/models/config # <-- Explicitly add this directory here

# Check if tar command was successful
if [ $? -eq 0 ]; then
  echo "[INFO] Backup archive 'comfyui-venv.tar.zst' created successfully in /internalworkspace."
  # Optional: List file size
  ls -lh comfyui-venv.tar.zst
else
  echo "[ERROR] Failed to create backup archive."
  exit 1
fi

echo "[INFO] Backup process complete."
