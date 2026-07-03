#!/usr/bin/env python3
"""Generate MotePad's retro app icon as a 1024x1024 PNG.

A pixel-art spiral-bound notepad on a rounded teal tile. Dependency-free:
uses only the standard library (zlib/struct) to encode the PNG, so it runs
anywhere without Pillow. build.sh turns the PNG into MotePad.icns.
"""
import zlib, struct, os

W = 1024          # output size
G = 32            # logical pixel grid (each cell = W/G = 32 px)
CELL = W // G
R = 176           # background corner radius (px)

# Retro palette (RGBA)
TEAL  = (34, 184, 166, 255)   # tile background
CREAM = (247, 244, 233, 255)  # paper
DARK  = (33, 40, 46, 255)     # outline / ring holes
CORAL = (240, 86, 58, 255)    # spiral rings + header line
SLATE = (120, 132, 146, 255)  # text lines
FOLD  = (214, 208, 190, 255)  # (unused reserve) paper shade

buf = bytearray(W * W * 4)    # transparent

def px(x, y, c):
    if 0 <= x < W and 0 <= y < W:
        i = (y * W + x) * 4
        buf[i:i+4] = bytes(c)

def rect_px(x0, y0, x1, y1, c):
    for y in range(max(0, y0), min(W, y1)):
        row = y * W
        for x in range(max(0, x0), min(W, x1)):
            i = (row + x) * 4
            buf[i:i+4] = bytes(c)

def cell(gx0, gy0, gx1, gy1, c):
    rect_px(gx0*CELL, gy0*CELL, gx1*CELL, gy1*CELL, c)

# --- rounded background tile ---
for y in range(W):
    for x in range(W):
        cx = cy = None
        if x < R and y < R: cx, cy = R, R
        elif x >= W-R and y < R: cx, cy = W-R-1, R
        elif x < R and y >= W-R: cx, cy = R, W-R-1
        elif x >= W-R and y >= W-R: cx, cy = W-R-1, W-R-1
        if cx is not None and (x-cx)**2 + (y-cy)**2 > R*R:
            continue
        px(x, y, TEAL)

# --- notepad ---
cell(5, 7, 27, 29, DARK)     # page outline
cell(6, 8, 26, 28, CREAM)    # paper

# spiral rings straddling the top edge, with a dark hole in each
for gx in (7, 11, 15, 19, 23):
    cell(gx, 5, gx+2, 9, CORAL)
    cell(gx, 4, gx+2, 6, DARK)    # ring hole poking above the page

# header line + body text lines
cell(9, 12, 23, 14, CORAL)   # header (thicker)
cell(9, 16, 23, 17, SLATE)
cell(9, 19, 23, 20, SLATE)
cell(9, 22, 20, 23, SLATE)   # shorter last line

# --- encode PNG (8-bit RGBA) ---
def png_bytes(width, height, data):
    def chunk(typ, payload):
        return (struct.pack(">I", len(payload)) + typ + payload +
                struct.pack(">I", zlib.crc32(typ + payload) & 0xffffffff))
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)                       # filter: none
        raw += data[y*stride:(y+1)*stride]
    return (b'\x89PNG\r\n\x1a\n'
            + chunk(b'IHDR', struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(bytes(raw), 9))
            + chunk(b'IEND', b''))

out = os.path.join(os.path.dirname(__file__), "motepad-icon.png")
with open(out, "wb") as f:
    f.write(png_bytes(W, W, buf))
print("wrote", out)
