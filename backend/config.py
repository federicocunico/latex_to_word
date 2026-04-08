from pathlib import Path

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    upload_dir: Path = Path("/app/uploads")
    output_dir: Path = Path("/app/output")
    max_upload_size_mb: int = 200

    model_config = {"env_file": ".env"}


settings = Settings()

# Ensure directories exist at import time
settings.upload_dir.mkdir(parents=True, exist_ok=True)
settings.output_dir.mkdir(parents=True, exist_ok=True)
