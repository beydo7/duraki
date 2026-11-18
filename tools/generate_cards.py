#!/usr/bin/env python3
"""Erzeugt die Kartenbilder für Duraki (36er-Blatt + Rückseite).

Aufruf (aus dem Projektordner):
    python tools/generate_cards.py
Benötigt: Pillow und numpy  (pip install pillow numpy)

Ausgabe: assets/cards/<farbe>_<rang>.png, assets/cards/back.png
         assets/cards/glass/<farbe>_<rang>.png  (Glaskarten, durchscheinend)
  farbe: h = Herz, d = Karo, c = Kreuz, s = Pik
  rang:  6..14 (11 = Bube, 12 = Dame, 13 = König, 14 = Ass)

Alle Figuren sind eigene, einfache Zeichnungen aus Grundformen.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "cards")
FONT_SYM = os.path.join(ROOT, "assets", "fonts", "DejaVuSans.ttf")
FONT_BOLD = os.path.join(ROOT, "assets", "fonts", "DejaVuSans-Bold.ttf")

S = 2                      # Supersampling, am Ende wird verkleinert
W, H = 500 * S, 700 * S    # Seitenverhältnis 1 : 1.4 wie die 3D-Karte

PAPER = (246, 240, 226)
RED = (178, 34, 30)
BLACK = (24, 21, 20)
GOLD = (212, 160, 40)
BLUE = (46, 86, 150)
SKIN = (242, 214, 182)
FRAME_BG = (240, 228, 200)
LINE = (60, 50, 45)

SUITS = {"h": ("♥", RED), "d": ("♦", RED), "c": ("♣", BLACK), "s": ("♠", BLACK)}
RANK_TEXT = {6: "6", 7: "7", 8: "8", 9: "9", 10: "10", 11: "B", 12: "D", 13: "K", 14: "A"}

# Positionen der Symbole (x, y) relativ zur Karte, klassische Anordnung
L, C, R = 0.31, 0.5, 0.69
PIPS = {
    6: [(L, .22), (R, .22), (L, .5), (R, .5), (L, .78), (R, .78)],
    7: [(L, .22), (R, .22), (C, .36), (L, .5), (R, .5), (L, .78), (R, .78)],
    8: [(L, .22), (R, .22), (C, .36), (L, .5), (R, .5), (C, .64), (L, .78), (R, .78)],
    9: [(L, .22), (R, .22), (L, .407), (R, .407), (C, .5), (L, .593), (R, .593), (L, .78), (R, .78)],
    10: [(L, .22), (R, .22), (C, .315), (L, .407), (R, .407), (L, .593), (R, .593), (C, .685), (L, .78), (R, .78)],
}


def font(path, size):
    return ImageFont.truetype(path, int(size))


def draw_glyph(img, text, center, size, color, rotate=False, fnt=FONT_SYM):
    """Zeichnet ein Zeichen zentriert (optional um 180° gedreht)."""
    f = font(fnt, size)
    box = f.getbbox(text)
    w, h = box[2] - box[0], box[3] - box[1]
    tile = Image.new("RGBA", (w + 8, h + 8), (0, 0, 0, 0))
    ImageDraw.Draw(tile).text((4 - box[0], 4 - box[1]), text, font=f, fill=color)
    if rotate:
        tile = tile.rotate(180)
    img.alpha_composite(tile, (int(center[0] - tile.width / 2), int(center[1] - tile.height / 2)))


def draw_index(img, rank, sym, color):
    """Großer Index oben links und (gedreht) unten rechts."""
    for rotate in (False, True):
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        tx = RANK_TEXT[rank]
        size = 0.17 * W if len(tx) == 1 else 0.145 * W
        cx = 0.115 * W
        draw_glyph(layer, tx, (cx, 0.085 * H), size, color, fnt=FONT_BOLD)
        draw_glyph(layer, sym, (cx, 0.19 * H), 0.12 * W, color)
        if rotate:
            layer = layer.rotate(180)
        img.alpha_composite(layer)


def base_card():
    img = Image.new("RGBA", (W, H), PAPER + (255,))
    d = ImageDraw.Draw(img)
    m = 0.03 * W
    d.rounded_rectangle([m, m, W - m, H - m], radius=0.05 * W, outline=(210, 198, 170), width=int(0.008 * W))
    return img


def pip_card(rank, suit):
    sym, color = SUITS[suit]
    img = base_card()
    draw_index(img, rank, sym, color)
    size = 0.2 * W
    for (x, y) in PIPS[rank]:
        draw_glyph(img, sym, (x * W, y * H), size, color, rotate=y > 0.5)
    return img


def ace_card(suit):
    sym, color = SUITS[suit]
    img = base_card()
    draw_index(img, 14, sym, color)
    d = ImageDraw.Draw(img)
    # dekorativer Ring um das große Ass-Symbol
    r = 0.3 * W
    cx, cy = W / 2, H / 2
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=GOLD, width=int(0.012 * W))
    d.ellipse([cx - r * 0.9, cy - r * 0.9, cx + r * 0.9, cy + r * 0.9], outline=color, width=int(0.005 * W))
    draw_glyph(img, sym, (cx, cy), 0.42 * W, color)
    return img


# --- Bildkarten -------------------------------------------------------------------

def figure_half(rank, suit):
    """Obere Hälfte einer Bildkarte (wird gespiegelt für unten)."""
    sym, color = SUITS[suit]
    fw, fh = int(0.6 * W), int(0.38 * H)
    img = Image.new("RGBA", (fw, fh), FRAME_BG + (255,))
    d = ImageDraw.Draw(img)
    robe = RED if color == RED else BLUE
    trim = GOLD
    accent = BLACK if color == BLACK else (120, 20, 20)
    cx = fw * 0.5
    lw = max(2, int(0.006 * W))

    # Schultern / Gewand
    d.polygon([(cx - fw * 0.42, fh), (cx - fw * 0.30, fh * 0.62), (cx + fw * 0.30, fh * 0.62), (cx + fw * 0.42, fh)],
              fill=robe, outline=LINE)
    # Kragen + Muster
    d.polygon([(cx - fw * 0.17, fh * 0.62), (cx, fh * 0.80), (cx + fw * 0.17, fh * 0.62)], fill=trim, outline=LINE)
    for i in range(5):
        x = cx - fw * 0.36 + i * fw * 0.18
        d.ellipse([x - fw * 0.025, fh * 0.88 - fw * 0.025, x + fw * 0.025, fh * 0.88 + fw * 0.025], fill=trim, outline=LINE)
    d.line([(cx - fw * 0.40, fh * 0.80), (cx + fw * 0.40, fh * 0.80)], fill=trim, width=lw * 2)

    # Hals + Kopf
    hr = fw * 0.13
    hy = fh * 0.43
    d.rectangle([cx - hr * 0.35, hy + hr * 0.7, cx + hr * 0.35, fh * 0.64], fill=SKIN, outline=LINE)
    # Haare (Dame lang, Bube kurz, König mittel)
    hair = (110, 70, 30) if rank != 13 else (200, 200, 200)
    if rank == 12:
        d.rounded_rectangle([cx - hr * 1.25, hy - hr * 0.6, cx + hr * 1.25, hy + hr * 1.8], radius=hr, fill=hair, outline=LINE)
    else:
        d.ellipse([cx - hr * 1.1, hy - hr * 1.05, cx + hr * 1.1, hy + hr * 0.6], fill=hair, outline=LINE)
    d.ellipse([cx - hr, hy - hr, cx + hr, hy + hr * 1.05], fill=SKIN, outline=LINE, width=lw)
    # Gesicht
    for side in (-1, 1):
        ex = cx + side * hr * 0.38
        d.ellipse([ex - hr * 0.1, hy - hr * 0.12, ex + hr * 0.1, hy + hr * 0.08], fill=LINE)
        d.line([(ex - hr * 0.2, hy - hr * 0.3), (ex + hr * 0.18, hy - hr * 0.34)], fill=LINE, width=lw)
    d.line([(cx, hy), (cx - hr * 0.12, hy + hr * 0.38), (cx + hr * 0.05, hy + hr * 0.42)], fill=LINE, width=lw)
    d.arc([cx - hr * 0.35, hy + hr * 0.35, cx + hr * 0.35, hy + hr * 0.75], 20, 160, fill=(150, 40, 40), width=lw)

    if rank == 13:
        # König: Bart, Krone, Zepter
        d.polygon([(cx - hr * 0.8, hy + hr * 0.45), (cx, hy + hr * 1.6), (cx + hr * 0.8, hy + hr * 0.45),
                   (cx + hr * 0.4, hy + hr * 0.75), (cx - hr * 0.4, hy + hr * 0.75)], fill=(225, 225, 225), outline=LINE)
        base_y = hy - hr * 0.85
        pts = [(cx - hr * 1.05, base_y), (cx - hr * 1.15, base_y - hr * 0.9), (cx - hr * 0.55, base_y - hr * 0.45),
               (cx, base_y - hr * 1.15), (cx + hr * 0.55, base_y - hr * 0.45), (cx + hr * 1.15, base_y - hr * 0.9),
               (cx + hr * 1.05, base_y)]
        d.polygon(pts, fill=GOLD, outline=LINE)
        for jx in (-0.55, 0, 0.55):
            d.ellipse([cx + hr * jx - hr * 0.12, base_y - hr * 0.3, cx + hr * jx + hr * 0.12, base_y - hr * 0.06], fill=RED)
        sx = cx + fw * 0.33
        d.line([(sx, fh * 0.98), (sx, fh * 0.18)], fill=GOLD, width=lw * 3)
        d.ellipse([sx - fw * 0.04, fh * 0.12, sx + fw * 0.04, fh * 0.2], fill=GOLD, outline=LINE)
    elif rank == 12:
        # Dame: Diadem, Blume
        base_y = hy - hr * 0.85
        d.polygon([(cx - hr * 0.9, base_y + hr * 0.1), (cx - hr * 0.45, base_y - hr * 0.45), (cx, base_y - hr * 0.2),
                   (cx + hr * 0.45, base_y - hr * 0.45), (cx + hr * 0.9, base_y + hr * 0.1)], fill=GOLD, outline=LINE)
        d.ellipse([cx - hr * 0.13, base_y - hr * 0.5, cx + hr * 0.13, base_y - hr * 0.24], fill=BLUE)
        fx, fy = cx + fw * 0.3, fh * 0.6
        d.line([(fx, fh * 0.98), (fx, fy)], fill=(40, 110, 50), width=lw * 2)
        for k in range(6):
            import math
            a = k * math.pi / 3
            px, py = fx + math.cos(a) * fw * 0.04, fy + math.sin(a) * fw * 0.04
            d.ellipse([px - fw * 0.03, py - fw * 0.03, px + fw * 0.03, py + fw * 0.03], fill=RED if color == RED else (210, 120, 160))
        d.ellipse([fx - fw * 0.022, fy - fw * 0.022, fx + fw * 0.022, fy + fw * 0.022], fill=GOLD)
    else:
        # Bube: Mütze mit Feder, Hellebarde
        base_y = hy - hr * 0.7
        d.polygon([(cx - hr * 1.2, base_y + hr * 0.15), (cx - hr * 0.9, base_y - hr * 0.7), (cx + hr * 0.9, base_y - hr * 0.7),
                   (cx + hr * 1.2, base_y + hr * 0.15)], fill=robe, outline=LINE)
        d.line([(cx - hr * 1.2, base_y + hr * 0.15), (cx + hr * 1.2, base_y + hr * 0.15)], fill=GOLD, width=lw * 2)
        d.polygon([(cx + hr * 0.6, base_y - hr * 0.6), (cx + hr * 1.6, base_y - hr * 1.6), (cx + hr * 1.0, base_y - hr * 0.5)],
                  fill=(235, 235, 235), outline=LINE)
        sx = cx - fw * 0.33
        d.line([(sx, fh * 0.98), (sx, fh * 0.1)], fill=(110, 80, 50), width=lw * 3)
        d.polygon([(sx, fh * 0.04), (sx + fw * 0.06, fh * 0.16), (sx, fh * 0.22), (sx - fw * 0.06, fh * 0.16)],
                  fill=(190, 190, 200), outline=LINE)

    # kleines Farbsymbol neben dem Kopf
    draw_glyph(img, sym, (fw * 0.14 if rank != 11 else fw * 0.86, fh * 0.2), 0.1 * W, color)
    return img


def face_card(rank, suit):
    sym, color = SUITS[suit]
    img = base_card()
    draw_index(img, rank, sym, color)
    half = figure_half(rank, suit)
    fx = int(0.2 * W)
    fy = int(0.12 * H)
    img.alpha_composite(half, (fx, fy))
    img.alpha_composite(half.rotate(180), (fx, int(H - fy - half.height)))
    d = ImageDraw.Draw(img)
    d.rectangle([fx, fy, fx + half.width, H - fy], outline=LINE, width=int(0.008 * W))
    d.line([(fx, H / 2), (fx + half.width, H / 2)], fill=LINE, width=int(0.006 * W))
    return img


def back_card():
    img = Image.new("RGBA", (W, H), (233, 220, 192, 255))
    d = ImageDraw.Draw(img)
    m = int(0.06 * W)
    inner = (59, 42, 110)
    d.rounded_rectangle([m, m, W - m, H - m], radius=int(0.04 * W), fill=inner)
    # Rautengitter
    step = int(0.09 * W)
    col = (82, 62, 145)
    for x in range(-H, W + H, step):
        d.line([(x, m), (x + (H - 2 * m), H - m)], fill=col, width=int(0.006 * W))
        d.line([(x, H - m), (x + (H - 2 * m), m)], fill=col, width=int(0.006 * W))
    # Rand wiederherstellen
    frame = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frame)
    fd.rectangle([0, 0, W, m], fill=(233, 220, 192, 255))
    fd.rectangle([0, H - m, W, H], fill=(233, 220, 192, 255))
    fd.rectangle([0, 0, m, H], fill=(233, 220, 192, 255))
    fd.rectangle([W - m, 0, W, H], fill=(233, 220, 192, 255))
    img.alpha_composite(frame)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([m, m, W - m, H - m], radius=int(0.04 * W), outline=(233, 220, 192), width=int(0.012 * W))
    # Mittelmedaillon
    r = 0.17 * W
    d.ellipse([W / 2 - r, H / 2 - r, W / 2 + r, H / 2 + r], fill=(233, 220, 192), outline=(30, 22, 60), width=int(0.01 * W))
    draw_glyph(img, "◆", (W / 2, H / 2), 0.22 * W, (110, 40, 90))
    return img


def save(img, name):
    img = img.convert("RGB").resize((W // S, H // S), Image.LANCZOS)
    img.save(os.path.join(OUT, name + ".png"), optimize=True)


def glass_version(img):
    """Macht aus einer Karte eine Glaskarte: Papier wird durchscheinend
    blau, Symbole bleiben kräftig, dazu Lichtreflexe und mattierter Rand."""
    import numpy as np
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    paper = np.array(PAPER, dtype=np.float32)
    dist = np.sqrt(((a - paper) ** 2).sum(axis=2)) / 120.0
    ink = np.clip(dist, 0.0, 1.0)                      # 0 = Papier, 1 = Farbe
    h, w = ink.shape
    glass_rgb = np.array([205, 232, 250], dtype=np.float32)
    rgb = a * ink[..., None] + glass_rgb * (1 - ink[..., None])
    alpha = 0.22 + 0.78 * ink                          # Papier fast durchsichtig
    # mattierter Rand
    yy, xx = np.mgrid[0:h, 0:w]
    edge = np.minimum.reduce([xx, yy, w - 1 - xx, h - 1 - yy]).astype(np.float32)
    frost = np.clip(1.0 - edge / (0.06 * w), 0, 1)
    rgb = rgb * (1 - frost[..., None] * 0.6) + np.array([235, 247, 255]) * frost[..., None] * 0.6
    alpha = np.maximum(alpha, 0.55 * frost)
    # diagonale Lichtreflexe
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
    os.makedirs(OUT, exist_ok=True)
    for suit in SUITS:
        for rank in range(6, 15):
            if rank <= 10:
                img = pip_card(rank, suit)
            elif rank == 14:
                img = ace_card(suit)
            else:
                img = face_card(rank, suit)
            save(img, "%s_%d" % (suit, rank))
            save_glass(img, "%s_%d" % (suit, rank))
    save(back_card(), "back")
    print("Karten erzeugt in", OUT)


if __name__ == "__main__":
    main()
