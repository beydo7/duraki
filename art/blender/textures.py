"""Erzeugt die kachelbaren Texturen (Farbe + Normalmap) für die Blender-Modelle.

Alle Texturen sind nahtlos kachelbar (Rauschen über FFT, also periodisch).
Wird von build_models.py aufgerufen, kann aber auch allein laufen:

    python3 art/blender/textures.py
"""
from __future__ import annotations

import os

import numpy as np
from PIL import Image

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "textures")


# --- Rauschen ---------------------------------------------------------------------

def noise(size: int, sigma: float, seed: int, aspect: float = 1.0) -> np.ndarray:
    """Glattes, kachelbares Rauschen in [0, 1]. sigma in Pixeln, aspect > 1 = in x gestreckt."""
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((size, size))
    fy = np.fft.fftfreq(size)[:, None]
    fx = np.fft.fftfreq(size)[None, :]
    sx = sigma * aspect
    sy = sigma
    kernel = np.exp(-2 * (np.pi ** 2) * ((fx * sx) ** 2 + (fy * sy) ** 2))
    smooth = np.real(np.fft.ifft2(np.fft.fft2(white) * kernel))
    smooth -= smooth.min()
    smooth /= max(smooth.max(), 1e-9)
    return smooth


def fbm(size: int, base_sigma: float, seed: int, octaves: int = 4, aspect: float = 1.0) -> np.ndarray:
    total = np.zeros((size, size))
    amp = 1.0
    norm = 0.0
    sigma = base_sigma
    for o in range(octaves):
        total += noise(size, sigma, seed + o * 17, aspect) * amp
        norm += amp
        amp *= 0.5
        sigma = max(sigma * 0.5, 0.6)
    return total / norm


def lerp_color(a, b, t):
    a = np.array(a, dtype=np.float64)
    b = np.array(b, dtype=np.float64)
    return a[None, None, :] * (1 - t[..., None]) + b[None, None, :] * t[..., None]


def hex_rgb(h: str):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]


def normal_from_height(h: np.ndarray, strength: float) -> np.ndarray:
    """Normalmap (OpenGL/glTF-Konvention) aus einer Höhenkarte, kachelbar."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = dy * strength  # Bildzeilen laufen nach unten, V nach oben
    nz = np.ones_like(h)
    length = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    n = np.stack([nx / length, ny / length, nz / length], axis=-1)
    return n * 0.5 + 0.5


def save(name: str, rgb: np.ndarray) -> str:
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".png")
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB")
    img.save(path, optimize=True)
    return path


# --- Materialien ------------------------------------------------------------------

def brick(size=1024):
    """Ziegelwand. Kachel = 1 × 1 m: 4 Ziegel pro Reihe, 14 Reihen."""
    rows, cols = 14, 4
    y = np.arange(size)[:, None] / size * rows
    x = np.arange(size)[None, :] / size * cols
    row = np.floor(y).astype(int)
    x_off = x + (row % 2) * 0.5
    col = np.floor(x_off).astype(int) % cols
    fx = x_off - np.floor(x_off)
    fy = y - np.floor(y)
    # Abstand zur Fuge in Metern (Ziegel 25 × 7 cm, Fuge ca. 1 cm)
    edge = np.minimum(np.minimum(fx, 1 - fx) / cols, np.minimum(fy, 1 - fy) / rows)
    brick_mask = np.clip((edge - 0.005) / 0.006, 0, 1)
    # Farbe je Ziegel
    rng = np.random.default_rng(3)
    per = rng.random((rows, cols))
    tone = per[row % rows, col]
    grain = fbm(size, 6, 11)
    chips = noise(size, 2.0, 12)
    base = lerp_color(hex_rgb("3e1c2c"), hex_rgb("6a3046"), np.clip(tone * 0.8 + grain * 0.4 - 0.1, 0, 1))
    base *= (0.85 + chips[..., None] * 0.25)
    soot = fbm(size, 60, 13)
    base *= (0.7 + soot[..., None] * 0.4)
    mortar = lerp_color(hex_rgb("120e18"), hex_rgb("2a2230"), noise(size, 3, 14))
    color = mortar * (1 - brick_mask[..., None]) + base * brick_mask[..., None]
    height = brick_mask * (0.8 + grain * 0.2) - (chips < 0.25) * 0.15 * brick_mask
    save("brick_color", color)
    save("brick_normal", normal_from_height(height, 6.0))


def wood(size=1024, name="wood", dark="2a1710", light="5a3622", seed=20, rings=38.0):
    """Holzmaserung entlang U (Bretter laufen in x-Richtung)."""
    warp = fbm(size, 40, seed, aspect=8.0)
    fine = noise(size, 1.2, seed + 1, aspect=12.0)
    y = np.arange(size)[:, None] / size
    ring = 0.5 + 0.5 * np.sin((y + warp * 0.18) * np.pi * 2 * rings)
    ring = ring ** 3
    t = np.clip(ring * 0.55 + fine * 0.35 + warp * 0.25, 0, 1)
    color = lerp_color(hex_rgb(dark), hex_rgb(light), t)
    color *= (0.85 + noise(size, 80, seed + 2)[..., None] * 0.3)
    save(name + "_color", color)
    save(name + "_normal", normal_from_height(ring * 0.5 + fine * 0.5, 2.0))


def floor_planks(size=1024):
    """Dielenboden: 6 Dielen pro Kachel, versetzte Stöße."""
    planks = 6
    warp = fbm(size, 40, 30, aspect=8.0)
    fine = noise(size, 1.2, 31, aspect=12.0)
    y = np.arange(size)[:, None] / size * planks
    x = np.arange(size)[None, :] / size
    idx = np.floor(y).astype(int)
    fy = y - idx
    rng = np.random.default_rng(32)
    joints = rng.random(planks)
    tone = rng.random(planks)
    fxj = (x + joints[idx]) % 1.0
    gap = np.minimum(fy, 1 - fy) * 40
    gap_x = np.minimum(fxj, 1 - fxj) * 400
    plank_mask = np.clip(np.minimum(gap, gap_x) - 0.3, 0, 1)
    ring = (0.5 + 0.5 * np.sin((fy + warp * 0.6 + idx * 0.37) * np.pi * 10)) ** 3
    t = np.clip(ring * 0.45 + fine * 0.35 + tone[idx] * 0.35, 0, 1)
    color = lerp_color(hex_rgb("120c0a"), hex_rgb("3a2619"), t)
    color *= (0.75 + fbm(size, 50, 33)[..., None] * 0.4)
    color *= plank_mask[..., None] * 0.85 + 0.15
    save("floor_color", color)
    save("floor_normal", normal_from_height(plank_mask * 0.8 + ring * 0.2 + fine * 0.2, 4.0))


def felt(size=512):
    """Spieltisch-Filz: feine Fasern, leichte Flecken."""
    fibers = noise(size, 0.8, 40)
    clouds = fbm(size, 40, 41)
    t = np.clip(fibers * 0.5 + clouds * 0.6, 0, 1)
    color = lerp_color(hex_rgb("1f2e22"), hex_rgb("3b5238"), t)
    save("felt_color", color)
    save("felt_normal", normal_from_height(fibers, 1.5))


def fabric(size=512):
    """Mantelstoff (hell, wird in Godot mit der Gegnerfarbe eingefärbt)."""
    y = np.arange(size)[:, None]
    x = np.arange(size)[None, :]
    period = size / 48
    weave = 0.5 + 0.25 * (np.sin(x / period * np.pi * 2) * np.sign(np.sin(y / period * np.pi)) +
                          np.sin(y / period * np.pi * 2) * np.sign(np.sin(x / period * np.pi)))
    wear = fbm(size, 30, 50)
    t = np.clip(weave * 0.18 + wear * 0.82, 0, 1)
    color = lerp_color(hex_rgb("9a9a9a"), hex_rgb("e0e0e0"), t)
    save("fabric_color", color)
    save("fabric_normal", normal_from_height(weave, 2.5))


def porcelain(size=1024):
    """Porzellanmaske: fast weiß, feine Risse und etwas Schmutz in den Ritzen."""
    rng = np.random.default_rng(60)
    cracks = np.zeros((size, size))
    for _ in range(14):
        pos = rng.random(2) * size
        angle = rng.random() * np.pi * 2
        length = rng.integers(80, 320)
        for _step in range(length):
            angle += rng.normal(0, 0.12)
            pos += np.array([np.cos(angle), np.sin(angle)]) * 1.5
            px, py = int(pos[0]) % size, int(pos[1]) % size
            cracks[py, px] = 1.0
            if rng.random() < 0.03:  # Verzweigung
                angle += rng.choice([-1, 1]) * 0.9
    # Risse leicht verbreitern
    k = noise(size, 0.7, 61)
    cracks = np.clip(cracks + np.roll(cracks, 1, 0) * 0.5 + np.roll(cracks, 1, 1) * 0.5, 0, 1)
    grime = fbm(size, 60, 62)
    base = lerp_color(hex_rgb("cfc7b6"), hex_rgb("fbf7ee"), np.clip(grime * 0.8 + k * 0.2 + 0.2, 0, 1))
    color = base * (1 - cracks[..., None] * 0.7)
    save("porcelain_color", color)
    save("porcelain_normal", normal_from_height(-cracks * 0.6 + grime * 0.1, 3.0))


def metal(size=512):
    """Dunkles, angelaufenes Metall mit Kratzern (Lampe, Scheinwerfer)."""
    base = fbm(size, 30, 70)
    scratches = noise(size, 0.6, 71, aspect=30.0)
    t = np.clip(base * 0.7 + (scratches > 0.72) * 0.5, 0, 1)
    color = lerp_color(hex_rgb("141312"), hex_rgb("3d3a36"), t)
    save("metal_color", color)
    save("metal_normal", normal_from_height(scratches * 0.5 + base * 0.2, 1.5))


def crate(size=512):
    wood(size, "crate", dark="3b2617", light="7a5434", seed=80, rings=22.0)


def cloth_dark(size=512):
    """Lautsprecherbespannung / Lederpolster."""
    y = np.arange(size)[:, None]
    x = np.arange(size)[None, :]
    mesh = (np.sin(x * 0.9) * np.sin(y * 0.9)) * 0.5 + 0.5
    t = np.clip(mesh * 0.4 + fbm(size, 20, 90) * 0.6, 0, 1)
    color = lerp_color(hex_rgb("0d0b0b"), hex_rgb("2e2826"), t)
    save("cloth_color", color)
    save("cloth_normal", normal_from_height(mesh, 2.0))


# --- Charakter-Materialien ---------------------------------------------------------

def _finish(name, t, height, dark, light, strength=2.0, grime=0.25, seed=0):
    """Farbe aus Verlauf dark→light nach t, etwas Schmutz, Normalmap aus height."""
    size = t.shape[0]
    color = lerp_color(hex_rgb(dark), hex_rgb(light), np.clip(t, 0, 1))
    if grime > 0:
        g = fbm(size, 50, 500 + seed)
        color *= (1 - grime) + g[..., None] * grime * 1.6
    save(name + "_color", color)
    save(name + "_normal", normal_from_height(height, strength))


def fur(name, dark, light, size=512, seed=0):
    """Fell: feine Strähnen, senkrecht gekämmt (V-Richtung)."""
    strands = noise(size, 0.7, 600 + seed, aspect=0.08)
    clumps = fbm(size, 14, 610 + seed, aspect=0.3)
    t = strands * 0.55 + clumps * 0.6 - 0.1
    _finish(name, t, strands * 0.7 + clumps * 0.3, dark, light, 3.0, seed=seed)


def feathers(name, dark, light, size=512, seed=0):
    """Federkleid: überlappende Federn in versetzten Reihen."""
    rows, cols = 10, 8
    y = np.arange(size)[:, None] / size * rows
    x = np.arange(size)[None, :] / size * cols
    row = np.floor(y).astype(int)
    xo = x + (row % 2) * 0.5
    fx = xo - np.floor(xo) - 0.5
    fy = y - np.floor(y)
    # Feder = oben runde Kante, Schaft in der Mitte
    edge = np.clip(1 - (fx * 2) ** 2 - (1 - fy) ** 2 * 0.6, 0, 1)
    shaft = np.exp(-(fx ** 2) / (2 * 0.02 ** 2)) * 0.4
    barbs = 0.5 + 0.5 * np.sin((fy * 40 + np.abs(fx) * 60))
    t = edge * 0.6 + barbs * 0.2 + shaft + noise(size, 2, 620 + seed) * 0.2
    _finish(name, t, edge * 0.8 + barbs * 0.2, dark, light, 4.0, grime=0.15, seed=seed)


def leather(name, dark, light, size=512, seed=0):
    base = fbm(size, 20, 630 + seed)
    pores = noise(size, 0.8, 631 + seed)
    cracks = np.abs(noise(size, 6, 632 + seed) - 0.5) < 0.02
    t = base * 0.7 + pores * 0.3 - cracks * 0.4
    _finish(name, t, pores * 0.5 + base * 0.5 - cracks * 0.6, dark, light, 2.5, seed=seed)


def burlap(name="burlap", dark="4a3522", light="9a7a52", size=512, seed=0):
    """Sackleinen: grobe Leinwandbindung."""
    y = np.arange(size)[:, None]
    x = np.arange(size)[None, :]
    period = size / 40
    wx = np.abs(np.sin(x / period * np.pi))
    wy = np.abs(np.sin(y / period * np.pi))
    over = (np.floor(x / period) + np.floor(y / period)) % 2
    weave = np.where(over > 0, wx * 0.8 + wy * 0.2, wy * 0.8 + wx * 0.2)
    fuzz = noise(size, 1.0, 640 + seed)
    t = weave * 0.55 + fuzz * 0.25 + fbm(size, 40, 641 + seed) * 0.4 - 0.1
    _finish(name, t, weave, dark, light, 4.0, grime=0.35, seed=seed)


def moss(name="moss", dark="16200e", light="5b7a2c", size=512, seed=0):
    clumps = fbm(size, 8, 650 + seed)
    fine = noise(size, 0.8, 651 + seed)
    drip = noise(size, 1.2, 652 + seed, aspect=0.05)
    t = clumps * 0.6 + fine * 0.25 + drip * 0.3 - 0.1
    _finish(name, t, clumps * 0.6 + drip * 0.4, dark, light, 4.0, grime=0.3, seed=seed)


def bark(name="bark", dark="1a1a10", light="4f5a2c", size=512, seed=0):
    ridges = noise(size, 1.5, 660 + seed, aspect=0.06)
    knots = fbm(size, 25, 661 + seed)
    t = ridges * 0.6 + knots * 0.5 - 0.1
    _finish(name, t, ridges, dark, light, 5.0, grime=0.3, seed=seed)


def bone(name="bone", dark="6e604a", light="e2d6b8", size=512, seed=0):
    base = fbm(size, 30, 670 + seed)
    pits = noise(size, 1.0, 671 + seed)
    t = base * 0.6 + pits * 0.2 + 0.25
    _finish(name, t, pits * 0.5 + base * 0.5, dark, light, 2.0, grime=0.4, seed=seed)


def skin(name, dark, light, size=512, seed=0):
    base = fbm(size, 35, 680 + seed)
    pores = noise(size, 0.7, 681 + seed)
    t = base * 0.7 + pores * 0.15 + 0.2
    _finish(name, t, pores, dark, light, 1.0, grime=0.25, seed=seed)


def cloth(name, dark, light, size=512, seed=0):
    """Grober, abgetragener Stoff für Kutten, Umhänge und Kostüme."""
    y = np.arange(size)[:, None]
    x = np.arange(size)[None, :]
    period = size / 64
    weave = 0.5 + 0.25 * (np.sin(x / period * np.pi * 2) + np.sin(y / period * np.pi * 2))
    wear = fbm(size, 30, 690 + seed)
    folds = noise(size, 12, 691 + seed, aspect=0.2)
    t = weave * 0.15 + wear * 0.55 + folds * 0.4 - 0.1
    _finish(name, t, weave * 0.4 + folds * 0.6, dark, light, 2.5, grime=0.35, seed=seed)


CHARACTER_TEXTURES = [
    lambda: fur("fur_grey", "1e1c1a", "8a8276", seed=1),
    lambda: feathers("feathers_black", "06050a", "3a3550", seed=2),
    lambda: leather("leather_dark", "120c08", "4e3524", seed=3),
    lambda: leather("leather_brown", "2a1a0e", "7a5232", seed=4),
    lambda: burlap(),
    lambda: moss(),
    lambda: bark(),
    lambda: bone(),
    lambda: skin("skin_pale", "8a8478", "d8d0c0", seed=5),
    lambda: skin("skin_witch", "5c6450", "aab094", seed=6),
    lambda: cloth("cloth_brown", "120c08", "4a3826", seed=7),
    lambda: cloth("cloth_black", "07060a", "2c2834", seed=8),
    lambda: cloth("cloth_purple", "1a0c24", "6a3c8a", seed=9),
    lambda: cloth("cloth_red", "2a0608", "8a1c20", seed=10),
    lambda: cloth("cloth_dark_purple", "0a0610", "34243e", seed=11),
    lambda: cloth("cloth_tan", "2e2216", "7c6448", seed=12),
]


ALL = [brick, lambda: wood(), floor_planks, felt, fabric, porcelain, metal, crate, cloth_dark]


def build_all() -> str:
    for fn in ALL + CHARACTER_TEXTURES:
        fn()
    return OUT_DIR


if __name__ == "__main__":
    print("Texturen in", build_all())
