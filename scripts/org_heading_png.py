"""Render one org headline as a PNG for pure/render-org.lua's 'image' mode.

Usage: org_heading_png.py OUT FONT ROWS MAXCOLS FG BG TEXT

  OUT     PNG path to write
  FONT    TrueType font file (the bold face of the editor font)
  ROWS    editor rows the image takes (its height in cells)
  MAXCOLS the widest it may be, in cells (a long headline gets a smaller font)
  FG      text colour, #rrggbb
  BG    background, #rrggbb, or "none" for transparent
  TEXT  the headline text

The image is a whole number of cells: the cell size is taken from the font's own
metrics (advance of "M", ascent + descent), the way a GUI sizes its grid with that
font, so the GUI scales it without distortion. Prints the width in cells.
"""
import math
import sys

from PIL import Image, ImageDraw, ImageFont

CELL_H_PX = 40  # render resolution: pixels per editor row (the GUI scales it down)


def main():
    out, font_path, rows, max_cols, fg, bg, text = sys.argv[1:8]
    rows = int(rows)
    max_cols = int(max_cols)

    # Cell size at the render resolution, from the font at its base size.
    base = ImageFont.truetype(font_path, 100)
    ascent, descent = base.getmetrics()
    cell_w_px = base.getlength("M") * CELL_H_PX / (ascent + descent)

    # The text fills about 3/4 of the image height.
    height_px = rows * CELL_H_PX
    size = max(8, int(height_px * 0.62))
    font = ImageFont.truetype(font_path, size)
    left, _, right, _ = font.getbbox(text)
    # Too wide for the window: a smaller font, same height.
    max_w_px = max_cols * cell_w_px
    if right - left + cell_w_px * 0.5 > max_w_px:
        size = max(8, int(size * (max_w_px - cell_w_px * 0.5) / (right - left)))
        font = ImageFont.truetype(font_path, size)
        left, _, right, _ = font.getbbox(text)
    text_w_px = right - left
    cols = min(max_cols, max(1, math.ceil((text_w_px + cell_w_px * 0.5) / cell_w_px)))
    width_px = max(1, round(cols * cell_w_px))

    image = Image.new("RGBA", (width_px, height_px), (0, 0, 0, 0) if bg == "none" else bg)
    draw = ImageDraw.Draw(image)
    f_ascent, f_descent = font.getmetrics()
    y = (height_px - (f_ascent + f_descent)) / 2
    draw.text((-left, y), text, font=font, fill=fg)
    image.save(out)
    print(cols)


if __name__ == "__main__":
    main()
