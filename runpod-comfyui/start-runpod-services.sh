#!/bin/bash

set -e
set -o pipefail

echo "[INFO] Updating and installing required packages..."
apt update -y && \
DEBIAN_FRONTEND=noninteractive apt install -y openssh-server nginx python3 python3-pip bsdutils

echo "[INFO] Upgrading pip and installing JupyterLab..."
pip install --upgrade pip
pip install jupyterlab

# Setup SSH if PUBLIC_KEY is set
if [[ $PUBLIC_KEY ]]; then
    echo "[INFO] Setting up SSH..."
    mkdir -p ~/.ssh
    echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
    chmod 700 -R ~/.ssh

    for key_type in rsa dsa ecdsa ed25519; do
        key_path="/etc/ssh/ssh_host_${key_type}_key"
        if [ ! -f "$key_path" ]; then
            ssh-keygen -t $key_type -f $key_path -q -N ""
            echo "$key_type key fingerprint:"
            ssh-keygen -lf "${key_path}.pub"
        fi
    done

    service ssh start
fi

echo "[INFO] Exporting environment variables to /etc/rp_environment..."
printenv | grep -E "^RUNPOD_|^PATH=|^_=" | awk -F = '{ print "export " $1 "=\"" $2 "\"" }' >> /etc/rp_environment
echo "source /etc/rp_environment" >> ~/.bashrc

echo "[INFO] Starting Nginx..."
service nginx start

# Jupyter
echo "[INFO] Starting JupyterLab..."
mkdir -p /workspace

# Create a file to store the Jupyter token for RunPod
JUPYTER_TOKEN_FILE="/tmp/jupyter_token.txt"

# Build the base Jupyter command
JUPYTER_CMD="jupyter lab --allow-root --no-browser --port=8888 --ip=* \
    --FileContentsManager.delete_to_trash=False \
    --ServerApp.terminado_settings='{\"shell_command\":[\"/bin/bash\"]}' \
    --ServerApp.allow_origin=* \
    --ServerApp.preferred_dir=/workspace"

# Add token if provided, otherwise use auto-generated and extract it
if [[ $JUPYTER_PASSWORD ]]; then
    echo "[INFO] Using custom Jupyter token."
    JUPYTER_CMD="$JUPYTER_CMD --ServerApp.token=$JUPYTER_PASSWORD"
    echo "$JUPYTER_PASSWORD" > "$JUPYTER_TOKEN_FILE"
else
    echo "[INFO] No Jupyter token provided. Using auto-generated token."
    # Start Jupyter in the background and capture output
    jupyter lab --allow-root --no-browser --port=8888 --ip=* \
        --FileContentsManager.delete_to_trash=False \
        --ServerApp.terminado_settings='{\"shell_command\":[\"/bin/bash\"]}' \
        --ServerApp.allow_origin=* \
        --ServerApp.preferred_dir=/workspace > /jupyter.log 2>&1 &
    
    # Wait for Jupyter to start and extract the token
    sleep 5
    TOKEN=$(grep -oP "(?<=token=)[a-zA-Z0-9]+" /jupyter.log | head -1)
    
    if [[ -n "$TOKEN" ]]; then
        echo "[INFO] Auto-generated Jupyter token: $TOKEN"
        echo "$TOKEN" > "$JUPYTER_TOKEN_FILE"
        
        # Create a file that RunPod UI can use to add the token to URLs
        echo "{\"jupyterToken\": \"$TOKEN\"}" > /runpod-jupyter-token.json
        
        # No need to start Jupyter again as we already started it above
        exit 0
    else
        echo "[WARNING] Could not extract auto-generated token. Starting Jupyter without token extraction."
    fi
fi

# Only execute this if we're using a custom token or couldn't extract the auto-generated one
nohup bash -c "$JUPYTER_CMD" &> /jupyter.log &

# If we have a custom token, also save it for RunPod UI
if [[ $JUPYTER_PASSWORD ]]; then
    echo "{\"jupyterToken\": \"$JUPYTER_PASSWORD\"}" > /runpod-jupyter-token.json
fi
