#!/usr/bin/env python3
"""Erzeugt das Kartenblatt für Duraki im Stil „Okkult-Gold“.

Nachtblaue Karten mit leuchtender Goldlinie und Sternenstaub. Rote Farben (Herz, Karo)
in Korallenrot, schwarze Farben (Pik, Kreuz) in Gold. Bildkarten als doppelköpfige
Goldlinien-Figuren mit Heiligenschein, Asse mit Himmelsmotiven
(Herz = Sonne, Karo = Auge, Pik = Mond, Kreuz = Stern).

Aufruf (aus dem Projektordner):
    python tools/generate_cards.py            # alles
    python tools/generate_cards.py faces      # nur Vorderseiten (+ Glas)
    python tools/generate_cards.py backs      # nur Rückseiten
    python tools/generate_cards.py special    # nur Gold- und Glückskarten
Benötigt: Pillow und numpy  (pip install pillow numpy)

Ausgabe:
  assets/cards/<farbe>_<rang>.png         Vorderseiten
  assets/cards/glass/<farbe>_<rang>.png   Glaskarten (durchscheinend, Linien bleiben)
  assets/cards/gold/<farbe>_<rang>.png    Goldkarten („Blattgold“: vergoldet, Linien eingraviert)
  assets/cards/lucky/<farbe>_<rang>.png   Glückskarten (Kleeblätter in den freien Ecken)
  assets/cards/blank.png                   leere Vorderseite (Menükarten)
  assets/cards/back.png                    Standard-Rückseite (= Deck „hinterzimmer“)
  assets/cards/backs/<deck>.png            Rückseiten aller Decks (siehe DECK_BACKS)
    farbe: h = Herz, d = Karo, c = Kreuz, s = Pik
    rang:  6..14 (11 = Bube/J, 12 = Dame, 13 = König, 14 = Ass)

Alle Motive sind eigene Zeichnungen aus Grundformen (keine fremden Vorlagen).
Schriften: Cinzel Decorative (OFL), DejaVu Sans (frei).
"""
import math
import os
import random
import zlib

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "cards")
FONTS = os.path.join(ROOT, "assets", "fonts")
FONT_SYM = os.path.join(FONTS, "DejaVuSans.ttf")
FONT_SYM_B = os.path.join(FONTS, "DejaVuSans-Bold.ttf")
FONT_IDX = os.path.join(FONTS, "CinzelDecorative-Bold.ttf")

S = 2                      # Supersampling, am Ende wird verkleinert
W, H = 500 * S, 700 * S    # Seitenverhältnis 1 : 1.4 wie die 3D-Karte

NAVY_TOP = (27, 24, 52)
NAVY_BOT = (11, 10, 24)
PANEL = (34, 30, 66)
ROBE = (40, 34, 78)
ROBE_DARK = (26, 22, 52)
SKIN = (58, 52, 96)
GOLD = (236, 200, 124)
GOLD_DIM = (168, 136, 82)
CORAL = (242, 98, 92)
STAR = (206, 196, 255)

SUITS = {"h": ("♥", CORAL), "d": ("♦", CORAL), "c": ("♣", GOLD), "s": ("♠", GOLD)}
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


def rgba(c, a=255):
    return tuple(c[:3]) + (int(a),)


def layer(w=W, h=H):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def glow(img, radius, strength=0.8):
    """Weiches Leuchten einer Linienebene (wird darunter gelegt)."""
    g = img.filter(ImageFilter.GaussianBlur(radius))
    a = np.asarray(g).astype(np.float32)
    a[..., 3] *= strength
    return Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")


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


def bez(p0, p1, p2, p3, n=28):
    pts = []
    for i in range(n + 1):
        t = i / n
        a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
        pts.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
    return pts


def star4(d, cx, cy, r, col):
    """Vierzackiger Funkelstern."""
    k = r * 0.22
    d.polygon([(cx, cy - r), (cx + k, cy - k), (cx + r, cy), (cx + k, cy + k), (cx, cy + r), (cx - k, cy + k), (cx - r, cy), (cx - k, cy - k)], fill=col)


def background(seed, top=NAVY_TOP, bot=NAVY_BOT, stars=70):
    """Nachtblauer Verlauf mit feinem Korn, Vignette und Sternenstaub."""
    rng = np.random.RandomState(seed)
    t = np.linspace(0, 1, H)[:, None, None]
    a = np.array(top, np.float32) * (1 - t) + np.array(bot, np.float32) * t
    a = np.broadcast_to(a, (H, W, 3)).copy()
    yy, xx = np.mgrid[0:H, 0:W]
    dist = np.sqrt(((xx - W / 2) / W) ** 2 + ((yy - H * 0.45) / H) ** 2)
    a *= (1.08 - 0.55 * np.clip(dist, 0, 1) ** 1.6)[..., None]
    noise = rng.normal(0, 3.0, (H // 2, W // 2)).repeat(2, 0).repeat(2, 1)
    a += noise[..., None]
    img = Image.fromarray(a.clip(0, 255).astype(np.uint8)).convert("RGBA")
    d = ImageDraw.Draw(img)
    r = random.Random(seed)
    for _ in range(stars):
        x, y = r.uniform(0.04, 0.96) * W, r.uniform(0.04, 0.96) * H
        s = r.uniform(0.6, 1.8) * S
        d.ellipse([x - s, y - s, x + s, y + s], fill=rgba(STAR, r.randint(50, 130)))
    return img


def frame(d, col=GOLD):
    m1, m2 = 0.035 * W, 0.052 * W
    d.rounded_rectangle([m1, m1, W - m1, H - m1], radius=0.03 * W, outline=rgba(col, 190), width=int(0.0045 * W))
    d.rounded_rectangle([m2, m2, W - m2, H - m2], radius=0.022 * W, outline=rgba(col, 95), width=int(0.0025 * W))
    for x, y in ((m2, m2), (W - m2, m2), (m2, H - m2), (W - m2, H - m2)):
        star4(d, x, y, 0.016 * W, rgba(col, 230))
    star4(d, W / 2, m1 + (m2 - m1) / 2, 0.012 * W, rgba(col, 200))
    star4(d, W / 2, H - m1 - (m2 - m1) / 2, 0.012 * W, rgba(col, 200))


def draw_index(art, rank, sym, color):
    tile = layer(int(0.2 * W), int(0.26 * W))
    d = ImageDraw.Draw(tile)
    tx = RANK_TEXT[rank]
    f = font(FONT_IDX, (0.1 if len(tx) > 1 else 0.125) * W)
    d.text((tile.width / 2, 0.075 * W), tx, font=f, fill=rgba(color), anchor="mm")
    put(tile, glyph(sym, 0.085 * W, rgba(color)), (tile.width / 2, 0.19 * W))
    pos = (0.115 * W, 0.185 * W)
    put(art, tile, pos)
    put(art, tile, (W - pos[0], H - pos[1]), rotate=True)


def compose(bg, art, glow_r=6, glow_s=0.75):
    out = bg.copy()
    out.alpha_composite(glow(art, glow_r * S, glow_s))
    out.alpha_composite(art)
    return out


def sacred(d, cx, cy, r, col, alpha=40):
    """Feine Ringe und Hexagramm hinter den Zahlen (kaum sichtbar)."""
    for k, rr in enumerate((r, r * 0.93, r * 0.55)):
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=rgba(col, alpha if k != 1 else alpha * 0.6), width=max(1, int(0.002 * W)))
    for off in (0, math.pi):
        pts = [(cx + r * 0.93 * math.cos(off + -math.pi / 2 + i * 2 * math.pi / 3), cy + r * 0.93 * math.sin(off + -math.pi / 2 + i * 2 * math.pi / 3)) for i in range(3)]
        d.line(pts + [pts[0]], fill=rgba(col, alpha * 0.8), width=max(1, int(0.002 * W)))


# --- Zahlenkarten --------------------------------------------------------------------

def pip_card(rank, suit, seed):
    sym, col = SUITS[suit]
    art = layer()
    d = ImageDraw.Draw(art)
    frame(d)
    sacred(d, W / 2, H / 2, 0.3 * W, GOLD, 34)
    draw_index(art, rank, sym, col)
    tile = glyph(sym, 0.15 * W, rgba(col))
    for (u, v) in PIPS[rank]:
        put(art, tile, (0.12 * W + u * 0.76 * W, 0.08 * H + v * 0.84 * H), rotate=v > 0.5)
    return background(seed), art


# --- Asse -----------------------------------------------------------------------------

def ace_card(suit, seed):
    sym, col = SUITS[suit]
    art = layer()
    d = ImageDraw.Draw(art)
    frame(d)
    draw_index(art, 14, sym, col)
    cx, cy = W / 2, H * 0.5
    lw = int(0.004 * W)
    g = rgba(GOLD)
    if suit == "h":   # Sonne
        r = 0.2 * W
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=g, width=lw)
        d.ellipse([cx - r * 0.9, cy - r * 0.9, cx + r * 0.9, cy + r * 0.9], outline=rgba(GOLD, 110), width=max(1, lw // 2))
        for k in range(32):
            a = k * math.pi / 16
            r2 = r * (1.55 if k % 2 == 0 else 1.3)
            if k % 4 == 0:
                d.polygon([(cx + math.cos(a) * r2, cy + math.sin(a) * r2),
                           (cx + math.cos(a + 0.05) * r * 1.08, cy + math.sin(a + 0.05) * r * 1.08),
                           (cx + math.cos(a - 0.05) * r * 1.08, cy + math.sin(a - 0.05) * r * 1.08)], fill=g)
            else:
                d.line([(cx + math.cos(a) * r * 1.1, cy + math.sin(a) * r * 1.1), (cx + math.cos(a) * r2, cy + math.sin(a) * r2)], fill=g, width=max(1, lw // 2))
        put(art, glyph(sym, 0.26 * W, rgba(col)), (cx, cy + 0.01 * W))
    elif suit == "d":  # Auge
        r = 0.27 * W
        top = bez((cx - r, cy), (cx - r * 0.45, cy - r * 0.62), (cx + r * 0.45, cy - r * 0.62), (cx + r, cy))
        bot = bez((cx + r, cy), (cx + r * 0.45, cy + r * 0.62), (cx - r * 0.45, cy + r * 0.62), (cx - r, cy))
        d.line(top + bot, fill=g, width=lw, joint="curve")
        ri = r * 0.36
        d.ellipse([cx - ri, cy - ri, cx + ri, cy + ri], outline=g, width=lw)
        put(art, glyph(sym, 0.17 * W, rgba(col)), (cx, cy + 0.005 * W))
        for k in range(13):
            a = math.pi + (k + 1) * math.pi / 14
            d.line([(cx + math.cos(a) * r * 0.72, cy - 0.04 * W + math.sin(a) * r * 0.72),
                    (cx + math.cos(a) * r * (1.05 if k % 2 else 1.18), cy - 0.04 * W + math.sin(a) * r * (1.05 if k % 2 else 1.18))], fill=g, width=max(1, lw // 2))
        for k in range(7):
            a = (k + 1) * math.pi / 8
            d.line([(cx + math.cos(a) * r * 0.75, cy + 0.04 * W + math.sin(a) * r * 0.75),
                    (cx + math.cos(a) * r * 0.98, cy + 0.04 * W + math.sin(a) * r * 0.98)], fill=rgba(GOLD, 120), width=max(1, lw // 2))
    elif suit == "s":  # Mond
        r = 0.23 * W
        moon = layer()
        md = ImageDraw.Draw(moon)
        md.ellipse([cx - r, cy - r, cx + r, cy + r], fill=g)
        md.ellipse([cx - r * 0.72, cy - r * 1.02, cx + r * 1.15, cy + r * 0.86], fill=(0, 0, 0, 0))
        art.alpha_composite(moon)
        put(art, glyph(sym, 0.22 * W, rgba(GOLD)), (cx + 0.06 * W, cy + 0.015 * W))
        rr = random.Random(3)
        for k in range(7):
            a = -2.4 + k * 0.55
            star4(d, cx + math.cos(a) * r * 1.5, cy + math.sin(a) * r * 1.45, (0.012 + rr.random() * 0.012) * W, g)
        d.text((cx, H * 0.79), "DURAKI", font=font(FONT_IDX, 0.07 * W), fill=g, anchor="mm")
    else:  # Kreuz: Stern
        r = 0.26 * W
        for rot in (0, math.pi / 4):
            pts = []
            for k in range(8):
                a = rot + k * math.pi / 4
                rr = r if k % 2 == 0 else r * 0.38
                pts.append((cx + math.cos(a - math.pi / 2) * rr, cy + math.sin(a - math.pi / 2) * rr))
            d.line(pts + [pts[0]], fill=g if rot == 0 else rgba(GOLD, 140), width=lw if rot == 0 else max(1, lw // 2), joint="curve")
        ri = r * 0.42
        d.ellipse([cx - ri, cy - ri, cx + ri, cy + ri], fill=rgba(NAVY_BOT), outline=g, width=lw)
        put(art, glyph(sym, 0.17 * W, rgba(col)), (cx, cy + 0.003 * W))
    return background(seed), art


# --- Bildkarten ----------------------------------------------------------------------

def figure_half(rank, suit, w, h):
    """Obere Hälfte einer doppelköpfigen Figur (Goldlinien auf Nachtblau)."""
    sym, col = SUITS[suit]
    img = layer(w, h)
    d = ImageDraw.Draw(img)
    lw = max(2, int(0.0042 * W))
    thin = max(1, int(0.0024 * W))
    g = rgba(GOLD)

    def P(u, v):
        return (u * w, v * h)

    # Heiligenschein mit Strahlen
    hc, hr = P(0.5, 0.36), 0.25 * w
    d.ellipse([hc[0] - hr, hc[1] - hr, hc[0] + hr, hc[1] + hr], outline=rgba(GOLD, 120), width=thin)
    d.ellipse([hc[0] - hr * 0.94, hc[1] - hr * 0.94, hc[0] + hr * 0.94, hc[1] + hr * 0.94], outline=rgba(GOLD, 60), width=thin)
    for k in range(36):
        a = k * math.pi / 18
        if math.sin(a) > 0.55:
            continue
        r1, r2 = hr * 1.04, hr * (1.16 if k % 2 else 1.26)
        d.line([(hc[0] + math.cos(a) * r1, hc[1] + math.sin(a) * r1), (hc[0] + math.cos(a) * r2, hc[1] + math.sin(a) * r2)], fill=rgba(GOLD, 120), width=thin)

    # Gewand: Schultern als Kurven bis zum unteren Rand
    left = bez(P(0.04, 1.0), P(0.06, 0.8), P(0.2, 0.68), P(0.42, 0.64))
    right = bez(P(0.58, 0.64), P(0.8, 0.68), P(0.94, 0.8), P(0.96, 1.0))
    robe = left + right + [P(0.96, 1.0), P(0.04, 1.0)]
    d.polygon(robe, fill=rgba(ROBE))
    # Muster im Gewand: feine Rautenschraffur
    pat = layer(w, h)
    pd = ImageDraw.Draw(pat)
    step = int(0.05 * w)
    for x in range(-h, w + h, step):
        pd.line([(x, 0), (x + h, h)], fill=rgba(GOLD, 38), width=thin)
        pd.line([(x, h), (x + h, 0)], fill=rgba(GOLD, 38), width=thin)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).polygon(robe, fill=255)
    img.paste(pat, (0, 0), Image.composite(pat.split()[3], Image.new("L", (w, h), 0), mask))
    d = ImageDraw.Draw(img)
    d.line(robe[:-2], fill=g, width=lw, joint="curve")
    # Kragen / Brustlatz mit Edelsteinen
    collar = [P(0.36, 0.66), P(0.64, 0.66), P(0.6, 0.78), P(0.5, 0.86), P(0.4, 0.78)]
    d.polygon(collar, fill=rgba(ROBE_DARK), outline=g)
    d.line(collar + [collar[0]], fill=g, width=thin)
    for k, (u, v) in enumerate(((0.43, 0.7), (0.5, 0.74), (0.57, 0.7), (0.5, 0.81))):
        c = P(u, v)
        rr = 0.013 * w
        d.ellipse([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], fill=rgba(col if k == 1 else GOLD))
    # Saum mit Perlen
    d.line([P(0.08, 0.95), P(0.92, 0.95)], fill=g, width=thin)
    for k in range(15):
        c = P(0.1 + k * 0.057, 0.975)
        rr = 0.008 * w
        d.ellipse([c[0] - rr, c[1] - rr, c[0] + rr, c[1] + rr], fill=rgba(GOLD, 200))

    # Hals + Kopf
    d.rectangle([P(0.46, 0.55)[0], P(0.46, 0.55)[1], P(0.54, 0.66)[0], P(0.54, 0.66)[1]], fill=rgba(SKIN))
    d.line([P(0.46, 0.56), P(0.46, 0.65)], fill=g, width=thin)
    d.line([P(0.54, 0.56), P(0.54, 0.65)], fill=g, width=thin)
    head = [P(0.395, 0.38), P(0.605, 0.6)]
    if rank == 12:
        # Zöpfe hinter dem Kopf
        for s in (-1, 1):
            x0 = 0.5 + s * 0.105
            pts = []
            for k in range(9):
                v = 0.42 + k * 0.035
                pts.append(P(x0 + s * 0.02 * (1 if k % 2 else -1), v))
            d.line(pts, fill=g, width=lw * 2, joint="curve")
            d.line(pts, fill=rgba(ROBE_DARK), width=lw, joint="curve")
            end = P(x0, 0.74)
            d.ellipse([end[0] - 0.015 * w, end[1] - 0.015 * w, end[0] + 0.015 * w, end[1] + 0.015 * w], fill=rgba(col))
    d.ellipse(head, fill=rgba(SKIN), outline=g, width=lw)
    # Gesicht
    for s in (-1, 1):
        ex = 0.5 + s * 0.045
        eye = bez(P(ex - 0.028, 0.475), P(ex - 0.01, 0.458), P(ex + 0.01, 0.458), P(ex + 0.028, 0.475), 10) + \
            bez(P(ex + 0.028, 0.475), P(ex + 0.01, 0.488), P(ex - 0.01, 0.488), P(ex - 0.028, 0.475), 10)
        d.line(eye, fill=g, width=thin)
        c = P(ex, 0.474)
        d.ellipse([c[0] - 0.007 * w, c[1] - 0.007 * w, c[0] + 0.007 * w, c[1] + 0.007 * w], fill=g)
        brow = bez(P(ex - 0.035, 0.448), P(ex - 0.01, 0.435), P(ex + 0.015, 0.438), P(ex + 0.035, 0.447), 10)
        d.line(brow, fill=g, width=thin)
    d.line(bez(P(0.5, 0.48), P(0.495, 0.51), P(0.49, 0.525), P(0.505, 0.532), 8), fill=g, width=thin)

    if rank == 13:  # König: Krone, Bart, Zepter
        crown = [P(0.39, 0.4), P(0.39, 0.29), P(0.43, 0.34), P(0.465, 0.25), P(0.5, 0.32), P(0.535, 0.25), P(0.57, 0.34), P(0.61, 0.29), P(0.61, 0.4)]
        d.polygon(crown, fill=rgba(ROBE_DARK))
        d.line(crown + [crown[0]], fill=g, width=lw, joint="curve")
        d.line([P(0.39, 0.385), P(0.61, 0.385)], fill=g, width=thin)
        for u in (0.465, 0.535):
            c = P(u, 0.25)
            d.ellipse([c[0] - 0.013 * w, c[1] - 0.013 * w, c[0] + 0.013 * w, c[1] + 0.013 * w], fill=g)
        c = P(0.5, 0.36)
        d.ellipse([c[0] - 0.016 * w, c[1] - 0.016 * w, c[0] + 0.016 * w, c[1] + 0.016 * w], fill=rgba(col))
        beard = bez(P(0.405, 0.52), P(0.4, 0.62), P(0.45, 0.7), P(0.5, 0.74), 16) + bez(P(0.5, 0.74), P(0.55, 0.7), P(0.6, 0.62), P(0.595, 0.52), 16)
        d.polygon(beard, fill=rgba(ROBE_DARK))
        d.line(beard, fill=g, width=lw, joint="curve")
        for k in range(4):
            u = 0.44 + k * 0.04
            d.line(bez(P(u, 0.56), P(u - 0.01, 0.62), P(u + 0.01, 0.66), P(u, 0.7), 10), fill=rgba(GOLD, 150), width=thin)
        d.line(bez(P(0.44, 0.545), P(0.47, 0.53), P(0.53, 0.53), P(0.56, 0.545), 10), fill=g, width=lw)
        # Zepter
        d.line([P(0.83, 0.2), P(0.83, 1.0)], fill=g, width=lw)
        c = P(0.83, 0.17)
        d.ellipse([c[0] - 0.035 * w, c[1] - 0.035 * w, c[0] + 0.035 * w, c[1] + 0.035 * w], outline=g, width=lw, fill=rgba(ROBE_DARK))
        star4(d, c[0], c[1], 0.022 * w, rgba(col))
        for v in (0.4, 0.6, 0.8):
            c = P(0.83, v)
            d.ellipse([c[0] - 0.012 * w, c[1] - 0.012 * w, c[0] + 0.012 * w, c[1] + 0.012 * w], fill=g)
    elif rank == 12:  # Dame: Kokoschnik, Kerze
        kok = bez(P(0.36, 0.42), P(0.33, 0.2), P(0.67, 0.2), P(0.64, 0.42), 30)
        d.polygon(kok + [P(0.6, 0.4), P(0.4, 0.4)], fill=rgba(ROBE_DARK))
        d.line(kok, fill=g, width=lw, joint="curve")
        inner = bez(P(0.4, 0.4), P(0.38, 0.26), P(0.62, 0.26), P(0.6, 0.4), 20)
        d.line(inner, fill=rgba(GOLD, 160), width=thin)
        for k in range(9):
            t = (k + 1) / 10
            idx = int(t * (len(kok) - 1))
            c = kok[idx]
            d.ellipse([c[0] - 0.009 * w, c[1] - 0.009 * w, c[0] + 0.009 * w, c[1] + 0.009 * w], fill=rgba(GOLD, 230))
        c = P(0.5, 0.3)
        d.polygon([(c[0], c[1] - 0.03 * w), (c[0] + 0.02 * w, c[1]), (c[0], c[1] + 0.03 * w), (c[0] - 0.02 * w, c[1])], fill=rgba(col))
        d.line(bez(P(0.47, 0.555), P(0.49, 0.565), P(0.51, 0.565), P(0.53, 0.555), 8), fill=rgba(col), width=lw)
        # Kerze links
        d.rectangle([P(0.135, 0.42)[0], P(0.135, 0.42)[1], P(0.175, 0.9)[0], P(0.175, 0.9)[1]], fill=rgba(ROBE_DARK), outline=g, width=thin)
        d.line([P(0.155, 0.42), P(0.155, 0.39)], fill=g, width=thin)
        fl = bez(P(0.155, 0.27), P(0.19, 0.33), P(0.18, 0.39), P(0.155, 0.395), 12) + bez(P(0.155, 0.395), P(0.13, 0.39), P(0.12, 0.33), P(0.155, 0.27), 12)
        d.polygon(fl, fill=rgba(col))
        d.line([P(0.1, 0.9), P(0.21, 0.9)], fill=g, width=lw)
    else:  # Bube: Pelzmütze mit Feder, Hellebarde
        hat = [P(0.37, 0.41), P(0.37, 0.3), P(0.4, 0.26), P(0.6, 0.26), P(0.63, 0.3), P(0.63, 0.41)]
        d.polygon(hat, fill=rgba(ROBE_DARK))
        d.line(hat + [hat[0]], fill=g, width=lw, joint="curve")
        for k in range(10):
            u = 0.385 + k * 0.026
            d.line([P(u, 0.36), P(u + 0.01, 0.41)], fill=rgba(GOLD, 140), width=thin)
        d.line([P(0.37, 0.36), P(0.63, 0.36)], fill=g, width=thin)
        feather = bez(P(0.6, 0.28), P(0.68, 0.18), P(0.74, 0.1), P(0.8, 0.06), 20)
        d.line(feather, fill=g, width=lw)
        for k in range(2, 19, 2):
            x, y = feather[k]
            d.line([(x, y), (x + 0.03 * w, y + 0.025 * w)], fill=rgba(GOLD, 170), width=thin)
            d.line([(x, y), (x - 0.02 * w, y - 0.03 * w)], fill=rgba(GOLD, 170), width=thin)
        c = P(0.6, 0.29)
        d.ellipse([c[0] - 0.014 * w, c[1] - 0.014 * w, c[0] + 0.014 * w, c[1] + 0.014 * w], fill=rgba(col))
        d.line(bez(P(0.46, 0.545), P(0.48, 0.535), P(0.52, 0.535), P(0.54, 0.545), 8), fill=g, width=thin)
        # Hellebarde rechts... links
        d.line([P(0.16, 0.14), P(0.16, 1.0)], fill=g, width=lw)
        blade = [P(0.16, 0.06), P(0.2, 0.16), P(0.16, 0.2), P(0.12, 0.16)]
        d.polygon(blade, fill=rgba(ROBE_DARK))
        d.line(blade + [blade[0]], fill=g, width=lw, joint="curve")
        axe = bez(P(0.16, 0.22), P(0.25, 0.2), P(0.27, 0.3), P(0.16, 0.32), 12)
        d.polygon(axe, fill=rgba(ROBE_DARK))
        d.line(axe, fill=g, width=lw)
        c = P(0.16, 0.36)
        d.ellipse([c[0] - 0.012 * w, c[1] - 0.012 * w, c[0] + 0.012 * w, c[1] + 0.012 * w], fill=rgba(col))
    return img


def face_card(rank, suit, seed):
    sym, col = SUITS[suit]
    art = layer()
    d = ImageDraw.Draw(art)
    frame(d)
    draw_index(art, rank, sym, col)
    x0, y0, x1, y1 = int(0.225 * W), int(0.12 * H), int(0.775 * W), int(0.88 * H)
    pw, ph = x1 - x0, y1 - y0
    # Feld der Figur: etwas helleres Blau mit Goldrahmen
    panel = Image.new("RGBA", (pw, ph), rgba(PANEL, 170))
    pm = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(pm).rounded_rectangle([0, 0, pw - 1, ph - 1], radius=int(0.02 * W), fill=255)
    art.paste(panel, (x0, y0), pm)
    d = ImageDraw.Draw(art)
    half = figure_half(rank, suit, pw, ph // 2)
    fig = layer(pw, ph)
    fig.alpha_composite(half, (0, 0))
    fig.alpha_composite(half.rotate(180), (0, ph - half.height))
    m = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, pw - 1, ph - 1], radius=int(0.02 * W), fill=255)
    art.paste(fig, (x0, y0), Image.fromarray(np.minimum(np.asarray(fig.split()[3]), np.asarray(m))))
    d = ImageDraw.Draw(art)
    d.rounded_rectangle([x0, y0, x1, y1], radius=int(0.02 * W), outline=rgba(GOLD), width=int(0.004 * W))
    # Mittellinie mit Farbsymbol
    cy = (y0 + y1) / 2
    d.line([(x0, cy), (x1, cy)], fill=rgba(GOLD, 200), width=int(0.003 * W))
    d.ellipse([W / 2 - 0.045 * W, cy - 0.045 * W, W / 2 + 0.045 * W, cy + 0.045 * W], fill=rgba(NAVY_BOT), outline=rgba(GOLD), width=int(0.003 * W))
    put(art, glyph(sym, 0.06 * W, rgba(col)), (W / 2, cy))
    return background(seed), art


# --- Rückseiten --------------------------------------------------------------------------

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


def _mix(a, b, t):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


def back_card(deck_id):
    base, pattern, kind = DECK_BACKS[deck_id]
    # Deckfarbe in das Nachtblau mischen, damit alle Rückseiten zur Familie gehören
    top = _mix(NAVY_TOP, base, 0.55)
    bot = _mix(NAVY_BOT, base, 0.3)
    img = background(zlib.crc32(deck_id.encode()) % 997, top, bot, stars=40)
    gold = GOLD if deck_id != "goldrand" else (255, 222, 150)
    art = layer()
    d = ImageDraw.Draw(art)
    frame(d, gold)
    # Sternengitter
    m = 0.075 * W
    step = 0.1 * W
    lat = layer()
    ld = ImageDraw.Draw(lat)
    for x in np.arange(-H, W + H, step):
        ld.line([(x, 0), (x + H, H)], fill=rgba(gold, 55), width=max(1, int(0.0022 * W)))
        ld.line([(x, H), (x + H, 0)], fill=rgba(gold, 55), width=max(1, int(0.0022 * W)))
    for iy in range(-1, int(H / step) + 2):
        for ix in range(-1, int(W / step) + 2):
            x = ix * step + (step / 2 if iy % 2 else 0)
            y = iy * step * 0.5 + W * 0.02
            star4(ld, x, y, 0.009 * W, rgba(gold, 130))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([m, m, W - m, H - m], radius=0.02 * W, fill=255)
    art.paste(lat, (0, 0), Image.fromarray(np.minimum(np.asarray(lat.split()[3]), np.asarray(mask))))
    d = ImageDraw.Draw(art)
    # Medaillon
    cx, cy, r = W / 2, H / 2, 0.25 * W
    med_fill = rgba(_mix(bot, (0, 0, 0), 0.35))
    for k in range(48):
        a = k * math.pi / 24
        r2 = r * (1.32 if k % 2 == 0 else 1.2)
        d.line([(cx + math.cos(a) * r * 1.08, cy + math.sin(a) * r * 1.08), (cx + math.cos(a) * r2, cy + math.sin(a) * r2)], fill=rgba(gold, 170), width=max(1, int(0.0025 * W)))
    d.ellipse([cx - r * 1.05, cy - r * 1.05, cx + r * 1.05, cy + r * 1.05], fill=med_fill, outline=rgba(gold), width=int(0.005 * W))
    d.ellipse([cx - r * 0.95, cy - r * 0.95, cx + r * 0.95, cy + r * 0.95], outline=rgba(gold, 120), width=max(1, int(0.0025 * W)))
    em = layer()
    extra = emblem(ImageDraw.Draw(em), kind, cx, cy, r * 0.66, rgba(gold), med_fill)
    if extra is not None:
        put(em, extra, (cx, cy))
    art.alpha_composite(em)
    return compose(img, art, 5, 0.6)


# --- Glaskarten / Ausgabe -------------------------------------------------------------------

def save(img, name):
    img = img.convert("RGB").resize((W // S, H // S), Image.LANCZOS)
    img.save(os.path.join(OUT, name + ".png"), optimize=True)


def glass_version(art, suit="s"):
    """Glaskarte wie bei Balatro: eigener heller, grau-blauer Glasgrund mit schrägen
    Lichtbändern; Linien und Symbole werden dunkel (Schiefer, bei Herz/Karo gedecktes Rot).
    Undurchsichtig – auf dem Filz soll sie nicht weiß verschwinden."""
    w, h = W // S, H // S
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    a = np.zeros((h, w, 4), np.float32)
    a[..., :3] = (176, 190, 194)
    a[..., 3] = 255
    # schräge helle Bänder (breit, schmal, breit) wie Lichtreflexe auf Glas
    for offset, width, strength in ((0.12, 0.09, 0.55), (0.36, 0.035, 0.45), (0.62, 0.11, 0.5), (0.9, 0.04, 0.4)):
        d = (xx / w * 0.9 + yy / h * 0.75) - offset * 1.65
        band = (np.abs(d) < width).astype(np.float32) * strength
        a[..., :3] = a[..., :3] * (1 - band[..., None]) + np.array((228, 236, 238)) * band[..., None]
    # dunkler Rand und feine helle Innenkante
    edge = np.minimum.reduce([xx, yy, w - 1 - xx, h - 1 - yy])
    a[..., :3] = np.where((edge < 0.018 * w)[..., None], np.array((70, 88, 92)), a[..., :3])
    inner = (edge >= 0.018 * w) & (edge < 0.026 * w)
    a[..., :3] = np.where(inner[..., None], np.array((236, 242, 243)), a[..., :3])
    glass = Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")
    small = np.array(art.resize((w, h), Image.LANCZOS)).astype(np.float32)
    ink = np.array((150, 64, 66) if suit in ("h", "d") else (52, 70, 74), np.float32)
    lines = np.zeros_like(small)
    lines[..., :3] = ink
    # helle Linien (Gold, Koralle) voll dunkel, dunkle Flächen (z. B. Bildfelder) nur zart getönt
    lum = small[..., :3] @ np.array((0.299, 0.587, 0.114), np.float32)
    lines[..., 3] = small[..., 3] * np.clip(lum / 150.0, 0.18, 1.0)
    glass.alpha_composite(Image.fromarray(lines.clip(0, 255).astype(np.uint8), "RGBA"))
    return glass


# --- Gold- und Glückskarten ------------------------------------------------------------

GOLD_LEAF_TOP = (222, 178, 92)
GOLD_LEAF_BOT = (146, 102, 40)
ENGRAVE = (22, 20, 44)
DEEP_RED = (156, 26, 34)  # Herz/Karo auf Gold kräftiger, sonst zu blass
CLOVER = (92, 214, 120)


def gold_version(art, seed):
    """Blattgold: ganze Karte vergoldet mit feinem Craquelé und Glanzband,
    die goldenen Linien werden dunkel „eingraviert“, Korallenrot wird tiefrot."""
    bg = background(seed, GOLD_LEAF_TOP, GOLD_LEAF_BOT, stars=0)
    d = ImageDraw.Draw(bg)
    r = random.Random(seed)
    for _ in range(90):
        x, y = r.uniform(0, W), r.uniform(0, H)
        pts = [(x, y)]
        for _ in range(r.randint(2, 5)):
            x += r.uniform(-30, 30) * S
            y += r.uniform(-30, 30) * S
            pts.append((x, y))
        d.line(pts, fill=(120, 82, 30, 70), width=2)
    a = np.asarray(bg).astype(np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    band = np.clip(1 - np.abs((xx / W + yy / H * 0.7) - 0.75) / 0.12, 0, 1) ** 2
    a[..., :3] += band[..., None] * 60
    bg = Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGBA")
    ar = np.asarray(art).astype(np.float32)
    rr, gg, bb = ar[..., 0], ar[..., 1], ar[..., 2]
    goldish = (rr > 120) & (gg > 90) & (bb < 170) & (gg > bb + 25)
    coral = (rr > 180) & (gg < 150) & (bb < 150)
    for i in range(3):
        ar[..., i] = np.where(goldish, ENGRAVE[i], ar[..., i])
        ar[..., i] = np.where(coral, DEEP_RED[i], ar[..., i])
    bg.alpha_composite(Image.fromarray(ar.clip(0, 255).astype(np.uint8), "RGBA"))
    return bg


def _leaf(cx, cy, size, ang):
    """Herzförmiges Kleeblatt-Blatt, Spitze bei (cx, cy), in Richtung ang (Grad)."""
    pts = []
    for side in (-1, 1):
        seg = bez((0, 0), (side * 0.55, -0.35), (side * 0.75, -0.95), (side * 0.32, -1.0))
        seg += bez((side * 0.32, -1.0), (side * 0.12, -1.0), (side * 0.02, -0.9), (0, -0.78))
        pts.append(seg if side < 0 else list(reversed(seg)))
    a = math.radians(ang)
    return [(cx + x * size * math.cos(a) - y * size * math.sin(a), cy + x * size * math.sin(a) + y * size * math.cos(a))
            for x, y in pts[0] + pts[1]]


def clover(size, color, stem=True):
    """Vierblättriges Kleeblatt aus vier Herzblättern (Spitzen zur Mitte)."""
    ss = size * 2
    tile = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    d = ImageDraw.Draw(tile)
    c = ss / 2
    leaf = ss * 0.24
    dark = tuple(int(v * 0.6) for v in color[:3])
    if stem:
        pts = bez((c, c), (c + ss * 0.04, c + ss * 0.16), (c + ss * 0.14, c + ss * 0.28), (c + ss * 0.22, c + ss * 0.42))
        d.line(pts, fill=rgba(color), width=max(2, int(ss * 0.035)), joint="curve")
    for k in range(4):
        ang = 45 + k * 90
        d.polygon(_leaf(c, c, leaf, ang), fill=rgba(color))
        a = math.radians(ang)
        d.line([(c, c), (c + math.sin(a) * leaf * 0.7, c - math.cos(a) * leaf * 0.7)], fill=rgba(dark), width=max(1, int(ss * 0.008)))
    d.ellipse([c - ss * 0.03, c - ss * 0.03, c + ss * 0.03, c + ss * 0.03], fill=rgba(dark))
    return tile.resize((size, size), Image.LANCZOS)


def lucky_version(bg, art):
    """Klee-Ecken: Kartenbild bleibt, Kleeblätter in den beiden freien Ecken,
    grüne Innenlinie und kleine Kleeblätter oben/unten am Rahmen."""
    art = art.copy()
    big = clover(int(0.22 * W), CLOVER)
    put(art, big, (W - 0.13 * W, 0.16 * W))
    put(art, big, (0.13 * W, H - 0.16 * W), rotate=True)
    d = ImageDraw.Draw(art)
    m = 0.07 * W
    d.rounded_rectangle([m, m, W - m, H - m], radius=0.02 * W, outline=rgba(CLOVER, 120), width=int(0.004 * W))
    small = clover(int(0.06 * W), CLOVER, False)
    for x, y in ((W / 2, 0.043 * W), (W / 2, H - 0.043 * W)):
        put(art, small, (x, y))
    return compose(bg, art)


def blank_card():
    """Leere Vorderseite (Rahmen, Sterne, feine Ringe) für die Menükarten im Hauptmenü."""
    art = layer()
    d = ImageDraw.Draw(art)
    frame(d)
    sacred(d, W / 2, H * 0.42, 0.3 * W, GOLD, 40)
    return compose(background(99), art)


def save_card(bg, art, name):
    save(compose(bg, art), name)
    os.makedirs(os.path.join(OUT, "glass"), exist_ok=True)
    glass_version(art, name[0]).save(os.path.join(OUT, "glass", name + ".png"), optimize=True)


def save_special(bg, art, name, seed):
    """Gold- und Glücksversion einer Karte."""
    for folder in ("gold", "lucky"):
        os.makedirs(os.path.join(OUT, folder), exist_ok=True)
    save(gold_version(art, seed), os.path.join("gold", name))
    save(lucky_version(bg, art), os.path.join("lucky", name))


def main():
    import sys
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:]
    if not only or "faces" in only or "special" in only:
        faces = not only or "faces" in only
        seed = 0
        for suit in SUITS:
            for rank in range(6, 15):
                seed += 1
                if rank <= 10:
                    bg, art = pip_card(rank, suit, seed)
                elif rank == 14:
                    bg, art = ace_card(suit, seed)
                else:
                    bg, art = face_card(rank, suit, seed)
                if faces:
                    save_card(bg, art, "%s_%d" % (suit, rank))
                save_special(bg, art, "%s_%d" % (suit, rank), seed)
                print("  ", suit, rank)
        if faces:
            save(blank_card(), "blank")
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
