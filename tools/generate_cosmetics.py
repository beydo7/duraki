#!/usr/bin/env python3
"""Texturen und Geräusche für die Deck-Belohnungen (Tischfilz, Tischrand, Extras).

    python3 tools/generate_cosmetics.py

Schreibt nach assets/cosmetics/:
  felt_<id>.png   Tischfilz (kachelbar; felt_moon ist ein Bild für den ganzen Tisch). Einfarbige
                  Filze 512 px; Filze mit Muster 1024 px, groß gezeichnet und sauber verkleinert
                  (glatte Kanten statt Pixeltreppen)
  rim_<id>.png    Material für den Tischrand (kachelbar)
  rim_<id>_normal.png  Relief dazu (Maserung, Fugen, Risse, Strähnen), aus der Helligkeit berechnet
  caw.wav         Krähe krächzt
  bells.wav       Glöckchen klingeln
  howl.wav        Wolfsgeheul
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "cosmetics"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_sfx as sx  # noqa: E402

S = 512  # Kachelgröße; beim Zeichnen der Muster-Filze vorübergehend größer (siehe _fine)
Q = 1    # Maßstab dazu: alle Pixelmaße der Muster werden mit Q malgenommen


def _noise(cells, seed, size=None):
    """Kachelbares Wertrauschen (Zellen wiederholen sich am Rand)."""
    size = size or S
    rng = np.random.default_rng(seed)
    g = rng.random((cells, cells))
    g = np.concatenate([g, g[:1]], 0)
    g = np.concatenate([g, g[:, :1]], 1)
    img = Image.fromarray((g * 255).astype(np.uint8)).resize((size + size // cells, size + size // cells), Image.BICUBIC)
    a = np.asarray(img).astype(np.float32)[:size, :size] / 255
    return a


def _felt_grain(seed=1):
    return 0.86 + 0.08 * _noise(64, seed) + 0.06 * _noise(256, seed + 1)


def _tint(rgb, k):
    return np.clip(np.array(rgb, np.float32)[None, None, :] * k[..., None], 0, 255)


def _save(arr, name):
    img = Image.fromarray(np.asarray(arr).clip(0, 255).astype(np.uint8))
    if Q > 1:  # groß gezeichnetes Muster: je Q/2 × Q/2 Pixel mitteln (bleibt kachelbar)
        img = img.resize((S // (Q // 2), S // (Q // 2)), Image.BOX)
    img.save(OUT / name)
    print("geschrieben:", OUT / name)


def _px(v):
    """Strichbreite in Pixeln im aktuellen Maßstab."""
    return max(1, int(round(v * Q)))


def _fine(fn, q=8):
    """Muster-Filz in q-facher Größe zeichnen und auf 1024 px verkleinern: gleiches Muster,
    gleiche Farben, aber glatte Kanten."""
    global S, Q
    old = (S, Q)
    S, Q = 512 * q, q
    try:
        fn()
    finally:
        S, Q = old


def _normal(arr, name, strength=2.0, blur=1.0):
    """Normal-Map aus der Helligkeit (dunkel = tief). Am Kachelrand wird nicht über die Naht
    hinweg gerechnet: die Farbtexturen schließen dort nicht ganz an, das gäbe eine Kante."""
    h = np.asarray(arr, np.float32).mean(axis=2) / 255.0
    pad = 8
    hp = np.pad(h, pad, mode="edge")
    hp = np.asarray(Image.fromarray((hp * 255).clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(blur))).astype(np.float32) / 255.0
    hp = hp[pad - 1:-pad + 1, pad - 1:-pad + 1]
    dx = (hp[1:-1, 2:] - hp[1:-1, :-2]) * strength
    dy = (hp[2:, 1:-1] - hp[:-2, 1:-1]) * strength
    h = hp[1:-1, 1:-1]
    n = np.stack([-dx, -dy, np.ones_like(h) * 0.25], axis=2)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255).clip(0, 255).astype(np.uint8)).save(OUT / name)
    print("geschrieben:", OUT / name)


# --- Filz ---------------------------------------------------------------------------

def felt_plain(name, rgb, seed):
    _save(_tint(rgb, _felt_grain(seed)), f"felt_{name}.png")


def felt_feather():
    base = _tint((26, 26, 30), _felt_grain(11))
    img = Image.fromarray(base.astype(np.uint8))
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(12)
    for _ in range(28):  # Federn: Kiel + schräge Fahnen, leicht schimmernd
        cx, cy = rng.uniform(0, S, 2)
        ang = rng.uniform(0, np.pi)
        L = rng.uniform(70, 120) * Q
        dx, dy = np.cos(ang), np.sin(ang)
        for ox in (-S, 0, S):
            for oy in (-S, 0, S):
                x0, y0 = cx + ox - dx * L / 2, cy + oy - dy * L / 2
                d.line([(x0, y0), (x0 + dx * L, y0 + dy * L)], fill=(110, 116, 140), width=_px(2))
                for t in np.linspace(0.1, 0.95, 14):
                    px, py = x0 + dx * L * t, y0 + dy * L * t
                    w = 18 * Q * np.sin(np.pi * t)
                    for s in (-1, 1):
                        qx = px + (-dy * s * w) - dx * 6 * Q
                        qy = py + (dx * s * w) - dy * 6 * Q
                        d.line([(px, py), (qx, qy)], fill=(74, 82, 108), width=_px(1))
    _save(np.asarray(img.filter(ImageFilter.GaussianBlur(0.6 * Q))), "felt_feather.png")


def felt_wine_gold():
    base = _tint((96, 20, 30), _felt_grain(21))
    img = Image.fromarray(base.astype(np.uint8))
    d = ImageDraw.Draw(img)
    step = 128 * Q
    for y in range(0, S + step, step):  # goldene Rauten-Ornamente
        for x in range(0, S + step, step):
            for cx, cy in ((x, y), (x + step / 2, y + step / 2)):
                r = 22 * Q
                d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], outline=(214, 170, 80), width=_px(3))
                d.ellipse([cx - 5 * Q, cy - 5 * Q, cx + 5 * Q, cy + 5 * Q], fill=(226, 184, 92))
    _save(np.asarray(img.filter(ImageFilter.GaussianBlur(0.5 * Q))), "felt_wine.png")


def felt_stripes():
    k = _felt_grain(31)
    arr = np.zeros((S, S, 3), np.float32)
    w = S // 8
    for i in range(8):
        arr[:, i * w:(i + 1) * w] = (170, 34, 30) if i % 2 == 0 else (214, 168, 40)
    _save(arr * k[..., None], "felt_stripes.png")


def felt_harlequin():
    k = _felt_grain(41)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    n = 4
    u = (xx / S * n + yy / S * n)
    v = (xx / S * n - yy / S * n)
    check = ((np.floor(u) + np.floor(v)) % 2).astype(bool)
    arr = np.where(check[..., None], np.array((160, 28, 34), np.float32), np.array((206, 160, 44), np.float32))
    img = Image.fromarray((arr * k[..., None]).clip(0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    for i in range(-n, 2 * n + 1):  # schwarze Rautenlinien
        a = i * S / n
        d.line([(a, 0), (a - S, S)], fill=(30, 20, 20), width=_px(3))
        d.line([(a, 0), (a + S, S)], fill=(30, 20, 20), width=_px(3))
    _save(np.asarray(img), "felt_harlequin.png")


def felt_stars():
    base = _tint((62, 34, 96), _felt_grain(51))
    img = Image.fromarray(base.astype(np.uint8))
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(52)
    gold = (226, 196, 120)
    for _ in range(26):
        x, y = rng.uniform(10, 512 - 10, 2) * Q
        r = rng.uniform(5, 10) * Q
        pts = []
        for k in range(10):
            a = -np.pi / 2 + k * np.pi / 5
            rr = r if k % 2 == 0 else r * 0.45
            pts.append((x + np.cos(a) * rr, y + np.sin(a) * rr))
        d.polygon(pts, fill=gold)
    for _ in range(6):  # Mondsicheln
        x, y = rng.uniform(30, 512 - 30, 2) * Q
        r = rng.uniform(14, 20) * Q
        d.ellipse([x - r, y - r, x + r, y + r], fill=gold)
        d.ellipse([x - r + r * 0.45, y - r - 2 * Q, x + r + r * 0.45, y + r - 2 * Q], fill=tuple(int(c) for c in base[int(y) % S, int(x) % S]))
    _save(np.asarray(img.filter(ImageFilter.GaussianBlur(0.5 * Q))), "felt_stars.png")


def felt_claws():
    base = _tint((54, 66, 58), _felt_grain(61))
    img = Image.fromarray(base.astype(np.uint8))
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(62)
    for _ in range(5):  # je drei Krallenspuren, aufgerissener (hellerer) Filz
        x, y = rng.uniform(40, 512 - 40, 2) * Q
        ang = rng.uniform(-0.6, 0.6) + np.pi / 2
        for k in range(3):
            ox = (k - 1) * 14 * Q
            pts = []
            for t in np.linspace(0, 1, 12 if Q == 1 else 48):
                L = 110 * Q
                px = x + ox * np.cos(ang - np.pi / 2) + np.cos(ang) * L * t + 6 * Q * np.sin(t * 3)
                py = y + ox * np.sin(ang - np.pi / 2) + np.sin(ang) * L * t
                pts.append((px, py))
            for i in range(len(pts) - 1):
                w = 1 + 4 * np.sin(np.pi * i / (len(pts) - 1))
                if Q == 1:
                    w = int(w)
                d.line([pts[i], pts[i + 1]], fill=(20, 22, 20), width=_px(w + 2))
                d.line([pts[i], pts[i + 1]], fill=(120, 116, 96), width=_px(max(1, w - 1)))
    _save(np.asarray(img.filter(ImageFilter.GaussianBlur(0.4 * Q))), "felt_claws.png")


def felt_moon():
    """Ein Bild für den ganzen Tisch: nachtblauer Filz, großer Vollmond in der Mitte."""
    base = _tint((22, 30, 54), _felt_grain(71))
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    c = S / 2
    r = np.hypot(xx - c, yy - c)
    glow = np.clip(1 - (r - 70 * Q) / (90 * Q), 0, 1) ** 2 * 0.25
    base = base + glow[..., None] * np.array((120, 130, 150), np.float32)
    moon = r < 70 * Q
    crater = 0.85 + 0.15 * _noise(12, 72)
    mcol = np.array((140, 140, 128), np.float32)[None, None, :] * crater[..., None]
    base = np.where(moon[..., None], mcol, base)
    img = Image.fromarray(base.clip(0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(73)
    for _ in range(60):
        x, y = rng.uniform(0, S, 2)
        if np.hypot(x - c, y - c) > 110 * Q:
            s = rng.uniform(0.8, 2.0) * Q
            d.ellipse([x - s, y - s, x + s, y + s], fill=(220, 220, 240))
    _save(np.asarray(img.filter(ImageFilter.GaussianBlur(0.6 * Q))), "felt_moon.png")


def felt_velvet():
    k = 0.8 + 0.2 * _noise(8, 81) + 0.06 * _noise(256, 82)
    _save(_tint((150, 16, 26), k), "felt_velvet.png")


# --- Rand ---------------------------------------------------------------------------

def rim_wood(name, rgb, seed, coarse=False, moss=False):
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    n = _noise(8, seed)
    rings = np.sin((yy / S * (10 if coarse else 22) + n * 3) * 2 * np.pi) * 0.5 + 0.5
    k = 0.72 + 0.2 * rings + 0.1 * _noise(128, seed + 1)
    arr = _tint(rgb, k)
    if coarse:  # grobe Risse
        cr = (_noise(32, seed + 2) > 0.78) * 0.4
        arr *= (1 - cr)[..., None]
    if moss:
        m = np.clip(_noise(16, seed + 3) - 0.45, 0, 1) * 2.2
        arr = arr * (1 - m[..., None]) + np.array((70, 110, 40), np.float32) * m[..., None] * (0.8 + 0.4 * _noise(128, seed + 4))[..., None]
    _save(arr, f"rim_{name}.png")
    _normal(arr, f"rim_{name}_normal.png", 2.2 if coarse else 1.6, 0.8)


def rim_bone():
    k = 0.85 + 0.1 * _noise(16, 91) + 0.05 * _noise(128, 92)
    arr = _tint((226, 214, 184), k)
    img = Image.fromarray(arr.clip(0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    for x in range(0, S, 64):  # Gelenk-Knubbel quer über den Rand
        d.line([(x, 0), (x, S)], fill=(150, 136, 110), width=4)
        d.line([(x + 6, 0), (x + 6, S)], fill=(240, 232, 210), width=2)
    arr = np.asarray(img.filter(ImageFilter.GaussianBlur(1.0)))
    _save(arr, "rim_bone.png")
    _normal(arr, "rim_bone_normal.png", 2.6, 1.6)


def rim_stone(name, seed, moss=False):
    k = 0.6 + 0.3 * _noise(8, seed) + 0.15 * _noise(64, seed + 1)
    arr = _tint((140, 136, 128), k)
    if moss:
        m = np.clip(_noise(10, seed + 2) - 0.4, 0, 1) * 2.5
        arr = arr * (1 - m[..., None]) + np.array((64, 100, 40), np.float32) * m[..., None]
    else:  # Fugen einer Steinplatte
        img = Image.fromarray(arr.clip(0, 255).astype(np.uint8))
        d = ImageDraw.Draw(img)
        for p in (0, S // 2):
            d.line([(p, 0), (p, S)], fill=(70, 68, 64), width=3)
        arr = np.asarray(img).astype(np.float32)
    _save(arr, f"rim_{name}.png")
    _normal(arr, f"rim_{name}_normal.png", 2.4, 1.2)


def rim_fur():
    rng = np.random.default_rng(101)
    img = Image.fromarray(_tint((120, 118, 114), 0.8 + 0.2 * _noise(16, 102)).astype(np.uint8))
    d = ImageDraw.Draw(img)
    for _ in range(5000):  # Haarsträhnen
        x, y = rng.uniform(0, S, 2)
        L = rng.uniform(8, 18)
        a = np.pi / 2 + rng.uniform(-0.4, 0.4)
        c = int(rng.uniform(70, 190))
        d.line([(x, y), (x + np.cos(a) * L, y + np.sin(a) * L)], fill=(c, c - 2, c - 8), width=1)
    arr = np.asarray(img.filter(ImageFilter.GaussianBlur(0.5)))
    _save(arr, "rim_fur.png")
    _normal(arr, "rim_fur_normal.png", 1.4, 0.7)


# --- Geräusche ----------------------------------------------------------------------

def save_wav(name, x, peak=0.8):
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


def caw():
    buf = np.zeros(int(1.1 * sx.SR))
    for at in (0.0, 0.42):
        tt = sx.t(0.32)
        f = 520 + 220 * np.exp(-tt * 6)
        saw = 2 * ((np.cumsum(f) / sx.SR) % 1.0) - 1
        x = sx.bandpass(saw + 0.4 * np.random.default_rng(int(at * 10)).normal(0, 1, len(tt)), 600, 3200)
        sx.place(buf, x * sx.env(len(tt), 0.01, 0.25, 0.3), at)
    return sx.reverb(buf, 0.4, 0.2)


def bells():
    buf = np.zeros(int(1.2 * sx.SR))
    rng = np.random.default_rng(5)
    for k in range(7):
        f = rng.choice([2350, 2790, 3130, 3520])
        tt = sx.t(0.6)
        x = (np.sin(2 * np.pi * f * tt) + 0.4 * np.sin(2 * np.pi * f * 2.76 * tt)) * sx.env(len(tt), 0.001, 0.25)
        sx.place(buf, x, k * 0.05 + rng.uniform(0, 0.02), rng.uniform(0.4, 1.0))
    return sx.reverb(buf, 0.3, 0.2)


def howl():
    dur = 3.4
    tt = sx.t(dur)
    f = 330 + 260 * np.sin(np.pi * np.clip(tt / 2.6, 0, 1)) ** 0.7 - 80 * np.clip(tt - 2.6, 0, 1)
    f = f * (1 + 0.012 * np.sin(2 * np.pi * 5.5 * tt))
    x = np.sin(2 * np.pi * np.cumsum(f) / sx.SR) + 0.25 * np.sin(2 * np.pi * np.cumsum(f * 2) / sx.SR)
    x += 0.08 * sx.bandpass(np.random.default_rng(3).normal(0, 1, len(tt)), 400, 1800)
    x *= sx.env(len(tt), 0.35, 1.6, 0.0) * np.clip((dur - tt) / 0.8, 0, 1)
    return sx.reverb(x, 0.85, 0.5)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    felt_plain("grey", (110, 112, 112), 2)
    felt_plain("yellow", (200, 160, 46), 3)
    felt_plain("blue", (34, 64, 130), 4)
    felt_plain("bone", (214, 204, 176), 5)
    felt_plain("moss", (66, 96, 40), 6)
    felt_plain("violet", (84, 44, 120), 7)
    for pattern in (felt_feather, felt_wine_gold, felt_stripes, felt_harlequin, felt_stars, felt_claws, felt_moon):
        _fine(pattern)
    felt_velvet()
    rim_wood("oak", (150, 108, 64), 111, coarse=True)
    rim_wood("ebony", (40, 30, 28), 112)
    rim_wood("mossy", (100, 70, 44), 113, moss=True)
    rim_wood("wood", (110, 64, 34), 114)
    rim_bone()
    rim_stone("stone", 121)
    rim_stone("rock", 122, moss=True)
    rim_fur()
    save_wav("caw.wav", caw(), 0.6)
    save_wav("bells.wav", bells(), 0.5)
    save_wav("howl.wav", howl(), 0.7)
