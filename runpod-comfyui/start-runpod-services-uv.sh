#!/bin/bash

apt update && \
DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends openssh-server nginx python3 wget ca-certificates && \
wget -qO- https://astral.sh/uv/install.sh | sh && \
source $HOME/.local/bin/env && \
VENV_DIR="/opt/jupyter_venv" && \
uv python install 3.12 && \
uv venv --python 3.12 $VENV_DIR && \
uv pip install --python $VENV_DIR/bin/python jupyterlab && \
if [[ -n "$PUBLIC_KEY" ]]; then \
    mkdir -p ~/.ssh && chmod 700 ~/.ssh && \
    echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && \
    ssh-keygen -A && \
    sed -i \
        -e "s/#PasswordAuthentication yes/PasswordAuthentication no/g" \
        -e "s/PasswordAuthentication yes/PasswordAuthentication no/g" \
        -e "s/#PubkeyAuthentication yes/PubkeyAuthentication yes/g" \
        /etc/ssh/sshd_config && \
    echo "UseDNS no" >> /etc/ssh/sshd_config && \
    service ssh start; \
fi && \
printenv | grep -E "^RUNPOD_|^PATH=|^_=" | awk -F= "{print \"export \"\$1\"=\\\"\"\$2\"\\\"\"}" >> /etc/rp_environment && \
echo "source /etc/rp_environment" >> ~/.bashrc && \
service nginx start && \
mkdir -p /workspace && \
if [[ -n "$JUPYTER_PASSWORD" ]]; then \
    nohup $VENV_DIR/bin/jupyter lab \
        --allow-root --no-browser --port=8888 --ip=0.0.0.0 \
        --FileContentsManager.delete_to_trash=False \
        --ServerApp.terminado_settings="{\"shell_command\":[\"/bin/bash\"]}" \
        --ServerApp.allow_origin=* --ServerApp.preferred_dir=/workspace \
        --ServerApp.token="$JUPYTER_PASSWORD" &> /jupyter.log & \
else \
    nohup $VENV_DIR/bin/jupyter lab \
        --allow-root --no-browser --port=8888 --ip=0.0.0.0 \
        --FileContentsManager.delete_to_trash=False \
        --ServerApp.terminado_settings="{\"shell_command\":[\"/bin/bash\"]}" \
        --ServerApp.allow_origin=* --ServerApp.preferred_dir=/workspace & \
fi && \
sleep infinity
