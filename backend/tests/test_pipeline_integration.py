"""Integration test for the full conversion pipeline using the Nature Reviews ZIP."""

import io
import zipfile
from pathlib import Path

import pytest

DATA_DIR = Path(__file__).parents[2] / "data"
NATURE_ZIP = DATA_DIR / "_Nature_Reviews_2025__FINAL_V1.zip"
IPCAI_ZIP = DATA_DIR / "_IPCAI_2026__Surgical_Workflow_Anticipation.zip"


def _zip_bytes(path: Path) -> bytes:
    return path.read_bytes()


@pytest.mark.integration
@pytest.mark.skipif(not NATURE_ZIP.exists(), reason="Nature ZIP not found")
def test_nature_pipeline_produces_docx_and_scores():
    from backend.services.pipeline import run_pipeline

    result = run_pipeline(_zip_bytes(NATURE_ZIP))

    assert result.success, f"Pipeline failed: {result.error_message}"
    assert result.docx_path, "No DOCX path in result"
    assert Path(result.docx_path).exists(), f"DOCX file missing: {result.docx_path}"
    assert Path(result.docx_path).stat().st_size > 1000, "DOCX is suspiciously small"
    assert result.reference_pdf_path and Path(result.reference_pdf_path).exists(), "Reference PDF missing"
    assert result.converted_pdf_path and Path(result.converted_pdf_path).exists(), "Converted PDF missing"


@pytest.mark.integration
@pytest.mark.skipif(not IPCAI_ZIP.exists(), reason="IPCAI ZIP not found")
def test_ipcai_pipeline_produces_docx_and_scores():
    from backend.services.pipeline import run_pipeline

    result = run_pipeline(_zip_bytes(IPCAI_ZIP))

    assert result.success, f"Pipeline failed: {result.error_message}"
    assert result.docx_path and Path(result.docx_path).exists()
    assert result.reference_pdf_path and Path(result.reference_pdf_path).exists()


@pytest.mark.integration
def test_extract_finds_main_tex(tmp_path):
    """Unit-level integration: ZIP extractor correctly finds main.tex."""
    from backend.services.extractor import extract_zip

    # Build a minimal in-memory ZIP with main.tex
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("main.tex", r"\documentclass{article}\begin{document}Hello\end{document}")
        zf.writestr("figure.png", b"\x89PNG")
    buf.seek(0)

    extract_root, main_tex = extract_zip(buf.read(), tmp_path / "job")
    assert main_tex.name == "main.tex"
    assert main_tex.exists()


@pytest.mark.integration
def test_extract_raises_on_missing_tex(tmp_path):
    from backend.services.extractor import extract_zip

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("readme.txt", "no tex files here")
    buf.seek(0)

    with pytest.raises(FileNotFoundError, match="main.tex"):
        extract_zip(buf.read(), tmp_path / "job")
