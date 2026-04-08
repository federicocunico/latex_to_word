import logging
import shutil
import zipfile
from pathlib import Path

logger = logging.getLogger(__name__)


def extract_zip(zip_bytes: bytes, destination: Path) -> tuple[Path, Path]:
    """Extract ZIP bytes to destination dir, return (extract_root, main_tex_path)."""
    destination.mkdir(parents=True, exist_ok=True)
    zip_path = destination / "source.zip"
    zip_path.write_bytes(zip_bytes)

    with zipfile.ZipFile(zip_path, "r") as zf:
        # Security: prevent path traversal
        for member in zf.namelist():
            if member.startswith("..") or Path(member).is_absolute():
                raise ValueError(f"Unsafe ZIP entry: {member}")
        zf.extractall(destination)

    zip_path.unlink()
    main_tex = _find_main_tex(destination)
    if main_tex is None:
        raise FileNotFoundError("No main.tex found in the uploaded ZIP")

    logger.info("Extracted ZIP to %s, main.tex at %s", destination, main_tex)
    return destination, main_tex


def _find_main_tex(root: Path) -> Path | None:
    """Find main.tex: prefer a file literally named 'main.tex', else first .tex file."""
    candidates = sorted(root.rglob("main.tex"))
    if candidates:
        return candidates[0]
    # Fallback: any .tex file that is not in a hidden directory
    tex_files = [
        p for p in root.rglob("*.tex") if not any(part.startswith(".") for part in p.parts)
    ]
    if tex_files:
        logger.warning("No main.tex found, falling back to: %s", tex_files[0])
        return tex_files[0]
    return None
