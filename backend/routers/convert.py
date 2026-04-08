import logging
import mimetypes
from pathlib import Path

from fastapi import APIRouter, HTTPException, UploadFile
from fastapi.responses import FileResponse

from backend.config import settings
from backend.services.pipeline import run_pipeline

router = APIRouter()
logger = logging.getLogger(__name__)

MAX_UPLOAD_BYTES = settings.max_upload_size_mb * 1024 * 1024


def _resolve_output_file(job_id: str, filename: str) -> Path:
    """Validate job/file path parts and return a safe output file path."""
    if ".." in job_id or ".." in filename or "/" in job_id or "/" in filename:
        raise HTTPException(status_code=400, detail="Invalid path.")

    file_path = settings.output_dir / job_id / filename
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="File not found.")
    return file_path


@router.post("/convert")
async def convert(file: UploadFile) -> dict:
    """Accept a .zip file, run the full conversion pipeline, return results."""
    if not file.filename or not file.filename.lower().endswith(".zip"):
        raise HTTPException(status_code=400, detail="Only .zip files are accepted.")

    zip_bytes = await file.read()
    if len(zip_bytes) > MAX_UPLOAD_BYTES:
        raise HTTPException(
            status_code=413,
            detail=f"File too large. Maximum size is {settings.max_upload_size_mb} MB.",
        )

    result = run_pipeline(zip_bytes)

    if not result.success:
        raise HTTPException(status_code=422, detail=result.error_message)

    job_id = Path(result.docx_path).parent.name

    def _pdf_url(path: str) -> str | None:
        if not path:
            return None
        return f"/api/preview/{job_id}/{Path(path).name}"

    return {
        "success": True,
        "docx_download_url": f"/api/download/{job_id}/output.docx",
        "reference_pdf_url": _pdf_url(result.reference_pdf_path),
        "converted_pdf_url": _pdf_url(result.converted_pdf_path),
        "pandoc_log": result.pandoc_log,
        "latex_log": result.latex_log,
    }


@router.get("/download/{job_id}/{filename}")
def download_file(job_id: str, filename: str) -> FileResponse:
    """Serve a generated output file (DOCX or PDF)."""
    file_path = _resolve_output_file(job_id, filename)

    media_type, _ = mimetypes.guess_type(filename)
    return FileResponse(
        path=str(file_path),
        filename=filename,
        media_type=media_type or "application/octet-stream",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get("/preview/{job_id}/{filename}")
def preview_file(job_id: str, filename: str) -> FileResponse:
    """Serve a generated PDF inline for browser preview/iframe usage."""
    file_path = _resolve_output_file(job_id, filename)
    media_type, _ = mimetypes.guess_type(filename)
    if media_type != "application/pdf":
        raise HTTPException(status_code=400, detail="Only PDF files can be previewed.")

    return FileResponse(
        path=str(file_path),
        media_type="application/pdf",
        headers={"Content-Disposition": "inline"},
    )
