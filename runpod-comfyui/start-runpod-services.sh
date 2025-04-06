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

# Choose how to start Jupyter based on whether a password is provided
if [[ $JUPYTER_PASSWORD ]]; then
    echo "[INFO] Using custom Jupyter token."
    echo "============================================="
    echo "JUPYTER TOKEN: $JUPYTER_PASSWORD"
    echo "Access Jupyter at: http://localhost:8888/?token=$JUPYTER_PASSWORD"
    echo "============================================="
    
    # Start Jupyter with the custom token
    nohup jupyter lab --allow-root --no-browser --port=8888 --ip=* \
        --FileContentsManager.delete_to_trash=False \
        --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' \
        --ServerApp.allow_origin=* \
        --ServerApp.preferred_dir=/workspace \
        --ServerApp.token=$JUPYTER_PASSWORD > /jupyter.log 2>&1 &
    
    # Save token in format RunPod expects
    echo "{\"jupyter\": \"http://localhost:8888/?token=$JUPYTER_PASSWORD\"}" > /etc/runpod-jupyter.json
    
    # Keep the container running by tailing the log
    tail -f /jupyter.log
else
    echo "[INFO] No Jupyter token provided. Using auto-generated token."
    
    # Start Jupyter and capture output
    jupyter lab --allow-root --no-browser --port=8888 --ip=* \
        --FileContentsManager.delete_to_trash=False \
        --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' \
        --ServerApp.allow_origin=* \
        --ServerApp.preferred_dir=/workspace > /jupyter.log 2>&1 &

    # Wait for Jupyter to start fully
    sleep 5

    # Extract the token from the log file
    TOKEN=$(grep -oP "(?<=token=)[a-zA-Z0-9]+" /jupyter.log | head -1)

    if [[ -n "$TOKEN" ]]; then
        echo "============================================="
        echo "JUPYTER TOKEN: $TOKEN"
        echo "Access Jupyter at: http://localhost:8888/?token=$TOKEN"
        echo "============================================="
        
        # Save token in RunPod's expected format and location
        echo "{\"jupyter\": \"http://localhost:8888/?token=$TOKEN\"}" > /etc/runpod-jupyter.json
    else
        echo "[WARNING] Could not extract auto-generated token."
    fi

    # Keep the container running
    tail -f /jupyter.log
fi
