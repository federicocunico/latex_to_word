import logging
import subprocess
from pathlib import Path

logger = logging.getLogger(__name__)


def convert_docx_to_pdf(docx_path: Path, output_dir: Path) -> Path:
    """Convert DOCX to PDF using LibreOffice headless. Returns pdf_path."""
    output_dir.mkdir(parents=True, exist_ok=True)

    cmd = [
        "libreoffice",
        "--headless",
        "--norestore",
        "--convert-to", "pdf",
        "--outdir", str(output_dir),
        str(docx_path),
    ]

    logger.info("Running LibreOffice conversion: %s", " ".join(cmd))
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=180,
    )
    log = result.stdout + result.stderr
    if result.returncode != 0:
        raise RuntimeError(f"LibreOffice conversion failed (code {result.returncode}): {log}")

    pdf_path = output_dir / f"{docx_path.stem}.pdf"
    if not pdf_path.exists():
        raise RuntimeError(
            f"LibreOffice did not produce PDF at {pdf_path}. Log:\n{log}"
        )

    logger.info("LibreOffice produced PDF at %s", pdf_path)
    return pdf_path
