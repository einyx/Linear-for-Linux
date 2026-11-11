#!/usr/bin/env python3
"""Convert a Windows .ico file into a PNG.

The favicon that Linear serves is a multi-resolution .ico. A Linux desktop
entry wants a single PNG, so this picks the largest frame and writes it out.

Uses Pillow when it is available. Without Pillow it falls back to parsing the
ICO container itself and picking the largest PNG-encoded frame, which is the
case for every modern favicon.

The frame is scaled up to 512x512 with nearest-neighbour filtering. The
Linear glyph is a solid shape, so it survives the upscale cleanly and stays
crisp in a launcher or taskbar instead of looking blurry.

Usage: ico-to-png.py <input.ico> <output.png>
"""
import struct
import sys

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
TARGET_SIZE = 512


def convert_with_pillow(src: str, dst: str) -> bool:
    try:
        from PIL import Image
    except ImportError:
        return False
    try:
        with Image.open(src) as im:
            # Pick the largest available frame.
            best = None
            for size in sorted(im.info.get("sizes", []), reverse=True):
                im.size = size
                im.load()
                best = im.convert("RGBA").copy()
                break
            if best is None:
                best = im.convert("RGBA")
            if best.width < TARGET_SIZE:
                best = best.resize((TARGET_SIZE, TARGET_SIZE), Image.NEAREST)
            best.save(dst, "PNG")
        return True
    except Exception:
        return False


def largest_png_frame(data: bytes) -> bytes | None:
    """Find the biggest PNG-encoded image inside an ICO container."""
    if len(data) < 6:
        return None
    reserved, _type, count = struct.unpack("<HHH", data[:6])
    if reserved != 0 or _type not in (1, 2):
        return None

    best = None
    for i in range(count):
        entry = 6 + i * 16
        if entry + 16 > len(data):
            break
        width, height, _colors, _reserved, planes, bpp, size, offset = struct.unpack(
            "<BBBBHHII", data[entry : entry + 16]
        )
        width = width or 256
        height = height or 256
        payload = data[offset : offset + size]
        if not payload.startswith(PNG_SIGNATURE):
            continue
        area = width * height
        if best is None or area > best[0]:
            best = (area, payload)

    return best[1] if best else None


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    src, dst = sys.argv[1], sys.argv[2]

    if convert_with_pillow(src, dst):
        return 0

    with open(src, "rb") as fh:
        data = fh.read()

    png = largest_png_frame(data)
    if png is None:
        print("no PNG-encoded frame found in the ico", file=sys.stderr)
        return 1

    with open(dst, "wb") as fh:
        fh.write(png)
    return 0


if __name__ == "__main__":
    sys.exit(main())
