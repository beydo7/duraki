"""Die Hexe in HD (nach dem Konzeptbild „Am Spieltisch“, Feld 7):
uraltes, tief zerfurchtes Gesicht mit langer Hakennase und spitzem Kinn, Warzen, gelb
glühende Augen, schiefes Grinsen mit wenigen Zähnen; rotes Kopftuch mit Knoten, strähniges
graues Haar bis auf die Schultern, große Creolen, Halskette aus Zähnen und Krallen,
violettes, zerschlissenes Schultertuch, knotige Hände mit dunklen Nägeln. Auf dem Tisch
steht ihre Laterne.

    import hd_witch; hd_witch.build()
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
import hd_bandit as B
from geo import G

C = Vector((0, 0, 0.1))  # Schädelmitte (Head-Koordinaten)
HEAD_Y = 1.17
HEAD_SCALE = 1.4
RX, RY, RZ = 0.125, 0.14, 0.17
EYES = [(-0.047, 0.03), (0.047, 0.03)]
FACE_HW, FACE_HH = 0.2, 0.27
MOUTH_Z = -0.092  # Mitte des Mundes


def _g(a, s):
    return math.exp(-(a * a) / (2 * s * s))


# =====================================================================================
#  Texturen und Materialien
# =====================================================================================

def tex_face(size=1024, seed=171):
    """Gemalte, uralte Haut: wettergegerbt, tiefe Falten überall (Stirn, Augen, Wangen,
    Mund, Kinn), Altersflecken, dunkle Augenhöhlen, rötliche Nasenspitze."""
    rng = np.random.default_rng(seed)
    r, c = np.mgrid[0:size, 0:size] / (size - 1)
    x = c * 2 * FACE_HW - FACE_HW
    z = r * 2 * FACE_HH - FACE_HH
    g = lambda a, s: np.exp(-(a * a) / (2 * s * s))
    big = hd.fractal(size, 2.8, seed)
    mid = hd.fractal(size, 2.0, seed + 1)
    fine = hd.fractal(size, 0.7, seed + 2)
    wob = hd.fractal(size, 2.2, seed + 3) - 0.5
    ax = np.abs(x)

    base = hd.srgb_to_linear((0.44, 0.35, 0.24))
    col = base[None, None, :] * (0.78 + 0.32 * big + 0.12 * mid)[..., None]
    height = big * 0.15 + mid * 0.12

    wr = _wrinkle_strokes(x, z, size, seed)
    col *= (1 - 0.3 * np.clip(wr, 0, 1))[..., None]
    height -= 1.1 * wr

    # dunkle Augenhöhlen, rötliche Nasenspitze und Lider
    sock = np.zeros_like(x)
    for ex, ez in EYES:
        sock += g(x - ex, 0.026) * g(z - ez, 0.02)
    col *= (1 - 0.45 * np.clip(sock, 0, 1))[..., None]
    red = 0.6 * g(x, 0.016) * g(z + 0.045, 0.02)
    tint = hd.srgb_to_linear((0.5, 0.2, 0.14))
    col = col * (1 - 0.4 * red[..., None]) + tint[None, None, :] * 0.4 * red[..., None]
    # Altersflecken
    spots = np.clip((hd.fractal(size, 1.6, seed + 6) - 0.72) * 6, 0, 1) * (rng.random((size, size)) > 0.0)
    col *= (1 - 0.3 * spots)[..., None]
    # Poren
    pore = np.clip((fine - 0.62) * 5, 0, 1)
    height -= 0.2 * pore
    # Ränder (unter Kopftuch und Haar) dunkler
    col *= (1 - 0.35 * np.clip((ax - 0.09) / 0.05, 0, 1))[..., None]
    # Höhen weichzeichnen: scharfe Kanten zerfallen sonst in Godot (Kompression) zu Klötzchen
    for _ in range(2):
        height = (height + np.roll(height, 1, 0) + np.roll(height, -1, 0) + np.roll(height, 1, 1)
                  + np.roll(height, -1, 1)) / 5.0
    return (hd.to_image("face_color", col ** (1 / 2.2)),
            hd.to_image("face_normal", hd.height_to_normal(height, 3.0), non_color=True))


def _stroke_field(px, pz):
    """Faltenrichtung an (px, pz): Stirn quer, um die Augen strahlenförmig, um den Mund in
    Bögen, am Hals/Kinn quer, auf den Wangen schräg nach unten."""
    ax = abs(px)
    if pz > 0.06:
        return Vector((1, 0.12 * math.sin(px * 40), 0)).normalized()
    for ex, ez in EYES:
        dx, dz = px - ex, pz - ez
        r = math.hypot(dx, dz)
        if r < 0.05 and abs(dx) > 0.018 and px * ex > 0:
            return Vector((dx, dz, 0)).normalized()  # Krähenfüße
        if r < 0.045 and dz < 0:
            return Vector((-dz, dx, 0)).normalized()  # Bögen unter dem Auge
    if pz < -0.115:
        return Vector((1, 0.0, 0))
    # um den Mund: senkrechte Fältchen dicht am Mund, außen Bögen
    dx, dz = px, pz - MOUTH_Z
    if abs(dz) < 0.02 and ax < 0.04:
        return Vector((0, 1, 0))
    return Vector((-dz * 1.2, dx, 0)).normalized()


def _wrinkle_strokes(x, z, size, seed, count=420):
    """Viele kurze, unregelmäßige Faltenstriche entlang eines Richtungsfeldes (statt
    gleichmäßiger Kreise). Gibt eine Faltenstärke 0..1 pro Pixel zurück."""
    rng = random.Random(seed)
    out = np.zeros((size, size), np.float32)
    px_per = (size - 1) / (2 * FACE_HW)
    pz_per = (size - 1) / (2 * FACE_HH)
    for _ in range(count):
        cx = rng.uniform(-0.12, 0.12)
        cz = rng.uniform(-0.16, 0.16)
        # Nase und Augen selbst frei lassen
        if abs(cx) < 0.018 and -0.08 < cz < 0.05:
            continue
        if any(math.hypot((cx - ex) * 0.9, (cz - ez) * 1.4) < 0.017 for ex, ez in EYES):
            continue
        L = rng.uniform(0.018, 0.05)
        depth = rng.uniform(0.3, 0.85)
        w = rng.uniform(0.0016, 0.003)
        pts = []
        px, pz = cx, cz
        for k in range(8):
            d = _stroke_field(px, pz)
            d = Vector((d.x + rng.uniform(-0.15, 0.15), d.y + rng.uniform(-0.15, 0.15), 0)).normalized()
            px += d.x * L / 7
            pz += d.y * L / 7
            pts.append((px, pz))
        for k in range(len(pts) - 1):
            (x0, z0), (x1, z1) = pts[k], pts[k + 1]
            taper = math.sin(math.pi * (k + 0.5) / (len(pts) - 1))
            c0 = int((min(x0, x1) - 3 * w + FACE_HW) * px_per)
            c1 = int((max(x0, x1) + 3 * w + FACE_HW) * px_per) + 1
            r0 = int((min(z0, z1) - 3 * w + FACE_HH) * pz_per)
            r1 = int((max(z0, z1) + 3 * w + FACE_HH) * pz_per) + 1
            c0, r0 = max(c0, 0), max(r0, 0)
            c1, r1 = min(c1, size), min(r1, size)
            if c1 <= c0 or r1 <= r0:
                continue
            xs = x[r0:r1, c0:c1]
            zs = z[r0:r1, c0:c1]
            dx, dz = x1 - x0, z1 - z0
            ll = dx * dx + dz * dz + 1e-12
            t = np.clip(((xs - x0) * dx + (zs - z0) * dz) / ll, 0, 1)
            dd = np.hypot(xs - (x0 + t * dx), zs - (z0 + t * dz))
            out[r0:r1, c0:c1] = np.maximum(out[r0:r1, c0:c1], depth * taper * np.exp(-(dd / w) ** 2))
    return out


def tex_shawl(name, base, dark, size=1024, seed=181):
    """Grob gewebter, verfilzter Wollstoff mit Flecken und Mottenlöchern (als dunkle Stellen)."""
    c, n = hd.tex_cloth(name, base, dark, size=size, seed=seed, weave=110, rag=0.8)
    return c, n


def materials():
    m = {}
    c, n = tex_face()
    m["skin"] = hd.material("Hexe_Haut", c, n, rough=0.62, normal_strength=1.4, spec=0.3)
    c, n = hd.tex_skin("hands", (0.46, 0.34, 0.21), seed=173, pores=1.0, blotch=1.6)
    m["hands"] = hd.material("Hexe_Haende", c, n, rough=0.62, normal_strength=1.3, spec=0.3)
    m["nail"] = hd.material("Hexe_Nagel", color=(0.07, 0.045, 0.035, 1), rough=0.55, spec=0.25)
    c, n = hd.tex_cloth("scarf", (0.5, 0.1, 0.07), (0.17, 0.03, 0.025), size=1024, seed=175, weave=120, rag=0.5)
    m["scarf"] = hd.material("Hexe_Kopftuch", c, n, rough=0.85, normal_strength=1.0, double_sided=True, spec=0.25)
    c, n = tex_shawl("shawl", (0.24, 0.12, 0.3), (0.07, 0.035, 0.09))
    m["shawl"] = hd.material("Hexe_Tuch", c, n, rough=0.92, normal_strength=1.2, double_sided=True, spec=0.15)
    c, n = hd.tex_cloth("robe", (0.16, 0.1, 0.17), (0.05, 0.03, 0.055), size=1024, seed=183, weave=140, rag=0.5)
    m["robe"] = hd.material("Hexe_Kleid", c, n, rough=0.9, normal_strength=1.0, spec=0.15)
    c, n = hd.tex_hair("hair", (0.22, 0.2, 0.18), (0.62, 0.6, 0.56), w=96, h=384, seed=185, strands=34)
    m["hair"] = hd.material("Hexe_Haar", c, n, rough=0.8, normal_strength=0.5, double_sided=True, spec=0.15,
                            alpha_clip=True)
    c, n = hd.tex_hair("brow", (0.18, 0.16, 0.14), (0.5, 0.48, 0.44), w=64, h=128, seed=187, strands=26)
    m["brow"] = hd.material("Hexe_Braue", c, n, rough=0.8, double_sided=True, spec=0.15, alpha_clip=True)
    c, n = hd.tex_hair("fringe", (0.08, 0.04, 0.1), (0.22, 0.11, 0.27), w=64, h=128, seed=191, strands=20)
    m["fringe"] = hd.material("Hexe_Fransen", c, n, rough=0.9, double_sided=True, spec=0.1, alpha_clip=True)
    m["gold"] = hd.material("Hexe_Gold", color=(0.75, 0.52, 0.2, 1), rough=0.3, metal=0.9)
    m["cord"] = hd.material("Hexe_Schnur", color=(0.12, 0.08, 0.05, 1), rough=0.9, spec=0.1)
    c, n = hd.tex_skin("tooth", (0.66, 0.56, 0.38), size=256, seed=189, pores=0.6, blotch=1.2)
    m["tooth"] = hd.material("Hexe_Zahn", c, n, rough=0.5, normal_strength=0.6, spec=0.35)
    m["eye"] = hd.material("Hexe_Auge", color=(1.0, 0.6, 0.12, 1), rough=0.3,
                           emission=(1.0, 0.52, 0.06, 1), emission_strength=1.0)
    m["eyecore"] = hd.material("Hexe_Augenkern", color=(1.0, 0.9, 0.55, 1), rough=0.3,
                               emission=(1.0, 0.85, 0.45, 1), emission_strength=2.4)
    m["lid"] = hd.material("Hexe_Lid", color=(0.25, 0.16, 0.1, 1), rough=0.7, spec=0.2)
    m["iron"] = hd.material("Hexe_Laterne", color=(0.12, 0.1, 0.08, 1), rough=0.45, metal=0.85)
    m["lglass"] = hd.material("Hexe_Laternenglas", color=(1.0, 0.7, 0.3, 1), rough=0.2,
                              emission=(1.0, 0.62, 0.22, 1), emission_strength=3.5)
    return m


# =====================================================================================
#  Kopf (Head-Koordinaten, vorne = -Y)
# =====================================================================================

def face_shape(c: Vector, d: Vector) -> Vector:
    x, z = c.x, c.z
    front = max(0.0, -d.y)
    off = Vector()
    # schmaler, langer Schädel; unten zum spitzen Kinn hin schmal
    off.x -= c.x * (0.2 * max(0.0, -z) / RZ)
    off.x -= c.x * 0.05 * max(0.0, z) / RZ
    # Stirnwulst, über der Nase abgesenkt
    off.y -= 0.02 * front ** 2 * _g(z - 0.058, 0.014) * _g(abs(x) - 0.045, 0.04)
    # tiefe Augenhöhlen
    for ex, ez in EYES:
        off.y += 0.04 * front * _g(x - ex, 0.021) * _g(z - ez, 0.017)
    # Wangenknochen hoch und spitz, darunter eingefallen
    for s in (-1, 1):
        off += Vector((s * 0.014, -0.02 * front, 0)) * _g(x - s * 0.068, 0.02) * _g(z + 0.006, 0.016)
        off.y += 0.016 * front * _g(x - s * 0.06, 0.02) * _g(z + 0.055, 0.02)
    # langes, spitzes Kinn, das nach vorn ragt
    if z < -0.09:
        t = min(1.0, (-0.09 - z) / 0.08)
        off.y -= 0.055 * front * t ** 1.1 * _g(x, 0.026 + 0.02 * (1 - t))
        off.z -= 0.03 * t * front * _g(x, 0.03)
    # Mund eingefallen (zahnlos), Lippenwulst
    off.y += 0.01 * front * _g(x, 0.035) * _g(z - MOUTH_Z, 0.018)
    off.y -= 0.004 * front * _g(x, 0.03) * _g(z - MOUTH_Z - 0.012, 0.005)
    # Schläfen eingezogen
    for s in (-1, 1):
        off.x -= s * 0.01 * _g(x - s * RX, 0.03) * _g(z - 0.06, 0.03)
    off += d * 0.0025 * noise.noise(c * 25)
    return c + off


def nose_and_chin():
    """Lange, gekrümmte Hakennase mit Höcker und Warze, nach vorn ragendes spitzes Kinn."""
    parts = []
    bridge = [Vector((0.0, -0.128, 0.034)), Vector((0.0, -0.145, 0.014)), Vector((0.0, -0.165, -0.006)),
              Vector((0.0, -0.186, -0.028)), Vector((0.0, -0.203, -0.048)), Vector((0.0, -0.204, -0.063)),
              Vector((0.0, -0.19, -0.07))]
    parts.append(ch.geo.tube([C + p for p in bridge], [0.009, 0.0105, 0.012, 0.0135, 0.0155, 0.0135, 0.008], seg=16))
    parts.append(ch.geo.ellipsoid(Vector((0.01, 0.007, 0.009)), C + Vector((0.0, -0.163, -0.002)), 14, 10))  # Höcker
    parts.append(ch.geo.ellipsoid(Vector((0.016, 0.014, 0.015)), C + Vector((0.0, -0.198, -0.055)), 16, 12))  # Spitze
    for sx in (-1, 1):  # Nasenflügel
        parts.append(ch.geo.ellipsoid(Vector((0.013, 0.016, 0.011)), C + Vector((sx * 0.014, -0.158, -0.05)), 16, 10))
    # Kinn: spitz, ragt nach vorn

    return ch.geo.merge(*parts)


def build_head(rig, m, rnd):
    head = ch.Head((RX, RY, RZ), u=96, v=72)
    head.deform(face_shape)
    face = rig.headpart("Face", ch.geo.merge(head.bm.copy(), nose_and_chin()), m["skin"], smooth=True,
                        sharp_angle=None)
    hd.organic(face, voxel=0.0015, smooth=3, faces=26000)
    fb = bmesh.new()
    fb.from_mesh(face.data)
    hd.planar_uv(fb, C, FACE_HW, FACE_HH)
    fb.to_mesh(face.data)
    tree = BVHTree.FromBMesh(fb)
    fb.free()

    def surf(x, z, lift=0.0):
        hit = tree.ray_cast(C + Vector((x, -0.6, z)), Vector((0, 1, 0)))
        if hit[0] is None:
            return C + Vector((x, -RY, z)), Vector((0, -1, 0))
        return hit[0] + hit[1] * lift, hit[1]

    eyes(rig, m, surf)
    brows(rig, m, surf, rnd)
    mouth(rig, m, surf, rnd)
    warts(rig, m, surf, rnd)
    ears(rig, m, tree)
    scarf_and_hair(rig, m, tree, rnd)
    return face


def eyes(rig, m, surf):
    """Gelb glühende Augen tief in den Höhlen, schwere, faltige Lider darüber."""
    voids, glow, core, lids = [], [], [], []
    for i, (ex, ez) in enumerate(EYES):
        s = 1 if ex > 0 else -1
        p, _n = surf(ex, ez)
        voids.append(ch.geo.ellipsoid(Vector((0.02, 0.006, 0.012)), p + Vector((0, 0.001, 0)), 24, 12))
        c = p + Vector((0, -0.004, -0.001))
        glow.append(ch.geo.ellipsoid(Vector((0.0125, 0.006, 0.0085)), c, 20, 12))
        core.append(ch.geo.ellipsoid(Vector((0.0055, 0.003, 0.0055)), c + Vector((s * -0.002, -0.0045, 0)), 14, 8))
        rig.marker("EyeL" if i == 0 else "EyeR", rig.head, c + Vector((0, 0.002, 0)))
        # Oberlid: schwer, außen herabhängend; Unterlid mit Tränensack
        up = [surf(ex + (k / 8 - 0.5) * 0.044, ez + 0.009 - 0.006 * ((k / 8 - 0.5) * 2 * s) ** 2
                   - 0.004 * max(0.0, (k / 8 - 0.5) * 2 * s), 0.002)[0] for k in range(9)]
        lo = [surf(ex + (k / 8 - 0.5) * 0.04, ez - 0.01 + 0.004 * ((k / 8 - 0.5) * 2) ** 2, 0.0015)[0]
              for k in range(9)]
        lids.append(ch.geo.tube(up, [0.002, 0.004, 0.0055, 0.006, 0.0062, 0.006, 0.0055, 0.004, 0.002], seg=10))
        lids.append(ch.geo.tube(lo, [0.0015, 0.0028, 0.0035, 0.0038, 0.0038, 0.0035, 0.0028, 0.0022, 0.0012], seg=8))
    rig.headpart("Void_Sockets", ch.geo.merge(*voids), ch.void(), smooth=True, sharp_angle=None)
    rig.headpart("Glow_Eyes", ch.geo.merge(*glow), m["eye"], smooth=True, sharp_angle=None)
    rig.headpart("Glow_EyeCores", ch.geo.merge(*core), m["eyecore"], smooth=True, sharp_angle=None)
    rig.headpart("Face_Lids", ch.geo.merge(*lids), m["skin"], smooth=True, sharp_angle=None)


def brows(rig, m, surf, rnd):
    """Dünne, struppige, zur Nase hin herabgezogene Brauen (Alpha-Härchen)."""
    mb = hd.MeshBuilder()
    for ex, ez in EYES:
        s = 1 if ex > 0 else -1
        for k in range(60):
            t = rnd.random()
            x = ex + s * (t - 0.45) * 0.055
            z = ez + 0.024 - 0.01 * (1 - t) + rnd.uniform(-0.004, 0.004)
            p, n = surf(x, z, -0.001)
            d = Vector((s * 1.0, 0, 0.35 + rnd.uniform(-0.4, 0.3)))
            L = rnd.uniform(0.008, 0.016)
            hd.add_feather(mb, p, n, d, L, L * 0.5, lift=rnd.uniform(0.2, 0.5), curl=0.1, cup=0.1,
                           twist=rnd.uniform(-0.5, 0.5), along=3, across=2, shape=0.6)
    mb.finish("Face_Brows", m["brow"], parent=rig.head)


def mouth(rig, m, surf, rnd):
    """Schiefes Grinsen: dunkle, schmale Mundspalte, wenige krumme Zähne."""
    W = 0.042
    bm = bmesh.new()
    cols = []
    for k in range(25):
        u = k / 24 * 2 - 1
        x = u * W
        zc = MOUTH_Z + 0.012 * u * u + 0.004 * u  # Mundwinkel hoch, rechts etwas höher
        h = 0.0015 + 0.0032 * (1 - u * u)
        cols.append([bm.verts.new(surf(x, zc + dz, 0.0006)[0]) for dz in (h, 0.0, -h)])
    for k in range(24):
        for r in range(2):
            bm.faces.new((cols[k][r], cols[k + 1][r], cols[k + 1][r + 1], cols[k][r + 1]))
    rig.headpart("Void_Mouth", bm, ch.void(), smooth=True, sharp_angle=None)
    # wenige Zähne: oben zwei lange, schiefe; unten einer
    teeth = []
    for x, top, L, tilt in ((-0.012, True, 0.01, 0.2), (0.008, True, 0.009, -0.15), (0.022, True, 0.006, 0.3),
                            (-0.002, False, 0.006, 0.1)):
        u = x / W
        zc = MOUTH_Z + 0.012 * u * u + 0.004 * u
        h = 0.0015 + 0.0032 * (1 - u * u)
        p, n = surf(x, zc + (h if top else -h) * 0.9, -0.002)
        dz = -1 if top else 1
        pts = [p, p + Vector((tilt * L * 0.3, -0.001, dz * L * 0.55)), p + Vector((tilt * L * 0.6, -0.0015, dz * L))]
        teeth.append(ch.geo.tube(pts, [0.0038, 0.0034, 0.0022], seg=10))
    rig.headpart("Mouth_Teeth", ch.geo.merge(*teeth), m["tooth"], smooth=True, sharp_angle=None)


def warts(rig, m, surf, rnd):
    parts = []
    for x, z, r in ((0.006, -0.03, 0.0045), (-0.058, -0.06, 0.004), (0.018, -0.135, 0.0035), (0.07, 0.0, 0.003)):
        p, n = surf(x, z, -r * 0.3)
        parts.append(ch.geo.ellipsoid(Vector((r, r, r * 0.9)), p, 12, 8))
    rig.headpart("Face_Warts", ch.geo.merge(*parts), m["skin"], smooth=True, sharp_angle=None)


def ears(rig, m, tree):
    """Große, spitz zulaufende Ohren mit langen Ohrläppchen und goldenen Creolen."""
    parts, rings = [], []
    for s in (-1, 1):
        base = C + Vector((s * (RX - 0.008), 0.005, -0.005))
        ear = ch.geo.ellipsoid(Vector((0.012, 0.03, 0.05)), Vector((0, 0, 0)), 24, 16)
        for v in ear.verts:
            k = v.co
            v.co.y -= 0.01 * max(0.0, k.z / 0.05) ** 2  # Spitze nach vorne/oben
            if k.x * s > 0:  # Muschel innen etwas hohl
                v.co.x -= s * 0.006 * _g(k.y, 0.015) * _g(k.z, 0.025)
        M = Matrix.Translation(base + Vector((s * 0.012, 0, 0.004))) @ Matrix.Rotation(s * -0.35, 4, "Z") @ \
            Matrix.Rotation(-0.15, 4, "X")
        ch.geo.transform(ear, M)
        parts.append(ear)
        # Creole am Ohrläppchen
        lobe = base + Vector((s * 0.022, -0.004, -0.05))
        R = 0.022
        ring = [lobe + Vector((s * 0.004, -R * math.sin(a), -R + R * math.cos(a))) for a in
                [k / 32 * math.tau for k in range(33)]]
        rings.append(ch.geo.tube(ring, [0.0028] * 33, seg=10, cap_start=False))
    ob = rig.headpart("Ears", ch.geo.merge(*parts), m["skin"], smooth=True, sharp_angle=None)
    hd.organic(ob, voxel=0.0015, smooth=2, faces=4000, uv_tile=0.1)
    rig.headpart("Ears_Rings", ch.geo.merge(*rings), m["gold"], smooth=True, sharp_angle=None)


def scarf_and_hair(rig, m, tree, rnd):
    """Rotes Kopftuch (vorn tief über der Stirn, Knoten hinten links mit zwei Enden) und
    strähniges graues Haar, das darunter bis auf die Schultern hängt."""
    hc = C + Vector((0, 0.006, 0.0))
    ER = Vector((RX + 0.016, RY + 0.018, RZ + 0.012))

    def edge_z(a):  # Unterkante: vorne über der Stirn, hinten tiefer (a = 0 vorne)
        return 0.09 - 0.11 * (1 - math.cos(a)) * 0.5 - 0.02 * _g(abs((a + math.pi) % math.tau - math.pi) - 1.6, 0.4)
    mb = hd.MeshBuilder()
    rows, uvs = [], []
    n_a, n_t = 96, 24
    for i in range(n_t + 1):
        t = i / n_t
        row, uvr = [], []
        for j in range(n_a):
            a = j / n_a * math.tau
            z0 = edge_z(a)
            el0 = math.asin(max(-1.0, min(1.0, z0 / ER.z)))
            el = el0 + (math.pi / 2 - el0) * t
            p = hc + Vector((ER.x * math.cos(el) * math.sin(a), -ER.y * math.cos(el) * math.cos(a), ER.z * math.sin(el)))
            k = p - hc
            nn = k.normalized()
            p += nn * (0.006 * noise.noise(k * 18) + 0.005 * abs(noise.noise(k * 7 + Vector((3, 0, 0)))) + 0.01 * t * t)
            row.append(p)
            uvr.append((j / n_a * 4, t * 2))
        rows.append(row)
        uvs.append(uvr)
    mb.grid(rows, uvs, close=True)
    ob = mb.finish("Scarf", m["scarf"], parent=rig.head)
    mod = ob.modifiers.new("Dicke", "SOLIDIFY")
    mod.thickness = 0.005
    # Saum: Rolle an der Unterkante
    ring = []
    for k in range(n_a + 1):
        ring.append(rows[0][k % n_a] - Vector((0, 0, 0.002)))
    rig.headpart("Scarf_Hem", ch.geo.tube(ring, [0.008 + 0.003 * math.sin(k * 0.7) for k in range(n_a + 1)], seg=10,
                                          cap_start=False), m["scarf"], smooth=True, sharp_angle=None)
    # Knoten hinten links, zwei Enden hängen herab
    knot_c = hc + Vector((-0.09, 0.11, 0.0))
    parts = [ch.geo.ellipsoid(Vector((0.03, 0.026, 0.024)), knot_c, 20, 14),
             ch.geo.ellipsoid(Vector((0.022, 0.02, 0.018)), knot_c + Vector((-0.02, 0.01, -0.012)), 16, 12)]
    for k, (dx, L) in enumerate(((-0.03, 0.13), (0.01, 0.1))):
        pts = [knot_c + Vector((dx * t * 2, 0.012 * t, -L * t)) + Vector((-0.02 * t * t, 0.02 * t, 0))
               for t in [i / 6 for i in range(7)]]
        tail = ch.geo.tube(pts, [0.016, 0.02, 0.022, 0.022, 0.02, 0.016, 0.008], seg=12)
        for v in tail.verts:  # flach gedrückt
            v.co.x = pts[0].x + (v.co.x - pts[0].x) * 0.35 + dx * 0.2
        parts.append(tail)
    rig.headpart("Scarf_Knot", ch.geo.merge(*parts), m["scarf"], smooth=True, sharp_angle=None)

    # Haar: Strähnen aus der Saumlinie (seitlich und hinten), fallen auf die Schultern
    mb = hd.MeshBuilder()
    spans = []
    for k in range(380):
        a = rnd.uniform(-math.pi, math.pi)
        if abs(a) < 0.75:  # nicht vor dem Gesicht
            continue
        dirv = Vector((math.sin(a), -math.cos(a), 0))
        z = edge_z(a) - 0.004
        hit = tree.ray_cast(hc + dirv * 0.5 + Vector((0, 0, z)), -dirv)
        if hit[0] is None:
            continue
        p, n = hit[0] + hit[1] * 0.004, hit[1]
        L = rnd.uniform(0.15, 0.26) * (0.8 if abs(a) < 1.2 else 1.0)
        d = Vector((n.x * 0.25, n.y * 0.25, -1.0)) + Vector((rnd.uniform(-0.12, 0.12), rnd.uniform(-0.12, 0.12), 0))
        first = len(mb.bm.faces)
        hd.add_feather(mb, p, n, d, L, rnd.uniform(0.018, 0.03), lift=rnd.uniform(0.08, 0.22),
                       curl=rnd.uniform(-0.15, 0.05), cup=0.1, twist=rnd.uniform(-0.6, 0.6), along=7, across=2,
                       shape=0.4, sink=0.002)
        spans.append((first, len(mb.bm.faces), n.copy()))
    mb.bm.faces.ensure_lookup_table()
    flip = []
    for a0, b0, n in spans:
        if b0 > a0:
            mb.bm.faces[a0].normal_update()
            if mb.bm.faces[a0].normal.dot(n) < 0:
                flip.extend(mb.bm.faces[i] for i in range(a0, b0))
    bmesh.ops.reverse_faces(mb.bm, faces=flip)
    mb.finish("Hair_Fur", m["hair"], parent=rig.head)


# =====================================================================================
#  Körper (Torso-Koordinaten)
# =====================================================================================

def build_body(rig, m, rnd):
    tb = rig.torso
    mb = hd.MeshBuilder()
    zs = [-0.15 + i * 0.0105 for i in range(120)] + [1.1, 1.108]
    seg = 112
    rows, uvs = [], []
    for z in zs:
        rows.append([B.body_point(j / seg * math.tau, z) for j in range(seg)])
        uvs.append([(j / seg * 5.0, z * 2.5) for j in range(seg)])
    mb.grid(rows, uvs, close=True)
    mb.finish("Body", m["robe"], parent=tb)
    for side in (-1, 1):
        rig.marker("Shoulder_L" if side < 0 else "Shoulder_R", tb, Vector((side * 0.335, 0.02, 0.95)))

    # Hals (faltig) bis unter das Kinn
    neck = ch.geo.tube([Vector((0, 0.0, 0.98)), Vector((0, -0.005, 1.08)), Vector((0, -0.01, 1.15))],
                       [0.085, 0.075, 0.07], seg=28)
    rig.body("Body_Neck", neck, m["skin"], smooth=True, sharp_angle=None)

    # Schultertuch: liegt über Schultern und Rücken, vorne offen, Unterkante zerfranst
    sh = hd.MeshBuilder()
    n_th, n_t = 120, 22
    rows, uvs = [], []
    for i in range(n_t + 1):
        t = i / n_t  # 0 = Hals, 1 = Unterkante
        row, uvr = [], []
        for j in range(n_th + 1):
            u = j / n_th
            th = math.radians(-70 + u * 320)  # vorne offen (Lücke um th = -90°)
            front = max(0.0, -math.sin(th))
            z_bot = 0.62 + 0.12 * front + 0.03 * math.sin(th * 7) + 0.025 * noise.noise(
                Vector((math.cos(th) * 3, math.sin(th) * 3, 0.5)))
            z = 1.1 - (1.1 - z_bot) * t
            out = 0.012 + 0.03 * t + 0.008 * math.sin(th * 9 + t * 3) * t
            p = B.body_point(th, z, out, folds=False)
            p.z += 0.03 * (1 - t) * (1 - t)
            row.append(p)
            uvr.append((u * 5, t * 1.4))
        rows.append(row)
        uvs.append(uvr)
    sh.grid(rows, uvs)
    ob = sh.finish("Body_Shawl", m["shawl"], parent=tb)
    mod = ob.modifiers.new("Dicke", "SOLIDIFY")
    mod.thickness = 0.006
    # Fransen an der Unterkante
    fr = hd.MeshBuilder()
    spans = []
    for j in range(0, n_th + 1, 2):
        p = rows[-1][j]
        n = (Vector((p.x, p.y, 0))).normalized()
        L = rnd.uniform(0.03, 0.06)
        first = len(fr.bm.faces)
        hd.add_feather(fr, p, n, Vector((0, 0, -1)), L, 0.02, lift=0.05, curl=0.0, cup=0.0,
                       twist=rnd.uniform(-0.3, 0.3), along=4, across=2, shape=0.3, sink=0.0)
        spans.append((first, len(fr.bm.faces), n))
    fr.finish("Body_Shawl_Fringe", m["fringe"], parent=tb)

    # Halskette: Schnur mit Zähnen, Krallen und Perlen
    cord = [B.front_point(-0.11 + 0.22 * k / 24, 1.02 - 0.08 * math.sin(k / 24 * math.pi), 0.02) for k in range(25)]
    rig.body("Body_Necklace", ch.geo.tube(cord, [0.0025] * 25, seg=8), m["cord"], smooth=True, sharp_angle=None)
    trinkets = []
    for k in range(2, 23, 2):
        p = cord[k]
        L = rnd.uniform(0.03, 0.05) if k % 4 == 0 else rnd.uniform(0.015, 0.025)
        bend = Vector((rnd.uniform(-0.006, 0.006), -0.008, 0))
        trinkets.append(ch.geo.tube([p, p + bend + Vector((0, 0, -L * 0.5)), p + bend * 1.6 + Vector((0, 0, -L))],
                                    [0.0055, 0.0045, 0.0008], seg=10))
        if k % 4 == 2:
            trinkets.append(ch.geo.ellipsoid(Vector((0.005,) * 3), p + Vector((0.008, -0.002, -0.002)), 10, 8))
    rig.body("Body_Trinkets", ch.geo.merge(*trinkets), m["tooth"], smooth=True, sharp_angle=None)

    lantern(rig, m)


def lantern(rig, m):
    """Laterne auf dem Tisch (vom Spieler aus links), warmes Licht (PropLight)."""
    lp = G(-0.42, 0.8, 0.22)
    parts = [ch.geo.lathe([(0.0, 0.0), (0.05, 0.0), (0.052, 0.006), (0.045, 0.014), (0.0, 0.014)], 24, 0.2),
             ch.geo.lathe([(0.042, 0.15), (0.05, 0.152), (0.032, 0.18), (0.012, 0.2), (0.0, 0.205)], 24, 0.2)]
    for k in range(6):
        a = k / 6 * math.tau
        parts.append(ch.geo.tube([Vector((math.cos(a) * 0.042, math.sin(a) * 0.042, 0.012)),
                                  Vector((math.cos(a) * 0.04, math.sin(a) * 0.04, 0.152))], [0.0035, 0.0035], seg=6))
    handle = [Vector((math.cos(t) * 0.03, 0, 0.205 + math.sin(t) * 0.03)) for t in [math.pi * k / 10 for k in range(11)]]
    parts.append(ch.geo.tube(handle, [0.003] * 11, seg=6))
    bm = ch.geo.merge(*parts)
    ch.geo.transform(bm, Matrix.Translation(lp))
    rig.prop("Lantern", bm, m["iron"], smooth=True, sharp_angle=None)
    glass = ch.geo.lathe([(0.0, 0.014), (0.038, 0.014), (0.04, 0.08), (0.037, 0.15), (0.0, 0.15)], 24, 0.2)
    ch.geo.transform(glass, Matrix.Translation(lp))
    rig.prop("Lantern_Glass", glass, m["lglass"], smooth=True, sharp_angle=None)
    rig.marker("PropLight", rig.props, lp + Vector((0, 0, 0.08)))


def hands_and_sleeve(rig, m, rnd):
    hands = [hd.grip_hand(side, m["hands"], m["nail"], size=1.08, thick=0.92, knobby=0.85, finger_len=1.22,
                          bony=True, pitch=-0.45, wrist_back=0.06, wrist_up=0.0) for side in (-1, 1)]
    for side, h in zip((-1, 1), hands):
        h.location = G(side * 0.085, 0.9, 0.22)
    upper = hd.sleeve_segment("SleeveUpper", m["shawl"], 0.09, 0.08, folds=1.2, bunch_end=1.0, seed=3)
    fore = hd.sleeve_segment("SleeveFore", m["robe"], 0.074, 0.064, cuff=0.014, folds=1.0, seed=4)
    hd.preview_arms(upper, fore, hands[0], hands[1])


# =====================================================================================

def scale_head(rig, s):
    for ob in rig.head.children:
        ob.location = C + (Vector(ob.location) - C) * s
        if ob.type == "MESH":
            ob.data.transform(Matrix.Scale(s, 4))


def build(steps=("head", "body", "hands"), seed=41):
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
