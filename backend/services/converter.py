import logging
import subprocess
from pathlib import Path

logger = logging.getLogger(__name__)


def convert_to_docx(main_tex: Path, output_dir: Path) -> tuple[Path, str]:
    """Run pandoc to convert LaTeX file to DOCX. Returns (docx_path, log)."""
    output_dir.mkdir(parents=True, exist_ok=True)
    docx_path = output_dir / "output.docx"
    source_dir = main_tex.parent

    # Collect all subdirs that may contain images/resources
    resource_paths = _collect_resource_paths(source_dir)
    resource_path_str = ":".join(resource_paths)

    # Auto-detect bibliography files for citation processing
    bib_files = list(source_dir.rglob("*.bib"))
    bib_args = [f"--bibliography={bib}" for bib in bib_files]

    cmd = [
        "pandoc",
        str(main_tex),
        "--from=latex",
        "--to=docx",
        f"--output={docx_path}",
        f"--resource-path={resource_path_str}",
        "--standalone",
        "--citeproc",  # process \cite{} commands into formatted references
        *bib_args,
    ]

    logger.info("Running pandoc: %s", " ".join(cmd))
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        cwd=str(source_dir),
        timeout=120,
    )
    log = result.stdout + result.stderr
    if result.returncode != 0:
        logger.warning("Pandoc exited with code %d: %s", result.returncode, log)

    if not docx_path.exists():
        raise RuntimeError(f"Pandoc failed to produce DOCX. Log:\n{log}")

    logger.info("Pandoc produced DOCX at %s", docx_path)
    return docx_path, log


def _collect_resource_paths(root: Path) -> list[str]:
    """Return root plus all subdirectories that likely contain images."""
    paths = [str(root)]
    for p in root.rglob("*"):
        if p.is_dir():
            paths.append(str(p))
    return paths
