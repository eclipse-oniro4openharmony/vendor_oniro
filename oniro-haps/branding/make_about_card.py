#!/usr/bin/env python3
# Copyright (c) 2026 Eclipse Oniro for OpenHarmony contributors.
# SPDX-License-Identifier: Apache-2.0
"""Compose the Settings > About card background from the official Oniro logo.

The logo (Reversed vertical lockup, colour mark on the brand dark #0F0026) is
only scaled, never altered, as the Eclipse Foundation trademark policy requires.
The canvas matches the stock video_bg.png (2412x1608): the card shows it with
ImageSize.Cover, so a phone card (about square) keeps only the central ~1600 px,
and the version text and "Check for updates" button cover its bottom ~30 %.
"""
import sys
from PIL import Image, ImageDraw

W, H = 2412, 1608
LOGO_TOP, LOGO_H = 300, 600          # logo content box, in canvas pixels


def main(logo_png, out_png):
    logo = Image.open(logo_png).convert('RGBA')
    bg = logo.getpixel((5, 5))        # the lockup's own backdrop, #0F0026
    canvas = Image.new('RGBA', (W, H), bg)

    # Two faint arcs echoing the stock card, kept clear of the logo box.
    deco = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(deco)
    d.ellipse((650 - 560, -330 - 560, 650 + 560, -330 + 560),
              outline=(0, 201, 229, 70), width=34)       # cyan, top left
    d.ellipse((1950 - 640, 1650 - 640, 1950 + 640, 1650 + 640),
              outline=(255, 39, 183, 60), width=34)      # magenta, bottom right
    canvas.alpha_composite(deco)

    # Crop the lockup to its content (plus a margin of backdrop), scale, centre.
    x0, y0, x1, y1 = 269, 311, 1374, 1245
    m = 30
    crop = logo.crop((x0 - m, y0 - m, x1 + m, y1 + m))
    s = LOGO_H / (y1 - y0)
    crop = crop.resize((round(crop.width * s), round(crop.height * s)), Image.LANCZOS)
    canvas.alpha_composite(crop, ((W - crop.width) // 2, LOGO_TOP - round(m * s)))

    canvas.convert('RGB').save(out_png, optimize=True)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
