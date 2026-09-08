"""Audited theme presets — single source for admin theme swatches.

Each preset is a light/dark pair of full 14-token palettes. Colors are
hand-tuned for WCAG contrast on ink/background and accent/onAccent pairs;
admin UI only offers these presets (no arbitrary hex input).

Keys (all required per seed schema):
background, surface, ink, muted, line, accent, expense, income, warning,
heroFill, heroOn, mint, lilac, butter.
"""

THEME_KEYS = frozenset({
    "background", "surface", "ink", "muted", "line", "accent", "expense",
    "income", "warning", "heroFill", "heroOn", "mint", "lilac", "butter",
})

PRESETS: dict[str, dict[str, dict[str, str]]] = {
    # 1. Peach — warm pastel (current default look)
    "peach": {
        "light": {
            "background": "#FFF3EE", "surface": "#FFFFFF",
            "ink": "#4A3A48", "muted": "#9B8794", "line": "#F3E0D8",
            "accent": "#F3A6B8", "expense": "#E08B7C", "income": "#4EAE90",
            "warning": "#E8B86D", "heroFill": "#FFE8DC", "heroOn": "#4A3A48",
            "mint": "#9DD9C0", "lilac": "#D4C4F0", "butter": "#F6E3A1",
        },
        "dark": {
            "background": "#2A2430", "surface": "#3A3242",
            "ink": "#F7EEE8", "muted": "#C4B4BE", "line": "#4C4354",
            "accent": "#E9A0B2", "expense": "#F0A090", "income": "#7ED0B4",
            "warning": "#E8C47A", "heroFill": "#463848", "heroOn": "#F7EEE8",
            "mint": "#8FCFB6", "lilac": "#D4C4F0", "butter": "#E8D28A",
        },
    },
    # 2. Ocean — cool blues, mint accents
    "ocean": {
        "light": {
            "background": "#EFF6FB", "surface": "#FFFFFF",
            "ink": "#2F3E52", "muted": "#7E93A8", "line": "#DCEAF4",
            "accent": "#6FA8DC", "expense": "#E88B7C", "income": "#4EAE90",
            "warning": "#E8B86D", "heroFill": "#E3F0FB", "heroOn": "#2F3E52",
            "mint": "#9DD9C0", "lilac": "#C9D6F0", "butter": "#F6E3A1",
        },
        "dark": {
            "background": "#1C2532", "surface": "#2A3648",
            "ink": "#EAF2FA", "muted": "#A9BFD4", "line": "#3A4A61",
            "accent": "#7FB8E8", "expense": "#F0A090", "income": "#7ED0B4",
            "warning": "#E8C47A", "heroFill": "#26303F", "heroOn": "#EAF2FA",
            "mint": "#8FCFB6", "lilac": "#A9BCE0", "butter": "#E8D28A",
        },
    },
    # 3. Forest — sage greens, butter accents
    "forest": {
        "light": {
            "background": "#F2F7F1", "surface": "#FFFFFF",
            "ink": "#33443A", "muted": "#85968C", "line": "#DFEADF",
            "accent": "#7FBF9F", "expense": "#D98C7C", "income": "#4EAE90",
            "warning": "#E3B86D", "heroFill": "#E4F1E6", "heroOn": "#33443A",
            "mint": "#9DD9C0", "lilac": "#CED3C0", "butter": "#F2E3A1",
        },
        "dark": {
            "background": "#1E2A22", "surface": "#2C3B30",
            "ink": "#EEF6EE", "muted": "#A9B8AC", "line": "#3D4F42",
            "accent": "#8CC9A8", "expense": "#F0A090", "income": "#7ED0B4",
            "warning": "#E3C47A", "heroFill": "#27352A", "heroOn": "#EEF6EE",
            "mint": "#8FCFB6", "lilac": "#B8C4A8", "butter": "#E8D28A",
        },
    },
    # 4. Rose — dusty rose neutrals
    "rose": {
        "light": {
            "background": "#FBF3F4", "surface": "#FFFFFF",
            "ink": "#4A3540", "muted": "#A48E99", "line": "#F3E2E6",
            "accent": "#D9A0B0", "expense": "#D98B8B", "income": "#4EAE90",
            "warning": "#E8B86D", "heroFill": "#FBE9EC", "heroOn": "#4A3540",
            "mint": "#9DD9C0", "lilac": "#DCC3DD", "butter": "#F6E3A1",
        },
        "dark": {
            "background": "#2B2126", "surface": "#3B2E34",
            "ink": "#F9EFEF", "muted": "#C9B0B8", "line": "#4E3A42",
            "accent": "#E8A4B4", "expense": "#F0A090", "income": "#7ED0B4",
            "warning": "#E8C47A", "heroFill": "#473036", "heroOn": "#F9EFEF",
            "mint": "#8FCFB6", "lilac": "#D0B4D4", "butter": "#E8D28A",
        },
    },
}


def resolve_theme_preset(mode: str, preset_id: str) -> dict[str, str]:
    """Return the full token dict for a preset+mode, or raise KeyError."""
    theme = PRESETS.get(preset_id)
    if theme is None:
        raise KeyError(preset_id)
    palette = theme.get(mode)
    if palette is None:
        raise KeyError(f"{preset_id}.{mode}")
    return dict(palette)