"""Der Gaukler in HD (nach dem Konzeptbild „Am Spieltisch“, Feld 5):
Narrenkappe aus rotem und goldenem Stoff, die eng um das Gesicht liegt, fünf hängende, sich
windende Zipfel mit goldenen Schellen; glatte, elfenbeinfarbene Porzellanmaske mit breitem,
unheimlichem Grinsen (obere Zahnreihe sichtbar), schwarzen Rauten über und unter den Augen und
glühenden goldenen Augen; großer, mehrlagiger Halskragen (Halskrause) in Creme; Wams im
Harlekin-Rautenmuster (rot, orange, gold, weinrot); hagere, gelblich-blasse Hände mit langen,
knochigen Fingern, dunklen Nägeln und Rüschen an den Handgelenken.

    import hd_jester; hd_jester.build()
    hd_jester.build(steps=("head",))    # nur Teile
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

# Maske (Head-Koordinaten relativ zu C, vor dem Skalieren)
RX, RY, RZ = 0.118, 0.13, 0.165
EYES = [(-0.057, 0.03), (0.057, 0.03)]
EYE_W, EYE_H, EYE_SLANT = 0.025, 0.0135, 0.16  # halbe Breite/Höhe der Augenöffnung, Außenwinkel höher
# Grinsen: Mundwinkel (x = ±MW, z = MZC), Oberlippe Mitte MZU, Unterlippe Mitte MZL
MW, MZC, MZU, MZL = 0.088, -0.039, -0.086, -0.118
# Lachfalte (rechte Seite, links gespiegelt): vom Nasenflügel um die Wangen-Äpfel zum Mundwinkel
CREASE = [(0.027, -0.036), (0.045, -0.047), (0.068, -0.05), (0.088, -0.04), (0.1, -0.018)]
FACE_HW, FACE_HH = 0.135, 0.215  # Ausschnitt der gemalten Maskentextur (um C)


# =====================================================================================
#  Hilfen
# =====================================================================================

def _g(a, s):
    return math.exp(-(a * a) / (2 * s * s))


def _sstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def _np_sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def _zu(x):
    """Oberlippen-Linie (z) an Stelle x – geht für numpy-Arrays und Zahlen."""
    u = np.minimum(np.abs(x) / MW, 1.0)
    return MZU + (MZC - MZU) * u ** 2.2


def _zl(x):
    u = np.minimum(np.abs(x) / MW, 1.0)
    return MZL + (MZC - MZL) * u ** 1.7


def _eye_rho(x, z, ex, ez):
    """Abstandsmaß zur Augenmitte (1 = Rand der mandelförmigen Öffnung), schräg gestellt."""
    s = 1 if ex > 0 else -1
    th = -s * EYE_SLANT
    dx, dz = x - ex, z - ez
    lx = dx * math.cos(th) - dz * math.sin(th)
    lz = dx * math.sin(th) + dz * math.cos(th)
    # Mandel: oben/unten spitzer zu den Winkeln hin
    k = 1 + 0.35 * (lx / EYE_W) ** 2
    return np.sqrt((lx / EYE_W) ** 2 + (lz * k / EYE_H) ** 2)


def _eye_outline(ex, ez, a, grow=1.0):
    """Punkt (x, z) auf dem Rand der Augenöffnung bei Winkel a."""
    s = 1 if ex > 0 else -1
    lx = EYE_W * grow * math.cos(a)
    k = 1 + 0.35 * math.cos(a) ** 2
    lz = EYE_H * grow * math.sin(a) / k
    th = s * EYE_SLANT
    return (ex + lx * math.cos(th) - lz * math.sin(th), ez + lx * math.sin(th) + lz * math.cos(th))


def _poly_dist(px, pz, pts):
    """Abstand zu einer Polylinie (numpy oder Zahl)."""
    best = None
    for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
        dx, dz = x1 - x0, z1 - z0
        t = np.clip(((px - x0) * dx + (pz - z0) * dz) / (dx * dx + dz * dz), 0, 1)
        d = np.hypot(px - (x0 + t * dx), pz - (z0 + t * dz))
        best = d if best is None else np.minimum(best, d)
    return best


def _diamond(x, z, cx, ztop, zbot, hw, p=0.78, soft=0.0012):
    """Raute mit leicht eingezogenen Seiten (0..1, weiche Kante)."""
    cz, hh = (ztop + zbot) / 2, (ztop - zbot) / 2
    q = (np.abs(x - cx) / hw) ** p + (np.abs(z - cz) / hh) ** p
    return np.clip((1 - q) * hw / soft * 0.5, 0, 1)


def _catmull(pts, n):
    """Glatte Kurve durch Kontrollpunkte (Catmull-Rom), n Punkte."""
    P = [pts[0] + (pts[0] - pts[1])] + list(pts) + [pts[-1] + (pts[-1] - pts[-2])]
    out = []
    segs = len(pts) - 1
    for k in range(n):
        t = k / (n - 1) * segs
        i = min(int(t), segs - 1)
        f = t - i
        p0, p1, p2, p3 = P[i], P[i + 1], P[i + 2], P[i + 3]
        f2, f3 = f * f, f * f * f
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f2 +
                          (-p0 + 3 * p1 - 3 * p2 + p3) * f3))
    return out


def _superellipsoid(half, e=0.35, u=14, v=10):
    """Abgerundeter Quader (Zähne): Kugel, deren Punkte zu den Ecken gezogen werden."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0)
    for vt in bm.verts:
        c = vt.co
        vt.co = Vector((math.copysign(abs(c.x) ** e, c.x) * half.x, math.copysign(abs(c.y) ** e, c.y) * half.y,
                        math.copysign(abs(c.z) ** e, c.z) * half.z))
    return bm


def _frame_tube(mb, pts, radii, seg, flat=1.0, wrinkle=0.0, split=None, uv_len=0.05, phase=0.0, twist=0.0):
    """Röhre wie geo.tube, aber im MeshBuilder: abgeflachter Querschnitt (flat), Stoff-Knitter
    (wrinkle) und Längsteilung in zwei Materialien (split = Winkel der Naht, Bogenmaß; twist =
    Drehung der Naht bis zur Spitze).
    Gibt die Materialnummern der Flächen und die Rahmen (Punkt, Normale, Binormale) zurück."""
    n = len(pts)
    tang = [(pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized() for i in range(n)]
    ref = Vector((0, -1, 0)) if abs(tang[0].y) < 0.9 else Vector((1, 0, 0))
    nrm = (ref - tang[0] * ref.dot(tang[0])).normalized()
    rows, uvs, frames = [], [], []
    length = 0.0
    for i in range(n):
        t = tang[i]
        nrm = (nrm - t * nrm.dot(t)).normalized()
        bi = t.cross(nrm)
        if i > 0:
            length += (pts[i] - pts[i - 1]).length
        frames.append((pts[i], nrm.copy(), bi.copy()))
        row, uvr = [], []
        for k in range(seg):
            a = math.tau * k / seg
            w = 1.0
            if wrinkle:
                w += wrinkle * (0.6 * math.sin(i * 0.9 + a * 2 + phase) * math.sin(a * 3 + i * 0.37) +
                                0.4 * noise.noise(Vector((math.cos(a) * 1.5, math.sin(a) * 1.5, i * 0.21 + phase))))
            r = radii[i] * w
            row.append(pts[i] + (nrm * math.cos(a) * flat + bi * math.sin(a)) * r)
            uvr.append((k / seg * 2.0, length / uv_len))
        rows.append(row)
        uvs.append(uvr)
    first = len(mb.bm.faces)
    vs = mb.grid(rows, uvs, close=True)
    mb.bm.faces.ensure_lookup_table()
    if split is not None:
        for i in range(n - 1):
            sp = split + twist * i / max(1, n - 2)
            for k in range(seg):
                a = math.tau * (k + 0.5) / seg
                mb.bm.faces[first + i * seg + k].material_index = 0 if math.cos(a - sp) > 0 else 1
    # Deckel vorne (im Stoff versteckt) und Spitze
    try:
        mb.bm.faces.new(list(reversed(vs[0])))
    except ValueError:
        pass
    tip = mb.bm.verts.new(pts[-1] + tang[-1] * radii[-1] * 0.8)
    for k in range(seg):
        try:
            mb.bm.faces.new((vs[-1][k], vs[-1][(k + 1) % seg], tip))
        except ValueError:
            pass
    return frames


# =====================================================================================
#  Texturen und Materialien
# =====================================================================================

def tex_mask(size=1024, seed=41):
    """Gemalte Porzellanmaske (frontal projiziert): Elfenbein mit leichter Vergilbung in den
    Vertiefungen, feine Haarrisse, schwarze Rauten über und unter den Augen, dunkler Mundraum."""
    r, c = np.mgrid[0:size, 0:size] / (size - 1)
    x = c * 2 * FACE_HW - FACE_HW
    z = r * 2 * FACE_HH - FACE_HH
    g = lambda a, s: np.exp(-(a * a) / (2 * s * s))
    big = hd.fractal(size, 2.8, seed)
    mid = hd.fractal(size, 2.0, seed + 1)
    fine = hd.fractal(size, 0.8, seed + 2)

    base = hd.srgb_to_linear((0.64, 0.51, 0.33))
    col = base[None, None, :] * (0.88 + 0.14 * big + 0.05 * mid)[..., None]
    height = big * 0.12 + mid * 0.05

    # Patina in den Vertiefungen: um die Augen, Lachfalten, Mundwinkel, unter den Brauen, Nasenseiten
    ax = np.abs(x)
    grime = np.zeros_like(x)
    for ex, ez in EYES:
        rho = _eye_rho(x, z, ex, ez)
        grime += 0.8 * g(rho - 1.35, 0.35)
    grime += 0.9 * g(_poly_dist(ax, z, CREASE), 0.005)
    grime += 0.7 * g(ax - MW, 0.01) * g(z - MZC, 0.012)
    brow = 0.052 + 0.02 * _np_sstep(0.015, 0.09, ax)
    grime += 0.5 * g(z - brow + 0.011, 0.006) * g(ax - 0.055, 0.035)
    grime += 0.55 * g(ax - 0.022, 0.007) * g(z + 0.015, 0.03)        # Nasenseiten
    for s in (-1, 1):                                                  # unter den Wangen-Äpfeln
        grime += 0.35 * g(x - s * 0.09, 0.016) * g(z + 0.06, 0.02)
    grime += 0.4 * g(z - 0.0, 0.012) * g(ax - 0.03, 0.01)             # Augeninnenwinkel
    grime += 0.6 * g(z + 0.135, 0.01) * g(x, 0.03)  # Kinnfalte unter der Unterlippe
    grime += 0.7 * np.clip((ax - 0.085) / 0.035, 0, 1)  # zum Rand (unter der Kappe) dunkler
    grime = np.clip(grime * (0.7 + 0.6 * mid), 0, 1)
    patina = hd.srgb_to_linear((0.36, 0.26, 0.14))
    col = col * (1 - 0.75 * grime[..., None]) + patina[None, None, :] * 0.75 * grime[..., None]

    # feine Haarrisse im Porzellan (craquelure), nur stellenweise
    cr = hd.ridged(hd.fractal(size, 2.0, seed + 5))
    cracks = np.clip((cr - 0.965) * 30, 0, 1) * np.clip((mid - 0.5) * 3, 0, 1)
    col *= (1 - 0.3 * cracks)[..., None]
    height -= 0.35 * cracks

    # schwarze Rauten über und unter den Augen
    paint = np.zeros_like(x)
    for ex, ez in EYES:
        s = 1 if ex > 0 else -1
        paint = np.maximum(paint, _diamond(x, z, ex + s * 0.006, 0.104, 0.047, 0.0155))
        paint = np.maximum(paint, _diamond(x, z, ex + s * 0.013, 0.014, -0.052, 0.0135))
    black = hd.srgb_to_linear((0.025, 0.02, 0.022))
    col = col * (1 - paint[..., None]) + black[None, None, :] * (paint * (0.85 + 0.3 * fine))[..., None]
    height += 0.25 * paint

    # Augenöffnungen: Rand dunkel (Schatten der Maske)
    for ex, ez in EYES:
        d = np.clip((1.3 - _eye_rho(x, z, ex, ez)) / 0.3, 0, 1)
        col *= (1 - 0.75 * d)[..., None]

    # Mundraum schwarz, Lippenkanten dunkel
    zu, zl = _zu(x), _zl(x)
    inside = np.clip((zu - z) / 0.002, 0, 1) * np.clip((z - zl) / 0.002, 0, 1) * np.clip((MW - ax) / 0.003, 0, 1)
    col = col * (1 - inside[..., None]) + black[None, None, :] * inside[..., None]
    lips = (g(z - zu, 0.0015) + g(z - zl, 0.0015)) * (ax < MW + 0.004)
    col *= (1 - 0.35 * np.clip(lips, 0, 1))[..., None]

    # Nasenlöcher
    for s in (-1, 1):
        col *= (1 - 0.85 * g(x - s * 0.0145, 0.0045) * g(z + 0.055, 0.003))[..., None]

    return (hd.to_image("mask_color", col ** (1 / 2.2)),
            hd.to_image("mask_normal", hd.height_to_normal(height, 2.5), non_color=True))


MOTLEY = ((0.37, 0.055, 0.045), (0.5, 0.2, 0.06), (0.55, 0.37, 0.13), (0.19, 0.045, 0.08))


def tex_motley(size=1024, seed=51):
    """Harlekin-Stoff: Rauten in Rot, Orange, Gold und Weinrot, genähte Kanten, Webmuster,
    Abrieb. Kachelbar; eine Kachel = 4 Rauten quer, 2 hoch."""
    rng = np.random.default_rng(seed)
    v, u = np.mgrid[0:size, 0:size] / size
    a = 4 * u + 2 * v
    b = 4 * u - 2 * v
    A, B = np.floor(a), np.floor(b)
    p = np.mod(A + B, 4).astype(int)
    q = np.mod(A - B, 4).astype(int)
    # Nachbarn unterscheiden sich immer in p % 2 → vier Farben ohne gleichfarbige Nachbarn
    idx = (p % 2) + 2 * ((q // 2 + p // 2) % 2)
    pal = np.array([hd.srgb_to_linear(cc) for cc in MOTLEY])
    col = pal[idx]
    fa, fb = a - A, b - B
    edge = np.minimum(np.minimum(fa, 1 - fa), np.minimum(fb, 1 - fb))
    seam = np.exp(-(edge / 0.018) ** 2)
    jitter = (hd.fractal(size, 3.0, seed + 7) - 0.5) * 0.02
    weave = 150
    wx = 0.5 + 0.5 * np.sin((u + jitter) * math.tau * weave)
    wy = 0.5 + 0.5 * np.sin((v - jitter) * math.tau * weave)
    checker = np.sin(u * math.pi * weave) * np.sin(v * math.pi * weave) > 0
    weave_h = np.where(checker, wx, wy) ** 0.7
    big = hd.fractal(size, 2.6, seed)
    mid = hd.fractal(size, 2.0, seed + 1)
    stains = np.clip((hd.fractal(size, 3.2, seed + 3) - 0.6) * 4, 0, 1)
    wear = np.clip((hd.ridged(hd.fractal(size, 2.2, seed + 4)) - 0.82) * 5, 0, 1) * 0.35
    col = col * (0.72 + 0.35 * big + 0.1 * mid)[..., None]
    col *= (0.8 + 0.2 * weave_h)[..., None]
    col *= (1 - 0.3 * stains - 0.45 * seam)[..., None]
    col += wear[..., None] * col * 0.5
    col *= (0.94 + 0.1 * rng.random((size, size)))[..., None]
    height = weave_h * 0.4 + big * 1.2 + mid * 0.4 - seam * 1.2
    return (hd.to_image("motley_color", col ** (1 / 2.2)),
            hd.to_image("motley_normal", hd.height_to_normal(height, 5.0), non_color=True))


def tex_ruff(w=256, h=256, seed=55):
    """Leinen der Halskrause: U = eine Falte (Tal bei u = 0.75 dunkler), V = von innen nach außen."""
    v, u = np.mgrid[0:h, 0:w]
    u = u / w
    v = v / (h - 1)
    ph = np.sin(u * math.tau)
    fold = 0.5 + 0.5 * ph
    noise_ = hd.fractal(w, 2.4, seed)
    noise_ = np.tile(noise_, (h // w + 1, 1))[:h]
    weave = (0.5 + 0.5 * np.sin(u * math.tau * 24)) * (0.5 + 0.5 * np.sin(v * math.tau * 40))
    base = hd.srgb_to_linear((0.6, 0.49, 0.34))
    shade = 0.42 + 0.58 * fold ** 0.6
    shade *= 0.72 + 0.28 * _np_sstep(0.0, 0.35, v)        # innen am Hals dunkler
    shade *= 0.8 + 0.3 * noise_
    shade *= 0.92 + 0.08 * weave
    edge = np.exp(-((1 - v) / 0.04) ** 2)                  # Saum außen etwas dunkler
    shade *= 1 - 0.18 * edge
    col = base[None, None, :] * shade[..., None]
    height = weave * 0.3 + noise_ * 0.3
    return (hd.to_image("ruff_color", col ** (1 / 2.2)),
            hd.to_image("ruff_normal", hd.height_to_normal(height, 2.0), non_color=True))


def materials():
    m = {}
    c, n = tex_mask()
    m["mask"] = hd.material("Gaukler_Maske", c, n, rough=0.42, normal_strength=0.6, spec=0.4)
    m["teeth"] = hd.material("Gaukler_Zaehne", color=(0.5, 0.42, 0.28, 1), rough=0.35, spec=0.5)
    m["eye"] = hd.material("Gaukler_Augenglut", color=(1.0, 0.5, 0.08, 1), rough=0.5, spec=0.2,
                           emission=(1.0, 0.4, 0.04, 1), emission_strength=1.2)
    c, n = hd.tex_cloth("cloth_red", (0.46, 0.06, 0.05), (0.17, 0.02, 0.025), size=512, seed=52, weave=90, rag=0.2)
    m["red"] = hd.material("Gaukler_Stoff_Rot", c, n, rough=0.75, normal_strength=0.8, double_sided=True, spec=0.3)
    c, n = hd.tex_cloth("cloth_gold", (0.72, 0.46, 0.13), (0.36, 0.17, 0.045), size=512, seed=53, weave=90, rag=0.2)
    m["gold"] = hd.material("Gaukler_Stoff_Gold", c, n, rough=0.72, normal_strength=0.8, double_sided=True, spec=0.3)
    c, n = tex_motley()
    m["motley"] = hd.material("Gaukler_Wams", c, n, rough=0.8, normal_strength=0.9, double_sided=True, spec=0.3)
    c, n = tex_ruff()
    m["ruff"] = hd.material("Gaukler_Krause", c, n, rough=0.9, normal_strength=0.8, double_sided=True, spec=0.15)
    c, n = hd.tex_skin("hands", (0.5, 0.4, 0.27), seed=57, pores=0.3, blotch=0.25)
    m["hands"] = hd.material("Gaukler_Haende", c, n, rough=0.6, normal_strength=1.0, spec=0.3)
    m["nail"] = hd.material("Gaukler_Nagel", color=(0.07, 0.04, 0.03, 1), rough=0.65, spec=0.2)
    m["bell"] = hd.material("Gaukler_Schelle", color=(0.7, 0.48, 0.16, 1), rough=0.32, metal=0.9)
    m["thread"] = hd.material("Gaukler_Faden", color=(0.12, 0.03, 0.02, 1), rough=0.9)
    return m


# =====================================================================================
#  Kopf: Maske (Head-Koordinaten, vorne = -Y)
# =====================================================================================

def face_shape(c: Vector, d: Vector) -> Vector:
    """Verformt die Kopfkugel zur Maske: längliches Gesicht mit spitzem Kinn, kräftige Brauen,
    runde Wangen-Äpfel, tiefe Lachfalten und ein breites, nach oben gezogenes Grinsen."""
    x, z = c.x, c.z
    ax = abs(x)
    front = max(0.0, -d.y)
    off = Vector()
    # Kinn länger und spitz, Kiefer schmaler
    if z < -0.06:
        t = min(1.3, (-z - 0.06) / 0.11)
        off.z -= 0.03 * t ** 1.6 * front
        off.x -= x * 0.28 * t ** 1.2
    off.x -= x * 0.05 * max(0.0, z) / RZ
    # Stirn leicht gewölbt
    off.y -= 0.006 * front * _g(x, 0.05) * _g(z - 0.1, 0.04)
    # Brauenwülste, zur Nase hin abgesenkt (böser Blick)
    zb = 0.052 + 0.02 * _sstep(0.015, 0.09, ax)
    off.y -= 0.026 * front * _g(z - zb, 0.0095) * _g(ax - 0.052, 0.03)
    off.y += 0.004 * front * _g(z - zb - 0.017, 0.006) * _g(ax - 0.05, 0.03)  # Rinne über der Braue
    # Augenöffnungen (flache Mulde mit ebenem Boden – dort sitzen die Glut-Augen)
    for ex, ez in EYES:
        rho = float(_eye_rho(x, z, ex, ez))
        off.y += 0.012 * front * (1 - _sstep(1.0, 1.75, rho))
        # Tränensack unter dem Auge
        off.y -= 0.006 * front * _g(x - ex * 1.05, 0.018) * _g(z - (ez - 0.024), 0.007)
    # Wangen-Äpfel (vom Grinsen hochgeschoben)
    for s in (-1, 1):
        off += Vector((s * 0.004, -0.034 * front, 0.005)) * _g(x - s * 0.068, 0.023) * _g(z + 0.014, 0.018)
    # Lachfalten
    off.y += 0.012 * front * _g(float(_poly_dist(ax, z, CREASE)), 0.0042)
    # Nasenwurzel (die Nase selbst ist modelliert)
    off.y -= 0.007 * front * _g(x, 0.012) * _g(z - 0.025, 0.02)
    # Mund: Mundraum nach hinten, Lippen als Wülste
    u = ax / MW
    if u < 1.15:
        zu, zl = float(_zu(x)), float(_zl(x))
        sig = lambda a: 1 / (1 + math.exp(-a))
        inside = sig((zu - z) / 0.0018) * sig((z - zl) / 0.0018) * sig((1 - u) * MW / 0.0025)
        off.y += 0.016 * front * inside
        env = max(0.0, 1 - u ** 4)
        off.y -= 0.005 * front * _g(z - (zu + 0.0045), 0.004) * env
        off.y -= 0.006 * front * _g(z - (zl - 0.0055), 0.0045) * env
    # Kinn etwas vor
    off.y -= 0.01 * front * _g(x, 0.028) * _g(z + 0.15, 0.025)
    return c + off


def nose():
    """Lange, gerade Nase mit runder Spitze und deutlichen Nasenflügeln."""
    parts = []
    bridge = [Vector((0.0, -0.124, 0.042)), Vector((0.0, -0.136, 0.015)), Vector((0.0, -0.147, -0.01)),
              Vector((0.0, -0.158, -0.033))]
    parts.append(ch.geo.tube([C + p for p in bridge], [0.0078, 0.0092, 0.0105, 0.0122], seg=14))
    parts.append(ch.geo.ellipsoid(Vector((0.0158, 0.0152, 0.0145)), C + Vector((0.0, -0.155, -0.04)), 24, 16))
    for sx in (-1, 1):
        parts.append(ch.geo.ellipsoid(Vector((0.0125, 0.0125, 0.0095)), C + Vector((sx * 0.0155, -0.141, -0.046)),
                                      18, 12))
    parts.append(ch.geo.ellipsoid(Vector((0.0065, 0.012, 0.0055)), C + Vector((0.0, -0.15, -0.054)), 14, 10))
    return ch.geo.merge(*parts)


def build_head(rig, m, rnd):
    head = ch.Head((RX, RY, RZ), u=110, v=80)
    head.deform(face_shape)
    face_bm = ch.geo.merge(head.bm.copy(), nose())
    face = rig.headpart("Face", face_bm, m["mask"], smooth=True, sharp_angle=None)
    hd.organic(face, voxel=0.0013, smooth=4, faces=30000)
    fb = bmesh.new()
    fb.from_mesh(face.data)
    hd.planar_uv(fb, C, FACE_HW, FACE_HH)
    fb.to_mesh(face.data)
    tree = BVHTree.FromBMesh(fb)
    fb.free()

    def surf(x, z, lift=0.0):
        """Punkt auf der Maskenvorderseite (Strahl von vorne)."""
        hit = tree.ray_cast(C + Vector((x, -0.5, z)), Vector((0, 1, 0)))
        if hit[0] is None:
            return C + Vector((x, -RY, z)), Vector((0, -1, 0))
        return hit[0] + hit[1] * lift, hit[1]

    eyes(rig, m, surf)
    lids(rig, m, surf)
    mouth(rig, m, surf)
    hood(rig, m, tree, rnd)
    return face


def _eye_shell(mb, surf, ex, ez, rho0, rho1, lift, bulge=0.0, rows=8, seg=40):
    """Schale über der Augenöffnung zwischen rho0 und rho1, folgt der Maskenoberfläche."""
    rws, uvs = [], []
    for i in range(rows + 1):
        rho = rho0 + (rho1 - rho0) * i / rows
        row, uvr = [], []
        for j in range(seg):
            a = j / seg * math.tau
            x, z = _eye_outline(ex, ez, a, rho)
            p, n = surf(x, z, lift + bulge * (1 - rho * rho))
            row.append(p)
            uvr.append((j / seg, rho))
        rws.append(row)
        uvs.append(uvr)
    mb.grid(rws, uvs, close=True)


def eyes(rig, m, surf):
    """Glut-Augen: selbstleuchtende Linsen, die in den mandelförmigen Maskenöffnungen liegen, mit
    schwarzem Rand (Void). Die Godot-Marker sitzen knapp hinter der Linse; die Glutkugel von
    Godot schaut vorne als heller, pulsierender Kern heraus."""
    lens, rim = hd.MeshBuilder(), hd.MeshBuilder()
    for i, (ex, ez) in enumerate(EYES):
        p, _n = surf(ex, ez)
        _eye_shell(lens, surf, ex, ez, 0.02, 0.92, 0.0012, bulge=0.0022)
        _eye_shell(rim, surf, ex, ez, 0.86, 1.14, 0.0009)
        # Godot-Kugel (r = 0.012 × figure_scale) ragt so etwa 2 mm vor die Linse
        rig.marker("EyeL" if i == 0 else "EyeR", rig.head, p + Vector((0, 0.003, 0)))
    rim.finish("Void_Sockets", ch.void(), parent=rig.head)
    lens.finish("Glow_Eyes", m["eye"], parent=rig.head)


def lids(rig, m, surf):
    """Wulstige Ränder der Augenöffnungen (oben schwer, unten schmal)."""
    parts = []
    for ex, ez in EYES:
        up, rr = [], []
        n = 17
        for k in range(n):
            a = k / (n - 1) * math.pi
            x, z = _eye_outline(ex, ez, a, 1.08)
            up.append(surf(x, z, 0.0015)[0])
            rr.append(0.0016 + 0.0042 * math.sin(a) ** 0.8)
        parts.append(ch.geo.tube(up, rr, seg=10))
        low, rl = [], []
        for k in range(n):
            a = math.pi + k / (n - 1) * math.pi
            x, z = _eye_outline(ex, ez, a, 1.1)
            low.append(surf(x, z, 0.001)[0])
            rl.append(0.0012 + 0.0024 * abs(math.sin(a)) ** 0.8)
        parts.append(ch.geo.tube(low, rl, seg=8))
    bm = ch.geo.merge(*parts)
    hd.planar_uv(bm, C, FACE_HW, FACE_HH)
    rig.headpart("Face_Lids", bm, m["mask"], smooth=True, sharp_angle=None)


def mouth(rig, m, surf):
    """Grinsen: schwarzer Mundraum (Void) in der Mulde, obere Zahnreihe unter der Oberlippe."""
    cols = 40
    void = bmesh.new()
    rows = []
    for k in range(cols + 1):
        x = (k / cols * 2 - 1) * (MW - 0.002)
        zu, zl = float(_zu(x)) - 0.0012, float(_zl(x)) + 0.0012
        if zu < zl:
            zu = zl = (zu + zl) / 2
        col = []
        for t in (0.0, 0.25, 0.5, 0.75, 1.0):
            z = zu + (zl - zu) * t
            col.append(void.verts.new(surf(x, z, 0.0006)[0]))
        rows.append(col)
    for k in range(cols):
        for t in range(4):
            try:
                void.faces.new((rows[k][t], rows[k + 1][t], rows[k + 1][t + 1], rows[k][t + 1]))
            except ValueError:
                pass
    rig.headpart("Void_Mouth", void, ch.void(), smooth=True, sharp_angle=None)

    teeth = []
    n_t = 15
    span = 0.079
    wdt = 2 * span / n_t
    for k in range(n_t):
        x = -span + (k + 0.5) * wdt
        zu, zl = float(_zu(x)), float(_zl(x))
        h = min(0.017 * (1 - 0.4 * (x / MW) ** 2), (zu - zl) * 0.55)
        if h < 0.004:
            continue
        lip, n = surf(x, zu + 0.004)
        nh = Vector((n.x, n.y, 0)).normalized()
        zc = zu - h * 0.5 + 0.0025
        back, _n2 = surf(x, zc)
        # Mitte knapp hinter der Lippe, aber sicher vor dem schwarzen Mundraum
        y = min(lip.y + 0.0065, back.y - 0.0048)
        p = Vector((lip.x, y, C.z + zc))
        rot = Vector((0, -1, 0)).rotation_difference(nh).to_matrix().to_4x4()
        # Zähne folgen der Krümmung der Lippe (leicht schräg zu den Mundwinkeln)
        slope = (float(_zu(x + 0.002)) - float(_zu(x - 0.002))) / 0.004
        tilt = Matrix.Rotation(math.atan(slope) * 0.6, 4, "Y")
        tb = _superellipsoid(Vector((wdt * 0.49, 0.0042, h * 0.5)), e=0.4)
        ch.geo.transform(tb, Matrix.Translation(p) @ rot @ tilt)
        teeth.append(tb)
    # untere Zahnreihe (kürzer), steht auf der Unterlippe
    for k in range(n_t - 2):
        x = -span * 0.9 + (k + 0.5) * (2 * span * 0.9 / (n_t - 2))
        zu, zl = float(_zu(x)), float(_zl(x))
        h = min(0.012 * (1 - 0.4 * (x / MW) ** 2), (zu - zl) * 0.35)
        if h < 0.003:
            continue
        lip, n = surf(x, zl - 0.003)
        nh = Vector((n.x, n.y, 0)).normalized()
        zc = zl + h * 0.5 - 0.002
        back, _n2 = surf(x, zc)
        y = min(lip.y + 0.0065, back.y - 0.0048)
        p = Vector((lip.x, y, C.z + zc))
        rot = Vector((0, -1, 0)).rotation_difference(nh).to_matrix().to_4x4()
        slope = (float(_zl(x + 0.002)) - float(_zl(x - 0.002))) / 0.004
        tilt = Matrix.Rotation(math.atan(slope) * 0.6, 4, "Y")
        tb = _superellipsoid(Vector((span * 0.9 / (n_t - 2) * 0.96, 0.004, h * 0.5)), e=0.4)
        ch.geo.transform(tb, Matrix.Translation(p) @ rot @ tilt)
        teeth.append(tb)
    rig.headpart("Mouth_Teeth", ch.geo.merge(*teeth), m["teeth"], smooth=True, sharp_angle=None)


# --- Narrenkappe -----------------------------------------------------------------------

HOOD_C = C + Vector((0, 0.01, 0.0))
HOOD_B = 2.55  # Kappe reicht beidseits bis 146° (unten offen für den Hals)
# Umriss der Gesichtsöffnung (x, z relativ zu HOOD_C, rechte Hälfte): oben Herzform mit Spitze
RIM = [(0.0, 0.112), (0.018, 0.124), (0.048, 0.134), (0.078, 0.124), (0.098, 0.098), (0.11, 0.06),
       (0.114, 0.0), (0.112, -0.06), (0.104, -0.11), (0.094, -0.158)]
_RIM_A = [math.atan2(x, z) for x, z in RIM]
_RIM_R = [math.hypot(x, z) for x, z in RIM]


def _rim_r(beta):
    a = abs(beta)
    if a <= _RIM_A[0]:
        return _RIM_R[0]
    for i in range(len(RIM) - 1):
        if _RIM_A[i] <= a <= _RIM_A[i + 1]:
            t = (a - _RIM_A[i]) / (_RIM_A[i + 1] - _RIM_A[i])
            return _RIM_R[i] + (_RIM_R[i + 1] - _RIM_R[i]) * t
    return _RIM_R[-1]


def hood(rig, m, tree, rnd):
    """Kappe aus Stoff, liegt eng um die Maske: vom Rand der Gesichtsöffnung über Kopf und Nacken.
    Links (vom Spieler aus) rot, rechts oben gold, um das Gesicht rot; Rollsaum am Gesicht."""
    nj, ni = 104, 40
    rows, uvs, betas = [], [], []
    for j in range(nj):
        betas.append(-HOOD_B + 2 * HOOD_B * j / (nj - 1))
    rim_pts = []
    for beta in betas:
        sb, cb = math.sin(beta), math.cos(beta)
        # Rand der Maske in dieser Richtung: letzte Stelle, an der die Fläche noch nach vorne schaut
        # (Nase, Augen usw. innen zählen nicht – entscheidend ist der äußere Abfall zur Seite)
        r_edge, r = 0.03, 0.03
        while r < 0.25:
            hit = tree.ray_cast(Vector((HOOD_C.x + r * sb, -0.5, HOOD_C.z + r * cb)), Vector((0, 1, 0)))
            if hit[0] is None:
                break
            if hit[1].y < -0.25:
                r_edge = r
            r += 0.002
        r0 = min(_rim_r(beta), r_edge - 0.004)
        x0, z0 = HOOD_C.x + r0 * sb, HOOD_C.z + r0 * cb
        hit = tree.ray_cast(Vector((x0, -0.5, z0)), Vector((0, 1, 0)))
        rim_pts.append(hit[0] if hit[0] is not None else Vector((x0, -0.05, z0)))
    for i in range(ni + 1):
        s = i / ni
        row, uvr = [], []
        for j, beta in enumerate(betas):
            d = Vector((math.sin(beta), 0, math.cos(beta)))
            v0 = rim_pts[j] - HOOD_C
            g0 = math.atan2(Vector((v0.x, 0, v0.z)).length, -v0.y)
            gam = g0 + (math.pi - g0) * s ** 0.85
            dirv = (d * math.sin(gam) + Vector((0, -math.cos(gam), 0))).normalized()
            hit = tree.ray_cast(HOOD_C, dirv)
            h = (hit[0] - HOOD_C).length if hit[0] is not None else 0.15
            off = 0.006 + 0.014 * _sstep(0.0, 0.45, s)
            p = dirv * (h + off)
            # Falten: am Gesicht klein, zum Nacken hin größer
            warp = 1.6 * noise.noise(p * 9)
            f = 0.0035 * math.sin(beta * 11 + warp) * (0.3 + 0.7 * s)
            f += 0.003 * noise.noise(p * 24)
            p += dirv * f
            # unten fällt der Stoff gerade in die Halskrause
            if p.z < -0.09:
                t = min(1.0, (-0.09 - p.z) / 0.08)
                p.z -= 0.05 * t
                p.x *= 1 - 0.08 * t
            row.append(HOOD_C + p)
            uvr.append((j / (nj - 1) * 3.0, s * 1.5))
        rows.append(row)
        uvs.append(uvr)
    mb = hd.MeshBuilder()
    mb.grid(rows, uvs)
    mb.bm.faces.ensure_lookup_table()
    for i in range(ni):
        for j in range(nj - 1):
            b = (betas[j] + betas[j + 1]) * 0.5
            mb.bm.faces[i * (nj - 1) + j].material_index = 1 if 0.0 < b < 1.15 else 0
    hood_bm = mb.bm.copy()
    ob = mb.finish("Hood", m["red"], parent=rig.head)
    ob.data.materials.append(m["gold"])
    mod = ob.modifiers.new("Dicke", "SOLIDIFY")
    mod.thickness = 0.005
    mod.offset = 1.0
    # Rollsaum am Gesicht
    hem = [rows[0][j] + (rows[0][j] - HOOD_C).normalized() * 0.002 for j in range(nj)]
    radii = [0.0085 + 0.002 * math.sin(j * 0.8) * math.sin(j * 0.31) for j in range(nj)]
    hb = ch.geo.tube(hem, radii, seg=10)
    ch.geo.box_uv(hb, 0.1)
    rig.headpart("Hood_Hem", hb, m["red"], smooth=True, sharp_angle=None)
    # Nähte zwischen den Feldern
    seams = []
    for b_seam in (0.0, 1.15):
        j = min(range(nj), key=lambda jj: abs(betas[jj] - b_seam))
        pts = [rows[i][j] + (rows[i][j] - HOOD_C).normalized() * 0.0045 for i in range(1, ni + 1)]
        seams.append(ch.geo.tube(pts, [0.0016] * len(pts), seg=6))
    rig.headpart("Hood_Seams", ch.geo.merge(*seams), m["thread"], smooth=True, sharp_angle=None)
    htree = BVHTree.FromBMesh(hood_bm)
    hood_bm.free()
    points(rig, m, htree, rnd)
    return ob


# Zipfel: Kontrollpunkte (x, y, z relativ zu C), Grundradius, Schellenradius, Nahtwinkel
POINTS = [
    # links oben: großer Zipfel, steigt nach außen und hängt bis auf Augenhöhe
    ([(-0.05, 0.01, 0.16), (-0.12, 0.02, 0.235), (-0.215, 0.035, 0.228), (-0.272, 0.05, 0.17),
      (-0.3, 0.06, 0.1), (-0.302, 0.065, 0.058)], 0.046, 0.021, 0.6),
    # links darunter: kleiner Zipfel bis auf Mundhöhe
    ([(-0.09, 0.04, 0.11), (-0.155, 0.05, 0.13), (-0.21, 0.06, 0.085), (-0.23, 0.065, 0.02),
      (-0.232, 0.066, -0.012)], 0.034, 0.019, 2.2),
    # rechts oben: großer Zipfel
    ([(0.055, 0.01, 0.165), (0.11, 0.02, 0.245), (0.185, 0.035, 0.235), (0.236, 0.05, 0.18),
      (0.26, 0.06, 0.105), (0.265, 0.064, 0.07)], 0.046, 0.021, -0.6),
    # rechts hinten: dünner Zipfel weiter hinten
    ([(0.09, 0.07, 0.17), (0.15, 0.09, 0.2), (0.188, 0.1, 0.187), (0.197, 0.105, 0.168)], 0.026, 0.014, 2.6),
    # rechts darunter
    ([(0.09, 0.04, 0.11), (0.152, 0.05, 0.11), (0.19, 0.06, 0.066), (0.2, 0.064, 0.012),
      (0.2, 0.065, -0.008)], 0.034, 0.019, -2.2),
]


def points(rig, m, htree, rnd):
    """Fünf gefüllte Stoffzipfel, je zur Hälfte rot und gold, mit Knitterfalten; am Ende Schellen."""
    mb = hd.MeshBuilder()
    bells, slits, loops = [], [], []
    for ctrl, r0, rb, split in POINTS:
        pts = _catmull([C + Vector(p) for p in ctrl], 48)
        n = len(pts)
        radii = []
        for k in range(n):
            t = k / (n - 1)
            radii.append(r0 * (1 - t ** 1.5) ** 0.85 * (1 + 0.12 * math.sin(t * math.pi)) + 0.0035)
        _frame_tube(mb, pts, radii, 32, flat=0.8, wrinkle=0.08, split=split, uv_len=0.06,
                    phase=rnd.uniform(0, 6), twist=math.copysign(1.3, -split))
        # Schelle unter der Spitze
        tip = pts[-1]
        bc = tip + Vector((0, 0, -rb * 1.15))
        bell(bc, rb, bells, slits)
        loops.append(ch.geo.tube([tip + Vector((0, 0, 0.004)), tip + Vector((0, 0, -0.004)), bc + Vector((0, 0, rb * 0.9))],
                                 [0.0032, 0.0028, 0.0024], seg=8))
    ob = mb.finish("Hat_Points", m["red"], parent=rig.head)
    ob.data.materials.append(m["gold"])
    rig.headpart("Hat_Bells", ch.geo.merge(*bells, *loops), m["bell"], smooth=True, sharp_angle=None)
    rig.headpart("Void_BellSlits", ch.geo.merge(*slits), ch.void(), smooth=True, sharp_angle=None)


def bell(c, r, bells, slits):
    """Schelle: Kugel mit Wulst am Äquator, Schlitz von vorne über den Boden, Löcher an den Enden."""
    b = ch.geo.ellipsoid(Vector((r, r, r * 0.97)), c, 24, 16)
    bells.append(b)
    ring = [c + Vector((math.cos(a) * r * 1.01, math.sin(a) * r * 1.01, r * 0.05)) for a in
            (k / 32 * math.tau for k in range(33))]
    bells.append(ch.geo.tube(ring, [r * 0.07] * 33, seg=6, cap_start=False))
    # Schlitz (Meridian durch den Boden, von vorne nach hinten)
    arc = []
    for k in range(17):
        a = math.radians(-160 + k / 16 * 140)  # in der y-z-Ebene: -160° … -20°
        arc.append(c + Vector((0, math.cos(a) * r * 1.002, math.sin(a) * r * 1.002)))
    slits.append(ch.geo.tube(arc, [r * 0.11] * 17, seg=6))
    for a in (math.radians(-160), math.radians(-20)):
        q = c + Vector((0, math.cos(a) * r, math.sin(a) * r))
        nrm = (q - c).normalized()
        h = ch.geo.ellipsoid(Vector((r * 0.2, r * 0.2, r * 0.06)), Vector(), 12, 6)
        rot = Vector((0, 0, 1)).rotation_difference(nrm).to_matrix().to_4x4()
        ch.geo.transform(h, Matrix.Translation(q) @ rot)
        slits.append(h)


# --- Halskrause (nach dem Skalieren, also in endgültigen Head-Koordinaten) -------------------

RUFF_C = Vector((0, 0.04, -0.118))
RUFF_TILT = math.radians(30)  # vorne tiefer, hinten höher (wirkt von vorn wie ein Teller ums Kinn)


def _body_inside(x, y, z):
    r = _radius(z)
    t = min(1.0, max(0.0, (z - 0.72) / 0.4))
    yy = y + HUNCH * t * max(0.0, 1 - abs(x) / 0.5)
    return (x / (r * SX)) ** 2 + (yy / (r * SY)) ** 2 <= 1.0


def _body_top(x, y):
    """Höhe (Torso-z) der Körperoberfläche über dem Punkt x, y – None außerhalb des Körpers."""
    lo, hi = 0.5, 1.115
    if not _body_inside(x, y, lo):
        return None
    if _body_inside(x, y, hi):
        return hi
    for _ in range(20):
        mid = (lo + hi) * 0.5
        if _body_inside(x, y, mid):
            lo = mid
        else:
            hi = mid
    return lo


HEAD_IN_TORSO = Vector((0, -0.03, HEAD_Y))  # Lage des Head-Empties im Torso


def _drape(p, clear):
    """Krausenpunkt (Head-Koordinaten) auf die Schultern/Brust heben, falls er im Körper steckt."""
    q = p + HEAD_IN_TORSO
    top = _body_top(q.x, q.y)
    if top is not None and q.z < top + clear:
        q.z = top + clear
    return q - HEAD_IN_TORSO


def _ruff_layer(mb, r_in, r_out, amp, n_pleat, lift, phase, cone=-0.07, rows=14, seg_per=10):
    """Eine Lage gefältelter Leinenstreifen: Ring mit Röhrenfalten (figure-eight pleats)."""
    rot = Matrix.Rotation(RUFF_TILT, 3, "X")
    nz = rot @ Vector((0, 0, 1))
    seg = n_pleat * seg_per
    rws, uvs = [], []
    edge = []
    for i in range(rows + 1):
        t = i / rows
        row, uvr = [], []
        for j in range(seg):
            th = j / seg * math.tau
            ph = n_pleat * th + phase
            sn = math.sin(ph)
            f = math.copysign(abs(sn) ** 0.42, sn)
            a = amp * (0.25 + 0.75 * t ** 0.7)
            reach = (r_out - r_in) * (1 - 0.3 * max(0.0, -math.sin(th)) ** 2)  # vorne kürzer
            r = r_in + reach * t + 0.006 * math.cos(ph) * t
            loc = Vector((r * math.cos(th), r * math.sin(th), -cone * t ** 1.5 + lift))
            base = _drape(RUFF_C + rot @ loc, a + 0.008 + lift)
            p = base + nz * (a * f)
            row.append(p)
            uvr.append((j / seg_per + phase / math.tau, t))
            if i == rows:
                edge.append(p)
        rws.append(row)
        uvs.append(uvr)
    mb.grid(rws, uvs, close=True)
    return edge


def ruff(rig, m):
    """Großer, zweilagiger Halskragen aus gefälteltem Leinen mit gerolltem Saum."""
    mb = hd.MeshBuilder()
    e1 = _ruff_layer(mb, 0.075, 0.31, 0.034, 30, 0.0, 0.0)
    e2 = _ruff_layer(mb, 0.075, 0.245, 0.03, 26, 0.03, math.pi / 2)
    ob = mb.finish("Ruff", m["ruff"], parent=rig.head)
    mod = ob.modifiers.new("Dicke", "SOLIDIFY")
    mod.thickness = 0.004
    mod.offset = 0.0
    hems = []
    for e in (e1, e2):
        hems.append(ch.geo.tube(e + [e[0]], [0.0038] * (len(e) + 1), seg=8, cap_start=False))
    hb = ch.geo.merge(*hems)
    ch.geo.box_uv(hb, 0.05)
    rig.headpart("Ruff_Hem", hb, m["ruff"], smooth=True, sharp_angle=None)


# =====================================================================================
#  Körper (Torso-Koordinaten)
# =====================================================================================

PROFILE = [(0.25, -0.15), (0.27, 0.1), (0.28, 0.45), (0.292, 0.72), (0.295, 0.82), (0.28, 0.9),
           (0.25, 0.96), (0.19, 1.02), (0.13, 1.06), (0.08, 1.085), (0.05, 1.1)]
SX, SY, HUNCH = 1.5, 0.8, 0.06


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


def body_point(th, z, out=0.0, folds=True):
    r = _radius(z)
    fold = 0.0
    if folds:
        warp = noise.noise(Vector((math.cos(th) * 2.0, math.sin(th) * 2.0, z * 1.5))) * 1.4
        amp = 0.009 * min(1.0, max(0.0, (0.95 - z) / 0.5)) + 0.003
        fold = amp * (0.7 * math.sin(th * 9 + warp) + 0.3 * math.sin(th * 19 + warp * 2))
        # gebauschter Stoff: waagrechte Wülste unter den Achseln
        fold += 0.004 * math.sin(z * 30 + warp) * max(0.0, abs(math.cos(th)) - 0.5)
    rr = r + fold + out
    x = rr * SX * math.cos(th)
    y = rr * SY * math.sin(th)
    if z > 0.72:
        t = min(1.0, (z - 0.72) / 0.4)
        y -= HUNCH * t * max(0.0, 1 - abs(x) / 0.5)
    bump = math.exp(-((abs(x) - 0.33) ** 2) / (2 * 0.075 ** 2)) * math.exp(-((z - 0.98) ** 2) / (2 * 0.07 ** 2))
    return Vector((x, y, z + 0.03 * bump))


def build_body(rig, m, rnd):
    tb = rig.torso
    mb = hd.MeshBuilder()
    zs = [-0.15 + i * 0.0105 for i in range(120)] + [1.1, 1.112]
    seg = 112
    rows, uvs = [], []
    for z in zs:
        rows.append([body_point(j / seg * math.tau, z) for j in range(seg)])
        uvs.append([(j / seg * 6.0, z * 3.6) for j in range(seg)])
    mb.grid(rows, uvs, close=True)
    mb.finish("Body", m["motley"], parent=tb)

    # Schultergelenke für die Arme (in Godot: opponent_figure.gd → _update_arms)
    for side in (-1, 1):
        rig.marker("Shoulder_L" if side < 0 else "Shoulder_R", tb, Vector((side * 0.335, 0.02, 0.95)))

    # Hals (unter der Krause, schließt die Lücke zur Kappe)
    nb = ch.geo.lathe([(0.075, 0.98), (0.07, 1.1), (0.066, 1.2)], 24, 0.15)
    ch.geo.translate(nb, Vector((0, 0.0, 0)))
    rig.body("Body_Neck", nb, m["red"], smooth=True, sharp_angle=None)


# =====================================================================================
#  Hände und Arme
# =====================================================================================

HAND_KW = dict(size=1.06, thick=1.1, knobby=0.3, bony=False, finger_len=1.18, pitch=-0.45,
               wrist_back=0.06, wrist_up=0.0)


def cuff_ruffle(hand, side, m, size, roll=72.0, pitch=-0.45, wrist_back=0.06, wrist_up=0.0):
    """Rüsche am Handgelenk (Kind der Hand): gefältelter Leinenring, zu den Fingern hin offen."""
    orient = Matrix.Translation(Vector((0, wrist_back, wrist_up))) @ \
        Matrix.Rotation(math.radians(side * roll), 4, "Y") @ Matrix.Rotation(pitch, 4, "X")
    mb = hd.MeshBuilder()
    n_pleat, seg_per = 16, 8
    seg = n_pleat * seg_per
    for layer, (y0, r_in, r_out, flare) in enumerate(((0.035, 0.033, 0.066, 0.03), (0.018, 0.031, 0.058, 0.026))):
        rws, uvs = [], []
        for i in range(7):
            t = i / 6
            row, uvr = [], []
            for j in range(seg):
                a = j / seg * math.tau
                ph = n_pleat * a + layer * math.pi / 2
                f = math.copysign(abs(math.sin(ph)) ** 0.6, math.sin(ph))
                r = (r_in + (r_out - r_in) * t) * size
                y = (y0 - flare * t) * size + 0.006 * f * t * size
                r += 0.003 * math.cos(ph) * t * size
                row.append(orient @ Vector((math.cos(a) * r, y, math.sin(a) * r)))
                uvr.append((j / seg_per, t))
            rws.append(row)
            uvs.append(uvr)
        mb.grid(rws, uvs, close=True)
    ob = mb.finish(hand.name + "_Cuff", m["ruff"], parent=hand)
    ob.location = (0, 0, 0)
    mod = ob.modifiers.new("Dicke", "SOLIDIFY")
    mod.thickness = 0.0018
    return ob


def motley_sleeve(name, mat, r0, r1, puff=0.1, folds=1.0, bunch_end=0.0, seed=0, gather=0.0):
    """Gebauschter Ärmel im Rautenstoff (Länge 1 entlang Z, -0.5 körpernah). UVs in echten
    Maßen (Armsegment ≈ hd.ARM_SEGMENT lang), damit die Rauten nicht verzerrt sind.
    gather: am Ende zusammengerafft (Handgelenk)."""
    mb = hd.MeshBuilder()
    rows, uvs = [], []
    n_r, n_z = 44, 40
    ph = seed * 1.7
    for i in range(n_z + 1):
        t = i / n_z
        z = -0.5 + t
        r = (r0 + (r1 - r0) * t) * (1 + puff * math.sin(math.pi * min(1.0, t * 1.1)) ** 2)
        if gather > 0:
            r -= gather * _sstep(0.8, 1.0, t)
        row, uvr = [], []
        for j in range(n_r):
            a = j / n_r * math.tau
            warp = 1.5 * hd.noise3(Vector((math.cos(a), math.sin(a), z * 2 + ph)))
            fold = 0.005 * folds * math.sin(a * 5 + warp) + 0.0025 * folds * math.sin(a * 11 + warp * 2)
            inner = max(0.0, math.sin(a))
            fold += bunch_end * max(0.0, t - 0.6) / 0.4 * (0.006 + 0.008 * inner) * math.sin(z * 90 + warp)
            if gather > 0:
                fold += 0.006 * _sstep(0.8, 1.0, t) * math.sin(a * 9 + warp)  # Raffung
            row.append(Vector(((r + fold) * math.cos(a), (r + fold) * math.sin(a), z)))
            uvr.append((j / n_r * 2.0, t * hd.ARM_SEGMENT * 3.6))
        rows.append(row)
        uvs.append(uvr)
    vs = mb.grid(rows, uvs, close=True)
    mb.bm.faces.new(list(reversed(vs[0])))
    mb.bm.faces.new(vs[-1])
    return mb.finish(name, mat)


def hands_and_sleeve(rig, m, rnd):
    """Hagere, knochige Hände mit Rüschen + gebauschte Rautenärmel (Godot knickt sie per IK)."""
    hands = [hd.grip_hand(side, m["hands"], m["nail"], **HAND_KW) for side in (-1, 1)]
    for side, h in zip((-1, 1), hands):
        h.location = G(side * 0.085, 0.9, 0.22)  # Ruhelage: beide Hände halten den Fächer unten
        cuff_ruffle(h, side, m, HAND_KW["size"], pitch=HAND_KW["pitch"], wrist_back=HAND_KW["wrist_back"],
                    wrist_up=HAND_KW["wrist_up"])
    upper = motley_sleeve("SleeveUpper", m["motley"], 0.1, 0.088, puff=0.14, folds=1.2, bunch_end=1.0, seed=1)
    fore = motley_sleeve("SleeveFore", m["motley"], 0.088, 0.072, puff=0.12, folds=1.0, seed=2, gather=0.012)
    hd.preview_arms(upper, fore, hands[0], hands[1])


# =====================================================================================

def scale_head(rig, s):
    """Kopf als Ganzes vergrößern (um die Schädelmitte), Augen-Marker mit."""
    for ob in rig.head.children:
        ob.location = C + (Vector(ob.location) - C) * s
        if ob.type == "MESH":
            ob.data.transform(Matrix.Scale(s, 4))


def build(steps=("head", "body", "hands"), seed=31):
    rnd = random.Random(seed)
    if set(steps) >= {"head", "body", "hands"}:
        hd.clear_scene()
    rig = ch.Rig(HEAD_Y)
    m = materials()
    if "head" in steps:
        build_head(rig, m, rnd)
        scale_head(rig, HEAD_SCALE)
        ruff(rig, m)
    if "body" in steps:
        build_body(rig, m, rnd)
    if "hands" in steps:
        hands_and_sleeve(rig, m, rnd)
    return rig
