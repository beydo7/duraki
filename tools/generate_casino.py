#!/usr/bin/env python3
"""Texturen und Geräusche für den Raum „Altes Casino“ (ohne Blender).

    python3 tools/generate_casino.py

Schreibt nach assets/rooms/casino/:
  wallpaper.png   dunkelrote Damast-Tapete (kachelbar)
  carpet.png      Casino-Teppich: Ornamente auf Dunkelblau (kachelbar)
  roulette.png    Draufsicht des kleinen Roulettes (Fächer rot/schwarz, grüne Null)
  reels.png       Walzenband des Spielautomaten (7, Kirsche, Glocke, BAR, Zitrone)
  slot_pull.wav   Hebel ziehen (Ratsche + Klacken)
  slot_spin.wav   Walzen laufen und rasten nacheinander ein
  slot_win.wav    Gewinn: Glocke und klimpernde Münzen
  roulette.wav    Kugel rollt leise im Kessel und wird langsamer
  roulette_land.wav  Kugel hüpft über die Stege und bleibt im Fach liegen
  roulette_tick.wav  leiser Klick beim Anstupsen (Easter Egg: 5× klicken)
"""
import math
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "rooms" / "casino"
FONTS = ROOT / "assets" / "fonts"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_sfx as sx  # noqa: E402  (Klang-Bausteine wiederverwenden)


def font(name, size):
    return ImageFont.truetype(str(FONTS / name), size)


# --- Texturen ---------------------------------------------------------------------

def tile_draw(size, draw_fn):
    """Motiv an allen Kachelrändern wiederholen, damit die Textur nahtlos ist."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for dx in (-size, 0, size):
        for dy in (-size, 0, size):
            draw_fn(ImageDraw.Draw(img), dx, dy)
    return img


def wallpaper():
    S = 512
    base = Image.new("RGB", (S, S), (92, 14, 24))
    rng = np.random.default_rng(3)
    noise = (rng.normal(0, 6, (S, S))).astype(np.int16)
    arr = np.array(base, np.int16) + noise[..., None]
    base = Image.fromarray(arr.clip(0, 255).astype(np.uint8))

    def motif(d, dx, dy):
        for cx, cy in ((128, 128), (384, 384)):
            cx += dx
            cy += dy
            col = (128, 30, 38, 255)
            gold = (150, 98, 52, 190)
            # Damast-Lilie: Rauten, Bögen und Blätter
            d.polygon([(cx, cy - 92), (cx + 46, cy), (cx, cy + 92), (cx - 46, cy)], outline=gold, width=4)
            d.ellipse([cx - 22, cy - 22, cx + 22, cy + 22], fill=col, outline=gold, width=3)
            for s in (-1, 1):
                d.arc([cx + s * 18 - 48, cy - 80, cx + s * 18 + 48, cy + 10], 200 if s < 0 else -20, 340 if s < 0 else 160, fill=gold, width=4)
                d.ellipse([cx + s * 60 - 14, cy - 14, cx + s * 60 + 14, cy + 14], fill=col)
                d.line([(cx, cy + 30), (cx + s * 40, cy + 70)], fill=gold, width=3)
                d.ellipse([cx + s * 40 - 9, cy + 62, cx + s * 40 + 9, cy + 80], fill=gold)
            d.ellipse([cx - 7, cy - 112, cx + 7, cy - 96], fill=gold)
            d.ellipse([cx - 7, cy + 96, cx + 7, cy + 112], fill=gold)
        # kleine Rauten dazwischen
        for cx, cy in ((384, 128), (128, 384)):
            cx += dx
            cy += dy
            d.polygon([(cx, cy - 20), (cx + 14, cy), (cx, cy + 20), (cx - 14, cy)], fill=(122, 26, 34, 255))

    layer = tile_draw(S, motif).filter(ImageFilter.GaussianBlur(0.8))
    base = base.convert("RGBA")
    base.alpha_composite(layer)
    return base.convert("RGB")


def carpet():
    S = 512
    base = Image.new("RGB", (S, S), (18, 20, 44))
    rng = np.random.default_rng(7)
    arr = np.array(base, np.int16) + rng.normal(0, 7, (S, S, 1)).astype(np.int16)
    base = Image.fromarray(arr.clip(0, 255).astype(np.uint8)).convert("RGBA")

    def motif(d, dx, dy):
        red, gold, teal = (150, 26, 40, 255), (196, 150, 64, 255), (30, 96, 104, 255)
        for cx, cy in ((128, 128), (384, 384), (384, 128), (128, 384)):
            big = (cx + cy) % 512 == 256
            cx += dx
            cy += dy
            if big:
                d.ellipse([cx - 70, cy - 70, cx + 70, cy + 70], outline=gold, width=8)
                for k in range(8):
                    a = k * math.pi / 4
                    x, y = cx + math.cos(a) * 46, cy + math.sin(a) * 46
                    d.ellipse([x - 16, y - 16, x + 16, y + 16], fill=red)
                d.ellipse([cx - 22, cy - 22, cx + 22, cy + 22], fill=teal, outline=gold, width=4)
            else:
                d.polygon([(cx, cy - 40), (cx + 40, cy), (cx, cy + 40), (cx - 40, cy)], outline=red, width=7)
                d.ellipse([cx - 10, cy - 10, cx + 10, cy + 10], fill=gold)
        # Ranken-Linien
        for k in range(0, 512, 128):
            d.line([(k + dx, dy), (k + 128 + dx, 128 + dy)], fill=(40, 46, 86, 255), width=3)

    base.alpha_composite(tile_draw(S, motif).filter(ImageFilter.GaussianBlur(1.0)))
    return base.convert("RGB")


ROULETTE_ORDER = [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10,
                  5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]
REDS = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36}


def roulette():
    S = 1024
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S / 2
    n = len(ROULETTE_ORDER)
    f = font("RussoOne-Regular.ttf", 30)
    # Holzrand außen
    d.ellipse([0, 0, S - 1, S - 1], fill=(96, 50, 24, 255))
    d.ellipse([22, 22, S - 23, S - 23], fill=(64, 32, 16, 255))
    # Zahlenring und Fächer
    for i, num in enumerate(ROULETTE_ORDER):
        a0 = 360 * i / n - 90 - 180 / n
        a1 = a0 + 360 / n
        col = (24, 120, 60) if num == 0 else ((196, 22, 34) if num in REDS else (18, 16, 18))
        d.pieslice([60, 60, S - 61, S - 61], a0, a1, fill=col + (255,))
        # Fächer innen (etwas dunkler)
        d.pieslice([200, 200, S - 201, S - 201], a0, a1, fill=tuple(int(v * 0.7) for v in col) + (255,))
        # Zahl
        am = math.radians((a0 + a1) / 2)
        tx, ty = c + math.cos(am) * 400, c + math.sin(am) * 400
        txt = Image.new("RGBA", (60, 40), (0, 0, 0, 0))
        ImageDraw.Draw(txt).text((30, 20), str(num), font=f, fill=(240, 228, 200, 255), anchor="mm")
        txt = txt.rotate(-math.degrees(am) - 90, expand=True, resample=Image.BICUBIC)
        img.alpha_composite(txt, (int(tx - txt.width / 2), int(ty - txt.height / 2)))
    # Stege zwischen den Fächern (gold)
    for i in range(n):
        a = math.radians(360 * i / n - 90 - 180 / n)
        d.line([(c + math.cos(a) * 200, c + math.sin(a) * 200), (c + math.cos(a) * 360, c + math.sin(a) * 360)],
               fill=(210, 168, 80, 255), width=5)
    d.ellipse([352, 352, S - 353, S - 353], outline=(210, 168, 80, 255), width=6)
    # Mitte: Holz-Kegel mit goldenen Speichen
    d.ellipse([200, 200, S - 201, S - 201], outline=(210, 168, 80, 255), width=6)
    d.ellipse([300, 300, S - 301, S - 301], fill=(120, 66, 30, 255))
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        d.line([(c, c), (c + math.cos(a) * 160, c + math.sin(a) * 160)], fill=(226, 184, 92, 255), width=14)
    d.ellipse([c - 36, c - 36, c + 36, c + 36], fill=(230, 190, 96, 255))
    return img


def reels():
    """Ein Walzenband, 5 Symbole übereinander (u läuft rundherum)."""
    W, H = 256, 1280
    img = Image.new("RGB", (W, H), (244, 238, 222))
    d = ImageDraw.Draw(img)
    f7 = font("RussoOne-Regular.ttf", 170)
    fbar = font("RussoOne-Regular.ttf", 70)
    for k in range(5):
        y0 = k * 256
        cy = y0 + 128
        d.line([(0, y0), (W, y0)], fill=(200, 190, 170), width=4)
        if k == 0:  # rote 7
            d.text((W / 2, cy + 6), "7", font=f7, fill=(206, 22, 34), anchor="mm", stroke_width=6, stroke_fill=(120, 10, 16))
        elif k == 1:  # Kirschen
            d.line([(100, cy + 30), (140, cy - 60)], fill=(40, 110, 40), width=10)
            d.line([(170, cy + 24), (140, cy - 60)], fill=(40, 110, 40), width=10)
            d.ellipse([60, cy + 10, 140, cy + 90], fill=(196, 16, 30))
            d.ellipse([132, cy + 4, 212, cy + 84], fill=(214, 24, 40))
            d.ellipse([80, cy + 24, 100, cy + 44], fill=(255, 160, 160))
            d.polygon([(140, cy - 60), (190, cy - 80), (170, cy - 50)], fill=(60, 140, 50))
        elif k == 2:  # Glocke
            d.pieslice([58, cy - 90, 198, cy + 70], 180, 360, fill=(236, 176, 40))
            d.rectangle([58, cy - 10, 198, cy + 50], fill=(236, 176, 40))
            d.rectangle([44, cy + 44, 212, cy + 64], fill=(206, 146, 24))
            d.ellipse([110, cy + 56, 146, cy + 92], fill=(150, 100, 20))
            d.line([(90, cy - 50), (90, cy + 30)], fill=(255, 230, 150), width=10)
        elif k == 3:  # BAR
            d.rounded_rectangle([30, cy - 46, 226, cy + 46], 12, fill=(20, 18, 22))
            d.text((W / 2, cy + 2), "BAR", font=fbar, fill=(244, 238, 222), anchor="mm")
        else:  # Zitrone
            d.ellipse([54, cy - 60, 202, cy + 60], fill=(250, 214, 40), outline=(210, 170, 20), width=6)
            d.ellipse([86, cy - 40, 120, cy - 16], fill=(255, 240, 150))
    return img


# --- Geräusche ---------------------------------------------------------------------

def save_wav(name, x, peak=0.85):
    import wave
    x = np.asarray(x, np.float64)
    m = np.max(np.abs(x)) or 1.0
    x = (x / m * peak * 32767).astype(np.int16)
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sx.SR)
        w.writeframes(x.tobytes())
    print("geschrieben:", OUT / name)


def slot_pull():
    buf = np.zeros(int(0.8 * sx.SR))
    # Ratsche beim Herunterziehen
    for k in range(9):
        sx.place(buf, sx.clack(2600 - k * 120, 0.025), 0.03 + k * 0.045, 0.5)
    sx.place(buf, sx.whoosh(0.35, 300, 900), 0.0, 0.25)
    sx.place(buf, sx.clack(900, 0.08), 0.45, 1.0)  # Anschlag unten
    sx.place(buf, sx.clack(1400, 0.05), 0.62, 0.6)  # Hebel federt zurück
    return sx.reverb(buf, 0.25, 0.15)


def slot_spin():
    dur = 2.4
    buf = np.zeros(int(dur * sx.SR))
    # schnelles Rattern der drei Walzen, nacheinander anhalten
    tt = 0.0
    while tt < 2.0:
        sx.place(buf, sx.clack(3000 + (hash(round(tt, 3)) % 400), 0.012), tt, 0.25)
        tt += 0.028 + tt * 0.008
    for k, at in enumerate((1.0, 1.5, 2.0)):
        sx.place(buf, sx.clack(700 + k * 90, 0.07), at, 1.0)
    hum = np.sin(2 * np.pi * 110 * sx.t(2.0)) * sx.env(int(2.0 * sx.SR), 0.05, 1.6, 0.4) * 0.12
    sx.place(buf, hum, 0.0, 1.0)
    return sx.reverb(buf, 0.2, 0.12)


def slot_win():
    buf = np.zeros(int(2.2 * sx.SR))
    for k, f in enumerate((1568, 1976, 2349, 3136)):
        sx.place(buf, sx.chime(f, 0.9), k * 0.1, 0.5)
    rng = np.random.default_rng(5)
    for k in range(26):  # Münzen klimpern in die Schale
        sx.place(buf, sx.chime(2600 + rng.uniform(-500, 900), 0.18), 0.45 + k * 0.05 + rng.uniform(0, 0.02), 0.28)
    return sx.reverb(buf, 0.3, 0.2)


def roulette_sound():
    """Kugel rollt leise im Kessel und wird langsamer (weich, nicht schrill)."""
    dur = 3.8
    n = int(dur * sx.SR)
    roll = sx.lowpass(np.random.default_rng(9).normal(0, 1, n), 1100)
    tt = sx.t(dur)
    # Rollgeräusch: kurz einblenden, dann langsam leiser; leichtes Pulsieren (Kugel kreist)
    rate = np.linspace(4.5, 1.6, n)
    pulse = 0.75 + 0.25 * np.sin(2 * np.pi * np.cumsum(rate) / sx.SR)
    roll *= np.minimum(tt / 0.15, 1.0) * np.linspace(0.7, 0.0, n) ** 1.4 * pulse
    return sx.reverb(sx.lowpass(roll, 1400), 0.18, 0.08)


def roulette_land():
    """Kugel hüpft knapp 2 s über die Stege und bleibt im Fach liegen (weiche Klicks).
    Zeiten passen zu MiniRoulette: BOUNCE_TIME 1.9 s, 6 Sprünge, Aufprall bei t = T·√(k/6)."""
    T, hops = 1.9, 6
    buf = np.zeros(int(2.4 * sx.SR))
    sx.place(buf, sx.lowpass(sx.clack(1400, 0.04), 2800), 0.0, 0.85)  # trifft auf die Stege
    for k in range(1, hops):
        at = T * (k / hops) ** 0.5
        g = 0.75 * (1 - k / (hops + 1)) + 0.12
        sx.place(buf, sx.lowpass(sx.clack(1300 - k * 40, 0.04), 2600), at, g)
    sx.place(buf, sx.lowpass(sx.clack(900, 0.06), 2000), T, 0.4)  # liegt im Fach
    return sx.reverb(buf, 0.2, 0.1)


def roulette_tick():
    """Leiser Holzklick, wenn man den Kessel nur anstupst."""
    buf = np.zeros(int(0.25 * sx.SR))
    sx.place(buf, sx.lowpass(sx.clack(800, 0.05), 2200), 0.0, 1.0)
    return sx.reverb(buf, 0.12, 0.06)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    wallpaper().save(OUT / "wallpaper.png")
    carpet().save(OUT / "carpet.png")
    roulette().save(OUT / "roulette.png")
    reels().save(OUT / "reels.png")
    print("Texturen geschrieben:", OUT)
    save_wav("slot_pull.wav", slot_pull())
    save_wav("slot_spin.wav", slot_spin())
    save_wav("slot_win.wav", slot_win())
    save_wav("roulette.wav", roulette_sound(), 0.6)
    save_wav("roulette_land.wav", roulette_land(), 0.6)
    save_wav("roulette_tick.wav", roulette_tick(), 0.5)
