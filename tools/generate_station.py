#!/usr/bin/env python3
"""Texturen und Geräusche für den Raum „Bahnhofswartesaal“ (ohne Blender).

    python3 tools/generate_station.py

Schreibt nach assets/rooms/station/:
  tiles.png        glasierte weiße Wandkacheln mit Fugen (kachelbar, wird grün eingefärbt)
  floor.png        Fliesenboden, abgetretenes Schachbrett (kachelbar)
  plaster.png      fleckiger Wandputz über den Kacheln (kachelbar)
  newspaper.png    aufgeschlagene Zeitung „Bahnhofs-Anzeiger“ (Doppelseite)
  train_pass.wav   ein Zug rauscht draußen vorbei (Rumpeln, Schienenstöße, Pfiff)
  neon_buzz.wav    Brummen der Neonröhre (Schleife)
  neon_tick.wav    leises Klicken, wenn die Röhre flackert
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

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


FONTS = ROOT / "assets" / "fonts"


def font(name, size):
    return ImageFont.truetype(str(FONTS / name), size)


def newspaper():
    """Aufgeschlagene Doppelseite (2048 × 1400): Kopf, Schlagzeilen, Spalten, Bild, Falz."""
    W, H = 2048, 1400
    rng = np.random.default_rng(31)
    img = Image.new("RGB", (W, H), (226, 219, 198))
    d = ImageDraw.Draw(img)
    ink = (30, 28, 26)
    grey = (120, 116, 108)
    serif_b = lambda n: font("OldStandard-Bold.ttf", n)
    serif = lambda n: font("OldStandard-Regular.ttf", n)
    cond = lambda n: font("Oswald-Variable.ttf", n)

    def text_block(x0, y0, x1, y1, line=22):
        """Spaltentext als feine graue Zeilen (unlesbar klein, wie echte Zeitung von weitem)."""
        y = y0
        while y < y1:
            end = x1 if rng.random() > 0.12 else x0 + (x1 - x0) * rng.uniform(0.3, 0.8)
            d.line([(x0, y), (end, y)], fill=grey, width=5)
            y += line
            if rng.random() < 0.07:
                y += line  # Absatz

    def columns(x0, y0, x1, y1, n):
        cw = (x1 - x0 - (n - 1) * 26) / n
        for k in range(n):
            cx = x0 + k * (cw + 26)
            text_block(cx, y0, cx + cw, y1)
            if k < n - 1:
                d.line([(cx + cw + 13, y0), (cx + cw + 13, y1)], fill=(170, 164, 150), width=2)

    def train_picture(x0, y0, x1, y1):
        """Kleines Zeitungsfoto: Dampflok im Nebel (grau, gerastert)."""
        pic = Image.new("L", (int(x1 - x0), int(y1 - y0)), 170)
        pd = ImageDraw.Draw(pic)
        w, h = pic.size
        pd.rectangle([0, int(h * 0.72), w, h], fill=110)  # Bahnsteig
        pd.rectangle([int(w * 0.12), int(h * 0.38), int(w * 0.75), int(h * 0.72)], fill=45)  # Kessel
        pd.rectangle([int(w * 0.6), int(h * 0.22), int(w * 0.88), int(h * 0.72)], fill=35)  # Führerhaus
        pd.rectangle([int(w * 0.2), int(h * 0.2), int(w * 0.28), int(h * 0.38)], fill=40)  # Schornstein
        for k in range(4):
            cx = int(w * (0.16 + k * 0.17))
            pd.ellipse([cx - 34, int(h * 0.66), cx + 34, int(h * 0.66) + 68], fill=25)
        for k in range(6):  # Dampfwolke
            cx, cy = int(w * (0.22 - k * 0.04)), int(h * (0.15 - k * 0.02))
            pd.ellipse([cx - 60, cy - 40, cx + 60, cy + 40], fill=215)
        pic = pic.filter(ImageFilter.GaussianBlur(3))
        a = np.asarray(pic).astype(np.float32)
        yy, xx = np.mgrid[0:h, 0:w]
        dots = (np.sin(xx * 0.9) * np.sin(yy * 0.9) * 22)  # Druckraster
        pic = Image.fromarray((a + dots).clip(0, 255).astype(np.uint8)).convert("RGB")
        img.paste(pic, (int(x0), int(y0)))
        d.rectangle([x0, y0, x1, y1], outline=ink, width=3)

    half = W // 2
    m = 70
    # --- linke Seite: Titelseite
    d.text((half / 2, 120), "Bahnhofs-Anzeiger", font=serif_b(100), fill=ink, anchor="mm")
    d.line([(m, 200), (half - m, 200)], fill=ink, width=5)
    d.text((m, 222), "Nr. 47 · Ausgabe für Reisende", font=cond(32), fill=ink)
    d.text((half - m, 222), "Preis 10 Pfennig", font=cond(32), fill=ink, anchor="ra")
    d.line([(m, 270), (half - m, 270)], fill=ink, width=2)
    d.text((m, 300), "Durak-Turnier im Wartesaal:", font=serif_b(66), fill=ink)
    d.text((m, 380), "Wölfin bleibt ungeschlagen", font=serif_b(66), fill=ink)
    train_picture(m, 480, half - m, 900)
    d.text((m, 912), "Der Nachtzug nach Hannover fuhr pünktlich ab.", font=serif(30), fill=ink)
    columns(m, 975, half - m, H - m, 3)
    # --- rechte Seite: Vermischtes
    x0 = half + m
    d.text((x0, 70), "Vermischtes", font=cond(48), fill=ink)
    d.text((W - m, 78), "Seite 2", font=cond(34), fill=ink, anchor="ra")
    d.line([(x0, 140), (W - m, 140)], fill=ink, width=4)
    d.text((x0, 165), "Zug nach Neustadt am Rübenberge", font=serif_b(52), fill=ink)
    d.text((x0, 228), "mit 40 Minuten Verspätung", font=serif_b(52), fill=ink)
    columns(x0, 310, W - m, 700, 3)
    d.line([(x0, 725), (W - m, 725)], fill=ink, width=2)
    d.text((x0, 745), "Wer schiebt, gewinnt? Die Regeln des Durak", font=serif_b(42), fill=ink)
    columns(x0, 815, x0 + (W - m - x0) * 0.6, H - m, 2)
    # Kleinanzeigen-Kasten
    bx = x0 + (W - m - x0) * 0.64
    d.rectangle([bx, 815, W - m, H - m], outline=ink, width=3)
    d.text(((bx + W - m) / 2, 850), "ANZEIGEN", font=cond(36), fill=ink, anchor="mm")
    yy = 900
    for line in ("Kartenspiel gesucht", "Kofferträger frei", "Glückskarte verloren"):
        d.text((bx + 24, yy), line, font=serif(28), fill=ink)
        text_block(bx + 24, yy + 50, W - m - 24, yy + 110)
        yy += 140
    # Falz in der Mitte und vergilbte Ränder
    arr = np.asarray(img).astype(np.float32)
    xs = np.abs(np.arange(W) - half) / half
    fold = 1.0 - 0.18 * np.exp(-(xs * 40) ** 2)
    edge = np.minimum(np.minimum(np.arange(W)[None, :], W - np.arange(W)[None, :]),
                      np.minimum(np.arange(H)[:, None], H - np.arange(H)[:, None])) / 60.0
    yellow = 1.0 - 0.1 * np.exp(-edge)
    arr *= (fold[None, :] * yellow)[..., None]
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8))


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
    newspaper().save(OUT / "newspaper.png")
    print("Texturen geschrieben:", OUT)
    save_wav("train_pass.wav", train_pass(), 0.8)
    save_wav("neon_buzz.wav", neon_buzz(), 0.4)
    save_wav("neon_tick.wav", neon_tick(), 0.4)
