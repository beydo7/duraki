#!/usr/bin/env python3
"""Texturen und Geräusche für den Raum „Zirkuswagen“ (ohne Blender).

    python3 tools/generate_circus.py

Schreibt nach assets/rooms/circus/:
  boards.png       bunt gestrichene Holzbretter (rot/creme/blau, kachelbar)
  floor.png        abgetretene Holzdielen (kachelbar)
  tent.png         Zeltbahn rot/weiß gestreift (für den Blick durch den Vorhang)
  poster.png       Zirkusplakat „ZIRKUS DURAKI“
  music.wav        gedämpfte Zirkusmusik aus dem Zelt (Schleife, 8 s)
  applause.wav     Applaus und Lachen aus der Ferne
  pop.wav          Luftballon platzt
  musicbox.wav     Spieluhr-Melodie
  wind.wav         Spieluhr wird aufgezogen (Ratschen)
  boing.wav        Springteufel schnellt heraus
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "rooms" / "circus"
FONT = ROOT / "assets" / "fonts" / "RussoOne-Regular.ttf"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_sfx as sx  # noqa: E402


def _noise(w, h, cw, ch, seed):
    rng = np.random.default_rng(seed)
    return np.asarray(Image.fromarray((rng.random((ch, cw)) * 255).astype(np.uint8))
                      .resize((w, h), Image.BICUBIC)).astype(np.float32) / 255


def boards():
    """Senkrechte Bretter, abwechselnd rot, creme und blau, mit Maserung und abgeplatzter Farbe."""
    W, H = 512, 512
    cols = [(150, 36, 32), (222, 205, 168), (40, 64, 120), (222, 205, 168)]
    n = 8
    bw = W // n
    grain = 0.88 + 0.12 * _noise(W, H, 64, 6, 1)
    arr = np.zeros((H, W, 3), np.float32)
    for i in range(n):
        arr[:, i * bw:(i + 1) * bw] = cols[i % len(cols)]
    arr *= grain[..., None]
    chip = np.clip(_noise(W, H, 40, 40, 2) - 0.84, 0, 1) * 5  # abgeplatzte Farbe → Holz
    wood = np.array([120, 84, 52], np.float32)
    arr = arr * (1 - chip[..., None]) + wood * chip[..., None]
    img = Image.fromarray(arr.clip(0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    for i in range(n):
        d.line([(i * bw, 0), (i * bw, H)], fill=(40, 26, 18), width=3)
    for i in range(n):  # Nägel oben und unten
        for y in (20, H - 20):
            x = i * bw + bw // 2
            d.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(60, 56, 52))
    return img.filter(ImageFilter.GaussianBlur(0.4))


def floor():
    W, H = 512, 512
    n = 6
    bh = H // n
    rng = np.random.default_rng(5)
    arr = np.zeros((H, W, 3), np.float32)
    for i in range(n):
        tone = 0.8 + 0.2 * rng.random()
        arr[i * bh:(i + 1) * bh] = np.array([112, 76, 46], np.float32) * tone
    arr *= (0.85 + 0.15 * _noise(W, H, 4, 80, 6))[..., None]
    img = Image.fromarray(arr.clip(0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    for i in range(n):
        d.line([(0, i * bh), (W, i * bh)], fill=(40, 26, 16), width=3)
        x = int(rng.random() * W)
        d.line([(x, i * bh), (x, (i + 1) * bh)], fill=(50, 32, 20), width=2)
    return img


def tent():
    W, H = 512, 512
    img = Image.new("RGB", (W, H), (230, 220, 200))
    d = ImageDraw.Draw(img)
    n = 8
    for i in range(0, n, 2):
        d.rectangle([i * W // n, 0, (i + 1) * W // n, H], fill=(170, 30, 30))
    arr = np.asarray(img).astype(np.float32) * (0.85 + 0.15 * _noise(W, H, 8, 8, 9))[..., None]
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8))


def poster():
    W, H = 512, 720
    img = Image.new("RGB", (W, H), (232, 214, 170))
    d = ImageDraw.Draw(img)
    for k in range(16):  # Strahlen
        a0 = k * np.pi / 8
        a1 = a0 + np.pi / 16
        c = (W / 2, H * 0.55)
        R = 700
        d.polygon([c, (c[0] + np.cos(a0) * R, c[1] + np.sin(a0) * R),
                   (c[0] + np.cos(a1) * R, c[1] + np.sin(a1) * R)], fill=(214, 170, 90))
    d.rectangle([0, 0, W, 150], fill=(160, 28, 28))
    d.rectangle([0, H - 110, W, H], fill=(28, 28, 32))
    try:
        f_big = ImageFont.truetype(str(FONT), 86)
        f_mid = ImageFont.truetype(str(FONT), 46)
        f_s = ImageFont.truetype(str(FONT), 34)
    except OSError:
        f_big = f_mid = f_s = None
    if f_big:
        d.text((W / 2, 78), "ZIRKUS", font=f_big, fill=(244, 230, 190), anchor="mm")
        d.text((W / 2, H - 56), "DURAKI", font=f_mid, fill=(244, 196, 70), anchor="mm")
        d.text((W / 2, H * 0.3), "HEUTE ABEND", font=f_s, fill=(28, 28, 32), anchor="mm")
    d.ellipse([W / 2 - 110, H * 0.55 - 110, W / 2 + 110, H * 0.55 + 110], outline=(160, 28, 28), width=10)
    arr = np.asarray(img).astype(np.float32) * (0.82 + 0.18 * _noise(W, H, 10, 14, 11))[..., None]
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))


# --- Geräusche --------------------------------------------------------------------

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


def _note(freq, dur, kind="organ"):
    tt = sx.t(dur)
    if kind == "organ":
        x = (np.sin(2 * np.pi * freq * tt) + 0.5 * np.sin(2 * np.pi * freq * 2 * tt)
             + 0.25 * np.sign(np.sin(2 * np.pi * freq * tt)) * 0.3)
        return x * sx.env(len(tt), 0.01, dur * 0.9, 0.6)
    if kind == "box":  # Spieluhr: hell, kurz, glockig
        x = np.sin(2 * np.pi * freq * tt) + 0.3 * np.sin(2 * np.pi * freq * 3.01 * tt)
        return x * sx.env(len(tt), 0.002, 0.5)
    if kind == "bass":
        return np.sin(2 * np.pi * freq * tt) * sx.env(len(tt), 0.005, dur * 0.6)
    raise ValueError(kind)


def _hz(semis):
    return 440.0 * 2 ** (semis / 12)


def music():
    """Kleiner Zirkusmarsch (Umpa-Umpa), dumpf wie durch die Zeltwand, genau 8 s."""
    bpm = 120
    beat = 60 / bpm
    dur = 8.0
    buf = np.zeros(int(dur * sx.SR))
    # Melodie (Halbtöne relativ zu A4), je ein Achtel
    mel = [3, 7, 10, 15, 14, 10, 7, 10, 12, 8, 5, 8, 12, 15, 12, 8,
           3, 7, 10, 15, 17, 15, 14, 12, 10, 7, 3, 7, 10, 10, 3, None]
    for i, s in enumerate(mel):
        if s is not None:
            sx.place(buf, _note(_hz(s), beat * 0.5), i * beat * 0.5, 0.5)
    roots = [-9, -9, -16, -16, -14, -14, -9, -9]  # Umpa: Bass auf 1, Akkord auf 2
    for bar in range(8):
        sx.place(buf, _note(_hz(roots[bar] - 12), beat * 0.5, "bass"), bar * beat * 2, 0.9)
        for k in (0, 4, 7):
            sx.place(buf, _note(_hz(roots[bar] + k), beat * 0.4), bar * beat * 2 + beat, 0.18)
    x = sx.lowpass(buf, 1100)  # durch die Zeltwand
    return sx.reverb(x, 0.6, 0.3)[: len(buf)]


def applause():
    dur = 3.5
    n = int(dur * sx.SR)
    rng = np.random.default_rng(12)
    buf = np.zeros(n)
    for _ in range(900):  # viele einzelne Klatscher
        at = rng.random() * (dur - 0.1)
        sx.place(buf, sx.bandpass(rng.normal(0, 1, int(0.02 * sx.SR)), 800, 4000)
                 * sx.env(int(0.02 * sx.SR), 0.001, 0.012), at, rng.uniform(0.3, 1.0))
    for _ in range(5):  # Lacher (kurze gleitende Töne)
        at = rng.uniform(0.3, 2.5)
        tt = sx.t(0.5)
        f = rng.uniform(220, 320) * (1 + 0.2 * np.sin(2 * np.pi * 7 * tt))
        ha = np.sin(2 * np.pi * np.cumsum(f) / sx.SR) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 6 * tt)))
        sx.place(buf, ha * sx.env(len(tt), 0.02, 0.3), at, 0.25)
    shape = np.minimum(1, np.minimum(sx.t(dur) / 0.4, (dur - sx.t(dur)) / 1.6))
    return sx.reverb(sx.lowpass(buf * shape, 3000), 0.6, 0.35)


def pop():
    n = int(0.35 * sx.SR)
    x = np.random.default_rng(4).normal(0, 1, n) * sx.env(n, 0.0005, 0.04)
    sx.place(x, sx.thud(220, 90, 0.2), 0.0, 0.5)
    return sx.reverb(sx.highpass(x, 300), 0.3, 0.2)


def musicbox():
    """Die Spieluhr: kurze Walzermelodie, glockig, 4 s."""
    beat = 0.32
    mel = [12, 16, 19, 24, 19, 16, 14, 17, 21, 17, 14, 12, 16, 19, 16, 12]
    buf = np.zeros(int(len(mel) * beat * sx.SR + 1.0 * sx.SR))
    for i, s in enumerate(mel):
        sx.place(buf, _note(_hz(s + 12), 0.9, "box"), i * beat, 0.6)
        if i % 3 == 0:
            sx.place(buf, _note(_hz(s), 0.9, "box"), i * beat, 0.25)
    return sx.reverb(buf, 0.4, 0.25)


def wind():
    buf = np.zeros(int(0.7 * sx.SR))
    for k in range(7):
        sx.place(buf, sx.lowpass(sx.clack(2600 + (k % 2) * 500, 0.02), 6000), k * 0.08, 0.5)
    return sx.reverb(buf, 0.25, 0.1)


def boing():
    dur = 1.2
    tt = sx.t(dur)
    f = 180 + 260 * np.exp(-tt * 3) * (1 + 0.5 * np.sin(2 * np.pi * 9 * tt))
    x = np.sin(2 * np.pi * np.cumsum(f) / sx.SR) * sx.env(len(tt), 0.005, 0.8)
    return sx.reverb(x, 0.4, 0.2)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    boards().save(OUT / "boards.png")
    floor().save(OUT / "floor.png")
    tent().save(OUT / "tent.png")
    poster().save(OUT / "poster.png")
    print("Texturen geschrieben:", OUT)
    save_wav("music.wav", music(), 0.5)
    save_wav("applause.wav", applause(), 0.5)
    save_wav("pop.wav", pop(), 0.6)
    save_wav("musicbox.wav", musicbox(), 0.5)
    save_wav("wind.wav", wind(), 0.5)
    save_wav("boing.wav", boing(), 0.6)
