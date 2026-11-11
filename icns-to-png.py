#!/usr/bin/env python3
"""Extract the largest PNG image embedded in a macOS .icns file.

Linear ships its icon as an .icns. Linux desktops want a plain PNG, so this
pulls one out. It first tries Pillow, which understands .icns directly. If
Pillow is not installed it falls back to scanning the file for PNG chunks and
reassembling the largest one it can find.

Usage: icns-to-png.py <input.icns> <output.png>
"""
import struct
import sys

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def find_largest_png(data: bytes) -> bytes | None:
    """Scan for PNG images and return the largest complete one."""
    best = None
    offset = 0
    while True:
        start = data.find(PNG_SIGNATURE, offset)
        if start == -1:
            break
        # Walk the PNG chunk list to find where this image ends.
        pos = start + len(PNG_SIGNATURE)
        valid = True
        while pos + 8 <= len(data):
            length = struct.unpack(">I", data[pos : pos + 4])[0]
            ctype = data[pos + 4 : pos + 8]
            if ctype == b"IEND":
                pos += 12
                break
            pos += 12 + length
        else:
            valid = False
        if valid and pos > start:
            candidate = data[start:pos]
            if best is None or len(candidate) > len(best):
                best = candidate
        offset = start + 1
    return best


def convert_with_pillow(src: str, dst: str) -> bool:
    try:
        from PIL import Image
    except ImportError:
        return False
    try:
        with Image.open(src) as im:
            im.seek(0)
            im.convert("RGBA").save(dst, "PNG")
        return True
    except Exception:
        return False


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    src, dst = sys.argv[1], sys.argv[2]

    if convert_with_pillow(src, dst):
        return 0

    with open(src, "rb") as fh:
        data = fh.read()

    png = find_largest_png(data)
    if png is None:
        print("no PNG image found in the icns", file=sys.stderr)
        return 1

    with open(dst, "wb") as fh:
        fh.write(png)
    return 0


if __name__ == "__main__":
    sys.exit(main())
