#!/usr/bin/env python3
"""Texturen und Geräusche für den Raum „Bahnhofswartesaal“ (ohne Blender).

    python3 tools/generate_station.py

Schreibt nach assets/rooms/station/:
  tiles.png        glasierte weiße Wandkacheln mit Fugen (kachelbar, wird grün eingefärbt)
  floor.png        Fliesenboden, abgetretenes Schachbrett (kachelbar)
  plaster.png      fleckiger Wandputz über den Kacheln (kachelbar)
  train_pass.wav   ein Zug rauscht draußen vorbei (Rumpeln, Schienenstöße, Pfiff)
  glass_clink.wav  Teegläser klirren in ihren Haltern
  neon_buzz.wav    Brummen der Neonröhre (Schleife)
  neon_tick.wav    leises Klicken, wenn die Röhre flackert
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "rooms" / "station"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_sfx as sx  # noqa: E402


# --- Texturen ---------------------------------------------------------------------

def tiles():
    """4 × 4 glasierte Kacheln, leicht unterschiedlich hell, graue Fugen, etwas Schmutz."""
    S, n = 512, 4
    rng = np.random.default_rng(3)
    img = Image.new("RGB", (S, S), (150, 150, 140))
    d = ImageDraw.Draw(img)
    c = S // n
    g = 5
    for y in range(n):
        for x in range(n):
            v = int(rng.uniform(228, 246))
            d.rectangle([x * c + g, y * c + g, (x + 1) * c - g, (y + 1) * c - g], fill=(v, v, v - 4))
            # Glanzkante oben links
            d.line([(x * c + g + 4, y * c + g + 4), ((x + 1) * c - g - 6, y * c + g + 4)], fill=(255, 255, 252), width=3)
    arr = np.asarray(img).astype(np.float32)
    dirt = np.asarray(Image.fromarray((rng.random((64, 64)) * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC)).astype(np.float32)
    arr *= (0.93 + 0.07 * dirt[..., None] / 255.0)
    # ein paar Haarrisse
    img = Image.fromarray(arr.clip(0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    for _ in range(4):
        x0, y0 = rng.uniform(0, S, 2)
        pts = [(x0, y0)]
        for _k in range(5):
            x0 += rng.uniform(-18, 18)
            y0 += rng.uniform(4, 16)
            pts.append((x0, y0))
        d.line(pts, fill=(170, 168, 160), width=1)
    return img


def floor():
    """Schachbrett aus Terrakotta und Creme, abgetreten (kachelbar)."""
    S, n = 512, 4
    rng = np.random.default_rng(8)
    img = Image.new("RGB", (S, S), (60, 52, 44))
    d = ImageDraw.Draw(img)
    c = S // n
    for y in range(n):
        for x in range(n):
            base = (150, 70, 48) if (x + y) % 2 == 0 else (206, 192, 160)
            k = rng.uniform(0.9, 1.05)
            d.rectangle([x * c + 3, y * c + 3, (x + 1) * c - 3, (y + 1) * c - 3], fill=tuple(int(v * k) for v in base))
    arr = np.asarray(img).astype(np.float32)
    wear = np.asarray(Image.fromarray((rng.random((32, 32)) * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC)).astype(np.float32)
    arr *= (0.8 + 0.2 * wear[..., None] / 255.0)
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))


def plaster():
    """Heller, leicht fleckiger Wandputz (Ölfarbe, vergilbt)."""
    S = 512
    rng = np.random.default_rng(12)
    a = np.asarray(Image.fromarray((rng.random((24, 24)) * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC)).astype(np.float32) / 255
    b = np.asarray(Image.fromarray((rng.random((96, 96)) * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC)).astype(np.float32) / 255
    k = 0.86 + 0.1 * a + 0.04 * b
    base = np.array([214, 208, 184], np.float32)
    return Image.fromarray((base * k[..., None]).clip(0, 255).astype(np.uint8))


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


def train_pass():
    """Zug kommt näher, rauscht vorbei, entfernt sich (ca. 7 s)."""
    dur = 7.5
    n = int(dur * sx.SR)
    tt = sx.t(dur)
    rng = np.random.default_rng(21)
    # Lautstärkeverlauf: an- und abschwellen, Höhepunkt bei 3,2 s
    level = np.exp(-((tt - 3.2) / 1.6) ** 2)
    rumble = sx.lowpass(rng.normal(0, 1, n), 160) * 2.2
    roar = sx.lowpass(rng.normal(0, 1, n), 1400) * 0.6
    buf = (rumble + roar) * level
    # Schienenstöße: ta-tamm … ta-tamm (zwei Achsen je Wagen)
    at = 0.6
    while at < 6.6:
        g = float(np.exp(-((at - 3.2) / 1.5) ** 2))
        for off in (0.0, 0.11):
            sx.place(buf, sx.lowpass(sx.clack(220, 0.09), 900), at + off, 1.2 * g)
        at += 0.42
    # leiser Pfiff am Anfang (zwei Töne, wird beim Vorbeifahren tiefer: Doppler)
    whistle_t = sx.t(1.6)
    f = np.where(whistle_t < 0.9, 640, 560)
    w = (np.sin(2 * np.pi * np.cumsum(f) / sx.SR) + 0.4 * np.sin(2 * np.pi * np.cumsum(f * 1.5) / sx.SR))
    w *= sx.env(len(w), 0.05, 1.3, 0.6) * 0.12
    sx.place(buf, sx.lowpass(w, 2500), 1.4, 1.0)
    return sx.reverb(sx.lowpass(buf, 3000), 0.3, 0.15)


def glass_clink():
    """Teegläser klappern in den Metallhaltern (mehrere leise Klirrer)."""
    buf = np.zeros(int(1.6 * sx.SR))
    rng = np.random.default_rng(4)
    at = 0.0
    while at < 1.2:
        f = rng.uniform(2600, 4200)
        sx.place(buf, sx.chime(f, 0.25), at, rng.uniform(0.25, 0.6))
        sx.place(buf, sx.clack(1800, 0.02), at, 0.15)
        at += rng.uniform(0.05, 0.16)
    return sx.reverb(buf, 0.15, 0.1)


def neon_buzz():
    """Netzbrummen (100 Hz) mit Obertönen, genau 2 s, damit die Schleife nahtlos ist."""
    dur = 2.0
    tt = sx.t(dur)
    x = (np.sin(2 * np.pi * 100 * tt) * 0.5 + np.sin(2 * np.pi * 200 * tt) * 0.3
         + np.sin(2 * np.pi * 300 * tt) * 0.12 + np.sin(2 * np.pi * 1200 * tt) * 0.03)
    return x * (0.9 + 0.1 * np.sin(2 * np.pi * 1.5 * tt))


def neon_tick():
    buf = np.zeros(int(0.2 * sx.SR))
    sx.place(buf, sx.tick(3000), 0.0, 0.8)
    sx.place(buf, sx.tick(2600), 0.05, 0.4)
    return buf


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    tiles().save(OUT / "tiles.png")
    floor().save(OUT / "floor.png")
    plaster().save(OUT / "plaster.png")
    print("Texturen geschrieben:", OUT)
    save_wav("train_pass.wav", train_pass(), 0.8)
    save_wav("glass_clink.wav", glass_clink(), 0.5)
    save_wav("neon_buzz.wav", neon_buzz(), 0.4)
    save_wav("neon_tick.wav", neon_tick(), 0.4)
