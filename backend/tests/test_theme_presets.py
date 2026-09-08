"""Tests for audited theme presets (admin swatches single source)."""

import pytest

from app.core.theme_presets import PRESETS, THEME_KEYS, resolve_theme_preset


def test_every_preset_is_a_full_14_token_light_dark_pair():
    for preset_id, modes in PRESETS.items():
        assert set(modes) == {"light", "dark"}, preset_id
        for mode, palette in modes.items():
            # palette must carry exactly the full seed key set (no missing,
            # no stray tokens that bootstrap wouldn't understand)
            assert set(palette) == set(THEME_KEYS), f"{preset_id}.{mode}"
            for token, hexv in palette.items():
                assert len(hexv) == 7 and hexv[0] == "#", f"{preset_id}.{mode}.{token}"
                int(hexv[1:], 16)  # valid hex


def test_resolve_returns_full_palette_for_known_preset():
    palette = resolve_theme_preset("dark", "ocean")
    assert set(palette) == set(THEME_KEYS)
    assert isinstance(palette["background"], str)


def test_resolve_unknown_preset_raises():
    with pytest.raises(KeyError):
        resolve_theme_preset("light", "neon")


def test_resolve_unknown_mode_raises():
    with pytest.raises(KeyError):
        resolve_theme_preset("sepia", "peach")