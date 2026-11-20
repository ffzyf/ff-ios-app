#!/usr/bin/env python3
"""Generate the iOS 18 adaptive AppIcon set for the floating-double-F mark.

The script renders three 1024x1024 variants from one confirmed geometry:

* ``icon-1024.png``       - default/light: light silver-gray back F and pure
                            white front F on an opaque neutral dark background.
* ``icon-1024-dark.png``  - dark: same two-tone lettering on a transparent
                            background (RGBA); the system dark backdrop shows
                            through and the shadow stays alpha-based.
* ``icon-1024-tinted.png`` - tinted: grayscale-encoded back (201) and front
                            (255) lettering on a neutral dark gray background
                            (RGB, R=G=B pixel by pixel), so the system can tint
                            it while preserving the two-layer luminance gap.

The back F is a neutral light silver rather than pure white: the separation
between the two floating letters comes from a luminance step plus a soft,
genuinely Gaussian cast shadow instead of from color.

Rendering note
--------------
CairoSVG 2.8.2 has no ``feGaussianBlur`` implementation (only ``feOffset``,
``feBlend`` and ``feFlood``), so SVG filter chains are silently ignored. The
shadows are therefore built in Pillow from each glyph's antialiased alpha
mask with ``ImageFilter.GaussianBlur``, then alpha-composited between the
layers. This produces the real soft falloff that an ``feDropShadow`` would.
The two F layers keep the exact confirmed path and transforms, and all layer
colors / backgrounds remain unchanged.
"""

from __future__ import annotations

import io
import sys
from pathlib import Path
from typing import Any, Iterable

import cairosvg
from PIL import Image, ImageCms, ImageDraw, ImageFilter, ImageFont, ImageOps

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
PROJECT_ROOT: Path = Path(__file__).resolve().parent.parent
ICONSET_DIR: Path = PROJECT_ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
CONTENTS_JSON: Path = ICONSET_DIR / "Contents.json"
PREVIEW_PATH: Path = PROJECT_ROOT.parent / "FF图标-App落地预览.png"
ZOOM_PATH: Path = PROJECT_ROOT.parent / "FF图标-层次放大.png"

LIGHT_ICON: Path = ICONSET_DIR / "icon-1024.png"
DARK_ICON: Path = ICONSET_DIR / "icon-1024-dark.png"
TINTED_ICON: Path = ICONSET_DIR / "icon-1024-tinted.png"

# ---------------------------------------------------------------------------
# Confirmed artwork geometry - DO NOT CHANGE
# ---------------------------------------------------------------------------
ICON_SIZE: int = 1024
VIEWBOX: int = 512
LAYER_SCALE: float = ICON_SIZE / VIEWBOX

F_PATH: str = "M30 18 H78 V34 H48 V48 H70 V64 H48 V88 H30 Z"
BACK_X: int = 74
BACK_Y: int = 71
BACK_SCALE: float = 2.9
FRONT_X: int = 150
FRONT_Y: int = 142
FRONT_SCALE: float = 2.6

BACK_TRANSFORM: str = f"translate({BACK_X},{BACK_Y}) scale({BACK_SCALE})"
FRONT_TRANSFORM: str = f"translate({FRONT_X},{FRONT_Y}) scale({FRONT_SCALE})"

# Shadow parameters (viewBox units for offsets/blur, ratios for opacity).
# The blur radii are converted to output pixels by LAYER_SCALE.
BACK_SHADOW_DY: int = 5
FRONT_SHADOW_DY: int = 11
BACK_SHADOW_BLUR: float = 9.0
FRONT_SHADOW_BLUR: float = 13.0
BACK_SHADOW_OPACITY: float = 0.50
FRONT_SHADOW_OPACITY: float = 0.44

# Neutral palette - no theme color, no hue cast.
LIGHT_BG_TOP: str = "#16191E"
LIGHT_BG_BOTTOM: str = "#0B0D10"
TINTED_BG_TOP: str = "#1C1C1C"
TINTED_BG_BOTTOM: str = "#0A0A0A"

# Luminance gap between the two floating letters.
BACK_GLYPH_SILVER: str = "#C6CCD4"      # ~203 luma: "light silver", still reads white
FRONT_GLYPH_WHITE: str = "#FFFFFF"      # 255 luma: pure white, front and brightest
TINTED_BACK_GRAY: str = "#C9C9C9"       # exactly 201, explicit neutral gray
TINTED_FRONT_GRAY: str = "#FFFFFF"      # exactly 255
SHADOW_COLOR: str = "#3A3A3A"           # light/dark: neutral gray, alpha carries depth
TINTED_SHADOW_COLOR: str = "#3A3A3A"    # neutral mid-dark gray, R=G=B

# Sample points that land on one layer only (output pixel coordinates).
SAMPLE_BACK: tuple[int, int] = (370, 600)
SAMPLE_FRONT: tuple[int, int] = (500, 680)

ZOOM_BOX: tuple[int, int, int, int] = (300, 260, 720, 700)
ZOOM_FACTOR: int = 3

# Exact Contents.json requested by the design.
CONTENTS_JSON_TEXT: str = """{
  "images": [
    { "filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" },
    { "appearances": [ { "appearance": "luminosity", "value": "dark" } ], "filename": "icon-1024-dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" },
    { "appearances": [ { "appearance": "luminosity", "value": "tinted" } ], "filename": "icon-1024-tinted.png", "idiom": "universal", "platform": "ios", "size": "1024x1024" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
"""

FONT_CANDIDATES_BOLD: tuple[str, ...] = (
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
    "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
)
FONT_CANDIDATES_REGULAR: tuple[str, ...] = (
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
)


def _svg_document(body: str) -> str:
    """Wrap SVG body in a fixed 1024-output / 512-viewBox document."""
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{ICON_SIZE}" '
        f'height="{ICON_SIZE}" viewBox="0 0 {VIEWBOX} {VIEWBOX}">{body}</svg>'
    )


def build_background_svg(variant: str) -> str:
    """Return the SVG for the background layer of one variant."""
    if variant == "dark":
        # Empty document: every pixel outside the artwork stays alpha=0.
        return _svg_document("")
    if variant == "light":
        top, bottom, gradient_id = LIGHT_BG_TOP, LIGHT_BG_BOTTOM, "bgLight"
    elif variant == "tinted":
        top, bottom, gradient_id = TINTED_BG_TOP, TINTED_BG_BOTTOM, "bgTinted"
    else:
        raise ValueError(f"Unknown icon variant: {variant!r}")
    body = (
        f'<defs><linearGradient id="{gradient_id}" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{top}"/>'
        f'<stop offset="1" stop-color="{bottom}"/>'
        "</linearGradient></defs>"
        f'<rect x="0" y="0" width="{VIEWBOX}" height="{VIEWBOX}" fill="url(#{gradient_id})"/>'
    )
    return _svg_document(body)


def build_glyph_svg(fill: str, transform: str) -> str:
    """Return the SVG for one F glyph, preserving the confirmed path/transform."""
    return _svg_document(f'<path d="{F_PATH}" transform="{transform}" fill="{fill}"/>')


def _render_rgba(svg: str) -> Image.Image:
    """Render an SVG document to an RGBA image of ICON_SIZE."""
    png_bytes = cairosvg.svg2png(
        bytestring=svg.encode("utf-8"),
        output_width=ICON_SIZE,
        output_height=ICON_SIZE,
    )
    return Image.open(io.BytesIO(png_bytes)).convert("RGBA")


def _hex_rgb(color: str) -> tuple[int, int, int]:
    """Convert a ``#RRGGBB`` string into an RGB tuple."""
    return tuple(bytes.fromhex(color.lstrip("#")))  # type: ignore[return-value]


def make_shadow(
    glyph: Image.Image,
    color: str,
    opacity: float,
    dy_viewbox: int,
    blur_viewbox: float,
) -> Image.Image:
    """Build a real Gaussian cast shadow from a glyph's antialiased alpha mask.

    The blur is intentionally performed in Pillow: CairoSVG 2.8.2 ignores
    ``feGaussianBlur``, which previously produced a hard offset copy.
    """
    radius = max(1, int(round(blur_viewbox * LAYER_SCALE)))
    blurred = glyph.getchannel("A").filter(ImageFilter.GaussianBlur(radius=radius))
    attenuated = blurred.point(lambda value: int(round(value * opacity)))

    shifted = Image.new("L", (ICON_SIZE, ICON_SIZE), 0)
    offset_px = int(round(dy_viewbox * LAYER_SCALE))
    if offset_px > 0:
        shifted.paste(attenuated.crop((0, 0, ICON_SIZE, ICON_SIZE - offset_px)), (0, offset_px))
    else:
        shifted.paste(attenuated, (0, 0))

    shadow = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), _hex_rgb(color) + (0,))
    shadow.putalpha(shifted)
    return shadow


def _srgb_profile() -> bytes | None:
    """Return an embedded sRGB ICC profile, or None if LittleCMS is unavailable."""
    try:
        return ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    except Exception:  # pragma: no cover - depends on the local Pillow build
        return None


def render_variant(variant: str, output_path: Path) -> Image.Image:
    """Render, composite and save one complete variant."""
    if variant == "tinted":
        back_fill, front_fill = TINTED_BACK_GRAY, TINTED_FRONT_GRAY
        shadow_color = TINTED_SHADOW_COLOR
    elif variant in ("light", "dark"):
        back_fill, front_fill = BACK_GLYPH_SILVER, FRONT_GLYPH_WHITE
        shadow_color = SHADOW_COLOR
    else:
        raise ValueError(f"Unknown icon variant: {variant!r}")

    canvas = _render_rgba(build_background_svg(variant))
    back_glyph = _render_rgba(build_glyph_svg(back_fill, BACK_TRANSFORM))
    front_glyph = _render_rgba(build_glyph_svg(front_fill, FRONT_TRANSFORM))

    back_shadow = make_shadow(
        back_glyph, shadow_color, BACK_SHADOW_OPACITY, BACK_SHADOW_DY, BACK_SHADOW_BLUR
    )
    front_shadow = make_shadow(
        front_glyph, shadow_color, FRONT_SHADOW_OPACITY, FRONT_SHADOW_DY, FRONT_SHADOW_BLUR
    )

    # Paint order: back shadow, back glyph, front shadow, front glyph.
    canvas.alpha_composite(back_shadow)
    canvas.alpha_composite(back_glyph)
    canvas.alpha_composite(front_shadow)
    canvas.alpha_composite(front_glyph)

    if variant == "dark":
        image = canvas
    else:
        image = canvas.convert("RGB")
        if variant == "tinted":
            # Guarantees R == G == B for every pixel after compositing.
            image = ImageOps.grayscale(image).convert("RGB")

    save_kwargs: dict[str, object] = {"format": "PNG", "optimize": True}
    profile = _srgb_profile()
    if profile is not None:
        save_kwargs["icc_profile"] = profile
    image.save(output_path, **save_kwargs)
    return Image.open(output_path)


def _iter_pixels(image: Image.Image) -> Iterable[Any]:
    """Iterate pixels with the current Pillow API and a legacy fallback."""
    getter = getattr(image, "get_flattened_data", None)
    if getter is None:
        getter = image.getdata
    return getter()


def _load_font(candidates: tuple[str, ...], size: int) -> ImageFont.FreeTypeFont:
    """Load the first available font from an ordered candidate list."""
    for candidate in candidates:
        if Path(candidate).is_file():
            return ImageFont.truetype(candidate, size=size)
    raise RuntimeError(f"No usable font found; tried: {', '.join(candidates)}")


def _luma(pixel: tuple[int, ...]) -> int:
    """Return the Rec.601 luma of an RGB or RGBA sample."""
    red, green, blue = pixel[:3]
    return int(round(0.299 * red + 0.587 * green + 0.114 * blue))


def count_tone_bands(image: Image.Image) -> dict[str, int]:
    """Count near-black and midtone pixels used to verify a soft shadow."""
    rgb = image.convert("RGB")
    luma_values = (_luma(pixel) for pixel in _iter_pixels(rgb))
    counts = {"near_black": 0, "mid_26_100": 0, "mid_26_150": 0}
    for value in luma_values:
        if value <= 8:
            counts["near_black"] += 1
        if 26 <= value <= 100:
            counts["mid_26_100"] += 1
        if 26 <= value <= 150:
            counts["mid_26_150"] += 1
    return counts


def build_preview(icons: list[tuple[Path, str]]) -> None:
    """Render a three-column preview with Chinese labels to ``PREVIEW_PATH``."""
    pad: int = 56
    gap: int = 56
    icon_display: int = 440
    top: int = 132
    canvas_width: int = pad * 2 + icon_display * 3 + gap * 2
    canvas_height: int = 706

    canvas = Image.new("RGB", (canvas_width, canvas_height), (16, 18, 22))
    draw = ImageDraw.Draw(canvas)

    title_font = _load_font(FONT_CANDIDATES_BOLD, 42)
    label_font = _load_font(FONT_CANDIDATES_REGULAR, 33)
    draw.text(
        (canvas_width // 2, 54),
        "FF 悬浮双字母 · iOS 18 AppIcon 三态落地预览",
        font=title_font,
        fill=(242, 244, 247),
        anchor="mm",
    )

    checker_light = (58, 58, 58)
    checker_dark = (38, 38, 38)
    checker_step = 22
    label_y = top + icon_display + 44

    for index, (path, label) in enumerate(icons):
        left = pad + index * (icon_display + gap)
        box = (left, top, left + icon_display, top + icon_display)

        if "dark" in path.name:
            # Reveal the real transparency of the dark variant with a checkerboard.
            for row in range(top, top + icon_display, checker_step):
                for col in range(left, left + icon_display, checker_step):
                    color = checker_light if ((row - top) // checker_step + (col - left) // checker_step) % 2 == 0 else checker_dark
                    draw.rectangle(
                        (col, row, min(col + checker_step, box[2]), min(row + checker_step, box[3])),
                        fill=color,
                    )
            dark_icon = Image.open(path).convert("RGBA")
            dark_icon = dark_icon.resize((icon_display, icon_display), Image.Resampling.LANCZOS)
            canvas.paste(dark_icon, (left, top), dark_icon)
        else:
            icon = Image.open(path).convert("RGB")
            icon = icon.resize((icon_display, icon_display), Image.Resampling.LANCZOS)
            canvas.paste(icon, (left, top))

        draw.rounded_rectangle(box, radius=22, outline=(92, 96, 104), width=2)
        draw.text(
            (left + icon_display // 2, label_y),
            label,
            font=label_font,
            fill=(226, 230, 236),
            anchor="mm",
        )

    canvas.save(PREVIEW_PATH, format="PNG", optimize=True)


def build_zoom(icon_path: Path) -> None:
    """Save a 3x magnified crop of the default icon's overlapping F letters."""
    with Image.open(icon_path) as source:
        region = source.convert("RGB").crop(ZOOM_BOX)
    zoom = region.resize(
        (region.width * ZOOM_FACTOR, region.height * ZOOM_FACTOR),
        Image.Resampling.LANCZOS,
    )
    zoom.save(ZOOM_PATH, format="PNG", optimize=True)


def verify_assets() -> list[str]:
    """Verify every output file against the quality gates and return a report."""
    lines: list[str] = []
    expected = {
        LIGHT_ICON: "RGB",
        DARK_ICON: "RGBA",
        TINTED_ICON: "RGB",
    }

    for path, expected_mode in expected.items():
        with Image.open(path) as image:
            mode = image.mode
            size = image.size
            has_alpha = "A" in image.getbands() or "transparency" in image.info
            icc = image.info.get("icc_profile")
            lines.append(
                f"{path.name}: mode={mode}, size={size[0]}x{size[1]}, "
                f"has_alpha={has_alpha}, icc={'sRGB' if icc else 'none'}"
            )
            assert mode == expected_mode, f"{path.name}: expected {expected_mode}, got {mode}"
            assert size == (ICON_SIZE, ICON_SIZE), f"{path.name}: wrong size {size}"
            assert has_alpha == (expected_mode == "RGBA"), f"{path.name}: unexpected alpha state"

            back_pixel = image.getpixel(SAMPLE_BACK)
            front_pixel = image.getpixel(SAMPLE_FRONT)
            back_luma = _luma(back_pixel)
            front_luma = _luma(front_pixel)
            lines.append(
                f"  layer samples: back={back_pixel} (luma={back_luma}), "
                f"front={front_pixel} (luma={front_luma}), gap={front_luma - back_luma}"
            )
            assert front_luma - back_luma >= 35, f"{path.name}: layer luminance gap too small"

            if path == LIGHT_ICON:
                bands = count_tone_bands(image)
                lines.append(
                    f"  shadow tones: near_black(<=8)={bands['near_black']}, "
                    f"mid(26-100)={bands['mid_26_100']}, mid(26-150)={bands['mid_26_150']}"
                )
                assert bands["near_black"] < 1000, "shadow still has a near-black plateau"
                assert bands["mid_26_150"] > 3000, "shadow lacks soft midtone gradient"

            if path == DARK_ICON:
                corners = [image.getpixel(p)[3] for p in ((0, 0), (1023, 0), (0, 1023), (1023, 1023))]
                opaque_count = sum(1 for a in _iter_pixels(image.getchannel("A")) if a > 0)
                lines.append(
                    f"  dark background: corner_alphas={corners}, nontransparent_pixels={opaque_count}"
                )
                assert all(a == 0 for a in corners), "dark variant has a non-transparent corner"
                assert opaque_count > 0, "dark variant has no glyph pixels"
                assert back_pixel[3] == 255 and front_pixel[3] == 255, "glyph layers must be opaque"

            if path == TINTED_ICON:
                mismatches = sum(1 for r, g, b in _iter_pixels(image) if r != g or r != b)
                lines.append(
                    f"  tinted RGB equality: mismatched_pixels={mismatches}, "
                    f"back_gray={back_pixel[0]}, front_gray={front_pixel[0]}"
                )
                assert mismatches == 0, f"tinted variant has {mismatches} non-gray pixels"
                assert back_pixel[0] == 201 and front_pixel[0] == 255, "tinted gray levels wrong"

    payload = CONTENTS_JSON.read_text(encoding="utf-8")
    assert payload == CONTENTS_JSON_TEXT, "Contents.json does not match the requested structure"
    lines.append("Contents.json: exact requested three-appearance structure confirmed")

    with Image.open(ZOOM_PATH) as zoom:
        expected_zoom = (
            (ZOOM_BOX[2] - ZOOM_BOX[0]) * ZOOM_FACTOR,
            (ZOOM_BOX[3] - ZOOM_BOX[1]) * ZOOM_FACTOR,
        )
        lines.append(f"zoom crop: size={zoom.size[0]}x{zoom.size[1]}")
        assert zoom.size == expected_zoom, "zoom crop has wrong size"
    return lines


def main() -> int:
    """Generate all assets and print the verification report."""
    ICONSET_DIR.mkdir(parents=True, exist_ok=True)

    outputs = (
        ("light", LIGHT_ICON),
        ("dark", DARK_ICON),
        ("tinted", TINTED_ICON),
    )
    for variant, path in outputs:
        render_variant(variant, path)
        print(f"generated {path}")

    CONTENTS_JSON.write_text(CONTENTS_JSON_TEXT, encoding="utf-8")
    print(f"generated {CONTENTS_JSON}")

    build_preview(
        [
            (LIGHT_ICON, "默认（深底白FF）"),
            (DARK_ICON, "深色（透明白FF）"),
            (TINTED_ICON, "染色（灰度·系统可上色）"),
        ]
    )
    print(f"generated {PREVIEW_PATH}")

    build_zoom(LIGHT_ICON)
    print(f"generated {ZOOM_PATH}")

    print("\n--- verification ---")
    for line in verify_assets():
        print(line)
    print("--- all checks passed ---")
    return 0


if __name__ == "__main__":
    sys.exit(main())
