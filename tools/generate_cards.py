#!/usr/bin/env python3
"""Erzeugt das Kartenblatt für Duraki im Stil „Papier & Tinte“.

Aufruf (aus dem Projektordner):
    python tools/generate_cards.py
Benötigt: Pillow und numpy  (pip install pillow numpy)

Ausgabe:
  assets/cards/<farbe>_<rang>.png         Vorderseiten (gealtertes Papier, Tintendruck)
  assets/cards/glass/<farbe>_<rang>.png   Glaskarten (durchscheinend)
  assets/cards/back.png                    Standard-Rückseite (= Deck „hinterzimmer“)
  assets/cards/backs/<deck>.png            Rückseiten aller Decks (siehe DECK_BACKS)
    farbe: h = Herz, d = Karo, c = Kreuz, s = Pik
    rang:  6..14 (11 = Bube/J, 12 = Dame, 13 = König, 14 = Ass)

Alle Motive sind eigene Zeichnungen aus Grundformen (keine fremden Vorlagen).
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "cards")
FONTS = os.path.join(ROOT, "assets", "fonts")
FONT_SYM = os.path.join(FONTS, "DejaVuSans.ttf")
FONT_SYM_B = os.path.join(FONTS, "DejaVuSans-Bold.ttf")
FONT_DISP = os.path.join(FONTS, "RuslanDisplay-Regular.ttf")
FONT_SERIF = os.path.join(FONTS, "OldStandard-Bold.ttf")
FONT_TYPE = os.path.join(FONTS, "SpecialElite-Regular.ttf")

S = 2                      # Supersampling, am Ende wird verkleinert
W, H = 500 * S, 700 * S    # Seitenverhältnis 1 : 1.4 wie die 3D-Karte

PAPER = (232, 221, 196)
RED = (158, 28, 24)
INK = (28, 23, 28)
OCHRE = (196, 148, 66)
BLUE = (44, 66, 110)
SKIN = (236, 214, 180)

SUITS = {"h": ("♥", RED), "d": ("♦", RED), "c": ("♣", INK), "s": ("♠", INK)}
RANK_TEXT = {6: "6", 7: "7", 8: "8", 9: "9", 10: "10", 11: "J", 12: "D", 13: "K", 14: "A"}

L, C, R = 0.31, 0.5, 0.69
PIPS = {
    6: [(L, .22), (R, .22), (L, .5), (R, .5), (L, .78), (R, .78)],
    7: [(L, .22), (R, .22), (C, .36), (L, .5), (R, .5), (L, .78), (R, .78)],
    8: [(L, .22), (R, .22), (C, .36), (L, .5), (R, .5), (C, .64), (L, .78), (R, .78)],
    9: [(L, .22), (R, .22), (L, .407), (R, .407), (C, .5), (L, .593), (R, .593), (L, .78), (R, .78)],
    10: [(L, .22), (R, .22), (C, .315), (L, .407), (R, .407), (L, .593), (R, .593), (C, .685), (L, .78), (R, .78)],
}


# --- Hilfen ----------------------------------------------------------------------------

def font(path, size):
    return ImageFont.truetype(path, int(size))


def blur(a, r):
    img = Image.fromarray(np.clip(a * 60 + 128, 0, 255).astype(np.uint8))
    return (np.asarray(img.filter(ImageFilter.GaussianBlur(r))).astype(np.float32) - 128) / 60


def aged_paper(w, h, col=PAPER, seed=0, stains=2, edge_wear=0.35):
    rng = np.random.default_rng(seed)
    n = blur(rng.normal(0, 1, (h, w)), 18) * 6 + blur(rng.normal(0, 1, (h, w)), 3) * 3 + rng.normal(0, 1, (h, w)) * 2.5
    yy, xx = np.mgrid[0:h, 0:w]
    # Ränder vergilbt/abgegriffen
    ed = np.minimum.reduce([xx, yy, w - 1 - xx, h - 1 - yy]).astype(np.float32) / (0.09 * w)
    wear = np.clip(1 - ed, 0, 1) ** 2 * edge_wear
    rgb = np.zeros((h, w, 3), np.float32)
    for i in range(3):
        rgb[..., i] = col[i] + n
    rgb *= (1 - wear[..., None] * np.array([0.25, 0.32, 0.45]))
    r = random.Random(seed)
    for _ in range(stains):
        cx, cy = r.uniform(0.15, 0.85) * w, r.uniform(0.15, 0.85) * h
        rad = r.uniform(0.1, 0.22) * w
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / rad
        ring = np.exp(-((d - 1.0) ** 2) / 0.004) * 0.06 + np.clip(1 - d, 0, 1) * 0.025
        rgb *= (1 - ring[..., None] * np.array([0.3, 0.45, 0.75]))
    a = np.full((h, w, 1), 255, np.float32)
    return Image.fromarray(np.clip(np.concatenate([rgb, a], axis=2), 0, 255).astype(np.uint8), "RGBA")


def ink_texture(layer, seed=0, strength=0.22):
    """Macht gedruckte Flächen unregelmäßig wie Hochdruck (Alpha + leichte Aufhellung)."""
    a = np.asarray(layer).astype(np.float32)
    rng = np.random.default_rng(seed)
    g = blur(rng.normal(0, 1, a.shape[:2]), 1.4) * 0.6 + rng.normal(0, 1, a.shape[:2]) * 0.25
    a[..., 3] *= np.clip(1 - strength + g * strength, 0.55, 1)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def glyph(text, size, color, fnt=FONT_SYM):
    f = font(fnt, size)
    box = f.getbbox(text)
    w, h = box[2] - box[0], box[3] - box[1]
    tile = Image.new("RGBA", (w + 8, h + 8), (0, 0, 0, 0))
    ImageDraw.Draw(tile).text((4 - box[0], 4 - box[1]), text, font=f, fill=color)
    return tile


def put(img, tile, center, rotate=False):
    if rotate:
        tile = tile.rotate(180)
    img.alpha_composite(tile, (int(center[0] - tile.width / 2), int(center[1] - tile.height / 2)))


def draw_index(img, rank, sym, color):
    for rotate in (False, True):
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        tx = RANK_TEXT[rank]
        size = 0.16 * W if len(tx) == 1 else 0.125 * W
        cx = 0.115 * W
        put(layer, glyph(tx, size, color, FONT_DISP), (cx, 0.085 * H))
        put(layer, glyph(sym, 0.1 * W, color), (cx, 0.175 * H))
        if rotate:
            layer = layer.rotate(180)
        img.alpha_composite(ink_texture(layer, seed=rank))


def base_card(seed):
    img = aged_paper(W, H, seed=seed)
    d = ImageDraw.Draw(img)
    m = 0.035 * W
    d.rounded_rectangle([m, m, W - m, H - m], radius=0.045 * W, outline=INK + (150,), width=int(0.004 * W))
    m2 = 0.048 * W
    d.rounded_rectangle([m2, m2, W - m2, H - m2], radius=0.035 * W, outline=INK + (70,), width=int(0.002 * W))
    return img


def hatch(d, box, col, step, width, angle=1.0):
    """Schraffur innerhalb eines Rechtecks (für Holzschnitt-Schatten)."""
    x0, y0, x1, y1 = box
    h = y1 - y0
    for x in range(int(x0 - h), int(x1), int(step)):
        d.line([(x, y1), (x + h * angle, y0)], fill=col, width=width)


# --- Zahlenkarten / Ass -----------------------------------------------------------------

def pip_card(rank, suit, seed):
    sym, color = SUITS[suit]
    img = base_card(seed)
    draw_index(img, rank, sym, color)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    tile = glyph(sym, 0.19 * W, color)
    for (x, y) in PIPS[rank]:
        put(layer, tile, (x * W, y * H), rotate=y > 0.5)
    img.alpha_composite(ink_texture(layer, seed=seed, strength=0.12))
    return img


def ace_card(suit, seed):
    sym, color = SUITS[suit]
    img = base_card(seed)
    draw_index(img, 14, sym, color)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = W / 2, H / 2
    # Strahlenkranz wie auf alten Spielkarten-Stempeln
    for k in range(48):
        a = k / 48 * math.tau
        r0, r1 = 0.24 * W, (0.33 if k % 2 == 0 else 0.29) * W
        d.line([(cx + math.cos(a) * r0, cy + math.sin(a) * r0), (cx + math.cos(a) * r1, cy + math.sin(a) * r1)],
               fill=OCHRE + (255,), width=int(0.006 * W))
    r = 0.23 * W
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=INK + (255,), width=int(0.007 * W))
    d.ellipse([cx - r * 0.93, cy - r * 0.93, cx + r * 0.93, cy + r * 0.93], outline=color + (255,), width=int(0.003 * W))
    put(layer, glyph(sym, 0.34 * W, color), (cx, cy))
    if suit == "s":
        # Pik-Ass trägt den Spielnamen
        put(layer, glyph("DURAKI", 0.075 * W, INK, FONT_DISP), (cx, cy + 0.4 * W))
        put(layer, glyph("·  HINTERZIMMER  ·", 0.035 * W, INK, FONT_TYPE), (cx, cy + 0.47 * W))
    img.alpha_composite(ink_texture(layer, seed=seed + 3))
    return img


# --- Bildkarten (Holzschnitt-Stil, nach Art alter russischer Blätter) -------------------

def figure_half(rank, suit):
    """Obere Hälfte einer Bildkarte; unten wird gespiegelt."""
    sym, color = SUITS[suit]
    fw, fh = int(0.6 * W), int(0.375 * H)
    img = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lw = max(2, int(0.007 * W))
    robe = color if color == RED else BLUE
    cx = fw * 0.5
    hr = fw * 0.12
    hy = fh * 0.42
    ink = INK + (255,)

    # Gewand mit Pelz-/Borte und Schraffur
    body = [(cx - fw * 0.46, fh), (cx - fw * 0.34, fh * 0.6), (cx - fw * 0.1, fh * 0.55),
            (cx + fw * 0.1, fh * 0.55), (cx + fw * 0.34, fh * 0.6), (cx + fw * 0.46, fh)]
    d.polygon(body, fill=robe + (255,), outline=ink)
    mask = Image.new("L", (fw, fh), 0)
    ImageDraw.Draw(mask).polygon(body, fill=255)
    hl = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    hatch(ImageDraw.Draw(hl), (0, fh * 0.55, fw, fh), INK + (110,), fw * 0.03, max(1, lw // 2))
    img.paste(hl, (0, 0), Image.composite(hl.split()[3], Image.new("L", (fw, fh), 0), mask))
    d = ImageDraw.Draw(img)
    # Ornamentborte
    d.line([(cx - fw * 0.4, fh * 0.83), (cx + fw * 0.4, fh * 0.83)], fill=OCHRE + (255,), width=lw * 3)
    for i in range(9):
        x = cx - fw * 0.36 + i * fw * 0.09
        d.polygon([(x, fh * 0.80), (x + fw * 0.022, fh * 0.83), (x, fh * 0.86), (x - fw * 0.022, fh * 0.83)], fill=ink)
    # Kragen
    if rank == 13:
        d.ellipse([cx - fw * 0.3, fh * 0.5, cx + fw * 0.3, fh * 0.7], fill=(240, 234, 220, 255), outline=ink, width=lw)
        for k in range(14):
            x = cx - fw * 0.26 + k * fw * 0.04
            d.point([(x, fh * 0.6 + (k % 3) * 4)], fill=ink)
            d.ellipse([x - 3, fh * 0.6 - 3 + (k % 3) * 5, x + 3, fh * 0.6 + 3 + (k % 3) * 5], fill=ink)
    else:
        d.polygon([(cx - fw * 0.16, fh * 0.56), (cx, fh * 0.74), (cx + fw * 0.16, fh * 0.56)], fill=OCHRE + (255,), outline=ink)

    # Hals und Kopf
    d.rectangle([cx - hr * 0.33, hy + hr * 0.7, cx + hr * 0.33, fh * 0.58], fill=SKIN + (255,), outline=ink)
    hair = (60, 40, 28, 255) if rank != 13 else (215, 210, 200, 255)
    if rank == 12:
        # zwei Zöpfe über die Schultern
        for side in (-1, 1):
            for k in range(5):
                y = hy + hr * (0.6 + k * 0.42)
                x = cx + side * hr * (1.0 + k * 0.06)
                d.ellipse([x - hr * 0.2, y - hr * 0.24, x + hr * 0.2, y + hr * 0.24], fill=hair, outline=ink)
        d.rounded_rectangle([cx - hr * 1.15, hy - hr * 0.6, cx + hr * 1.15, hy + hr * 1.5], radius=hr, fill=hair, outline=ink)
    else:
        d.ellipse([cx - hr * 1.08, hy - hr * 1.02, cx + hr * 1.08, hy + hr * 0.55], fill=hair, outline=ink)
    # Gesicht: länglich, ernst
    d.ellipse([cx - hr * 0.9, hy - hr * 0.95, cx + hr * 0.9, hy + hr * 1.1], fill=SKIN + (255,), outline=ink, width=lw)
    for side in (-1, 1):
        ex = cx + side * hr * 0.36
        d.polygon([(ex - hr * 0.2, hy - hr * 0.05), (ex, hy - hr * 0.16), (ex + hr * 0.2, hy - hr * 0.05), (ex, hy + hr * 0.04)], fill=ink)
        d.line([(ex - hr * 0.24, hy - hr * 0.32), (ex + hr * 0.2, hy - hr * 0.26 - side * hr * 0.04)], fill=ink, width=lw)
    d.line([(cx + hr * 0.02, hy - hr * 0.1), (cx - hr * 0.1, hy + hr * 0.42), (cx + hr * 0.1, hy + hr * 0.46)], fill=ink, width=lw)
    d.line([(cx - hr * 0.22, hy + hr * 0.7), (cx + hr * 0.22, hy + hr * 0.7)], fill=RED + (255,), width=lw)
    # Wangen-Schraffur
    for side in (-1, 1):
        for k in range(3):
            x = cx + side * hr * (0.62 + k * 0.08)
            d.line([(x, hy + hr * 0.15), (x - side * hr * 0.05, hy + hr * 0.55)], fill=INK + (90,), width=max(1, lw // 2))

    if rank == 13:
        # König: Vollbart, Krone mit Kreuzen, Zepter
        d.polygon([(cx - hr * 0.82, hy + hr * 0.4), (cx - hr * 0.55, hy + hr * 1.7), (cx, hy + hr * 2.0),
                   (cx + hr * 0.55, hy + hr * 1.7), (cx + hr * 0.82, hy + hr * 0.4), (cx + hr * 0.3, hy + hr * 0.85),
                   (cx - hr * 0.3, hy + hr * 0.85)], fill=(225, 220, 210, 255), outline=ink)
        for k in range(5):
            x = cx - hr * 0.5 + k * hr * 0.25
            d.line([(x, hy + hr * 1.0), (x + hr * 0.05, hy + hr * 1.6)], fill=INK + (120,), width=max(1, lw // 2))
        by = hy - hr * 0.82
        crown = [(cx - hr * 1.05, by), (cx - hr * 1.0, by - hr * 0.95), (cx - hr * 0.5, by - hr * 0.55),
                 (cx, by - hr * 1.25), (cx + hr * 0.5, by - hr * 0.55), (cx + hr * 1.0, by - hr * 0.95), (cx + hr * 1.05, by)]
        d.polygon(crown, fill=OCHRE + (255,), outline=ink)
        d.line([(cx - hr * 1.05, by - hr * 0.12), (cx + hr * 1.05, by - hr * 0.12)], fill=ink, width=lw)
        for jx in (-0.5, 0, 0.5):
            d.ellipse([cx + hr * jx - hr * 0.1, by - hr * 0.45, cx + hr * jx + hr * 0.1, by - hr * 0.25], fill=RED + (255,), outline=ink)
        d.line([(cx, by - hr * 1.25), (cx, by - hr * 1.6)], fill=ink, width=lw)
        d.line([(cx - hr * 0.15, by - hr * 1.45), (cx + hr * 0.15, by - hr * 1.45)], fill=ink, width=lw)
        sx = cx + fw * 0.35
        d.line([(sx, fh), (sx, fh * 0.16)], fill=ink, width=lw * 3)
        d.ellipse([sx - fw * 0.045, fh * 0.08, sx + fw * 0.045, fh * 0.18], fill=OCHRE + (255,), outline=ink, width=lw)
    elif rank == 12:
        # Dame: Kokoschnik (hoher Kopfschmuck) mit Perlen, Fächer
        by = hy - hr * 0.7
        kok = [(cx - hr * 1.2, by + hr * 0.15)]
        for k in range(21):
            a = math.pi - k / 20 * math.pi
            kok.append((cx + math.cos(a) * hr * 1.2, by - math.sin(a) * hr * 1.55))
        kok.append((cx + hr * 1.2, by + hr * 0.15))
        d.polygon(kok, fill=RED + (255,) if color != RED else BLUE + (255,), outline=ink)
        inner = [(cx + math.cos(math.pi - k / 20 * math.pi) * hr * 0.95, by - math.sin(math.pi - k / 20 * math.pi) * hr * 1.25) for k in range(21)]
        d.line(inner, fill=OCHRE + (255,), width=lw * 2)
        for k in range(1, 20, 2):
            a = math.pi - k / 20 * math.pi
            x, y = cx + math.cos(a) * hr * 1.08, by - math.sin(a) * hr * 1.4
            d.ellipse([x - hr * 0.06, y - hr * 0.06, x + hr * 0.06, y + hr * 0.06], fill=(245, 240, 230, 255), outline=ink)
        d.ellipse([cx - hr * 0.16, by - hr * 0.85, cx + hr * 0.16, by - hr * 0.53], fill=OCHRE + (255,), outline=ink)
        # Fächer
        fx, fy = cx + fw * 0.3, fh * 0.62
        for k in range(7):
            a = -math.pi * 0.9 + k * math.pi * 0.13
            d.line([(fx, fy + fw * 0.12), (fx + math.cos(a) * fw * 0.13, fy + math.sin(a) * fw * 0.13)], fill=ink, width=lw)
        d.pieslice([fx - fw * 0.13, fy - fw * 0.13, fx + fw * 0.13, fy + fw * 0.13], 198, 342, outline=ink, width=lw)
    else:
        # Bube: Barett mit Feder, Schnurrbart, Hellebarde
        by = hy - hr * 0.62
        d.polygon([(cx - hr * 1.3, by + hr * 0.1), (cx - hr * 1.1, by - hr * 0.55), (cx + hr * 0.9, by - hr * 0.75),
                   (cx + hr * 1.35, by + hr * 0.05)], fill=robe + (255,), outline=ink)
        d.line([(cx - hr * 1.3, by + hr * 0.1), (cx + hr * 1.35, by + hr * 0.05)], fill=OCHRE + (255,), width=lw * 2)
        feather = [(cx + hr * 0.5, by - hr * 0.6), (cx + hr * 1.9, by - hr * 1.9), (cx + hr * 2.1, by - hr * 1.6), (cx + hr * 0.9, by - hr * 0.45)]
        d.polygon(feather, fill=(240, 234, 220, 255), outline=ink)
        for k in range(5):
            t = 0.2 + k * 0.15
            x = cx + hr * (0.6 + 1.3 * t)
            y = by - hr * (0.6 + 1.2 * t)
            d.line([(x, y), (x + hr * 0.2, y + hr * 0.12)], fill=ink, width=max(1, lw // 2))
        for side in (-1, 1):
            d.line([(cx, hy + hr * 0.55), (cx + side * hr * 0.5, hy + hr * 0.62)], fill=ink, width=lw * 2)
        sx = cx - fw * 0.36
        d.line([(sx, fh), (sx, fh * 0.12)], fill=(90, 66, 44, 255), width=lw * 3)
        d.polygon([(sx, fh * 0.02), (sx + fw * 0.07, fh * 0.14), (sx, fh * 0.2), (sx - fw * 0.05, fh * 0.12)], fill=(200, 196, 190, 255), outline=ink)

    put(img, glyph(sym, 0.085 * W, color), (fw * 0.13 if rank != 11 else fw * 0.87, fh * 0.16))
    return ink_texture(img, seed=rank * 7 + ord(suit), strength=0.12)


def face_card(rank, suit, seed):
    sym, color = SUITS[suit]
    img = base_card(seed)
    draw_index(img, rank, sym, color)
    half = figure_half(rank, suit)
    fx = int(0.2 * W)
    fy = int(0.125 * H)
    d = ImageDraw.Draw(img)
    # Hintergrund des Bildfelds: helles Ocker mit feinen Linien
    box = [fx, fy, fx + half.width, H - fy]
    d.rectangle(box, fill=(226, 208, 168, 255))
    for y in range(box[1], box[3], int(0.012 * W)):
        d.line([(box[0], y), (box[2], y)], fill=(196, 172, 128, 110), width=1)
    img.alpha_composite(half, (fx, fy))
    img.alpha_composite(half.rotate(180), (fx, int(H - fy - half.height)))
    d = ImageDraw.Draw(img)
    d.rectangle(box, outline=INK + (255,), width=int(0.007 * W))
    d.rectangle([box[0] + 8, box[1] + 8, box[2] - 8, box[3] - 8], outline=INK + (90,), width=2)
    d.line([(fx, H / 2), (fx + half.width, H / 2)], fill=INK + (255,), width=int(0.005 * W))
    return img


# --- Rückseiten ---------------------------------------------------------------------------

## id: (Grundfarbe, Musterfarbe, Motiv)
DECK_BACKS = {
    "hinterzimmer": ((92, 24, 30), (122, 40, 44), "diamond"),
    "bandit": ((58, 40, 28), (86, 60, 40), "mask"),
    "swamp_man": ((34, 56, 36), (54, 82, 50), "mushroom"),
    "crow": ((22, 18, 30), (48, 36, 64), "feather"),
    "wolf": ((70, 70, 76), (100, 96, 100), "claws"),
    "jester": ((54, 22, 64), (90, 40, 100), "harlequin"),
    "bone_man": ((24, 22, 22), (60, 56, 50), "skull"),
    "witch": ((44, 28, 70), (70, 50, 104), "moon"),
    "giant": ((96, 50, 24), (128, 72, 36), "stitches"),
    "zar": ((20, 18, 22), (120, 92, 40), "crown"),
    "kaufmann": ((24, 58, 52), (40, 86, 76), "coin"),
    "goldrand": ((120, 88, 30), (160, 122, 48), "sun"),
}
CREAM = (234, 222, 196)


def emblem(d, kind, cx, cy, r, ink, light):
    lw = max(3, int(r * 0.06))
    if kind == "diamond":
        d.polygon([(cx, cy - r * 0.8), (cx + r * 0.55, cy), (cx, cy + r * 0.8), (cx - r * 0.55, cy)], fill=ink)
        d.polygon([(cx, cy - r * 0.5), (cx + r * 0.32, cy), (cx, cy + r * 0.5), (cx - r * 0.32, cy)], fill=light)
    elif kind == "mask":
        d.chord([cx - r * 0.8, cy - r * 0.5, cx + r * 0.8, cy + r * 0.7], 180, 360, fill=ink)
        d.rectangle([cx - r * 0.8, cy + r * 0.08, cx + r * 0.8, cy + r * 0.32], fill=ink)
        for s in (-1, 1):
            d.ellipse([cx + s * r * 0.32 - r * 0.18, cy - r * 0.15, cx + s * r * 0.32 + r * 0.18, cy + r * 0.05], fill=light)
    elif kind == "mushroom":
        for dx, sc in ((-0.3, 0.7), (0.25, 1.0)):
            x = cx + dx * r
            d.rectangle([x - r * 0.1 * sc, cy - r * 0.1, x + r * 0.1 * sc, cy + r * 0.6 * sc], fill=ink)
            d.chord([x - r * 0.42 * sc, cy - r * 0.55 * sc, x + r * 0.42 * sc, cy + r * 0.2 * sc], 180, 360, fill=ink)
            d.ellipse([x - r * 0.1 * sc, cy - r * 0.32 * sc, x + r * 0.02 * sc, cy - r * 0.2 * sc], fill=light)
    elif kind == "feather":
        pts_l, pts_r = [], []
        for k in range(21):
            t = k / 20
            y = cy + r * 0.85 - t * r * 1.7
            w = math.sin(math.pi * min(1, t * 1.1)) * r * 0.32
            x = cx + math.sin(t * 2.2) * r * 0.12
            pts_l.append((x - w, y))
            pts_r.append((x + w, y))
        d.polygon(pts_l + pts_r[::-1], fill=ink)
        d.line([(cx, cy + r * 0.95), (cx + math.sin(2.2) * r * 0.12, cy - r * 0.85)], fill=light, width=lw)
        for k in range(1, 9):
            t = k / 10
            y = cy + r * 0.85 - t * r * 1.7
            d.line([(cx, y), (cx - r * 0.26, y - r * 0.12)], fill=light, width=max(1, lw // 3))
    elif kind == "claws":
        for k in (-1, 0, 1):
            x = cx + k * r * 0.3
            d.polygon([(x - r * 0.08, cy - r * 0.8), (x + r * 0.06, cy - r * 0.8), (x + r * 0.2 - k * 0.04 * r, cy + r * 0.8), (x + r * 0.1, cy + r * 0.82)], fill=ink)
    elif kind == "harlequin":
        for i in range(-2, 3):
            for j in range(-2, 3):
                if (i + j) % 2 == 0:
                    x, y = cx + i * r * 0.32, cy + j * r * 0.42
                    if abs(i * 0.32) + abs(j * 0.42) < 0.9:
                        d.polygon([(x, y - r * 0.21), (x + r * 0.16, y), (x, y + r * 0.21), (x - r * 0.16, y)], fill=ink)
        d.ellipse([cx - r * 0.12, cy + r * 0.62, cx + r * 0.12, cy + r * 0.86], fill=light, outline=ink, width=lw // 2)
    elif kind == "skull":
        d.ellipse([cx - r * 0.55, cy - r * 0.7, cx + r * 0.55, cy + r * 0.3], fill=ink)
        d.rounded_rectangle([cx - r * 0.35, cy + r * 0.1, cx + r * 0.35, cy + r * 0.62], radius=r * 0.1, fill=ink)
        for s in (-1, 1):
            d.ellipse([cx + s * r * 0.24 - r * 0.17, cy - r * 0.3, cx + s * r * 0.24 + r * 0.17, cy - r * 0.0], fill=light)
        d.polygon([(cx, cy + r * 0.05), (cx - r * 0.07, cy + r * 0.2), (cx + r * 0.07, cy + r * 0.2)], fill=light)
        for k in range(-2, 3):
            d.line([(cx + k * r * 0.12, cy + r * 0.35), (cx + k * r * 0.12, cy + r * 0.6)], fill=light, width=max(1, lw // 2))
    elif kind == "moon":
        d.ellipse([cx - r * 0.7, cy - r * 0.7, cx + r * 0.7, cy + r * 0.7], fill=ink)
        d.ellipse([cx - r * 0.42, cy - r * 0.82, cx + r * 0.92, cy + r * 0.52], fill=light)
        for (sx, sy, ss) in ((0.55, -0.55, 0.12), (0.7, 0.1, 0.08), (0.3, 0.55, 0.1)):
            x, y = cx + sx * r, cy + sy * r
            d.polygon([(x, y - ss * r), (x + ss * r * 0.3, y), (x, y + ss * r), (x - ss * r * 0.3, y)], fill=ink)
            d.polygon([(x - ss * r, y), (x, y - ss * r * 0.3), (x + ss * r, y), (x, y + ss * r * 0.3)], fill=ink)
    elif kind == "stitches":
        d.rounded_rectangle([cx - r * 0.6, cy - r * 0.75, cx + r * 0.6, cy + r * 0.75], radius=r * 0.3, fill=ink)
        d.line([(cx, cy - r * 0.75), (cx, cy + r * 0.75)], fill=light, width=lw)
        for k in range(6):
            y = cy - r * 0.6 + k * r * 0.24
            d.line([(cx - r * 0.12, y - r * 0.06), (cx + r * 0.12, y + r * 0.06)], fill=light, width=lw)
        for s in (-1, 1):
            d.line([(cx + s * r * 0.4, cy - r * 0.2), (cx + s * r * 0.18, cy - r * 0.15)], fill=light, width=lw)
    elif kind == "crown":
        pts = [(cx - r * 0.75, cy + r * 0.4), (cx - r * 0.8, cy - r * 0.45), (cx - r * 0.4, cy - r * 0.05), (cx, cy - r * 0.7),
               (cx + r * 0.4, cy - r * 0.05), (cx + r * 0.8, cy - r * 0.45), (cx + r * 0.75, cy + r * 0.4)]
        d.polygon(pts, fill=ink)
        d.rectangle([cx - r * 0.75, cy + r * 0.45, cx + r * 0.75, cy + r * 0.62], fill=ink)
        for jx in (-0.8, 0, 0.8):
            d.ellipse([cx + jx * r - r * 0.09, cy - r * (0.62 if jx else 0.88), cx + jx * r + r * 0.09, cy - r * (0.44 if jx else 0.7)], fill=ink)
    elif kind == "coin":
        d.ellipse([cx - r * 0.7, cy - r * 0.7, cx + r * 0.7, cy + r * 0.7], fill=ink)
        d.ellipse([cx - r * 0.55, cy - r * 0.55, cx + r * 0.55, cy + r * 0.55], outline=light, width=lw)
        put_text = glyph("₽", r * 0.7, light, FONT_SYM_B)
        return put_text
    elif kind == "sun":
        for k in range(16):
            a = k / 16 * math.tau
            d.polygon([(cx + math.cos(a - 0.1) * r * 0.45, cy + math.sin(a - 0.1) * r * 0.45),
                       (cx + math.cos(a) * r * (0.9 if k % 2 == 0 else 0.7), cy + math.sin(a) * r * (0.9 if k % 2 == 0 else 0.7)),
                       (cx + math.cos(a + 0.1) * r * 0.45, cy + math.sin(a + 0.1) * r * 0.45)], fill=ink)
        d.ellipse([cx - r * 0.42, cy - r * 0.42, cx + r * 0.42, cy + r * 0.42], fill=ink)
    return None


def back_card(deck_id):
    base, pattern, kind = DECK_BACKS[deck_id]
    img = aged_paper(W, H, CREAM, seed=hash(deck_id) % 997, stains=1)
    d = ImageDraw.Draw(img)
    m = int(0.055 * W)
    inner = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    idr = ImageDraw.Draw(inner)
    idr.rounded_rectangle([m, m, W - m, H - m], radius=int(0.035 * W), fill=base + (255,))
    # Muster: Rautengitter + kleine Punkte
    pat = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    pd = ImageDraw.Draw(pat)
    step = int(0.07 * W)
    for x in range(-H, W + H, step):
        pd.line([(x, 0), (x + H, H)], fill=pattern + (255,), width=int(0.004 * W))
        pd.line([(x, H), (x + H, 0)], fill=pattern + (255,), width=int(0.004 * W))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([m + 10, m + 10, W - m - 10, H - m - 10], radius=int(0.03 * W), fill=255)
    inner.paste(pat, (0, 0), Image.composite(pat.split()[3], Image.new("L", (W, H), 0), mask))
    img.alpha_composite(ink_texture(inner, seed=5, strength=0.18))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([m + 14, m + 14, W - m - 14, H - m - 14], radius=int(0.03 * W), outline=CREAM + (220,), width=int(0.006 * W))
    # Medaillon
    cx, cy, r = W / 2, H / 2, 0.24 * W
    med = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    md = ImageDraw.Draw(med)
    md.ellipse([cx - r * 1.12, cy - r * 1.12, cx + r * 1.12, cy + r * 1.12], fill=base + (255,), outline=CREAM + (255,), width=int(0.008 * W))
    md.ellipse([cx - r, cy - r, cx + r, cy + r], fill=CREAM + (255,), outline=base + (255,), width=int(0.006 * W))
    extra = emblem(md, kind, cx, cy, r * 0.78, base + (255,), CREAM + (255,))
    if extra is not None:
        put(med, extra, (cx, cy))
    img.alpha_composite(ink_texture(med, seed=9, strength=0.15))
    # Ecken-Ornamente
    for (x, y) in ((m + 0.09 * W, m + 0.09 * W), (W - m - 0.09 * W, m + 0.09 * W), (m + 0.09 * W, H - m - 0.09 * W), (W - m - 0.09 * W, H - m - 0.09 * W)):
        d.polygon([(x, y - 0.035 * W), (x + 0.022 * W, y), (x, y + 0.035 * W), (x - 0.022 * W, y)], fill=CREAM + (230,))
    return img


# --- Glaskarten / Ausgabe -------------------------------------------------------------------

def save(img, name):
    img = img.convert("RGB").resize((W // S, H // S), Image.LANCZOS)
    img.save(os.path.join(OUT, name + ".png"), optimize=True)


def glass_version(img):
    """Papier wird durchscheinend bläulich, Druck bleibt kräftig, dazu Lichtreflexe."""
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    paper = np.array(PAPER, dtype=np.float32)
    dist = np.sqrt(((a - paper) ** 2).sum(axis=2)) / 110.0
    ink = np.clip((dist - 0.25) * 1.6, 0.0, 1.0)
    h, w = ink.shape
    glass_rgb = np.array([205, 232, 250], dtype=np.float32)
    rgb = a * ink[..., None] + glass_rgb * (1 - ink[..., None])
    alpha = 0.22 + 0.78 * ink
    yy, xx = np.mgrid[0:h, 0:w]
    edge = np.minimum.reduce([xx, yy, w - 1 - xx, h - 1 - yy]).astype(np.float32)
    frost = np.clip(1.0 - edge / (0.06 * w), 0, 1)
    rgb = rgb * (1 - frost[..., None] * 0.6) + np.array([235, 247, 255]) * frost[..., None] * 0.6
    alpha = np.maximum(alpha, 0.55 * frost)
    for offset, width, strength in ((0.18, 0.05, 0.55), (0.30, 0.018, 0.4), (0.78, 0.03, 0.3)):
        d = (xx / w + yy / h * 0.6) - offset * 1.6
        band = np.clip(1 - np.abs(d) / width, 0, 1) ** 2 * strength
        rgb = rgb * (1 - band[..., None]) + 255 * band[..., None]
        alpha = np.maximum(alpha, band * 0.9)
    out = np.dstack([np.clip(rgb, 0, 255), np.clip(alpha * 255, 0, 255)]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def save_glass(img, name):
    os.makedirs(os.path.join(OUT, "glass"), exist_ok=True)
    small = img.convert("RGB").resize((W // S, H // S), Image.LANCZOS)
    glass_version(small).save(os.path.join(OUT, "glass", name + ".png"), optimize=True)


def main():
    import sys
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:]
    if not only or "faces" in only:
        seed = 0
        for suit in SUITS:
            for rank in range(6, 15):
                seed += 1
                if rank <= 10:
                    img = pip_card(rank, suit, seed)
                elif rank == 14:
                    img = ace_card(suit, seed)
                else:
                    img = face_card(rank, suit, seed)
                save(img, "%s_%d" % (suit, rank))
                save_glass(img, "%s_%d" % (suit, rank))
                print("  ", suit, rank)
    if not only or "backs" in only:
        os.makedirs(os.path.join(OUT, "backs"), exist_ok=True)
        for deck_id in DECK_BACKS:
            img = back_card(deck_id)
            save(img, os.path.join("backs", deck_id))
            if deck_id == "hinterzimmer":
                save(img, "back")
            print("   Rückseite", deck_id)
    print("Karten erzeugt in", OUT)


if __name__ == "__main__":
    main()
