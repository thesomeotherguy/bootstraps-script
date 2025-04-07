#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "[INFO] Starting ComfyUI backup process..."

# Navigate to the correct base directory
cd /workspace || { echo "[ERROR] Failed to change directory to /workspace"; exit 1; }

echo "[INFO] Creating backup archive 'workspace.tar.zst'..."
echo "[INFO] Include only: input, output, workflows"

# Create the compressed tar archive
tar \
  --no-same-owner \
  -I 'zstd -T0' \
  -cf workspace.tar.zst \
  input \
  output \
  workflows

# Check if tar command was successful (though set -e should handle this)
if [ $? -eq 0 ]; then
  echo "[INFO] Backup archive 'workspace.tar.zst' created successfully in /workspace."
  # Optional: List file size
  ls -lh workspace.tar.zst
else
  echo "[ERROR] Failed to create backup archive."
  exit 1
fi

echo "[INFO] Backup process complete."
