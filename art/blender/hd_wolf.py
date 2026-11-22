"""Die Wölfin in HD (nach dem Konzeptbild „Am Spieltisch“, Feld 4):
graue Wölfin mit echter Schnauze, schwarzer Nase, heller Schnauzenpartie und Wangen,
dunklerer Stirn, schmalen gelben Augen und einem schlauen, leichten Grinsen.
Spitze Ohren ragen aus der roten Kapuze; roter Umhang über den Schultern, vorne offen,
mit zwei Messingknöpfen und Kordel; darunter rotes Mieder mit Spitzenkante und Brustfell.
Graue, fellige Hände mit dunklen Krallen.

    import hd_wolf; hd_wolf.build()
    hd_wolf.build(steps=("head",))    # nur Teile
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

import characters as ch
import hd
from geo import G

C = Vector((0, 0, 0.1))  # Schädelmitte (Head-Koordinaten)
HEAD_Y = 1.2
HEAD_SCALE = 1.4

RX, RY, RZ = 0.112, 0.12, 0.125      # Schädel
EYES = [(-0.05, 0.032), (0.05, 0.032)]
EYE_SLANT = 0.35                      # Außenwinkel höher (schmale, schlaue Augen)
FACE_HW, FACE_HH = 0.17, 0.2          # Ausschnitt der gemalten Gesichtstextur (um C)


def _g(a, s):
    return math.exp(-(a * a) / (2 * s * s))


def _sstep(e0, e1, x):
    t = min(1.0, max(0.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def _lerp_path(pts, t):
    t = max(0.0, min(1.0, t)) * (len(pts) - 1)
    i = min(int(t), len(pts) - 2)
    return pts[i].lerp(pts[i + 1], t - i)


def _lerp_table(table, x):
    """Stückweise linear in einer Tabelle [(x, y), …] (x aufsteigend)."""
    if x <= table[0][0]:
        return table[0][1]
    for (x0, y0), (x1, y1) in zip(table, table[1:]):
        if x0 <= x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    return table[-1][1]


# Oberlippenkante (rechte Seite, relativ zu C) von unter der Nase bis zum Mundwinkel;
# der Winkel ist nach oben gezogen → schlaues Grinsen
MOUTH = [Vector(p) for p in ((0.0, -0.226, -0.036), (0.012, -0.221, -0.04), (0.022, -0.208, -0.044),
                             (0.03, -0.185, -0.048), (0.037, -0.16, -0.052), (0.043, -0.125, -0.055),
                             (0.048, -0.102, -0.054), (0.052, -0.09, -0.049), (0.055, -0.083, -0.04), (0.056, -0.079, -0.032))]

# Lefzenlinie von vorne (x, z), rechte Seite; wird nach dem Bau der Schnauze durch die echten
# Oberflächenpunkte ersetzt (build_head → lips), damit Gemaltes und Form übereinstimmen
_LIP_XZ = [(p.x, p.z) for p in MOUTH]


# =====================================================================================
#  Texturen
# =====================================================================================

def face_masks(x, z):
    """Fellzeichnung des Gesichts (frontal, relativ zu C): (weiß, dunkel, schwarz) je 0..1.
    Gilt für die gemalte Textur und für die Farbe der Fellbüschel."""
    x = np.asarray(x, dtype=np.float64)
    z = np.asarray(z, dtype=np.float64)
    ax = np.abs(x)

    def g(a, s):
        return np.exp(-(a * a) / (2 * s * s))

    def ss(e0, e1, v):
        t = np.clip((v - e0) / (e1 - e0), 0, 1)
        return t * t * (3 - 2 * t)

    # weiß: Schnauzenseiten, Wangen, Kinn; der Nasenrücken bleibt grau
    white = ss(0.014, -0.008, z)
    white *= 1 - 0.85 * g(x, 0.017) * ss(-0.016, 0.0, z)
    white *= 1 - 0.6 * ss(0.1, 0.15, ax) * ss(-0.06, 0.0, z)
    # helle „Brauen“-Flecken über den Augen, innen tiefer (finsterer Blick)
    brow = 0.9 * g(ax - 0.05, 0.012) * g(z - (0.06 + 0.16 * (ax - 0.05)), 0.0065)
    white = np.clip(white + brow, 0, 1)
    # dunkel: Stirn, Nasenrücken, über den Augen, Tränenstrich vom inneren Augenwinkel
    dark = 0.9 * ss(0.04, 0.085, z) * (1 - ss(0.09, 0.15, ax))
    dark += 0.8 * g(x, 0.02) * ss(-0.012, 0.016, z) * (1 - ss(0.07, 0.1, z))
    tear = np.zeros_like(x)
    for ex, ez in EYES:
        s = 1 if ex > 0 else -1
        dark += 0.55 * g(x - ex, 0.022) * g(z - (ez + 0.014), 0.008)
        x0, z0, x1, z1 = s * 0.031, ez - 0.006, s * 0.04, ez - 0.034
        dx, dz = x1 - x0, z1 - z0
        t = np.clip(((x - x0) * dx + (z - z0) * dz) / (dx * dx + dz * dz), 0, 1)
        d = np.hypot(x - (x0 + t * dx), z - (z0 + t * dz))
        tear += g(d, 0.0035) * (1 - 0.6 * t)
    frown = np.zeros_like(x)
    for s in (-1, 1):
        for off, ln in ((0.006, 0.026), (0.014, 0.018)):
            x0, z0, x1, z1 = s * off, 0.047, s * (off + 0.006), 0.047 + ln
            dx, dz = x1 - x0, z1 - z0
            t = np.clip(((x - x0) * dx + (z - z0) * dz) / (dx * dx + dz * dz), 0, 1)
            frown += g(np.hypot(x - (x0 + t * dx), z - (z0 + t * dz)), 0.0018) * (1 - 0.5 * t)
    dark = np.clip(dark + 0.6 * tear + 0.7 * frown, 0, 1) * (1 - brow)
    # schwarz: Lidränder und Lefzen
    black = np.zeros_like(x)
    for ex, ez in EYES:
        s = 1 if ex > 0 else -1
        dx = x - ex
        dz = (z - ez) - s * EYE_SLANT * dx
        e = np.sqrt((dx / 0.021) ** 2 + (dz / 0.0105) ** 2)
        black += g(e - 1.0, 0.22)
    for (ax0, az0), (ax1, az1) in zip(_LIP_XZ, _LIP_XZ[1:]):
        for s in (-1, 1):
            x0, z0, x1, z1 = s * ax0, az0, s * ax1, az1
            dx, dz = x1 - x0, z1 - z0
            t = np.clip(((x - x0) * dx + (z - z0) * dz) / max(dx * dx + dz * dz, 1e-9), 0, 1)
            d = np.hypot(x - (x0 + t * dx), z - (z0 + t * dz))
            sg = 0.0016 + 0.0008 * max(0.0, 1 - (ax0 + ax1) * 0.5 / 0.035)  # schmal: sonst wirkt der Mund offen
            black = np.maximum(black, g(d, sg))
    # Nasenspalt (Philtrum) von der Nase zur Lippe
    black = np.maximum(black, g(x, 0.0016) * ss(-0.024, -0.028, z) * ss(-0.042, -0.036, z))
    return white, dark, np.clip(black, 0, 1)


def tex_face(size=1024, seed=91):
    """Gemaltes Gesichtsfell (frontal projiziert): grau, Stirn und Nasenrücken dunkler,
    Schnauze/Wangen/Kinn hell, schwarze Lidränder und Lefzen, feine Haarstriche."""
    r, c = np.mgrid[0:size, 0:size] / (size - 1)
    x = c * 2 * FACE_HW - FACE_HW
    z = r * 2 * FACE_HH - FACE_HH
    big = hd.fractal(size, 2.8, seed)
    mid = hd.fractal(size, 2.0, seed + 1)
    fine = hd.fractal(size, 0.8, seed + 2)
    # Haarstriche: feines Rauschen entlang der Fellrichtung verschmiert
    # (Stirn: nach oben, Wangen: nach außen-unten → grob senkrecht/schräg)
    strokes = np.zeros_like(fine)
    for k in range(12):
        strokes += np.roll(fine, k, axis=0)
    strokes = (strokes - strokes.min()) / (strokes.max() - strokes.min())
    white, dark, black = face_masks(x, z)

    grey = hd.srgb_to_linear((0.43, 0.41, 0.4))
    light = hd.srgb_to_linear((0.7, 0.68, 0.645))
    dk = hd.srgb_to_linear((0.2, 0.19, 0.19))
    col = grey[None, None, :] * (0.8 + 0.3 * big + 0.15 * mid)[..., None]
    col = col * (1 - white[..., None]) + light[None, None, :] * (0.9 + 0.15 * mid)[..., None] * white[..., None]
    col = col * (1 - dark[..., None]) + dk[None, None, :] * (0.85 + 0.3 * big)[..., None] * dark[..., None]
    col *= (0.82 + 0.3 * strokes)[..., None]
    col *= (1 - 0.92 * black)[..., None]
    # Fake-AO zu den Rändern hin
    col *= (1 - 0.25 * np.clip((np.abs(x) - 0.12) / 0.05, 0, 1))[..., None]
    height = strokes * 0.6 + big * 0.15 - black * 0.5
    return (hd.to_image("face_color", col ** (1 / 2.2)),
            hd.to_image("face_normal", hd.height_to_normal(height, 3.0), non_color=True))


MUZ_Y0, MUZ_Y1, MUZ_Z0, MUZ_Z1 = -0.245, -0.075, -0.115, 0.055  # Seitenprojektion (y, z) um C


def tex_muzzle(lip, size=512, seed=93):
    """Schnauzenseiten, von der Seite projiziert (U = Tiefe y, V = Höhe z): helles Fell mit
    Strichen nach hinten, oben grauer Nasenrücken, schwarze Lefze genau entlang `lip`
    (Liste von (y, z)), darunter ein schmaler Schatten."""
    r, c = np.mgrid[0:size, 0:size] / (size - 1)
    y = MUZ_Y0 + c * (MUZ_Y1 - MUZ_Y0)
    z = MUZ_Z0 + r * (MUZ_Z1 - MUZ_Z0)
    big = hd.fractal(size, 2.6, seed)
    fine = hd.fractal(size, 0.8, seed + 1)
    strokes = np.zeros_like(fine)
    for k in range(14):
        strokes += np.roll(fine, k, axis=1)
    strokes = (strokes - strokes.min()) / (strokes.max() - strokes.min())
    # Oberkante der Schnauze je Tiefe (wie snout()): oben grau
    t = np.clip((-0.06 - y) / 0.168, 0, 1)
    zt = 0.03 - 0.03 * t
    grey_k = np.clip((z - (zt - 0.022)) / 0.016, 0, 1)
    light = hd.srgb_to_linear((0.7, 0.68, 0.645))
    grey = hd.srgb_to_linear((0.43, 0.41, 0.4))
    col = light[None, None, :] * (1 - grey_k[..., None]) + grey[None, None, :] * grey_k[..., None]
    col *= (0.85 + 0.2 * big)[..., None] * (0.82 + 0.3 * strokes)[..., None]
    # Lefze
    d = np.full_like(y, 9.0)
    below = np.zeros_like(y)
    for (y0, z0), (y1, z1) in zip(lip, lip[1:]):
        dy, dz = y1 - y0, z1 - z0
        tt = np.clip(((y - y0) * dy + (z - z0) * dz) / max(dy * dy + dz * dz, 1e-9), 0, 1)
        dist = np.hypot(y - (y0 + tt * dy), z - (z0 + tt * dz))
        closer = dist < d
        below = np.where(closer, (z < z0 + tt * dz).astype(np.float64), below)
        d = np.minimum(d, dist)
    g = lambda a, sg: np.exp(-(a * a) / (2 * sg * sg))
    sg = 0.0018 + 0.0004 * np.clip((-0.19 - y) / 0.03, 0, 1)   # schmale, geschlossene Lefze
    black = g(d, sg)
    shadow = g(d, 0.006) * below
    col *= (1 - 0.35 * shadow)[..., None]
    col *= (1 - 0.93 * black)[..., None]
    height = strokes * 0.6 - black * 0.8 - shadow * 0.3
    return (hd.to_image("muzzle_color", col ** (1 / 2.2)),
            hd.to_image("muzzle_normal", hd.height_to_normal(height, 3.0), non_color=True))


def tex_tuft(name, root, tip, w=128, h=256, seed=81, strands=80, body=0.26):
    """Wie hd.tex_hair, aber feinere Strähnen und nur ein kurzer dichter Ansatz – das Büschel
    zerfällt zur Spitze in einzelne Haare (wirkt weniger wie ein Papierfetzen)."""
    rng = np.random.default_rng(seed)
    v, u = np.mgrid[0:h, 0:w]
    u = u / (w - 1)
    v = v / (h - 1)
    cov = np.zeros((h, w), np.float32)
    shade = np.zeros((h, w), np.float32)
    for _ in range(strands):
        c = rng.uniform(0.1, 0.9)
        length = rng.uniform(0.5, 1.0)
        width = rng.uniform(0.012, 0.03) * (1 - 0.85 * np.clip(v / length, 0, 1))
        bend = rng.uniform(-0.14, 0.14)
        uu = c + bend * v ** 2 + (0.5 - c) * 0.3 * v
        st = np.exp(-((u - uu) / np.maximum(width, 1e-3)) ** 2) * (v < length)
        bright = rng.uniform(0.6, 1.2)
        shade = np.where(st > cov, bright, shade)
        cov = np.maximum(cov, st)
    du = np.abs(u - 0.5) * 2
    solid = np.clip(1.2 - (v / body) ** 2, 0, 1) * np.clip(1.25 - du * 1.2, 0, 1)
    alpha = np.clip(np.maximum(cov * 2.2, solid), 0, 1)
    root_l, tip_l = hd.srgb_to_linear(root), hd.srgb_to_linear(tip)
    k = v[..., None] ** 1.2
    col = root_l[None, None, :] * (1 - k) + tip_l[None, None, :] * k
    col *= (0.55 + 0.5 * np.clip(shade, 0.6, 1.2) * cov + 0.2 * (1 - cov))[..., None]
    height = cov * 1.0 - du * 0.3
    return (hd.to_image(name + "_color", col ** (1 / 2.2), alpha=alpha),
            hd.to_image(name + "_normal", hd.height_to_normal(height, 3.0), non_color=True))


def tex_furskin(name, base, dark, size=512, seed=95, streak=14):
    """Gekachelte Fell-Oberfläche (Ohren, Hals, Hände, Unterarme): Haarstriche entlang V."""
    fine = hd.fractal(size, 0.9, seed)
    acc = np.zeros_like(fine)
    for k in range(streak):
        acc += np.roll(fine, k, axis=0)
    acc = (acc - acc.min()) / (acc.max() - acc.min())
    big = hd.fractal(size, 2.6, seed + 1)
    t = np.clip(0.55 * acc + 0.45 * big, 0, 1)
    base_l, dark_l = hd.srgb_to_linear(base), hd.srgb_to_linear(dark)
    col = dark_l + (base_l - dark_l) * (0.2 + 0.8 * t)[..., None]
    height = acc * 1.2 + big * 0.4
    return (hd.to_image(name + "_color", col ** (1 / 2.2)),
            hd.to_image(name + "_normal", hd.height_to_normal(height, 4.0), non_color=True))


def tex_bodice(size=512, seed=97):
    """Rotes Mieder mit dunklerem Damastmuster (Blütenrosetten, versetzt)."""
    y, x = np.mgrid[0:size, 0:size] / size
    cells = 4
    row = np.floor(y * cells)
    cx = ((x * cells + 0.5 * (row % 2)) % 1) - 0.5
    cy = ((y * cells) % 1) - 0.5
    r = np.hypot(cx, cy)
    th = np.arctan2(cy, cx)
    petal = 0.22 + 0.08 * np.cos(6 * th)
    motif = np.exp(-((r - petal) / 0.018) ** 2) + np.exp(-(r / 0.045) ** 2)
    motif += 0.7 * np.exp(-((r - 0.36 - 0.03 * np.cos(12 * th)) / 0.012) ** 2) * (r < 0.45)
    motif = np.clip(motif, 0, 1)
    big = hd.fractal(size, 2.6, seed)
    fine = hd.fractal(size, 1.0, seed + 1)
    weave = 0.5 + 0.5 * np.sin(x * math.tau * 160) * np.sin(y * math.tau * 160)
    base = hd.srgb_to_linear((0.58, 0.08, 0.06))
    dark = hd.srgb_to_linear((0.26, 0.025, 0.025))
    col = base[None, None, :] * (0.8 + 0.25 * big + 0.1 * fine)[..., None]
    col = col * (1 - 0.75 * motif[..., None]) + dark[None, None, :] * 0.75 * motif[..., None]
    col *= (0.9 + 0.1 * weave)[..., None]
    height = weave * 0.3 + big * 0.6 + motif * 0.8
    return (hd.to_image("bodice_color", col ** (1 / 2.2)),
            hd.to_image("bodice_normal", hd.height_to_normal(height, 3.0), non_color=True))


def tex_lace(w=512, h=64):
    """Cremefarbene Spitzenborte mit Bogenkante und Lochmuster (Alpha). U entlang, V nach oben."""
    v, u = np.mgrid[0:h, 0:w]
    u = u / w
    v = v / (h - 1)
    reps = 16
    cu = (u * reps) % 1 - 0.5
    edge = 0.72 + 0.25 * np.sqrt(np.clip(1 - (cu * 2) ** 2, 0, 1))
    alpha = (v < edge).astype(np.float32)
    # Löcher: Reihe kleiner Kreise und Bögen
    hole = np.hypot(cu, (v - 0.45) * 1.6) < 0.16
    hole |= np.abs(np.hypot(cu, (v - 0.72) * 1.2) - 0.3) < 0.05
    alpha[hole] = 0
    alpha[v < 0.12] = 1
    base = hd.srgb_to_linear((0.86, 0.78, 0.66))
    col = base[None, None, :] * (0.8 + 0.2 * (v < 0.12))[..., None] * np.ones((h, w, 1))
    height = alpha * 1.0
    return (hd.to_image("lace_color", col ** (1 / 2.2), alpha=alpha),
            hd.to_image("lace_normal", hd.height_to_normal(height, 2.0), non_color=True))


def materials():
    m = {}
    c, n = tex_face()
    m["face"] = hd.material("Wolf_Gesicht", c, n, rough=0.95, normal_strength=1.4, spec=0.08)
    for key, title, root, tip, seed in (("fur_blood", "Blut", (0.08, 0.01, 0.008), (0.3, 0.035, 0.028), 84),
                                        ("fur_light", "Hell", (0.36, 0.345, 0.335), (0.74, 0.72, 0.685), 81),
                                        ("fur_grey", "Grau", (0.14, 0.13, 0.13), (0.47, 0.45, 0.435), 82),
                                        ("fur_dark", "Dunkel", (0.045, 0.042, 0.045), (0.23, 0.22, 0.225), 83)):
        c, n = tex_tuft(key, root, tip, seed=seed)
        m[key] = hd.material("Wolf_Fell_" + title, c, n, rough=0.92, normal_strength=0.6,
                             double_sided=True, spec=0.12, alpha_clip=True)
    c, n = tex_furskin("furskin", (0.43, 0.41, 0.4), (0.15, 0.14, 0.14), seed=95)
    m["furskin"] = hd.material("Wolf_Fellhaut", c, n, rough=0.9, normal_strength=0.9, spec=0.15)
    c, n = tex_furskin("chest", (0.66, 0.64, 0.6), (0.35, 0.335, 0.32), seed=96)
    m["chest"] = hd.material("Wolf_Brustfell", c, n, rough=0.9, normal_strength=0.9, spec=0.15)
    c, n = hd.tex_skin("hands", (0.27, 0.26, 0.26), seed=98, pores=0.6, blotch=0.3)
    m["hands"] = hd.material("Wolf_Haende", c, n, rough=0.85, normal_strength=0.8, spec=0.15)
    c, n = hd.tex_scales("nose", (0.03, 0.028, 0.028), size=512, seed=99, cells=46)
    m["nose"] = hd.material("Wolf_Nase", c, n, rough=0.55, normal_strength=0.22, spec=0.35)
    m["lip"] = hd.material("Wolf_Lefze", color=(0.012, 0.01, 0.01, 1), rough=0.45, spec=0.4)
    m["ear_inner"] = hd.material("Wolf_Ohr_Innen", color=(0.36, 0.24, 0.23, 1), rough=0.8, spec=0.2,
                                 double_sided=True)
    m["eyewhite"] = hd.material("Wolf_Augenrand", color=(0.22, 0.1, 0.02, 1), rough=0.15, spec=0.8)
    m["iris"] = hd.material("Wolf_Iris", color=(1.0, 0.74, 0.16, 1), rough=0.1, spec=0.9,
                            emission=(1.0, 0.76, 0.22, 1), emission_strength=0.5)
    m["pupil"] = hd.material("Wolf_Pupille", color=(0.005, 0.004, 0.004, 1), rough=0.05, spec=1.0)
    c, n = hd.tex_cloth("cloth", (0.5, 0.07, 0.05), (0.17, 0.018, 0.016), seed=84, weave=120, rag=0.25)
    m["cloth"] = hd.material("Wolf_Umhang", c, n, rough=0.88, normal_strength=0.9, double_sided=True, spec=0.25)
    c, n = tex_bodice()
    m["bodice"] = hd.material("Wolf_Mieder", c, n, rough=0.7, normal_strength=0.7, spec=0.35)
    c, n = tex_lace()
    m["lace"] = hd.material("Wolf_Spitze", c, n, rough=0.85, double_sided=True, spec=0.2, alpha_clip=True)
    m["brass"] = hd.material("Wolf_Messing", color=(0.45, 0.31, 0.1, 1), rough=0.35, metal=0.85)
    m["cord"] = hd.material("Wolf_Kordel", color=(0.2, 0.025, 0.02, 1), rough=0.8)
    m["claw"] = hd.material("Wolf_Kralle", color=(0.018, 0.016, 0.015, 1), rough=0.75, spec=0.1)
    return m


# =====================================================================================
#  Fell-Werkzeug: viele Alpha-Büschel, mehrere Fellfarben in einem Objekt
# =====================================================================================

class Fur:
    """Sammelt Büschel; jedes Büschel bekommt eine Materialnummer (Fellfarbe).
    finish() dreht die Vorderseite jedes Büschels nach außen (Godot: sonst schwarze Flecken)."""

    def __init__(self, mats):
        self.mb = hd.MeshBuilder()
        self.mats = mats
        self.tufts = []

    def add(self, p, nrm, direction, length, width, mat=0, **kw):
        first = len(self.mb.bm.faces)
        hd.add_feather(self.mb, p, nrm, direction, length, width, **kw)
        self.tufts.append((first, len(self.mb.bm.faces), nrm.copy(), mat))

    def finish(self, name, parent=None, shade=None, mix=0.6):
        bm = self.mb.bm
        bm.faces.ensure_lookup_table()
        flip = []
        for a, b, nrm, mi in self.tufts:
            f = bm.faces[a]
            f.normal_update()
            if f.normal.dot(nrm) < 0:
                flip.extend(bm.faces[i] for i in range(a, b))
            for i in range(a, b):
                bm.faces[i].material_index = mi
        bmesh.ops.reverse_faces(bm, faces=flip)
        ob = self.mb.finish(name, self.mats[0], parent=parent)
        for mt in self.mats[1:]:
            ob.data.materials.append(mt)
        if shade is not None:
            hd.shade_like(ob, shade, mix)
        return ob


def _tone(x, z, rnd):
    """Fellfarbe eines Büschels nach der Gesichtszeichnung: 0 hell, 1 grau, 2 dunkel."""
    w, d, _b = face_masks(x, z)
    w, d = float(w), float(d)
    if w > rnd.uniform(0.35, 0.65):
        return 0
    if d > rnd.uniform(0.3, 0.6):
        return 2
    return 1


# =====================================================================================
#  Kopf (Head-Koordinaten, vorne = -Y)
# =====================================================================================

def face_shape(c: Vector, d: Vector) -> Vector:
    """Verformt die Schädelkugel zum Wolfskopf (c = Punkt relativ zur Mitte)."""
    x, z = c.x, c.z
    front = max(0.0, -d.y)
    off = Vector()
    # Schädel oben flacher, Gesicht vorne etwas flacher (die Schnauze sitzt davor)
    off.z -= 0.012 * max(0.0, d.z) ** 2
    off.y += 0.01 * front ** 3
    # Jochbögen: Kopf auf Augenhöhe und darunter breiter
    off.x += c.x * 0.22 * _g(z + 0.01, 0.045)
    # Stirnwulst über den Augen, innen tiefer gezogen (finster, schlau)
    for ex, ez in EYES:
        s = 1 if ex > 0 else -1
        brow_z = ez + 0.026 + 0.16 * (abs(x) - 0.05)
        off.y -= 0.014 * front * _g(x - ex, 0.026) * _g(z - brow_z, 0.012)
        # Augenhöhle (schräg)
        dx = x - ex
        dz = (z - ez) - s * EYE_SLANT * dx
        off.y += 0.016 * front * _g(dx, 0.017) * _g(dz, 0.011)
    # flache Rinne zwischen den Augen bis zum Stop
    off.y += 0.004 * front * _g(x, 0.01) * _g(z - 0.045, 0.03)
    return c + off


def _snout_section(y, zt, zb, w, n=28):
    """Querschnitt (oben flach, Seiten steil) der Schnauze bei Tiefe y."""
    pts = []
    zc, h = (zt + zb) * 0.5, (zt - zb) * 0.5
    for k in range(n):
        a = k / n * math.tau
        ca, sa = math.cos(a), math.sin(a)
        ex = 0.6 if sa > 0 else 0.85
        xx = w * math.copysign(abs(ca) ** ex, ca)
        zz = zc + h * math.copysign(abs(sa) ** (0.55 if sa > 0 else 0.9), sa)
        pts.append(C + Vector((xx, y, zz)))
    return pts


def snout():
    """Schnauze aus Oberkiefer, Unterkiefer, Wangenpolstern und Mundwinkel-Polstern."""
    mb = hd.MeshBuilder()
    secs = []
    for i in range(15):
        t = i / 14
        y = -0.06 - 0.168 * t
        zt = 0.03 - 0.03 * t - 0.005 * _g(t - 0.22, 0.1) + 0.004 * _g(t - 0.6, 0.2)  # Stop, Nasenrücken
        zb = -0.062 + 0.026 * t
        w = 0.046 - 0.026 * t ** 0.75
        secs.append(_snout_section(y, zt, zb, w))
    hd.loft(mb, secs, close_tip=True)
    upper = mb.bm
    mb2 = hd.MeshBuilder()
    secs = []
    for i in range(12):
        t = i / 11
        y = -0.05 - 0.14 * t
        zt = -0.05 + 0.006 * t
        zb = -0.094 + 0.04 * t
        w = 0.041 - 0.022 * t
        secs.append(_snout_section(y, zt, zb, w, n=24))
    hd.loft(mb2, secs, close_tip=True)
    parts = [upper, mb2.bm]
    for s in (-1, 1):
        parts.append(ch.geo.ellipsoid(Vector((0.031, 0.036, 0.033)), C + Vector((s * 0.058, -0.07, -0.026)), 24, 16))
        parts.append(ch.geo.ellipsoid(Vector((0.017, 0.022, 0.015)), C + Vector((s * 0.05, -0.088, -0.042)), 16, 12))
    return ch.geo.merge(*parts)


def build_head(rig, m, rnd):
    head = ch.Head((RX, RY, RZ), u=96, v=64)
    head.deform(face_shape)
    ch.eye_sockets(rig, head, EYES, size=(0.02, 0.011, 0.012), slant=EYE_SLANT, inset=0.004)
    eyeballs(rig, m)
    face_bm = ch.geo.merge(head.bm.copy(), snout())
    face = rig.headpart("Face", face_bm, m["face"], smooth=True, sharp_angle=None)
    # Schädel und Schnauze zu einer Form verschmelzen, dann frontal projizieren
    hd.organic(face, voxel=0.0016, smooth=3, faces=24000)
    fb = bmesh.new()
    fb.from_mesh(face.data)
    lip = lips(BVHTree.FromBMesh(fb))
    mouth_groove(fb, lip)
    hd.planar_uv(fb, C, FACE_HW, FACE_HH)
    tree = BVHTree.FromBMesh(fb)
    # kein offener Spalt: wirkte von vorne wie zwei schwarze Zähne (Konzept: geschlossener Grinser)
    global _LIP_XZ
    _LIP_XZ = [(q.x, q.z) for q in lip]
    c, n = tex_face()   # Gesicht neu malen, jetzt mit der echten Lefzenlinie
    hd.material("Wolf_Gesicht", c, n, rough=0.85, normal_strength=0.8, spec=0.2)
    # Schnauzenseiten: eigene Seitenprojektion, damit die Lefze genau sitzt
    c, n = tex_muzzle(sorted((q.y, q.z) for q in lip))
    m["muzzle"] = hd.material("Wolf_Schnauze", c, n, rough=0.85, normal_strength=0.8, spec=0.2)
    face.data.materials.append(m["muzzle"])
    uv = fb.loops.layers.uv.verify()
    fb.normal_update()
    for f in fb.faces:
        k = f.calc_center_median() - C
        if k.y < -0.09 and abs(k.x) < 0.075 and -0.105 < k.z < 0.03 and abs(f.normal.x) > 0.5:
            f.material_index = 1
            for loop in f.loops:
                q = loop.vert.co - C
                loop[uv].uv = ((q.y - MUZ_Y0) / (MUZ_Y1 - MUZ_Y0), (q.z - MUZ_Z0) / (MUZ_Z1 - MUZ_Z0))
    fb.to_mesh(face.data)
    sample_bm = fb.copy()
    fb.free()

    def surf(x, z, lift=0.0):
        """Punkt auf der Gesichtsvorderseite (Strahl von vorne)."""
        hit = tree.ray_cast(C + Vector((x, -0.5, z)), Vector((0, 1, 0)))
        if hit[0] is None:
            return C + Vector((x, -RY, z)), Vector((0, -1, 0))
        return hit[0] + hit[1] * lift, hit[1]

    lids(rig, m, surf)
    nose(rig, m)
    ear_frames = ears(rig, m, rnd)
    face_fur(rig, m, sample_bm, face, rnd)
    sample_bm.free()
    brows(rig, m, surf, rnd)
    neck_fur(rig, m, tree, rnd)
    hood(rig, m, ear_frames, rnd)
    return face


def eyeballs(rig, m):
    """Echte Augen: fast nur Iris (bernsteingelb), runde Pupille, dunkler Rand."""
    whites, irises, pupils = [], [], []
    look = Vector((0, -1, 0.15)).normalized()
    for mk in [o for o in rig.head.children if o.type == "EMPTY" and o.name.startswith("Eye")]:
        c = Vector(mk.location) + Vector((0, 0.011, 0.001))
        whites.append(ch.geo.ellipsoid(Vector((0.0135, 0.0125, 0.0118)), c, 20, 14))
        rot = Vector((0, -1, 0)).rotation_difference(look).to_matrix().to_4x4()
        iris = ch.geo.ellipsoid(Vector((0.0098, 0.0022, 0.0098)), Vector((0, 0, 0)), 18, 8)
        ch.geo.transform(iris, Matrix.Translation(c + look * 0.0112) @ rot)
        irises.append(iris)
        pup = ch.geo.ellipsoid(Vector((0.0034, 0.0012, 0.0034)), Vector((0, 0, 0)), 12, 6)  # rund (Pascal)
        ch.geo.transform(pup, Matrix.Translation(c + look * 0.0132) @ rot)
        pupils.append(pup)
    rig.headpart("Augapfel", ch.geo.merge(*whites), m["eyewhite"], smooth=True, sharp_angle=None)
    rig.headpart("Augapfel_Iris", ch.geo.merge(*irises), m["iris"], smooth=True, sharp_angle=None)
    rig.headpart("Augapfel_Pupille", ch.geo.merge(*pupils), m["pupil"], smooth=True, sharp_angle=None)


def lids(rig, m, surf):
    """Schwarze Lidränder (mandelförmig, schräg), Oberlid etwas gesenkt → lauernder Blick."""
    parts = []
    for ex, ez in EYES:
        s = 1 if ex > 0 else -1
        up, low = [], []
        for k in range(11):
            t = k / 10
            dx = (t - 0.5) * 0.046
            z = ez + 0.0075 - 0.0095 * (2 * t - 1) ** 2 + s * EYE_SLANT * dx - 0.002 * s * (t - 0.5)
            up.append(surf(ex + dx, z, 0.0008)[0])
        for k in range(9):
            t = k / 8
            dx = (t - 0.5) * 0.04
            z = ez - 0.0095 + 0.006 * (2 * t - 1) ** 2 + s * EYE_SLANT * dx
            low.append(surf(ex + dx, z, 0.0004)[0])
        parts.append(ch.geo.tube(up, [0.0012, 0.0024, 0.0031, 0.0035, 0.0037, 0.0037, 0.0035, 0.0031, 0.0027, 0.002,
                                      0.0012], seg=10))
        parts.append(ch.geo.tube(low, [0.001, 0.0016, 0.002, 0.0022, 0.0022, 0.0022, 0.002, 0.0016, 0.001], seg=8))
    rig.headpart("Face_Lids", ch.geo.merge(*parts), m["lip"], smooth=True, sharp_angle=None)


def lips(tree, steps=40):
    """Lefzenlinie (rechte Seite) auf der Schnauzenoberfläche: Entwurf MOUTH auf die Fläche
    gezogen und geglättet. Wird gemalt (Front- und Seitentextur) statt als Röhre gebaut –
    eine Röhre auf der Kante wirkt wie ein Draht."""

    def snap(p):
        hit = tree.find_nearest(C + p)
        return hit[0] - C if hit[0] is not None else p

    pts = [snap(_lerp_path(MOUTH, k / (steps - 1))) for k in range(steps)]
    for _ in range(4):
        sm = [pts[0]] + [(pts[i - 1] + pts[i] * 2 + pts[i + 1]) / 4 for i in range(1, steps - 1)] + [pts[-1]]
        pts = [snap(p) for p in sm]
        pts[0].x = 0.0
    return pts


def _dist_polyline(p, pts):
    """Abstand von p zur Polylinie pts und Parameter 0..1 des nächsten Punkts."""
    best, best_t = 9.0, 0.0
    n = len(pts)
    for i in range(n - 1):
        a, b = pts[i], pts[i + 1]
        ab = b - a
        t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-12)))
        d = (p - (a + ab * t)).length
        if d < best:
            best, best_t = d, (i + t) / (n - 1)
    return best, best_t


def mouth_groove(bm, lip, depth=0.0036, sigma=0.0019):
    """Mundfurche entlang der Lefze in die Gesichtsoberfläche drücken, darüber ein leichter
    Wulst (Oberlippe). Zu den Mundwinkeln flacher."""
    bm.normal_update()
    sides = [lip, [Vector((-q.x, q.y, q.z)) for q in lip]]
    for v in bm.verts:
        k = v.co - C
        if k.y > -0.06 or abs(k.x) > 0.075 or not -0.08 < k.z < -0.015:
            continue
        d, t = _dist_polyline(k, sides[0] if k.x >= 0 else sides[1])
        if d > 0.01:
            continue
        fade = 1.0 - 0.6 * _sstep(0.75, 1.0, t)
        above = k.z - (lip[min(int(t * (len(lip) - 1)), len(lip) - 1)].z)
        push = -depth * _g(d, sigma) * fade
        if above > 0:
            push += 0.0016 * _g(d - 0.004, 0.0022) * fade
        v.co += v.normal * push
    bm.normal_update()


def mouth_slit(rig, tree, lip):
    """Kurzer, offener Mundspalt vorne unter der Nase (im Konzept ist das Maul leicht geöffnet),
    tief in der Mundfurche. Void → in Godot pechschwarz."""
    front = [q for q in lip if q.x < 0.026]
    path = [Vector((-q.x, q.y, q.z)) for q in reversed(front)] + front[1:]
    pts, radii = [], []
    n = len(path)
    for k, q in enumerate(path):
        hit = tree.find_nearest(C + q)
        nrm = hit[1] if hit[0] is not None else Vector((0, -1, 0))
        pts.append(C + q - nrm * 0.0022)
        radii.append(0.0005 + 0.0022 * math.sin(math.pi * k / (n - 1)))
    rig.headpart("Void_Mouth", ch.geo.tube(pts, radii, seg=10), ch.void(), smooth=True, sharp_angle=None)


def nose(rig, m):
    """Schwarze Nasenkuppe wie beim echten Wolf: von vorne oben breit und kantig, unten schmaler
    (Herzform), flache Vorderseite, Mittelfurche (Philtrum) bis zur Lippe, kommaförmige
    Nasenlöcher, die seitlich nach außen-oben auslaufen, feine Pflasterstruktur, feucht glänzend."""
    nc = C + Vector((0.0, -0.229, -0.0085))
    NX, NY, NZ = 0.0192, 0.0165, 0.0142
    bm = ch.geo.ellipsoid(Vector((NX, NY, NZ)), nc, 44, 30)
    for v in bm.verts:
        k = v.co - nc
        w = k.z / NZ
        f = max(0.0, -k.y / NY)
        x = k.x
        if w < 0:  # unten schmaler → Herzform
            x *= 1 - 0.3 * min(1.0, -w) ** 1.4
        else:      # oben etwas breiter und kantiger
            x *= 1 + 0.07 * w
        y = k.y * (0.8 if k.y < 0 else 1.0)          # Vorderseite flacher
        z = k.z
        if w > 0.35:                                   # Oberseite flach, läuft in den Nasenrücken
            z -= (w - 0.35) * NZ * 0.3
            y += (w - 0.35) * 0.004
        # Philtrum: Furche vorne-unten in der Mitte
        y += 0.0032 * _g(k.x, 0.0021) * max(0.0, -w + 0.1) * f
        # leichte Delle oben in der Mitte (zwei Nasenhälften)
        z -= 0.0012 * _g(k.x, 0.003) * max(0.0, w)
        # Nasenflügel um die Löcher leicht aufgewölbt
        for s in (-1, 1):
            bulge = _g(k.x - s * 0.0125, 0.004) * _g(k.z + 0.0015, 0.0045) * f
            x += s * 0.0012 * bulge
            y -= 0.0018 * bulge
        v.co = nc + Vector((x, y, z))
    bm.normal_update()
    hd.planar_uv(bm, nc, 0.03, 0.03)
    tree = BVHTree.FromBMesh(bm)
    rig.headpart("Nose", bm, m["nose"], smooth=True, sharp_angle=None)

    def on_nose(px, pz, sink):
        hit = tree.ray_cast(nc + Vector((px, -0.2, pz)), Vector((0, 1, 0)))
        if hit[0] is None:
            return nc + Vector((px, -NY * 0.8, pz))
        return hit[0] - hit[1] * sink

    holes = []
    for s in (-1, 1):
        # Komma: innen vorne rund, dann seitlich nach außen-hinten und leicht hoch
        # rundes Loch vorne, Schlitz läuft seitlich nach außen und leicht nach unten
        path = [(0.0048, -0.0042), (0.0074, -0.0052), (0.0104, -0.0058), (0.013, -0.0066),
                (0.015, -0.0078), (0.0162, -0.0092)]
        radii = [0.0026, 0.0027, 0.002, 0.0013, 0.0009, 0.0005]
        pts = [on_nose(s * px, pz, r * 0.35) for (px, pz), r in zip(path, radii)]
        holes.append(ch.geo.tube(pts, radii, seg=10))
    rig.headpart("Void_Nostrils", ch.geo.merge(*holes), ch.void(), smooth=True, sharp_angle=None)


# --- Ohren ---------------------------------------------------------------------------

EAR_H, EAR_W = 0.22, 0.054


def _ear_frame(s):
    base = C + Vector((s * 0.07, 0.016, 0.085))
    tip = C + Vector((s * 0.15, 0.036, 0.3))
    up = (tip - base).normalized()
    face = Vector((s * 0.35, -1, 0.0))
    face = (face - up * face.dot(up)).normalized()  # Ohröffnung schaut nach vorne, leicht nach außen
    side = up.cross(face).normalized()
    if side.x * s < 0:
        side = -side
    return base, up, face, side


def _ear_w(v):
    return EAR_W * max(0.0, 1 - v ** 1.35) ** 0.85 * (1 + 0.12 * math.sin(math.pi * v))


def ears(rig, m, rnd):
    """Spitze Ohren: gewölbte Rückseite, hohle Vorderseite mit hellem Innenohr und Fellbüscheln."""
    parts, inner = [], []
    frames = []
    fur = Fur([m["fur_light"], m["fur_grey"], m["fur_dark"]])
    nv, nu = 16, 13
    for s in (-1, 1):
        base, up, face, side = _ear_frame(s)
        frames.append((s, base, up, face, side))

        def front(u, v):
            w = _ear_w(v)
            cup = 0.012 * (1 - u * u) * math.sin(math.pi * min(1.0, v * 1.1)) ** 0.6
            return base + up * (v * EAR_H) + side * (u * w) - face * cup + face * 0.006 * (1 - v)

        def back(u, v):
            w = _ear_w(v)
            th = 0.016 * (1 - u * u) ** 0.5 * (1 - v) ** 0.7 + 0.001
            return base + up * (v * EAR_H) + side * (u * w) - face * th + face * 0.006 * (1 - v) \
                - face * 0.012 * (1 - u * u) * 0.3

        bm = bmesh.new()
        F = [[bm.verts.new(front(j / (nu - 1) * 2 - 1, i / (nv - 1))) for j in range(nu)] for i in range(nv)]
        B = [[F[i][j] if j in (0, nu - 1) else bm.verts.new(back(j / (nu - 1) * 2 - 1, i / (nv - 1)))
              for j in range(nu)] for i in range(nv)]
        for i in range(nv - 1):
            for j in range(nu - 1):
                bm.faces.new((F[i][j], F[i + 1][j], F[i + 1][j + 1], F[i][j + 1]))
                bm.faces.new((B[i][j], B[i][j + 1], B[i + 1][j + 1], B[i + 1][j]))
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        parts.append(bm)
        # Innenohr: kleinere Fläche knapp vor der Höhlung
        ib = bmesh.new()
        rows = []
        for i in range(10):
            v = 0.3 + 0.55 * i / 9
            rows.append([ib.verts.new(front(u * 0.62, v) + face * 0.0015) for u in (k / 4 - 1 for k in range(9))])
        for i in range(9):
            for j in range(8):
                ib.faces.new((rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1]))
        inner.append(ib)
        # Fell: helle Büschel aus dem Innenohr, graue an den Rändern und hinten
        for _ in range(170):
            u = rnd.uniform(-0.75, 0.75)
            v = rnd.uniform(0.3, 0.68)
            p = front(u * 0.65, v) + face * 0.002
            d = up * 1.0 + face * 0.55 + side * (u * 0.8)
            L = rnd.uniform(0.022, 0.04) * (1.1 - v)
            fur.add(p, face, d, L, L * 0.5, mat=0, lift=0.4, curl=0.15, cup=0.1,
                    twist=rnd.uniform(-0.4, 0.4), along=4, across=3, shape=0.6)
        for _ in range(260):
            u = rnd.choice((-1, 1)) * rnd.uniform(0.75, 1.0)
            v = rnd.uniform(0.0, 0.85)
            p = back(u, v)
            nrm = (side * u - face * 0.4).normalized()
            d = up * 1.0 + side * (u * 0.4)
            L = rnd.uniform(0.016, 0.03) * (1.05 - v * 0.7)
            fur.add(p, nrm, d, L, L * 0.55, mat=1 if rnd.random() < 0.7 else 2, lift=0.25, curl=0.1, cup=0.1,
                    twist=rnd.uniform(-0.4, 0.4), along=4, across=3, shape=0.6)
        for _ in range(220):
            u = rnd.uniform(-0.8, 0.8)
            v = rnd.uniform(0.0, 0.75)
            p = back(u, v)
            nrm = -face
            d = up * 1.0 + side * (u * 0.3)
            L = rnd.uniform(0.014, 0.026)
            fur.add(p, nrm, d, L, L * 0.55, mat=2 if rnd.random() < 0.5 else 1, lift=0.15, curl=0.05, cup=0.1,
                    twist=rnd.uniform(-0.4, 0.4), along=4, across=3, shape=0.6)
    ear_bm = ch.geo.merge(*parts)
    ch.geo.box_uv(ear_bm, 0.12)
    ear_ob = rig.headpart("Ears", ear_bm, m["furskin"], smooth=True, sharp_angle=None)
    ib = ch.geo.merge(*inner)
    ch.geo.box_uv(ib, 0.1)
    rig.headpart("Ears_Inner", ib, m["ear_inner"], smooth=True, sharp_angle=None)
    fur.finish("Ears_Fur", parent=rig.head)
    return frames


# --- Gesichtsfell ----------------------------------------------------------------------

def face_fur(rig, m, sample_bm, face_ob, rnd):
    """Fell auf Stirn, Wangen, Schnauze und Kinn: kurz auf Schnauze und Stirn, lange,
    nach außen stehende Wangenbüschel (Backenbart). Farbe folgt der Gesichtszeichnung."""
    fur = Fur([m["fur_light"], m["fur_grey"], m["fur_dark"]])

    def keep(p, nrm):
        k = p - C
        if k.y > 0.015 or k.z > 0.2 or (k.z > 0.15 and k.y > -0.04):
            return False  # unter der Kapuze
        for ex, ez in EYES:
            if ((k.x - ex) / 0.03) ** 2 + ((k.z - ez) / 0.019) ** 2 < 1 and k.y < -0.06:
                return False
        if k.y < -0.211 and abs(k.x) < 0.026 and k.z > -0.03:
            return False  # Nase
        if k.y < -0.1 and abs(k.x) < 0.065 and -0.07 < k.z < -0.03 and nrm.z < 0.3:
            # Lefzenkante freihalten
            for q in MOUTH:
                if abs(abs(k.x) - q.x) < 0.008 and abs(k.y - q.y) < 0.02 and abs(k.z - q.z) < 0.007:
                    return False
        return True

    pts = hd.sample_surface(sample_bm, 11000, rnd, keep=keep)
    for p, nrm in pts:
        k = p - C
        s = 1 if k.x >= 0 else -1
        flow = Vector((noise.noise(k * 30), noise.noise(k * 30 + Vector((5, 0, 0))),
                       noise.noise(k * 30 + Vector((0, 9, 0))))) * 0.5
        on_snout = k.y < -0.115 and abs(k.x) < 0.06 and k.z > -0.075
        cheek = abs(k.x) > 0.07 and k.z < 0.035 and not on_snout
        chin = k.z < -0.065 and not cheek
        if on_snout:
            L = rnd.uniform(0.007, 0.012)
            d = Vector((s * 0.15, 1.0, 0.25)) + flow * 0.4   # Schnauzenfell liegt nach hinten an
            lift = 0.1
        elif cheek:
            reach = _sstep(0.07, 0.12, abs(k.x)) * _sstep(0.04, -0.03, k.z)
            L = rnd.uniform(0.018, 0.03) + 0.03 * reach * rnd.uniform(0.6, 1.0)
            d = Vector((s * 1.0, 0.35, -0.55)) + flow
            lift = 0.25 + 0.25 * reach
        elif chin:
            L = rnd.uniform(0.016, 0.028)
            d = Vector((s * 0.3, 0.2, -1.0)) + flow * 0.6
            lift = 0.3
        else:  # Stirn, zwischen den Augen, Schläfen
            L = rnd.uniform(0.014, 0.024) + 0.01 * _sstep(0.08, 0.12, abs(k.x))
            d = Vector((k.x * 3.0, 0.6, 1.0)) + flow * 0.5
            lift = 0.18
        tone = _tone(k.x, k.z, rnd)
        fur.add(p - nrm * 0.0015, nrm, d, L, L * rnd.uniform(0.32, 0.5), mat=tone, lift=lift,
                curl=rnd.uniform(0.05, 0.15), cup=0.12, twist=rnd.uniform(-0.5, 0.5), along=4, across=3,
                shape=0.6, sink=0.002)
    # dichtes, kurzes, anliegendes Fell auf Nasenrücken und Schnauzenseiten (sonst wirkt die
    # Schnauze wie Plastik)
    def keep_snout(p, nrm):
        k = p - C
        y_min = -0.245 if k.z < -0.024 else -0.214  # unter der Nase bis ganz vorn (Oberlippe)
        if not (y_min < k.y < -0.09 and abs(k.x) < 0.058 and -0.068 < k.z < 0.045):
            return False
        if k.y < -0.205 and abs(k.x) < 0.024 and k.z > -0.03:
            return False  # Nase
        for q in MOUTH:  # Lefze frei lassen
            if abs(abs(k.x) - q.x) < 0.006 and abs(k.y - q.y) < 0.016 and abs(k.z - q.z) < 0.005:
                return False
        return True
    for p, nrm in hd.sample_surface(sample_bm, 11000, rnd, keep=keep_snout):
        k = p - C
        s = 1 if k.x >= 0 else -1
        L = rnd.uniform(0.008, 0.014)
        if k.z < -0.024 and k.y < -0.2:   # Oberlippe vorne: Fell fällt nach unten-außen
            d = Vector((s * 0.6, 0.3, -1.0))
        else:
            d = Vector((s * 0.35 * min(1.0, abs(k.x) / 0.02), 1.0, 0.25 if k.z > -0.03 else -0.3))  # nach hinten
        fur.add(p - nrm * 0.001, nrm, d, L, L * rnd.uniform(0.45, 0.65), mat=_tone(k.x, k.z, rnd), lift=0.2,
                curl=0.03, cup=0.08, twist=rnd.uniform(-0.3, 0.3), along=3, across=3, shape=0.6, sink=0.001)
    fur.finish("Face_Fur", parent=rig.head, shade=face_ob, mix=0.55)


def brows(rig, m, surf, rnd):
    """Helle Brauenbüschel, innen abgesenkt und schräg nach außen-oben gekämmt."""
    fur = Fur([m["fur_light"], m["fur_grey"]])
    for ex, ez in EYES:
        s = 1 if ex > 0 else -1
        for _ in range(70):
            t = rnd.random()
            x = ex + s * (t - 0.4) * 0.04
            z = 0.06 + 0.16 * (abs(x) - 0.05) + rnd.uniform(-0.004, 0.004)
            p, n = surf(x, z, -0.001)
            d = Vector((s * 1.0, 0.2, 0.55 + 0.3 * t))
            L = rnd.uniform(0.014, 0.024)
            fur.add(p, n, d, L, L * 0.5, mat=0 if rnd.random() < 0.8 else 1, lift=rnd.uniform(0.2, 0.4),
                    curl=0.1, cup=0.1, twist=rnd.uniform(-0.4, 0.4), along=4, across=3, shape=0.6)
    fur.finish("Face_Brows", parent=rig.head)


def neck_fur(rig, m, tree, rnd):
    """Kehle und Hals: helle Halskrause unter dem Kinn, fällt zur Brust."""
    parts = []
    nb = ch.geo.tube([C + Vector((0, 0.0, -0.04)), C + Vector((0, 0.01, -0.14)), C + Vector((0, 0.02, -0.26))],
                     [0.085, 0.092, 0.1], seg=32)
    ch.geo.box_uv(nb, 0.12)
    sample = nb.copy()
    parts.append(nb)
    neck = rig.headpart("Neck", ch.geo.merge(*parts), m["chest"], smooth=True, sharp_angle=None)
    fur = Fur([m["fur_light"], m["fur_grey"]])

    def keep(p, nrm):
        k = p - C
        if nrm.y > 0.3 or not -0.24 < k.z < -0.05:
            return False
        return tree.ray_cast(p + nrm * 0.001, nrm, 0.06)[0] is None  # nicht im Kiefer versteckt

    for p, nrm in hd.sample_surface(sample, 1300, rnd, keep=keep):
        k = p - C
        s = 1 if k.x >= 0 else -1
        L = rnd.uniform(0.03, 0.05)
        d = Vector((s * 0.35 * abs(k.x) / 0.09, -0.15, -1.0))
        fur.add(p, nrm, d, L, L * 0.55, mat=0 if abs(k.x) < 0.06 or rnd.random() < 0.4 else 1,
                lift=rnd.uniform(0.25, 0.45), curl=0.12, cup=0.12, twist=rnd.uniform(-0.5, 0.5),
                along=4, across=3, shape=0.6)
    sample.free()
    fur.finish("Neck_Fur", parent=rig.head, shade=neck, mix=0.5)


# --- Kapuze ------------------------------------------------------------------------------

HOOD_C = C + Vector((0, -0.005, 0.03))
HRX, HRY, HRZ = 0.172, 0.155, 0.182
HOOD_BETA = 2.6   # Kapuze reicht beidseits bis 149° (unten offen für den Hals)


def _hood_rim(beta):
    """Winkel des Gesichtsausschnitts (von vorne gemessen) je Richtung beta (0 = oben)."""
    a = abs(beta)
    if a <= math.pi / 2:
        k = a / (math.pi / 2)
        return 0.86 + 0.3 * k * k * (3 - 2 * k)
    return 1.16 + 0.26 * (a - math.pi / 2) / (math.pi / 2)


def hood_point(beta, gam, folds=True):
    rr = 1 / math.sqrt((math.sin(beta) / HRX) ** 2 + (math.cos(beta) / HRZ) ** 2)
    d = Vector((math.sin(beta), 0, math.cos(beta)))
    p = d * rr * math.sin(gam) + Vector((0, -HRY * math.cos(gam), 0))
    if folds:
        n = p.normalized()
        warp = 1.6 * noise.noise(p * 8)
        near_rim = max(0.0, 1 - (gam - _hood_rim(beta)) / 0.7)
        f = 0.007 * math.sin(beta * 9 + warp) * (0.35 + 0.65 * near_rim)
        f += 0.004 * noise.noise(p * 22) + 0.006 * max(0.0, -p.z / 0.18) * math.sin(math.atan2(p.x, p.y) * 7 + warp)
        f += 0.008 * max(0.0, p.y / HRY) * math.sin(math.atan2(p.x, p.z) * 6 + warp)  # Raffung hinten
        p = p + n * f
    # die Krempe hängt vorne über die Stirn
    near = max(0.0, 1 - (gam - _hood_rim(beta)) / 0.55)
    top = max(0.0, math.cos(beta)) ** 2
    p.z -= 0.062 * near ** 2 * top
    p.y -= 0.008 * near ** 2 * top
    # unten fällt der Stoff auf die Schultern
    if p.z < -0.05:
        t = min(1.0, (-p.z - 0.05) / 0.15)
        p.x *= 1 + 0.5 * t
        p.y += 0.03 * t
        p.z -= 0.1 * t
    return HOOD_C + p


def hood(rig, m, ear_frames, rnd):
    """Rote Kapuze mit Falten, dickem Rollsaum am Gesichtsausschnitt und Löchern für die Ohren."""
    nj, ni = 96, 36
    rows, uvs = [], []
    for i in range(ni + 1):
        row, uvr = [], []
        for j in range(nj):
            beta = -HOOD_BETA + 2 * HOOD_BETA * j / (nj - 1)
            g0 = _hood_rim(beta)
            gam = g0 + (math.pi - g0) * (i / ni) ** 0.9
            row.append(hood_point(beta, gam))
            uvr.append((j / (nj - 1) * 3.2, i / ni * 1.6))
        rows.append(row)
        uvs.append(uvr)
    mb = hd.MeshBuilder()
    mb.grid(rows, uvs)
    hood_bm = mb.bm.copy()
    ob = mb.finish("Hood", m["cloth"], parent=rig.head)
    mod = ob.modifiers.new("Dicke", "SOLIDIFY")
    mod.thickness = 0.008
    mod.offset = 0.0
    # Rollsaum am Gesichtsausschnitt
    hem = []
    for j in range(nj):
        beta = -HOOD_BETA + 2 * HOOD_BETA * j / (nj - 1)
        p = hood_point(beta, _hood_rim(beta) + 0.02)
        hem.append(p + (p - HOOD_C).normalized() * 0.003)
    radii = [0.0075 + 0.0025 * math.sin(j * 0.8) * math.sin(j * 0.31) for j in range(nj)]
    parts = [ch.geo.tube(hem, radii, seg=10)]
    # Saum um die Ohrlöcher (die Ohren stoßen durch den Stoff)
    tree = BVHTree.FromBMesh(hood_bm)
    for s, base, up, face, side in ear_frames:
        hit = tree.ray_cast(base, up)
        if hit[0] is None:
            continue
        v = (hit[0] - base).dot(up) / EAR_H
        w = _ear_w(v) + 0.008
        ring = []
        for k in range(29):
            a = k / 28 * math.tau
            r = 1 + 0.12 * math.sin(a * 5 + s)
            q = hit[0] + side * (math.cos(a) * w * r) + face * (math.sin(a) * 0.017 * r - 0.006) + up * 0.004
            ring.append(q)
        parts.append(ch.geo.tube(ring, [0.0075 + 0.002 * math.sin(k * 1.3) for k in range(29)], seg=8))
    hood_bm.free()
    hb = ch.geo.merge(*parts)
    ch.geo.box_uv(hb, 0.1)
    rig.headpart("Hood_Hem", hb, m["cloth"], smooth=True, sharp_angle=None)
    return ob


# =====================================================================================
#  Körper (Torso-Koordinaten)
# =====================================================================================

PROFILE = [(0.24, -0.15), (0.25, 0.1), (0.24, 0.45), (0.26, 0.66), (0.276, 0.8), (0.288, 0.9),
           (0.268, 0.96), (0.212, 1.02), (0.135, 1.06), (0.07, 1.085), (0.03, 1.09)]
SX, SY, HUNCH = 1.45, 0.75, 0.05


def _radius(z):
    prof = PROFILE
    if z <= prof[0][1]:
        return prof[0][0]
    for (r0, z0), (r1, z1) in zip(prof, prof[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            t = t * t * (3 - 2 * t)
            return r0 + (r1 - r0) * t
    return prof[-1][0]


def _bust(x, z):
    return 0.032 * _g(abs(x) - 0.095, 0.052) * _g(z - 0.79, 0.05)


def body_point(th, z, out=0.0, folds=True):
    r = _radius(z)
    fold = 0.0
    if folds:
        warp = noise.noise(Vector((math.cos(th) * 2.0, math.sin(th) * 2.0, z * 1.5))) * 1.4
        amp = 0.004 * min(1.0, max(0.0, (0.75 - z) / 0.4)) + 0.001
        fold = amp * (0.7 * math.sin(th * 9 + warp) + 0.3 * math.sin(th * 19 + warp * 2))
    rr = r + fold + out
    x = rr * SX * math.cos(th)
    y = rr * SY * math.sin(th)
    if z > 0.72:
        t = min(1.0, (z - 0.72) / 0.4)
        y -= HUNCH * t * max(0.0, 1 - abs(x) / 0.5)
    y -= _bust(x, z) * max(0.0, -math.sin(th))
    bump = math.exp(-((abs(x) - 0.33) ** 2) / (2 * 0.075 ** 2)) * math.exp(-((z - 0.98) ** 2) / (2 * 0.07 ** 2))
    return Vector((x, y, z + 0.025 * bump))


def _th_front(x, z, out=0.0):
    r = _radius(z) + out
    cx = max(-0.999, min(0.999, x / (r * SX)))
    return -math.acos(cx)


def front_point(x, z, out=0.0):
    """Punkt vorne auf dem Körper an Stelle x, z (ohne Falten)."""
    return body_point(_th_front(x, z, out), z, out, folds=False)


def neckline(x):
    """Ausschnitt des Mieders (Herzform): Mitte tief, über der Brust hoch, seitlich tiefer."""
    ax = abs(x)
    return 0.872 - 0.068 * _g(x, 0.022) - 0.03 * _sstep(0.1, 0.2, ax)


def build_body(rig, m, rnd):
    tb = rig.torso
    mb = hd.MeshBuilder()
    zs = [-0.15 + i * 0.0105 for i in range(120)] + [1.1, 1.108]
    seg = 112
    rows, uvs = [], []
    for z in zs:
        rows.append([body_point(j / seg * math.tau, z) for j in range(seg)])
        uvs.append([(j / seg * 5.0, z * 2.5) for j in range(seg)])
    mb.grid(rows, uvs, close=True)
    # Material: oberhalb des Ausschnitts Brustfell, darunter Mieder
    for f in mb.bm.faces:
        cen = f.calc_center_median()
        top = neckline(cen.x) if cen.y < 0 else 0.95
        f.material_index = 1 if cen.z > top else 0
    body = mb.finish("Body", m["bodice"], parent=tb)
    body.data.materials.append(m["chest"])

    for side in (-1, 1):
        rig.marker("Shoulder_L" if side < 0 else "Shoulder_R", tb, Vector((side * 0.335, 0.02, 0.95)))

    # Spitzenborte am Ausschnitt
    lace = hd.MeshBuilder()
    n = 60
    xs = [-0.23 + 0.46 * k / (n - 1) for k in range(n)]
    length = 0.0
    prev = None
    bottom, top, uvb, uvt = [], [], [], []
    for x in xs:
        z = neckline(x)
        p0 = front_point(x, z - 0.006, 0.004)
        if prev is not None:
            length += (p0 - prev).length
        prev = p0
        p1 = front_point(x, z + 0.016, 0.009)
        bottom.append(p0)
        top.append(p1)
        uvb.append((length / 0.06, 0.0))
        uvt.append((length / 0.06, 1.0))
    lace.grid([bottom, top], [uvb, uvt])
    lo = lace.finish("Body_Lace", m["lace"], parent=tb)
    lo.modifiers.new("Dicke", "SOLIDIFY").thickness = 0.0015

    cape(rig, m, rnd)
    chest_fur(rig, m, body, rnd)

    # Hals (verdeckt fast ganz, schließt die Lücke zwischen Brust und Kopf)
    nb = ch.geo.lathe([(0.085, 0.95), (0.08, 1.1), (0.075, 1.25)], 24, 0.15)
    ch.geo.translate(nb, Vector((0, -0.02, 0)))
    rig.body("Body_Neck", nb, m["chest"], smooth=True, sharp_angle=None)


def chest_fur(rig, m, body, rnd):
    """Brustfell zwischen Kehle und Mieder: hell in der Mitte, grau zu den Seiten, mit ein paar
    Blutspritzern (Pascal: „sie spielt, um zu überleben“)."""
    fur = Fur([m["fur_light"], m["fur_grey"], m["fur_blood"]])
    spl = [Vector((rnd.uniform(-0.09, 0.09), 0, rnd.uniform(0.93, 1.04))) for _ in range(3)]
    for _ in range(1500):
        x = rnd.uniform(-0.2, 0.2)
        z = rnd.uniform(neckline(x) + 0.004, 1.085)
        th = _th_front(x, z)
        p = body_point(th, z, folds=False)
        e = 0.004
        a = body_point(th + e, z, folds=False) - p
        b = body_point(th, z + e, folds=False) - p
        nrm = a.cross(b).normalized()
        if nrm.y > 0:
            nrm = -nrm
        d = Vector((x * 1.4, -0.25, -1.0))
        L = rnd.uniform(0.025, 0.045)
        tone = 0 if abs(x) < rnd.uniform(0.03, 0.1) and rnd.random() < 0.75 else 1
        for k, sp in enumerate(spl):  # Spritzer: Fleck + Tropfenspur nach unten
            r_sp = 0.006 + 0.003 * (k % 2)
            dz = z - sp.z
            if math.hypot(x - sp.x, dz * (0.6 if dz < 0 else 1.0)) < r_sp * rnd.uniform(0.6, 1.1):
                tone = 2
        fur.add(p - nrm * 0.002, nrm, d, L, L * 0.55, mat=tone, lift=rnd.uniform(0.15, 0.35), curl=0.1,
                cup=0.12, twist=rnd.uniform(-0.5, 0.5), along=4, across=3, shape=0.6)
    fur.finish("Body_Fur", parent=rig.torso, shade=body, mix=0.5)


# Öffnung des Umhangs vorne (halbe Breite in x je Höhe z)
CAPE_OPEN = [(0.3, 0.6), (0.55, 0.5), (0.7, 0.42), (0.8, 0.33), (0.88, 0.24), (0.95, 0.16), (1.0, 0.12),
             (1.1, 0.075), (1.2, 0.06)]


def _cape_out(z):
    return 0.05 + 0.15 * _sstep(1.0, 0.62, z)


def _cape_r(z):
    """Radius des Umhangs: folgt dem Körper, oben um den Hals gerafft (unter der Kapuze)."""
    r = max(_radius(z), 0.15) + _cape_out(z)
    k = _sstep(1.04, 1.2, z)
    return r * (1 - k) + 0.1 * k


def cape_point(th, z, folds=True):
    r = _cape_r(z)
    fold = 0.0
    if folds:
        warp = noise.noise(Vector((math.cos(th) * 1.6, math.sin(th) * 1.6, z * 1.2))) * 1.7
        amp = 0.005 + 0.03 * _sstep(0.98, 0.45, z) + 0.012 * _sstep(1.04, 1.14, z)
        fold = amp * (0.65 * math.sin(th * 8 + warp) + 0.35 * math.sin(th * 17 + warp * 1.7 + 1.0))
    rr = r + fold
    sx = SX + (1.12 - SX) * _sstep(1.04, 1.2, z)   # am Hals rund
    x = rr * sx * math.cos(th)
    y = rr * (SY + (1.0 - SY) * _sstep(1.04, 1.2, z)) * math.sin(th) - 0.02 * _sstep(1.04, 1.2, z)
    if z > 0.72:
        t = min(1.0, (z - 0.72) / 0.4)
        y -= HUNCH * t * max(0.0, 1 - abs(x) / 0.5)
    bump = math.exp(-((abs(x) - 0.36) ** 2) / (2 * 0.09 ** 2)) * math.exp(-((z - 0.98) ** 2) / (2 * 0.08 ** 2))
    return Vector((x, y, z + 0.03 * bump))


def _cape_edge(z):
    """Winkel der rechten Vorderkante; links gespiegelt."""
    r = _cape_r(z)
    sx = SX + (1.12 - SX) * _sstep(1.04, 1.2, z)
    c = _lerp_table(CAPE_OPEN, z) / (r * sx)
    return -math.acos(max(-0.999, min(0.999, c)))


SHOULDER = Vector((0.335, 0.02, 0.95))
HAND_REST = Vector((0.085, -0.56, 0.88))   # G(±0.085, 0.9, 0.22) in Torso-Koordinaten


def _upper_arms():
    """Oberarm-Achsen (Schulter → Ellbogen) in Ruhelage, wie Godot sie per IK stellt."""
    arms = []
    for s in (-1, 1):
        sh = Vector((s * SHOULDER.x, SHOULDER.y, SHOULDER.z))
        hp = Vector((s * HAND_REST.x, HAND_REST.y + 0.05, HAND_REST.z))
        arms.append((sh, hd.arm_ik(sh, hp, s)))
    return arms


def _drape_over_arms(p, arms, r_arm=0.1):
    """Schiebt Umhangpunkte vor die Oberarme (Stoff fällt über den Arm statt dahinter)."""
    for a, b in arms:
        ab = b - a
        # Projektion in der x-z-Ebene (von vorne gesehen)
        ab2 = Vector((ab.x, ab.z))
        t = max(0.0, min(1.0, Vector((p.x - a.x, p.z - a.z)).dot(ab2) / ab2.length_squared))
        q = a + ab * t
        dist = math.hypot(p.x - q.x, p.z - q.z)
        if dist < r_arm + 0.06:
            w = 1.0 if dist < r_arm else 1 - _sstep(0.0, 0.06, dist - r_arm)
            cover = math.sqrt(max(0.0, r_arm * r_arm - min(dist, r_arm) ** 2))
            y_front = q.y - cover - 0.025
            if p.y > y_front:
                p.y += (y_front - p.y) * w
    return p


def cape(rig, m, rnd):
    """Roter Umhang: liegt über Schultern und Oberarmen, fällt hinten und seitlich, vorne offen."""
    arms = _upper_arms()
    mb = hd.MeshBuilder()
    zs = [0.3 + i * 0.01 for i in range(89)]
    n = 110
    rows, uvs = [], []
    for z in zs:
        th_r = _cape_edge(z)
        span = math.pi - 2 * th_r
        row, uvr = [], []
        for j in range(n):
            th = th_r + span * j / (n - 1)  # von rechts vorne über hinten nach links vorne
            p = cape_point(th, z)
            if math.sin(th) < 0.3:  # nur vorne/seitlich
                p = _drape_over_arms(p, arms)
            row.append(p)
            uvr.append((j / (n - 1) * 5.0, z * 2.4))
        rows.append(row)
        uvs.append(uvr)
    mb.grid(rows, uvs)
    ob = mb.finish("Body_Cape", m["cloth"], parent=rig.torso)
    mod = ob.modifiers.new("Dicke", "SOLIDIFY")
    mod.thickness = 0.01
    mod.offset = 0.0
    # Rollsäume an beiden Vorderkanten
    parts = []
    for idx in (0, n - 1):
        edge = [rows[i][idx] for i in range(len(rows))]
        radii = [0.008 + 0.002 * math.sin(i * 0.5) for i in range(len(edge))]
        parts.append(ch.geo.tube(edge, radii, seg=10))
    hb = ch.geo.merge(*parts)
    ch.geo.box_uv(hb, 0.1)
    rig.body("Body_Cape_Hem", hb, m["cloth"], smooth=True, sharp_angle=None)

    # Zwei Messingknöpfe an den Kanten, dazwischen eine durchhängende Kordel
    zb = 0.965
    btn, ends = [], []
    for s in (-1, 1):
        th = _cape_edge(zb)
        if s < 0:
            th = -math.pi - th
        p = cape_point(th, zb, folds=False)
        p += Vector((-s * 0.012, -0.012, 0))
        nrm = Vector((s * 0.25, -1, 0.15)).normalized()
        b = ch.geo.lathe([(0.0, 0.0), (0.019, 0.0), (0.02, 0.005), (0.015, 0.01), (0.0, 0.012)], 24, 0.1)
        rot = Vector((0, 0, 1)).rotation_difference(nrm).to_matrix().to_4x4()
        ch.geo.transform(b, Matrix.Translation(p) @ rot)
        btn.append(b)
        ends.append(p + nrm * 0.006)
    rig.body("Body_Buttons", ch.geo.merge(*btn), m["brass"], smooth=True, sharp_angle=None)
    cord = []
    for k in range(25):
        t = k / 24
        p = ends[0].lerp(ends[1], t)
        p.z -= 0.035 * math.sin(math.pi * t)
        p.y = min(p.y, front_point(p.x, p.z).y - 0.028)
        cord.append(p)
    rig.body("Body_Cord", ch.geo.tube(cord, [0.0035] * 25, seg=8), m["cord"], smooth=True, sharp_angle=None)


# =====================================================================================
#  Hände und Arme
# =====================================================================================

def hand_fur(hand, side, m, rnd, size, roll=72.0, pitch=-0.45, wrist_back=0.06, wrist_up=0.0):
    """Fell auf Handrücken und Handgelenk (Kind der Hand, gleiche Koordinaten)."""
    orient = Matrix.Translation(Vector((0, wrist_back, wrist_up))) @ \
        Matrix.Rotation(math.radians(side * roll), 4, "Y") @ Matrix.Rotation(pitch, 4, "X")
    inv = orient.inverted()
    rot_inv = inv.to_3x3()
    bm = bmesh.new()
    bm.from_mesh(hand.data)

    def keep(p, nrm):
        q = inv @ p
        n = rot_inv @ nrm
        if q.y > -0.01 * size:
            return True                      # Handgelenk rundum
        return q.y > -0.08 * size and n.z > 0.25  # Handrücken
    fur = Fur([m["fur_grey"], m["fur_dark"], m["fur_light"]])
    for p, nrm in hd.sample_surface(bm, 380, rnd, keep=keep):
        q = inv @ p
        d = orient.to_3x3() @ Vector((0, -1, 0.15))  # Fell läuft zu den Fingern
        L = rnd.uniform(0.014, 0.026) * (1.3 if q.y > 0 else 1.0)
        fur.add(p, nrm, d, L, L * 0.55, mat=0 if rnd.random() < 0.7 else (1 if rnd.random() < 0.6 else 2),
                lift=0.2, curl=0.08, cup=0.1, twist=rnd.uniform(-0.4, 0.4), along=4, across=3, shape=0.6)
    bm.free()
    ob = fur.finish(hand.name + "_Fur", parent=hand)
    ob.location = (0, 0, 0)
    return ob


def fur_forearm(name, m, rnd, r0=0.06, r1=0.05, length=hd.ARM_SEGMENT, count=1300):
    """Unterarm aus Fell: Röhre (Länge 1 entlang Z) mit Büscheln im selben Mesh.
    Godot streckt das Stück entlang Z auf die Armlänge → Büschel vorher in Z stauchen."""
    mb = hd.MeshBuilder()
    rows, uvs = [], []
    n_r, n_z = 32, 24
    for i in range(n_z + 1):
        t = i / n_z
        z = -0.5 + t
        r = r0 + (r1 - r0) * t
        row, uvr = [], []
        for j in range(n_r):
            a = j / n_r * math.tau
            bump = 0.003 * noise.noise(Vector((math.cos(a) * 2, math.sin(a) * 2, z * 4)))
            row.append(Vector(((r + bump) * math.cos(a), (r + bump) * math.sin(a), z)))
            uvr.append((j / n_r * 2, t * 2.5))
        rows.append(row)
        uvs.append(uvr)
    vs = mb.grid(rows, uvs, close=True)
    mb.bm.faces.new(list(reversed(vs[0])))
    mb.bm.faces.new(vs[-1])
    n_tube = len(mb.bm.faces)
    # Büschel in echten Maßen bauen, dann Z durch die Länge teilen
    fb = Fur([m["fur_grey"], m["fur_dark"], m["fur_light"]])
    for _ in range(count):
        t = rnd.random()
        a = rnd.random() * math.tau
        r = r0 + (r1 - r0) * t
        p = Vector((r * math.cos(a), r * math.sin(a), (t - 0.5) * length))
        nrm = Vector((math.cos(a), math.sin(a), 0))
        d = Vector((0, 0, 1)) + nrm * 0.15
        L = rnd.uniform(0.024, 0.04) * (1.25 if t > 0.85 else 1.0)
        rr = rnd.random()
        tone = 2 if rr < 0.08 else (1 if rr < 0.55 else 0)
        fb.add(p - nrm * 0.002, nrm, d, L, L * rnd.uniform(0.35, 0.5), mat=tone, lift=rnd.uniform(0.15, 0.35),
               curl=0.1, cup=0.1,
               twist=rnd.uniform(-0.5, 0.5), along=4, across=3, shape=0.6)
    fbm = fb.mb.bm
    fbm.faces.ensure_lookup_table()
    flip = []
    for a_, b_, nrm, mi in fb.tufts:
        f = fbm.faces[a_]
        f.normal_update()
        if f.normal.dot(nrm) < 0:
            flip.extend(fbm.faces[i] for i in range(a_, b_))
        for i in range(a_, b_):
            fbm.faces[i].material_index = mi + 1
    bmesh.ops.reverse_faces(fbm, faces=flip)
    for v in fbm.verts:
        v.co.z /= length
    # zusammenführen (UV-Ebene gleich benannt)
    me = bpy.data.meshes.new("_tmp_fur")
    fbm.to_mesh(me)
    fbm.free()
    mb.bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    ob = mb.finish(name, m["furskin"])
    for key in ("fur_grey", "fur_dark", "fur_light"):
        ob.data.materials.append(m[key])
    return ob


def hands_and_sleeve(rig, m, rnd):
    """Graue Krallenhände + Arme ganz unter dem roten Umhangstoff (Fell am Handgelenk)."""
    size = 1.08
    hands = [hd.grip_hand(side, m["hands"], None, size=size, thick=0.95, knobby=0.35, pitch=-0.45,
                          finger_len=1.15, claw=0.02, claw_mat=m["claw"], wrist_back=0.06, wrist_up=0.0)
             for side in (-1, 1)]
    for side, h in zip((-1, 1), hands):
        h.location = G(side * 0.085, 0.9, 0.22)  # Ruhelage: beide Hände halten den Fächer unten
        hand_fur(h, side, m, rnd, size)
    upper = hd.sleeve_segment("SleeveUpper", m["cloth"], 0.105, 0.088, folds=1.6, bunch_end=0.8, seed=1)
    fore = hd.sleeve_segment("SleeveFore", m["cloth"], 0.092, 0.078, cuff=0.012, folds=1.4, seed=2)  # Konzept: Arme unter dem Umhang
    hd.preview_arms(upper, fore, hands[0], hands[1])


# =====================================================================================

def scale_head(rig, s):
    """Kopf als Ganzes vergrößern (um die Schädelmitte), Augen-Marker mit."""
    for ob in rig.head.children:
        ob.location = C + (Vector(ob.location) - C) * s
        if ob.type == "MESH":
            ob.data.transform(Matrix.Scale(s, 4))


def build(steps=("head", "body", "hands"), seed=17):
    rnd = random.Random(seed)
    if set(steps) >= {"head", "body", "hands"}:
        hd.clear_scene()
    rig = ch.Rig(HEAD_Y)
    m = materials()
    if "head" in steps:
        build_head(rig, m, rnd)
        scale_head(rig, HEAD_SCALE)
    if "body" in steps:
        build_body(rig, m, rnd)
    if "hands" in steps:
        hands_and_sleeve(rig, m, rnd)
    return rig
