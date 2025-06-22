from huggingface_hub import HfApi, create_repo
import os

# Your model info
model_name = "Razvanix/music-transcription-model"
model_path = "models/saved_model"  # Path to your SavedModel folder

# Initialize API
api = HfApi()

# Create repository (if it doesn't exist)
try:
    create_repo(repo_id=model_name, repo_type="model", private=False)
    print(f"Created repository: {model_name}")
except Exception as e:
    print(f"Repository might already exist: {e}")

# Upload the entire SavedModel folder
api.upload_folder(
    folder_path=model_path,
    repo_id=model_name,
    repo_type="model"
)

print(f"Model uploaded successfully to: https://huggingface.co/{model_name}")