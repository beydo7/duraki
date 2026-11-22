"""Erzeugt die UI-Texturen im Stil „Papier & Tinte“ nach assets/ui/.

    python tools/generate_ui.py

Braucht Python 3 mit Pillow und numpy (scipy optional, für weicheres Rauschen).
Alles ist prozedural und reproduzierbar (feste Seeds).
"""
from __future__ import annotations

import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui")
FONTS = os.path.join(ROOT, "assets", "fonts")

PAPER = (233, 223, 199)
PAPER_WARM = (240, 226, 192)
INK = (30, 24, 30)
RED = (158, 36, 32)
BLUE = (40, 70, 140)


def blur(a: np.ndarray, r: float) -> np.ndarray:
    img = Image.fromarray(np.clip(a * 127 + 128, 0, 255).astype(np.uint8))
    return (np.asarray(img.filter(ImageFilter.GaussianBlur(r))).astype(np.float32) - 128) / 127


def paper_rgb(w: int, h: int, col=PAPER, seed=0, stains=True, vignette=0.16, noise=1.0) -> np.ndarray:
    rng = np.random.default_rng(seed)
    big = blur(rng.normal(0, 1, (h, w)), 10) * 3.0
    mid = blur(rng.normal(0, 1, (h, w)), 2.5) * 1.2
    fine = rng.normal(0, 1, (h, w)) * 0.35
    n = big * 9 + mid * 6 + fine * 6
    # Fasern
    fib = blur(rng.normal(0, 1, (h, w)), 0.6)
    fib = np.repeat(fib.mean(axis=0, keepdims=True), h, axis=0) * 0.0 + blur(rng.normal(0, 1, (h, w * 1)), 0.8)
    n += fib * 2
    n *= noise
    yy, xx = np.mgrid[0:h, 0:w]
    vig = 1 - vignette * (((xx - w / 2) / (w / 2)) ** 2 + ((yy - h / 2) / (h / 2)) ** 2)
    rgb = np.zeros((h, w, 3), np.float32)
    for i in range(3):
        rgb[..., i] = (col[i] + n) * vig
    if stains:
        r = random.Random(seed)
        for _ in range(2):
            cx, cy = r.uniform(0.1, 0.9) * w, r.uniform(0.1, 0.9) * h
            rad = r.uniform(0.12, 0.3) * min(w, h)
            d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / rad
            ring = np.exp(-((d - 1.0) ** 2) / 0.006) * 0.07 + np.clip(1 - d, 0, 1) * 0.03
            rgb *= (1 - ring[..., None] * np.array([0.3, 0.45, 0.7]))
    return np.clip(rgb, 0, 255)


def torn_mask(w: int, h: int, pad: int, seed=0, depth=4.0, step=5) -> Image.Image:
    r = random.Random(seed)
    W, H = w + 2 * pad, h + 2 * pad
    pts = []
    for x in range(0, w + 1, step):
        pts.append((pad + x, pad + r.uniform(0, depth)))
    for y in range(0, h + 1, step):
        pts.append((pad + w - r.uniform(0, depth * 0.7), pad + y))
    for x in range(w, -1, -step):
        pts.append((pad + x, pad + h - r.uniform(0, depth * 1.2)))
    for y in range(h, -1, -step):
        pts.append((pad + r.uniform(0, depth * 0.7), pad + y))
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m.filter(ImageFilter.GaussianBlur(0.6))


def paper_piece(w, h, col=PAPER, seed=0, pad=6, depth=4.0, stains=True, noise=1.0) -> Image.Image:
    W, H = w + 2 * pad, h + 2 * pad
    rgb = paper_rgb(W, H, col, seed, stains, noise=noise)
    img = Image.fromarray(rgb.astype(np.uint8), "RGB").convert("RGBA")
    img.putalpha(torn_mask(w, h, pad, seed, depth))
    return img


def ink_rect(d: ImageDraw.ImageDraw, box, col, width=3, seed=0, wobble=0.8):
    """Gezeichneter Tintenrahmen, leicht unregelmäßig."""
    r = random.Random(seed)
    x0, y0, x1, y1 = box
    for (a, b) in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))):
        n = 14
        pts = []
        for i in range(n + 1):
            t = i / n
            pts.append((a[0] + (b[0] - a[0]) * t + r.uniform(-wobble, wobble), a[1] + (b[1] - a[1]) * t + r.uniform(-wobble, wobble)))
        d.line(pts, fill=col, width=width, joint="curve")


def grunge(img: Image.Image, seed=0, amount=0.25) -> Image.Image:
    a = np.asarray(img).astype(np.float32)
    rng = np.random.default_rng(seed)
    g = blur(rng.normal(0, 1, a.shape[:2]), 1.2)
    keep = np.clip(1 - amount + g * 0.9, 0, 1)
    a[..., 3] *= keep
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def save(img: Image.Image, name: str):
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name), optimize=True)
    print("  ", name, img.size)


# --- Stücke --------------------------------------------------------------------------

def make_panels():
    # großer Zettel (9-Slice, Ränder 28 px)
    save(paper_piece(256, 256, PAPER, seed=1, pad=8, depth=5), "paper.png")
    save(paper_piece(256, 256, PAPER_WARM, seed=2, pad=8, depth=5), "paper_warm.png")
    # dunkler Streifen (Sprechzeile, Tooltips auf dunkel)
    dark = paper_piece(256, 96, (30, 24, 32), seed=3, pad=6, depth=3, stains=False, noise=0.5)
    save(dark, "paper_dark.png")


def make_tags():
    """Knöpfe als Papieretiketten mit Tintenrahmen (9-Slice, Ränder 22 px)."""
    variants = {
        "tag": ((226, 214, 186), INK, 0),
        "tag_hover": (PAPER_WARM, RED, 0),
        "tag_pressed": ((214, 202, 176), RED, 0),
        "tag_disabled": ((170, 162, 148), (90, 84, 90), 0),
        "tag_primary": (PAPER_WARM, RED, 1),
        "tag_primary_hover": ((248, 236, 204), RED, 1),
        "tag_red": ((60, 18, 20), (226, 120, 110), 0),
        "tag_red_hover": ((84, 22, 24), (250, 170, 160), 0),
    }
    for name, (col, ink, double) in variants.items():
        w, h = 200, 56
        piece = paper_piece(w, h, col, seed=sum(map(ord, name)), pad=2, depth=1.8, stains=False, noise=0.35)
        d = ImageDraw.Draw(piece)
        # Rahmen liegt komplett in den 9-Slice-Rändern (oben 12, unten 14 px)
        ink_rect(d, (8, 7, w - 4, h - 3), ink + (230,), 2, seed=4, wobble=0.5)
        if double:
            ink_rect(d, (12, 10, w - 8, h - 6), ink + (140,), 1, seed=5, wobble=0.4)
        img = Image.new("RGBA", (piece.width + 3, piece.height + 4), (0, 0, 0, 0))
        sh = Image.new("RGBA", piece.size, (0, 0, 0, 0))
        sh.putalpha(piece.split()[3].point(lambda v: v * 110 // 255))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(1.5)), (2, 3))
        img.alpha_composite(piece, (0, 0))
        save(img, name + ".png")


def make_notepad():
    w, h = 380, 320
    img = paper_piece(w, h, (236, 229, 206), seed=7, pad=8, depth=4)
    d = ImageDraw.Draw(img)
    for y in range(8 + 72, 8 + h, 30):
        d.line((8, y, 8 + w, y), fill=(120, 150, 200, 110), width=1)
    d.line((8 + 46, 8, 8 + 46, 8 + h), fill=(190, 60, 60, 150), width=2)
    for k in range(4):
        cy = 8 + 54 + k * 66
        d.ellipse((8 + 14, cy, 8 + 28, cy + 14), fill=(24, 18, 26, 230))
    save(img, "notepad.png")


def make_chip(name, col):
    s = 128
    r = 56
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = s / 2
    d.ellipse((c - r, c - r, c + r, c + r), fill=col + (255,))
    edge = (238, 230, 212, 255)
    for k in range(8):
        a = k * math.pi / 4 + math.pi / 8
        pts = []
        for t in (-0.13, 0.13):
            pts.append((c + math.cos(a + t) * r, c + math.sin(a + t) * r))
        for t in (0.11, -0.11):
            pts.append((c + math.cos(a + t) * (r - 14), c + math.sin(a + t) * (r - 14)))
        d.polygon(pts, fill=edge)
    inner = tuple(int(v * 0.78) for v in col) + (255,)
    d.ellipse((c - r + 17, c - r + 17, c + r - 17, c + r - 17), fill=inner, outline=edge, width=2)
    d.ellipse((c - r + 22, c - r + 22, c + r - 22, c + r - 22), outline=(238, 230, 212, 90), width=1)
    # leichte Abnutzung + Lichtkante
    a = np.asarray(img).astype(np.float32)
    yy, xx = np.mgrid[0:s, 0:s]
    shade = 1 + 0.12 * ((c - yy) / r) - 0.05 * ((xx - c) / r)
    a[..., :3] *= shade[..., None]
    rng = np.random.default_rng(3)
    a[..., :3] += rng.normal(0, 4, (s, s, 1))
    save(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA"), name)


def make_stamp_frame():
    """Roter Stempelrahmen (9-Slice, Ränder 18 px), grob und unregelmäßig."""
    w, h = 220, 90
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # weiß, damit es im Spiel beliebig eingefärbt werden kann (self_modulate)
    ink_rect(d, (6, 6, w - 6, h - 6), (255, 255, 255, 255), 5, seed=11, wobble=1.2)
    ink_rect(d, (12, 12, w - 12, h - 12), (255, 255, 255, 200), 2, seed=12, wobble=1.0)
    save(grunge(img, seed=13, amount=0.35), "stamp_frame.png")


def make_photo_frame():
    w = 120
    img = Image.new("RGBA", (w, w), (0, 0, 0, 0))
    rgb = paper_rgb(w, w, (246, 241, 228), seed=21, stains=False, vignette=0.06)
    a = np.zeros((w, w, 4), np.uint8)
    a[..., :3] = rgb.astype(np.uint8)
    a[..., 3] = 255
    save(Image.fromarray(a, "RGBA"), "photo.png")


def make_arrow():
    img = Image.new("RGBA", (20, 14), (0, 0, 0, 0))
    ImageDraw.Draw(img).polygon([(2, 3), (18, 3), (10, 12)], fill=INK + (220,))
    save(img, "arrow_down.png")


def make_grain():
    """Kachelbare Tintenkörnung für den Stempel-Shader (Graustufen)."""
    s = 256
    rng = np.random.default_rng(31)
    g = blur(rng.normal(0, 1, (s, s)), 1.0) * 0.7 + blur(rng.normal(0, 1, (s, s)), 4.0) * 0.5
    g = np.clip(g * 0.5 + 0.5, 0, 1)
    save(Image.fromarray((g * 255).astype(np.uint8), "L"), "ink_grain.png")


def main():
    print("UI-Texturen →", OUT)
    make_panels()
    make_tags()
    make_notepad()
    make_chip("chip_blue.png", BLUE)
    make_chip("chip_red.png", RED)
    make_chip("chip_gold.png", (170, 120, 30))
    make_stamp_frame()
    make_photo_frame()
    make_grain()
    make_arrow()


if __name__ == "__main__":
    main()
