import logging
import shutil
import uuid
from dataclasses import dataclass
from pathlib import Path

from backend.config import settings
from backend.schemas import ConversionResult
from backend.services.converter import convert_to_docx
from backend.services.extractor import extract_zip
from backend.services.latex_compiler import compile_latex_to_pdf
from backend.services.pdf_converter import convert_docx_to_pdf

logger = logging.getLogger(__name__)


@dataclass
class PipelineProgress:
    step: str
    message: str


def run_pipeline(zip_bytes: bytes, progress_callback=None) -> ConversionResult:
    """
    Full conversion pipeline:
    1. Extract ZIP → find main.tex
    2. Convert LaTeX → DOCX (pandoc)
    3. Compile LaTeX → reference PDF (latexmk)
    4. Convert DOCX → PDF (LibreOffice) for side-by-side preview
    """
    job_id = uuid.uuid4().hex
    work_dir = settings.upload_dir / job_id
    out_dir = settings.output_dir / job_id

    def _progress(step: str, message: str) -> None:
        logger.info("[%s] %s: %s", job_id, step, message)
        if progress_callback:
            progress_callback(PipelineProgress(step=step, message=message))

    ref_pdf_dest = ""
    conv_pdf_dest = ""
    latex_log = ""
    pandoc_log = ""

    try:
        _progress("extract", "Extracting ZIP archive…")
        extract_root, main_tex = extract_zip(zip_bytes, work_dir)

        _progress("pandoc", "Converting LaTeX → DOCX with Pandoc…")
        docx_path, pandoc_log = convert_to_docx(main_tex, out_dir)

        # LaTeX compilation (optional – failure still returns DOCX)
        try:
            _progress("latex", "Compiling LaTeX → reference PDF…")
            ref_pdf_path, latex_log = compile_latex_to_pdf(main_tex, out_dir / "latex_out")
            # Copy to a stable flat path in the job dir for serving
            ref_pdf_dest_path = out_dir / "reference.pdf"
            shutil.copy2(ref_pdf_path, ref_pdf_dest_path)
            ref_pdf_dest = str(ref_pdf_dest_path)
        except Exception as exc:
            logger.warning("LaTeX compilation failed (non-fatal): %s", exc)

        # LibreOffice DOCX → PDF (optional – failure still returns DOCX + ref PDF)
        try:
            _progress("libreoffice", "Converting DOCX → PDF for preview…")
            conv_pdf_path = convert_docx_to_pdf(docx_path, out_dir / "lo_out")
            conv_pdf_dest_path = out_dir / "converted.pdf"
            shutil.copy2(conv_pdf_path, conv_pdf_dest_path)
            conv_pdf_dest = str(conv_pdf_dest_path)
        except Exception as exc:
            logger.warning("LibreOffice conversion failed (non-fatal): %s", exc)

        _progress("done", "Conversion complete.")

        return ConversionResult(
            docx_path=str(docx_path),
            reference_pdf_path=ref_pdf_dest,
            converted_pdf_path=conv_pdf_dest,
            pandoc_log=pandoc_log,
            latex_log=latex_log[:5000],  # truncate large logs
            success=True,
        )

    except Exception as exc:
        logger.exception("Pipeline failed for job %s", job_id)
        return ConversionResult(
            docx_path="",
            reference_pdf_path="",
            converted_pdf_path="",
            pandoc_log=pandoc_log,
            latex_log=latex_log,
            success=False,
            error_message=str(exc),
        )
    finally:
        # Clean up uploaded source (keep outputs)
        if work_dir.exists():
            shutil.rmtree(work_dir, ignore_errors=True)
