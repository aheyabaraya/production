#!/usr/bin/env python3
"""Apply a white grid overlay to local image files."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


def parse_color(value: str, alpha: int) -> tuple[int, int, int, int]:
    named = {
        "white": (255, 255, 255),
        "black": (0, 0, 0),
    }
    raw = value.strip().lower()
    if raw in named:
        r, g, b = named[raw]
        return (r, g, b, alpha)
    if raw.startswith("#") and len(raw) == 7:
        r = int(raw[1:3], 16)
        g = int(raw[3:5], 16)
        b = int(raw[5:7], 16)
        return (r, g, b, alpha)
    raise ValueError(f"Unsupported color: {value!r}. Use white, black, or #RRGGBB.")


def output_path_for(input_path: Path, cols: int, rows: int, explicit: Path | None) -> Path:
    if explicit:
        return explicit
    suffix = f"-grid-{cols}x{rows}.png"
    return input_path.with_name(f"{input_path.stem}{suffix}")


def apply_grid(
    input_path: Path,
    output_path: Path,
    cols: int,
    rows: int,
    line_width: int,
    color: tuple[int, int, int, int],
) -> tuple[int, int]:
    image = Image.open(input_path).convert("RGBA")
    width, height = image.size
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    for index in range(cols + 1):
        x = round(index * width / cols)
        if index == cols:
            x = width - 1
        draw.line([(x, 0), (x, height - 1)], fill=color, width=line_width)

    for index in range(rows + 1):
        y = round(index * height / rows)
        if index == rows:
            y = height - 1
        draw.line([(0, y), (width - 1, y)], fill=color, width=line_width)

    Image.alpha_composite(image, overlay).convert("RGB").save(output_path, quality=95)
    return width, height


def main() -> None:
    parser = argparse.ArgumentParser(description="Apply a visible grid overlay to image files.")
    parser.add_argument("images", nargs="+", type=Path, help="Input image path(s).")
    parser.add_argument("--cols", type=int, default=6, help="Number of grid columns.")
    parser.add_argument("--rows", type=int, default=6, help="Number of grid rows.")
    parser.add_argument("--line-width", type=int, default=14, help="Grid line width in pixels.")
    parser.add_argument("--color", default="white", help="Line color: white, black, or #RRGGBB.")
    parser.add_argument("--alpha", type=int, default=245, help="Line alpha from 0 to 255.")
    parser.add_argument("--output", type=Path, help="Output path. Only valid with one input image.")
    args = parser.parse_args()

    if args.cols < 1 or args.rows < 1:
        raise SystemExit("--cols and --rows must be at least 1.")
    if args.line_width < 1:
        raise SystemExit("--line-width must be at least 1.")
    if not 0 <= args.alpha <= 255:
        raise SystemExit("--alpha must be between 0 and 255.")
    if args.output and len(args.images) != 1:
        raise SystemExit("--output can only be used with a single input image.")

    color = parse_color(args.color, args.alpha)

    for input_path in args.images:
        if not input_path.exists():
            raise SystemExit(f"Missing input image: {input_path}")
        output_path = output_path_for(input_path, args.cols, args.rows, args.output)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        width, height = apply_grid(
            input_path=input_path,
            output_path=output_path,
            cols=args.cols,
            rows=args.rows,
            line_width=args.line_width,
            color=color,
        )
        print(f"{output_path} | {width}x{height} | {args.cols}x{args.rows} | line_width={args.line_width}px")


if __name__ == "__main__":
    main()
