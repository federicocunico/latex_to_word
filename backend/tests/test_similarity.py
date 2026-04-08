"""Unit tests for similarity.py – no external processes required."""

import numpy as np
import pytest

from backend.services.similarity import (
    _compute_ssim,
    _compute_text_similarity,
)


def white_page(h: int = 200, w: int = 150) -> np.ndarray:
    return np.full((h, w), 255, dtype=np.uint8)


def black_page(h: int = 200, w: int = 150) -> np.ndarray:
    return np.zeros((h, w), dtype=np.uint8)


@pytest.mark.unit
def test_ssim_identical_images_returns_one():
    page = white_page()
    score = _compute_ssim(page, page.copy())
    assert score == pytest.approx(1.0, abs=1e-3)


@pytest.mark.unit
def test_ssim_opposite_images_is_low():
    score = _compute_ssim(white_page(), black_page())
    assert score < 0.1


@pytest.mark.unit
def test_ssim_handles_size_mismatch():
    ref = white_page(200, 150)
    conv = white_page(100, 80)  # different size
    score = _compute_ssim(ref, conv)
    assert 0.0 <= score <= 1.0


@pytest.mark.unit
def test_text_similarity_identical():
    score = _compute_text_similarity("Hello world", "Hello world")
    assert score == pytest.approx(1.0)


@pytest.mark.unit
def test_text_similarity_empty_strings():
    score = _compute_text_similarity("", "")
    assert score == pytest.approx(1.0)


@pytest.mark.unit
def test_text_similarity_one_empty():
    score = _compute_text_similarity("Hello", "")
    assert score == pytest.approx(0.0)


@pytest.mark.unit
def test_text_similarity_partial():
    score = _compute_text_similarity("Hello world", "Hello earth")
    assert 0.0 < score < 1.0


@pytest.mark.unit
def test_text_similarity_completely_different():
    score = _compute_text_similarity("abc", "xyz")
    assert score == pytest.approx(0.0)
