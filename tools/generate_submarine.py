#!/usr/bin/env python3
"""Texturen und Geräusche für den Raum „U-Boot-Messe“ (ohne Blender).

    python3 tools/generate_submarine.py

Schreibt nach assets/rooms/submarine/:
  hull.png         grüne Stahlplatten mit Nieten und Rost (kachelbar)
  floor.png        Riffelblech (kachelbar)
  gauge.png        Zifferblatt einer Druckanzeige (grün → rot)
  hum.wav          Motorbrummen (Schleife, 4 s)
  sonar.wav        Sonar-„Ping“ mit Nachhall
  hiss.wav         Dampf zischt aus einem Ventil
  creak.wav        Metall knarzt
  drip.wav         Wassertropfen
  crank.wav        Periskop wird gedreht (Zahnrad-Ratschen)
  whale.wav        Walgesang (Easter Egg)
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "rooms" / "submarine"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_sfx as sx  # noqa: E402


def _noise(size, cells, seed):
    rng = np.random.default_rng(seed)
    return np.asarray(Image.fromarray((rng.random((cells, cells)) * 255).astype(np.uint8))
                      .resize((size, size), Image.BICUBIC)).astype(np.float32) / 255


def hull():
    """2 × 2 Stahlplatten, Nietenreihen an den Kanten, Rostflecken (kachelbar)."""
    S = 512
    base = np.array([62, 84, 70], np.float32)
    k = 0.82 + 0.12 * _noise(S, 16, 1) + 0.06 * _noise(S, 64, 2)
    arr = base * k[..., None]
    rust = np.clip(_noise(S, 12, 3) - 0.72, 0, 1) * 3.0
    arr = arr * (1 - rust[..., None] * 0.5) + np.array([110, 62, 34], np.float32) * rust[..., None] * 0.5
    img = Image.fromarray(arr.clip(0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    h = S // 2
    for p in (0, h):  # Plattenfugen
        d.line([(p, 0), (p, S)], fill=(28, 38, 32), width=4)
        d.line([(0, p), (S, p)], fill=(28, 38, 32), width=4)
    for p in (0, h):  # Nieten entlang der Fugen
        for q in range(16, S, 32):
            for x, y in ((p + 12, q), (q, p + 12), (p - 12 if p else S - 12, q), (q, p - 12 if p else S - 12)):
                d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=(92, 112, 98))
                d.ellipse([x - 4, y - 4, x + 2, y + 2], fill=(120, 140, 124))
    return img.filter(ImageFilter.GaussianBlur(0.5))


def floor():
    """Riffelblech: schräge Rauten auf grauem Stahl."""
    S = 256
    img = Image.new("RGB", (S, S), (70, 74, 74))
    d = ImageDraw.Draw(img)
    step = 32
    for y in range(0, S + step, step):
        for x in range(0, S + step, step):
            off = step // 2 if (y // step) % 2 else 0
            cx, cy = x + off, y
            if ((x // step) + (y // step)) % 2:
                d.line([(cx - 9, cy - 3), (cx + 9, cy + 3)], fill=(112, 116, 116), width=5)
            else:
                d.line([(cx - 3, cy - 9), (cx + 3, cy + 9)], fill=(112, 116, 116), width=5)
    arr = np.asarray(img).astype(np.float32) * (0.85 + 0.15 * _noise(S, 8, 5))[..., None]
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8))


def gauge():
    """Zifferblatt: creme Grund, Skala 0–10 über 270°, grüner und roter Bereich."""
    S = 256
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([4, 4, S - 4, S - 4], fill=(232, 224, 200, 255))
    c = S / 2
    r = S / 2 - 22
    # Bereiche: grün 0–6, gelb 6–8, rot 8–10 (Skala von -225° bis +45°, im Uhrzeigersinn)
    def ang(v):
        return -225 + 270 * v / 10
    d.arc([c - r, c - r, c + r, c + r], ang(0), ang(6), fill=(40, 150, 70), width=14)
    d.arc([c - r, c - r, c + r, c + r], ang(6), ang(8), fill=(220, 170, 40), width=14)
    d.arc([c - r, c - r, c + r, c + r], ang(8), ang(10), fill=(200, 40, 30), width=14)
    try:
        f = ImageFont.truetype(str(ROOT / "assets" / "fonts" / "Oswald-Variable.ttf"), 22)
    except OSError:
        f = None
    for v in range(11):
        a = np.radians(ang(v))
        x0, y0 = c + np.cos(a) * (r - 12), c + np.sin(a) * (r - 12)
        x1, y1 = c + np.cos(a) * (r - 30), c + np.sin(a) * (r - 30)
        d.line([(x0, y0), (x1, y1)], fill=(30, 28, 24), width=3)
        if f is not None and v % 2 == 0:
            tx, ty = c + np.cos(a) * (r - 48), c + np.sin(a) * (r - 48)
            d.text((tx, ty), str(v), font=f, fill=(30, 28, 24), anchor="mm")
    if f is not None:
        d.text((c, c + 52), "DRUCK", font=f, fill=(60, 56, 50), anchor="mm")
    return img


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


def hum():
    """Motorbrummen, genau 4 s (ganzzahlige Frequenzen → nahtlose Schleife)."""
    tt = sx.t(4.0)
    x = (np.sin(2 * np.pi * 42 * tt) * 0.6 + np.sin(2 * np.pi * 84 * tt) * 0.3
         + np.sin(2 * np.pi * 126 * tt) * 0.12)
    x *= 0.85 + 0.15 * np.sin(2 * np.pi * 0.5 * tt)  # leichtes Pumpen der Maschine
    rng = np.random.default_rng(3)
    n = sx.lowpass(rng.normal(0, 1, len(tt)), 300) * 0.25
    fade = np.minimum(1, np.minimum(tt, 4.0 - tt) / 0.05)  # Rauschen an den Enden ausblenden
    return x + n * fade


def sonar():
    dur = 2.6
    tt = sx.t(dur)
    ping = np.sin(2 * np.pi * 1180 * tt) * sx.env(len(tt), 0.004, 0.35)
    echo = np.zeros_like(ping)
    sx.place(echo, ping[: int(0.8 * sx.SR)] * 0.35, 0.9)
    return sx.reverb(ping + echo, 0.6, 0.45)


def hiss():
    dur = 1.1
    n = int(dur * sx.SR)
    x = sx.highpass(np.random.default_rng(6).normal(0, 1, n), 2500)
    return x * sx.env(n, 0.02, 0.35, 0.0)


def creak():
    dur = 1.3
    tt = sx.t(dur)
    f = 90 + 30 * np.sin(2 * np.pi * 0.7 * tt)
    x = np.sign(np.sin(2 * np.pi * np.cumsum(f) / sx.SR)) * 0.5
    x = sx.lowpass(x, 900) * sx.env(len(tt), 0.25, 0.5, 0.0)
    return sx.reverb(x, 0.5, 0.3)


def drip():
    dur = 0.6
    tt = sx.t(dur)
    f = np.geomspace(900, 2400, len(tt))
    x = np.sin(2 * np.pi * np.cumsum(f) / sx.SR) * sx.env(len(tt), 0.002, 0.05)
    return sx.reverb(x, 0.6, 0.4)


def crank():
    buf = np.zeros(int(1.0 * sx.SR))
    at = 0.0
    for k in range(10):
        sx.place(buf, sx.lowpass(sx.clack(1400 + (k % 2) * 300, 0.03), 4000), at, 0.6)
        at += 0.085
    return sx.reverb(buf, 0.3, 0.15)


def whale():
    """Walgesang: langsam gleitende tiefe Töne mit viel Hall."""
    dur = 5.5
    tt = sx.t(dur)
    f = 180 + 120 * np.sin(2 * np.pi * 0.18 * tt) + 60 * np.sin(2 * np.pi * 0.5 * tt)
    x = np.sin(2 * np.pi * np.cumsum(f) / sx.SR) + 0.3 * np.sin(2 * np.pi * np.cumsum(f * 2.02) / sx.SR)
    x *= sx.env(len(tt), 0.8, 2.4, 0.0) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.9 * tt) ** 2)
    return sx.reverb(sx.lowpass(x, 1800), 0.8, 0.55)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    hull().save(OUT / "hull.png")
    floor().save(OUT / "floor.png")
    gauge().save(OUT / "gauge.png")
    print("Texturen geschrieben:", OUT)
    save_wav("hum.wav", hum(), 0.5)
    save_wav("sonar.wav", sonar(), 0.6)
    save_wav("hiss.wav", hiss(), 0.5)
    save_wav("creak.wav", creak(), 0.5)
    save_wav("drip.wav", drip(), 0.4)
    save_wav("crank.wav", crank(), 0.5)
    save_wav("whale.wav", whale(), 0.7)
