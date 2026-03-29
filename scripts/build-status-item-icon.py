#!/usr/bin/env python3

from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image


# Keep icon content around common macOS menu bar visual footprint.
MENU_BAR_ICON_FILL_RATIO = 1.0


def alpha_for_pixel(red: int, green: int, blue: int, alpha: int) -> int:
    if alpha == 0:
        return 0

    luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
    darkness = max(0.0, 255.0 - luminance)

    if darkness < 18:
        return 0

    return max(0, min(255, int(round(darkness * (alpha / 255.0)))))


def build_template(source_path: Path, output_path: Path) -> None:
    source = Image.open(source_path).convert("RGBA")
    width, height = source.size

    template = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    source_pixels = source.load()
    template_pixels = template.load()

    for x in range(width):
        for y in range(height):
            red, green, blue, alpha = source_pixels[x, y]
            pixel_alpha = alpha_for_pixel(red, green, blue, alpha)
            if pixel_alpha == 0:
                continue

            template_pixels[x, y] = (0, 0, 0, pixel_alpha)

    bbox = template.getbbox()
    if bbox is None:
        raise RuntimeError("no visible icon content detected after template conversion")

    cropped = template.crop(bbox)
    max_side = max(cropped.size)
    padded_side = int(math.ceil(max_side / MENU_BAR_ICON_FILL_RATIO))
    square = Image.new("RGBA", (padded_side, padded_side), (0, 0, 0, 0))

    offset_x = (padded_side - cropped.size[0]) // 2
    offset_y = (padded_side - cropped.size[1]) // 2
    square.paste(cropped, (offset_x, offset_y), cropped)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    square.resize((256, 256), Image.Resampling.LANCZOS).save(output_path)


def main() -> int:
    root_dir = Path.cwd()
    source_path = Path(sys.argv[1]) if len(sys.argv) > 1 else root_dir / "artwork/status-item/source.png"
    output_path = (
        Path(sys.argv[2])
        if len(sys.argv) > 2
        else root_dir / "Sources/Swooshy/Resources/StatusItem/SwooshyStatusTemplate.png"
    )

    if not source_path.is_file():
        print(f"[status-item] ERROR: source image not found at {source_path}", file=sys.stderr)
        return 1

    try:
        build_template(source_path, output_path)
    except Exception as exc:  # noqa: BLE001
        print(f"[status-item] ERROR: {exc}", file=sys.stderr)
        return 1

    print(f"[status-item] Source: {source_path}")
    print(f"[status-item] Output: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
