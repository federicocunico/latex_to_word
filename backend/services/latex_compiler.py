import logging
import shutil
import subprocess
from pathlib import Path

logger = logging.getLogger(__name__)


def compile_latex_to_pdf(main_tex: Path, output_dir: Path) -> tuple[Path, str]:
    """
    Compile LaTeX to PDF using latexmk.
    Returns (pdf_path, log). Handles non-zero exit gracefully since
    LaTeX often exits non-zero even when producing a valid PDF (warnings as errors).
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    source_dir = main_tex.parent

    cmd = [
        "latexmk",
        "-pdf",
        "-interaction=nonstopmode",
        f"-outdir={output_dir}",
        str(main_tex.name),
    ]

    logger.info("Running latexmk: %s in %s", " ".join(cmd), source_dir)
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=str(source_dir),
        timeout=300,
    )
    log = result.stdout + result.stderr
    if result.returncode != 0:
        logger.warning("latexmk exited with code %d", result.returncode)

    # Look for PDF output – may be named after the main_tex stem
    pdf_path = output_dir / f"{main_tex.stem}.pdf"
    if not pdf_path.exists():
        # Try looking in source_dir (latexmk sometimes ignores -outdir)
        fallback = source_dir / f"{main_tex.stem}.pdf"
        if fallback.exists():
            shutil.copy2(fallback, pdf_path)
        else:
            raise RuntimeError(
                f"LaTeX compilation did not produce a PDF at {pdf_path}. Log:\n{log[:2000]}"
            )

    logger.info("latexmk produced PDF at %s", pdf_path)
    return pdf_path, log
