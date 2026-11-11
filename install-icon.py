#!/usr/bin/env python3
"""Install a PNG as a hicolor icon theme entry.

A desktop entry that points straight at one big PNG looks soft in launchers
that request a different size. The freedesktop.org way is to install the icon
under `~/.local/share/icons/hicolor/<size>x<size>/apps/` and let the icon
theme cache pick the closest match.

The source image is resized with Lanczos when Pillow is available, so the
edges of the rounded square stay smooth. Without Pillow the image is copied
unchanged and the theme cache will scale it.

Usage: install-icon.py <source.png> <theme-root> <icon-name>
"""
import os
import shutil
import sys

SIZES = (16, 24, 32, 48, 64, 128, 256, 512)


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    src, theme_root, name = sys.argv[1], sys.argv[2], sys.argv[3]

    if not os.path.isfile(src):
        print(f"no such file: {src}", file=sys.stderr)
        return 1

    try:
        from PIL import Image
    except ImportError:
        Image = None

    with Image.open(src) as im:
        base = im.convert("RGBA")
        for size in SIZES:
            directory = os.path.join(theme_root, "%dx%d" % (size, size), "apps")
            os.makedirs(directory, exist_ok=True)
            target = os.path.join(directory, "%s.png" % name)
            if base.width == size and base.height == size:
                base.save(target, "PNG")
            else:
                base.resize((size, size), Image.LANCZOS).save(target, "PNG")

    return 0


if __name__ == "__main__":
    sys.exit(main())
