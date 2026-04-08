import logging
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from backend.config import settings
from backend.routers import convert

logging.basicConfig(level=logging.INFO)

app = FastAPI(title="LaTeX to Word Converter", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(convert.router, prefix="/api")

# Serve generated output files
if settings.output_dir.exists():
    app.mount("/files", StaticFiles(directory=str(settings.output_dir)), name="files")


@app.get("/api/health")
def health() -> dict:
    return {"status": "ok"}
