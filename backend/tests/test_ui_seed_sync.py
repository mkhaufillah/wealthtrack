"""Guardrail: ui_seed.COPY_ID must stay in sync with copy_fallback.dart keys."""

from pathlib import Path
import re

from app.core.ui_seed import COPY_ID
from app.core.ui_copy_en import COPY_EN

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent

FALLBACK = Path(
    __import__("os").getenv(
        "WEALTHTRACK_FALLBACK_PATH",
        str(_REPO_ROOT / "mobile" / "lib" / "core" / "ui" / "copy_fallback.dart"),
    )
)


def _fallback_keys() -> set[str]:
    text = FALLBACK.read_text()
    return {k for k, _ in re.findall(r"'((?:\\'|[^'])*)'\s*:\s*'((?:\\'|[^'])*)'", text) if "." in k}


def test_seed_covers_fallback():
    fb = _fallback_keys()
    seed = set(COPY_ID.keys())
    assert seed == fb, f"drift: only-in-seed={sorted(seed - fb)[:10]} only-in-fallback={sorted(fb - seed)[:10]}"


def test_seed_values_match():
    text = FALLBACK.read_text()
    fb = {k: v.replace("\\'", "'") for k, v in re.findall(r"'((?:\\'|[^'])*)'\s*:\s*'((?:\\'|[^'])*)'", text) if "." in k}
    for k, v in COPY_ID.items():
        assert fb.get(k) == v, f"{k}: seed={v!r} fallback={fb.get(k)!r}"


def test_en_keys_match_id():
    assert set(COPY_EN.keys()) == set(COPY_ID.keys())
