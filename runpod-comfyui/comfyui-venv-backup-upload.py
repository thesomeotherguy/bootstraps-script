from huggingface_hub import HfApi
import os

# Get token from environment variable
token = os.environ.get("HUGGINGFACE_TOKEN")

# Initialize API with token
api = HfApi(token=token)

# Upload file
api.upload_file(
    path_or_fileobj="comfyui-venv.tar.zst",
    path_in_repo="comfyui-venv.tar.zst",
    repo_id="thesomeotherguy/for-runpod-deploy",
    repo_type="model",
)
