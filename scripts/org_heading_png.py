"""Render org headlines as one PNG for pure/render-org.lua's 'image' mode.

Usage: org_heading_png.py < JOB.json

JOB is a JSON object:

  out       PNG path to write
  font      TrueType font file (the bold face of the editor font)
  max_cols  the widest a line may be, in cells (a long headline gets a smaller font)
  bg        background, #rrggbb, or "none" for transparent
  lines     the headlines, top to bottom: [{"rows": N, "segments": [{"text": ..., "fg": "#rrggbb"}]}]
            rows is the editor rows that headline takes; segments are drawn one after the
            other, each in its own colour (a TODO keyword, then the rest of the title)

Several headlines on consecutive lines hang under the same visible line, and Neovim does
not keep the order of virtual lines anchored at one position, so they come as one image.

The image is a whole number of cells: the cell size is taken from the font's own
metrics (advance of "M", ascent + descent), the way a GUI sizes its grid with that
font, so the GUI scales it without distortion. Prints the width in cells.
"""
import json
import math
import sys

from PIL import Image, ImageDraw, ImageFont

CELL_H_PX = 40  # render resolution: pixels per editor row (the GUI scales it down)


def line_font(font_path, rows, text, max_w_px, pad_px):
    """The font for one headline: about 3/4 of its height, smaller when it is too wide."""
    size = max(8, int(rows * CELL_H_PX * 0.62))
    font = ImageFont.truetype(font_path, size)
    width = font.getlength(text)
    if width + pad_px > max_w_px:
        size = max(8, int(size * (max_w_px - pad_px) / width))
        font = ImageFont.truetype(font_path, size)
    return font


def main():
    job = json.loads(sys.stdin.buffer.read().decode("utf-8"))
    font_path = job["font"]
    max_cols = int(job["max_cols"])
    bg = job["bg"]

    # Cell size at the render resolution, from the font at its base size.
    base = ImageFont.truetype(font_path, 100)
    ascent, descent = base.getmetrics()
    cell_w_px = base.getlength("M") * CELL_H_PX / (ascent + descent)
    max_w_px = max_cols * cell_w_px
    pad_px = cell_w_px * 0.5

    laid = []
    cols = 1
    for line in job["lines"]:
        rows = int(line["rows"])
        segments = [s for s in line["segments"] if s["text"]]
        text = "".join(s["text"] for s in segments)
        font = line_font(font_path, rows, text, max_w_px, pad_px)
        cols = max(cols, min(max_cols, math.ceil((font.getlength(text) + pad_px) / cell_w_px)))
        laid.append((rows, segments, font, text))

    width_px = max(1, round(cols * cell_w_px))
    height_px = sum(line[0] for line in laid) * CELL_H_PX
    image = Image.new("RGBA", (width_px, height_px), (0, 0, 0, 0) if bg == "none" else bg)
    draw = ImageDraw.Draw(image)

    top = 0
    for rows, segments, font, text in laid:
        f_ascent, f_descent = font.getmetrics()
        y = top + (rows * CELL_H_PX - (f_ascent + f_descent)) / 2
        x = -font.getbbox(text)[0] if text else 0  # the first glyph starts at the left edge
        for segment in segments:
            draw.text((x, y), segment["text"], font=font, fill=segment["fg"])
            x += font.getlength(segment["text"])
        top += rows * CELL_H_PX

    image.save(job["out"])
    print(cols)


if __name__ == "__main__":
    main()
