import logging
from pathlib import Path

import fitz  # PyMuPDF
import numpy as np
from skimage.metrics import structural_similarity as ssim

from backend.schemas import PageScore, SimilarityReport

logger = logging.getLogger(__name__)

DPI = 150
SSIM_WEIGHT = 0.6
TEXT_WEIGHT = 0.4


def compare_pdfs(reference_pdf: Path, converted_pdf: Path) -> SimilarityReport:
    """
    Compare two PDFs page by page using SSIM (layout) + text similarity (content).
    Returns a SimilarityReport with per-page and global scores.
    """
    ref_doc = fitz.open(str(reference_pdf))
    conv_doc = fitz.open(str(converted_pdf))

    ref_count = len(ref_doc)
    conv_count = len(conv_doc)
    max_pages = max(ref_count, conv_count)

    logger.info(
        "Comparing PDFs: reference=%d pages, converted=%d pages",
        ref_count,
        conv_count,
    )

    page_scores: list[PageScore] = []

    for i in range(max_pages):
        ref_img = _render_page(ref_doc, i) if i < ref_count else None
        conv_img = _render_page(conv_doc, i) if i < conv_count else None
        ref_text = _extract_text(ref_doc, i) if i < ref_count else ""
        conv_text = _extract_text(conv_doc, i) if i < conv_count else ""

        ssim_score = _compute_ssim(ref_img, conv_img) if ref_img is not None and conv_img is not None else 0.0
        text_sim = _compute_text_similarity(ref_text, conv_text)
        combined = SSIM_WEIGHT * ssim_score + TEXT_WEIGHT * text_sim

        page_scores.append(
            PageScore(
                page_number=i + 1,
                ssim_score=round(ssim_score, 4),
                text_similarity=round(text_sim, 4),
                combined_score=round(combined, 4),
            )
        )

    overlap_pages = min(ref_count, conv_count)
    global_score = round(
        sum(p.combined_score for p in page_scores[:overlap_pages]) / overlap_pages
        if overlap_pages > 0
        else 0.0,
        4,
    )

    ref_doc.close()
    conv_doc.close()

    logger.info("Similarity comparison done. Global score: %.4f", global_score)
    return SimilarityReport(
        global_score=global_score,
        page_scores=page_scores,
        reference_page_count=ref_count,
        converted_page_count=conv_count,
    )


def _render_page(doc: fitz.Document, page_index: int) -> np.ndarray:
    """Render a PDF page to a grayscale numpy array."""
    page = doc[page_index]
    mat = fitz.Matrix(DPI / 72, DPI / 72)
    pix = page.get_pixmap(matrix=mat, colorspace=fitz.csGRAY)
    arr = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.height, pix.width)
    return arr


def _extract_text(doc: fitz.Document, page_index: int) -> str:
    page = doc[page_index]
    return page.get_text()


def _compute_ssim(ref: np.ndarray, conv: np.ndarray) -> float:
    """Compute SSIM between two grayscale page images, resizing conv to match ref."""
    if ref.shape != conv.shape:
        from PIL import Image
        conv_img = Image.fromarray(conv)
        conv_img = conv_img.resize((ref.shape[1], ref.shape[0]), Image.LANCZOS)
        conv = np.array(conv_img)

    score, _ = ssim(ref, conv, full=True)
    return float(max(0.0, score))


def _compute_text_similarity(ref_text: str, conv_text: str) -> float:
    """
    Compute text similarity using word-level Jaccard similarity.
    More robust than character SequenceMatcher for texts with different layout/formatting.
    """
    if not ref_text and not conv_text:
        return 1.0
    if not ref_text or not conv_text:
        return 0.0

    def tokenize(text: str) -> set[str]:
        # lowercase, split on whitespace/punctuation, filter short tokens
        import re
        words = re.findall(r"\b[a-z]{3,}\b", text.lower())
        return set(words)

    ref_words = tokenize(ref_text)
    conv_words = tokenize(conv_text)
    if not ref_words and not conv_words:
        return 1.0
    if not ref_words or not conv_words:
        return 0.0
    intersection = len(ref_words & conv_words)
    union = len(ref_words | conv_words)
    return intersection / union
