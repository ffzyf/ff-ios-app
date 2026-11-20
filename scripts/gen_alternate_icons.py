#!/usr/bin/env python3
"""Generate the eight theme-linked alternate App Icons for iOS 18.

Palette values are parsed directly out of ``Sources/Shared/Theme/Theme.swift``
so the icons can never drift from the in-app theme colors. Only the DARK tier
of each palette is used, and the registration name of each icon is its file
name without the ``.png`` extension (matching Info.plist's
``CFBundleAlternateIcons`` keys).

The double-F geometry and the real Gaussian cast-shadow pipeline are reused
from ``gen_app_icon.py``; no shape or shadow parameter is duplicated here.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from typing import Any, Iterable

from PIL import Image, ImageDraw, ImageFont

SCRIPTS_DIR: Path = Path(__file__).resolve().parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import gen_app_icon as base  # noqa: E402  (path bootstrap must run first)

PROJECT_ROOT: Path = base.PROJECT_ROOT
ALT_DIR: Path = PROJECT_ROOT / "Resources" / "AlternateIcons"
PREVIEW_PATH: Path = PROJECT_ROOT.parent / "FF图标-8套主题联动预览.png"
THEME_SWIFT: Path = PROJECT_ROOT / "Sources" / "Shared" / "Theme" / "Theme.swift"

# Registration order mirrors Theme.Palette.all in Theme.swift.
THEME_ORDER: tuple[str, ...] = (
    "lime", "violet", "sand", "ocean", "sakura", "aurora", "ember", "graphite",
)

# Fields of Theme.Palette consumed by the icon artwork (dark tier only).
COLOR_FIELDS: tuple[str, ...] = ("bgRaise", "bgBase", "limeDeep", "lime", "limeBright")

PALETTE_BLOCK = re.compile(r"static let (\w+) = Theme\.Palette\((.*?)\n    \)", re.S)
PALETTE_NAME = re.compile(r'name:\s*"([^"]+)"')
HEX_COLOR = re.compile(r'"(#[0-9A-Fa-f]{6})"')

FONT_CANDIDATES = (
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
)


def load_palettes() -> list[dict[str, Any]]:
    """Read the eight palettes straight from Theme.swift.

    Returns:
        Ordered list of dicts with ``id``, ``name`` and one dark hex per color
        field. Raises if a theme or a field is missing, so a rename in Swift
        fails the generator loudly instead of silently shipping a wrong icon.
    """
    source = THEME_SWIFT.read_text(encoding="utf-8")
    blocks: dict[str, str] = {}
    for match in PALETTE_BLOCK.finditer(source):
        blocks[match.group(1)] = match.group(2)

    palettes: list[dict[str, Any]] = []
    for theme_id in THEME_ORDER:
        if theme_id not in blocks:
            raise RuntimeError(f"Theme.swift missing palette block: {theme_id}")
        body = blocks[theme_id]
        id_match = re.search(rf'id:\s*"{re.escape(theme_id)}"', body)
        if id_match is None:
            raise RuntimeError(f"Theme.swift palette {theme_id} has a mismatched id field")
        name_match = PALETTE_NAME.search(body)
        if name_match is None:
            raise RuntimeError(f"Theme.swift palette {theme_id} has no display name")

        entry: dict[str, Any] = {
            "id": theme_id,
            "registration": f"icon-{theme_id}",
            "name": name_match.group(1),
        }
        for field in COLOR_FIELDS:
            # All five fields are (dark, light) pairs; the first hex is dark.
            field_match = re.search(
                rf'(?<![A-Za-z0-9]){field}\s*:\s*\(\s*"(#[0-9A-Fa-f]{{6}})"',
                body,
            )
            if field_match is None:
                raise RuntimeError(f"Theme.swift palette {theme_id} missing {field}")
            entry[field] = field_match.group(1).upper()
        palettes.append(entry)
    return palettes


def _gradient_defs(palette: dict[str, Any]) -> str:
    """Return background / back-F / front-F gradients for one palette."""
    return (
        "<defs>"
        f'<linearGradient id="bgGrad" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{palette["bgRaise"]}"/>'
        f'<stop offset="1" stop-color="{palette["bgBase"]}"/>'
        "</linearGradient>"
        f'<linearGradient id="backGrad" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{palette["limeDeep"]}"/>'
        f'<stop offset="1" stop-color="{palette["lime"]}"/>'
        "</linearGradient>"
        f'<linearGradient id="frontGrad" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{palette["lime"]}"/>'
        f'<stop offset="1" stop-color="{palette["limeBright"]}"/>'
        "</linearGradient>"
        "</defs>"
    )


def render_alternate(palette: dict[str, Any], output_path: Path) -> Image.Image:
    """Render one opaque sRGB alternate icon using the shared F/shadow pipeline."""
    defs = _gradient_defs(palette)
    rect = (
        f'<rect x="0" y="0" width="{base.VIEWBOX}" height="{base.VIEWBOX}" '
        'fill="url(#bgGrad)"/>'
    )
    back_path = (
        f'<path d="{base.F_PATH}" transform="{base.BACK_TRANSFORM}" fill="url(#backGrad)"/>'
    )
    front_path = (
        f'<path d="{base.F_PATH}" transform="{base.FRONT_TRANSFORM}" fill="url(#frontGrad)"/>'
    )

    canvas = base._render_rgba(base._svg_document(defs + rect))
    back_glyph = base._render_rgba(base._svg_document(defs + back_path))
    front_glyph = base._render_rgba(base._svg_document(defs + front_path))

    back_shadow = base.make_shadow(
        back_glyph,
        base.SHADOW_COLOR,
        base.BACK_SHADOW_OPACITY,
        base.BACK_SHADOW_DY,
        base.BACK_SHADOW_BLUR,
    )
    front_shadow = base.make_shadow(
        front_glyph,
        base.SHADOW_COLOR,
        base.FRONT_SHADOW_OPACITY,
        base.FRONT_SHADOW_DY,
        base.FRONT_SHADOW_BLUR,
    )

    canvas.alpha_composite(back_shadow)
    canvas.alpha_composite(back_glyph)
    canvas.alpha_composite(front_shadow)
    canvas.alpha_composite(front_glyph)

    image = canvas.convert("RGB")
    save_kwargs: dict[str, object] = {"format": "PNG", "optimize": True}
    profile = base._srgb_profile()
    if profile is not None:
        save_kwargs["icc_profile"] = profile
    image.save(output_path, **save_kwargs)
    return Image.open(output_path)


def _load_font(size: int) -> ImageFont.FreeTypeFont:
    """Load the first available CJK-capable font."""
    for candidate in FONT_CANDIDATES:
        if Path(candidate).is_file():
            return ImageFont.truetype(candidate, size=size)
    raise RuntimeError(f"No usable font found; tried: {', '.join(FONT_CANDIDATES)}")


def build_preview(icons: list[tuple[Path, str]]) -> None:
    """Render a 4x2 preview grid with Chinese theme names."""
    columns = 4
    pad = 40
    gap = 30
    tile = 300
    top = 96
    row_gap = 60
    rows = (len(icons) + columns - 1) // columns
    width = pad * 2 + tile * columns + gap * (columns - 1)
    height = top + rows * (tile + row_gap) + 10

    canvas = Image.new("RGB", (width, height), (12, 14, 18))
    draw = ImageDraw.Draw(canvas)
    title_font = _load_font(36)
    label_font = _load_font(28)
    draw.text(
        (width // 2, 42),
        "8 套主题 · 桌面图标联动预览",
        font=title_font,
        fill=(238, 242, 248),
        anchor="mm",
    )

    for index, (path, label) in enumerate(icons):
        row, col = divmod(index, columns)
        left = pad + col * (tile + gap)
        upper = top + row * (tile + row_gap)
        with Image.open(path) as source:
            tile_image = source.convert("RGB").resize((tile, tile), Image.Resampling.LANCZOS)
        canvas.paste(tile_image, (left, upper))
        draw.rounded_rectangle(
            (left, upper, left + tile, upper + tile),
            radius=18,
            outline=(86, 92, 102),
            width=2,
        )
        draw.text(
            (left + tile // 2, upper + tile + 26),
            label,
            font=label_font,
            fill=(224, 230, 238),
            anchor="mm",
        )

    canvas.save(PREVIEW_PATH, format="PNG", optimize=True)


def _iter_pixels(image: Image.Image) -> Iterable[Any]:
    """Iterate pixels with the current Pillow API and a legacy fallback."""
    getter = getattr(image, "get_flattened_data", None)
    if getter is None:
        getter = image.getdata
    return getter()


def _near(pixel: tuple[int, int, int], hex_color: str, tolerance: int = 3) -> bool:
    """Return whether a pixel is within tolerance of a hex color."""
    target = tuple(bytes.fromhex(hex_color.lstrip("#")))
    return all(abs(int(a) - int(b)) <= tolerance for a, b in zip(pixel, target))


def verify_assets(palettes: list[dict[str, Any]]) -> list[str]:
    """Verify all eight icons against the App Store / palette gates."""
    lines: list[str] = []
    for palette in palettes:
        path = ALT_DIR / f'{palette["registration"]}.png'
        with Image.open(path) as image:
            bands = image.getbands()
            has_alpha = "A" in bands or "transparency" in image.info
            pixels = list(_iter_pixels(image.convert("RGB")))
            found = {
                field: sum(1 for pixel in pixels if _near(pixel, palette[field]))
                for field in COLOR_FIELDS
            }
            lines.append(
                f'{path.name}: mode={image.mode}, size={image.size[0]}x{image.size[1]}, '
                f'has_alpha={has_alpha}, icc={"sRGB" if image.info.get("icc_profile") else "none"}'
            )
            lines.append(
                f'  palette dark hex { {f: palette[f] for f in COLOR_FIELDS} } '
                f'-> matching pixels {found}'
            )
            assert image.mode == "RGB", f"{path.name}: must be RGB (no alpha)"
            assert not has_alpha, f"{path.name}: alpha channel is not allowed"
            assert image.size == (base.ICON_SIZE, base.ICON_SIZE), f"{path.name}: wrong size"
            assert image.info.get("icc_profile"), f"{path.name}: missing sRGB profile"
            assert all(count > 0 for count in found.values()), f"{path.name}: palette mismatch"
    return lines


def main() -> int:
    """Generate eight alternates, their preview, and run all checks."""
    palettes = load_palettes()
    ALT_DIR.mkdir(parents=True, exist_ok=True)

    print("--- palettes parsed from Theme.swift (dark tier) ---")
    for palette in palettes:
        print(
            f'{palette["registration"]:14s} {palette["name"]:4s} '
            + " ".join(f"{field}={palette[field]}" for field in COLOR_FIELDS)
        )

    for palette in palettes:
        path = ALT_DIR / f'{palette["registration"]}.png'
        render_alternate(palette, path)
        print(f"generated {path}")

    build_preview([(ALT_DIR / f'{p["registration"]}.png', p["name"]) for p in palettes])
    print(f"generated {PREVIEW_PATH}")

    print("\n--- verification ---")
    for line in verify_assets(palettes):
        print(line)
    print("--- all checks passed ---")
    return 0


if __name__ == "__main__":
    sys.exit(main())
