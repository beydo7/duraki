"""Der Knochenmann in HD (nach dem Konzeptbild „Am Spieltisch“, Feld 6):
vergilbter Totenschädel mit tiefen Augenhöhlen, in denen orange Glut brennt, breites Grinsen
mit vollen Zahnreihen, Unterkiefer beweglich; abgegriffener Zylinder mit rotem Band und einer
brennenden Kerze auf der Krempe (Wachs läuft herunter); dunkler Gehrock mit rot gefüttertem
Revers und hohem Kragen, im Ausschnitt Brustbein, Rippen und Halswirbel; Knochenhände.

    import hd_bone_man; hd_bone_man.build()
    hd_bone_man.build(steps=("head",))    # nur Teile
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
HEAD_Y = 1.18
HEAD_SCALE = 1.5
RX, RY, RZ = 0.112, 0.132, 0.14
EYES = [(-0.041, 0.004), (0.041, 0.004)]
TEETH_Z = -0.086  # Beißkante (Unterkante der Oberkieferzähne)
GUM_Z = -0.068  # Zahnfleischlinie oben: bis hierher reicht der Schädel
HINGE = C + Vector((0.0, 0.035, -0.035))  # Kiefergelenk (Jaw-Empty)


def _g(a, s):
    return math.exp(-(a * a) / (2 * s * s))


def _cup(dist, r, soft):
    """1 innerhalb von r, weicher Rand der Breite soft, 0 außen (für Löcher mit Kante)."""
    t = max(0.0, min(1.0, (r - dist) / soft + 0.5))
    return t * t * (3 - 2 * t)


# =====================================================================================
#  Texturen und Materialien
# =====================================================================================

def tex_bone(name, base=(0.66, 0.55, 0.37), stain=(0.3, 0.21, 0.11), size=1024, seed=131, cracks=1.0):
    """Alter Knochen: elfenbein bis vergilbt, bräunliche Flecken, feine Haarrisse, Poren."""
    rng = np.random.default_rng(seed)
    big = hd.fractal(size, 2.8, seed)
    mid = hd.fractal(size, 1.9, seed + 1)
    fine = hd.fractal(size, 0.8, seed + 2)
    cr = hd.ridged(hd.fractal(size, 2.3, seed + 3))
    crack = np.clip((cr - 0.93) * 14, 0, 1) * cracks
    cr2 = hd.ridged(hd.fractal(size, 2.0, seed + 4))
    crack = np.maximum(crack, np.clip((cr2 - 0.95) * 18, 0, 1) * 0.6 * cracks)
    pores = (rng.random((size, size)) > 0.985).astype(np.float32)
    base_l, stain_l = hd.srgb_to_linear(base), hd.srgb_to_linear(stain)
    t = np.clip(0.55 * big + 0.3 * mid + 0.15 * fine, 0, 1)
    st = np.clip((t - 0.45) * 2.2, 0, 1)
    col = base_l * (1 - 0.6 * st[..., None]) + stain_l * 0.6 * st[..., None]
    col *= (0.9 + 0.15 * fine)[..., None]
    col *= (1 - 0.55 * crack)[..., None]
    col *= (1 - 0.25 * pores)[..., None]
    height = big * 0.2 + mid * 0.15 + fine * 0.15 - crack * 0.9 - pores * 0.4
    return (hd.to_image(name + "_color", col ** (1 / 2.2)),
            hd.to_image(name + "_normal", hd.height_to_normal(height, 3.5), non_color=True))


def materials():
    m = {}
    c, n = tex_bone("bone", seed=131)
    m["bone"] = hd.material("Knochen", c, n, rough=0.6, normal_strength=1.0, spec=0.35)
    c, n = tex_bone("teeth", base=(0.64, 0.54, 0.35), stain=(0.33, 0.23, 0.11), size=512, seed=133, cracks=0.4)
    m["teeth"] = hd.material("Knochen_Zahn", c, n, rough=0.45, normal_strength=0.6, spec=0.45)
    c, n = tex_bone("hands", base=(0.62, 0.52, 0.34), stain=(0.3, 0.21, 0.11), size=512, seed=135)
    m["handbone"] = hd.material("Knochen_Hand", c, n, rough=0.6, normal_strength=0.9, spec=0.35)
    c, n = hd.tex_cloth("coat", (0.15, 0.115, 0.085), (0.04, 0.03, 0.022), size=1024, seed=141, weave=150, rag=0.6)
    m["coat"] = hd.material("Knochen_Gehrock", c, n, rough=0.9, normal_strength=1.0, spec=0.2)
    c, n = hd.tex_cloth("lining", (0.4, 0.055, 0.045), (0.12, 0.015, 0.015), size=512, seed=143, weave=180, rag=0.3)
    m["lining"] = hd.material("Knochen_Futter", c, n, rough=0.75, normal_strength=0.6, spec=0.3)
    c, n = hd.tex_cloth("hat", (0.2, 0.14, 0.09), (0.06, 0.04, 0.025), size=1024, seed=145, weave=220, rag=0.4)
    m["hat"] = hd.material("Knochen_Zylinder", c, n, rough=0.85, normal_strength=0.8, spec=0.2)
    c, n = hd.tex_cloth("band", (0.52, 0.09, 0.06), (0.2, 0.03, 0.02), size=256, seed=147, weave=200, rag=0.15)
    m["band"] = hd.material("Knochen_Hutband", c, n, rough=0.5, normal_strength=0.4, spec=0.45)
    m["wax"] = hd.material("Knochen_Wachs", color=(0.8, 0.68, 0.44, 1), rough=0.42, spec=0.45)
    m["wick"] = hd.material("Knochen_Docht", color=(0.03, 0.025, 0.02, 1), rough=0.9, spec=0.1)
    m["flame"] = hd.material("Knochen_Flamme", color=(1.0, 0.75, 0.3, 1), rough=0.5,
                             emission=(1.0, 0.62, 0.2, 1), emission_strength=6.0)
    m["flamecore"] = hd.material("Knochen_Flammenkern", color=(1.0, 0.95, 0.75, 1), rough=0.5,
                                 emission=(1.0, 0.92, 0.7, 1), emission_strength=9.0)
    m["eye"] = hd.material("Knochen_Auge", color=(1.0, 0.42, 0.06, 1), rough=0.3,
                           emission=(1.0, 0.36, 0.03, 1), emission_strength=1.1)
    m["eyecore"] = hd.material("Knochen_Augenkern", color=(1.0, 0.78, 0.35, 1), rough=0.3,
                               emission=(1.0, 0.7, 0.25, 1), emission_strength=1.8)
    m["button"] = hd.material("Knochen_Knopf", color=(0.08, 0.06, 0.05, 1), rough=0.4, spec=0.5)
    return m


# =====================================================================================
#  Schädel (Head-Koordinaten, vorne = -Y)
# =====================================================================================

def skull_shape(c: Vector, d: Vector) -> Vector:
    x, z = c.x, c.z
    front = max(0.0, -d.y)
    off = Vector()
    # Gesichtsschädel unten schmaler, Hirnschädel hinten/oben voll
    off.x -= c.x * 0.22 * max(0.0, -z) / RZ
    off.y += c.y * 0.08 * max(0.0, -z) / RZ * (1 if c.y > 0 else 0)
    # Schläfen eingezogen (seitlich über den Wangenknochen)
    for s in (-1, 1):
        off.x -= s * 0.013 * _g(x - s * RX, 0.03) * _g(z - 0.02, 0.028) * max(0.0, -d.y + 0.4)
    # Stirn/Augenbrauenbogen
    off.y -= 0.011 * front ** 2 * _g(z - 0.035, 0.012) * _g(abs(x) - 0.04, 0.035)
    # Augenhöhlen: groß, rund, tief, mit Kante
    for ex, ez in EYES:
        dist = math.hypot((x - ex) * 0.95, (z - ez) * 1.0)
        off.y += 0.062 * front * _cup(dist, 0.024, 0.012)
        off.y -= 0.006 * front * _g(dist - 0.031, 0.005)  # Höhlenrand
    # Nasenöffnung: umgedrehtes Herz mit Kante
    if -0.062 < z < -0.012:
        tt = (z + 0.012) / -0.046  # 0 oben … 1 unten
        half = 0.004 + 0.019 * math.sin(min(1.0, tt * 1.05) * math.pi * 0.6) * (1 - 0.55 * tt ** 3)
        off.y += 0.04 * front * _cup(abs(x), half, 0.005) * _cup(abs(tt - 0.5), 0.48, 0.08)
    # Wangenknochen (Jochbein) vor und außen
    for s in (-1, 1):
        off += Vector((s * 0.014, -0.016 * front, 0)) * _g(x - s * 0.066, 0.018) * _g(z + 0.03, 0.013)
        # eingefallen unter dem Jochbein
        off.y += 0.02 * front * _g(x - s * 0.058, 0.016) * _g(z + 0.062, 0.012)
    # Oberkiefer: vorn gewölbt bis zur Zahnreihe, darunter abgeschnitten
    off.y -= 0.014 * front * _g(x, 0.042) * _g(z - GUM_Z - 0.006, 0.01)
    if z < GUM_Z:
        off.z += (GUM_Z - z) * 0.85
        off.x -= c.x * 0.12
        off.y -= c.y * 0.12
    # Unebenheiten im Knochen
    off += d * 0.0025 * noise.noise(c * 30)
    return c + off


def build_head(rig, m, rnd):
    head = ch.Head((RX, RY, RZ), u=110, v=76)
    head.deform(skull_shape)
    skull = rig.headpart("Skull", head.bm.copy(), m["bone"], smooth=True, sharp_angle=None)
    hd.organic(skull, voxel=0.0015, smooth=2, faces=30000, uv_tile=0.12)
    fb = bmesh.new()
    fb.from_mesh(skull.data)
    tree = BVHTree.FromBMesh(fb)
    fb.free()

    def surf(x, z, lift=0.0):
        hit = tree.ray_cast(C + Vector((x, -0.6, z)), Vector((0, 1, 0)))
        if hit[0] is None:
            return C + Vector((x, -RY, z)), Vector((0, -1, 0))
        return hit[0] + hit[1] * lift, hit[1]

    sockets(rig, m, surf)
    nose_hole(rig, surf)
    upper_teeth(rig, m, surf, rnd)
    jaw(rig, m, surf, rnd)
    top_hat(rig, m, tree, rnd)
    return skull


def sockets(rig, m, surf):
    """Schwarze Tiefe in den Augenhöhlen, darin die Glut (selbstleuchtend). Die Godot-Marker
    sitzen in der Glut, Godot setzt dort noch einen glühenden Kern und Licht dazu."""
    voids, glow, core = [], [], []
    for i, (ex, ez) in enumerate(EYES):
        p, _n = surf(ex, ez)  # Boden der Höhle
        voids.append(ch.geo.ellipsoid(Vector((0.024, 0.004, 0.023)), p + Vector((0, -0.002, 0)), 24, 10))
        c = p + Vector((0, -0.011, -0.001))
        glow.append(ch.geo.ellipsoid(Vector((0.0115, 0.008, 0.011)), c, 22, 14))
        core.append(ch.geo.ellipsoid(Vector((0.0058, 0.003, 0.0055)), c + Vector((0, -0.0068, 0.0005)), 16, 10))
        rig.marker("EyeL" if i == 0 else "EyeR", rig.head, c)
    rig.headpart("Void_Sockets", ch.geo.merge(*voids), ch.void(), smooth=True, sharp_angle=None)
    rig.headpart("Glow_Eyes", ch.geo.merge(*glow), m["eye"], smooth=True, sharp_angle=None)
    rig.headpart("Glow_EyeCores", ch.geo.merge(*core), m["eyecore"], smooth=True, sharp_angle=None)


def nose_hole(rig, surf):
    """Dunkle Nasenöffnung (umgedrehtes Herz mit Scheidewand-Rest)."""
    bm = bmesh.new()
    rows = []
    for i in range(9):
        t = i / 8
        z = -0.016 - t * 0.04
        half = 0.003 + 0.018 * math.sin(min(1.0, t * 1.05) * math.pi * 0.6) * (1 - 0.55 * t ** 3)
        row = []
        for j in range(7):
            u = j / 6 * 2 - 1
            x = u * half * 0.72
            p, n = surf(x, z, 0.0012)
            row.append(bm.verts.new(p))
        rows.append(row)
    for i in range(8):
        for j in range(6):
            bm.faces.new((rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]))
    rig.headpart("Void_Nose", bm, ch.void(), smooth=True, sharp_angle=None)


def _tooth(base: Vector, up: Vector, out: Vector, w, h, d, rnd, crown_down=True):
    """Ein Zahn: Krone als abgerundeter Block, Wurzelansatz im Kiefer."""
    bm = ch.geo.ellipsoid(Vector((w * 0.5, d * 0.5, h * 0.5)), Vector((0, 0, 0)), 14, 10)
    for v in bm.verts:
        k = v.co.z / (h * 0.5)
        # Krone unten flacher und breiter, oben schmal
        v.co.x *= 1.0 - 0.25 * max(0.0, k if crown_down else -k)
        v.co.z = max(v.co.z, -h * 0.42) if crown_down else min(v.co.z, h * 0.42)
    x = up.cross(out).normalized()
    M = Matrix((x, out.normalized(), up.normalized())).transposed().to_4x4()
    M.translation = base
    tilt = Matrix.Rotation(rnd.uniform(-0.08, 0.08), 4, "Y")
    return ch.geo.transform(bm, M @ tilt)


TOOTH_X = [0.006, 0.0175, 0.028, 0.0375, 0.0455, 0.052]  # Mitte der Zähne (eine Seite)
TOOTH_W = [0.0112, 0.0104, 0.0096, 0.0092, 0.0088, 0.0084]


def upper_teeth(rig, m, surf, rnd):
    parts = []
    for s in (-1, 1):
        for k, (xx, w) in enumerate(zip(TOOTH_X, TOOTH_W)):
            x = s * xx
            h = (0.026 if k < 2 else 0.024 if k < 4 else 0.021) * rnd.uniform(0.94, 1.04)
            p, n = surf(x, GUM_Z + 0.012, 0.0)
            out = Vector((n.x, n.y, 0)).normalized()
            base = Vector((p.x, p.y, C.z + TEETH_Z + h * 0.5)) - out * 0.0045
            parts.append(_tooth(base, Vector((0, 0, 1)), out, w, h, 0.009, rnd))
    rig.headpart("Teeth_Upper", ch.geo.merge(*parts), m["teeth"], smooth=True, sharp_angle=None)
    # dunkler Mundraum hinter den Zähnen: Zahnlücken werden schwarz
    bm = bmesh.new()
    cols = []
    for k in range(25):
        x = (k / 24 * 2 - 1) * 0.05
        p, n = surf(x, GUM_Z + 0.012, 0.0)
        out = Vector((n.x, n.y, 0)).normalized()
        q = Vector((p.x, p.y, C.z + TEETH_Z)) - out * 0.011
        cols.append([bm.verts.new(q + Vector((0, 0, dz))) for dz in (0.03, 0.0, -0.02)])
    for k in range(24):
        for r in range(2):
            bm.faces.new((cols[k][r], cols[k + 1][r], cols[k + 1][r + 1], cols[k][r + 1]))
    rig.headpart("Void_Mouth", bm, ch.void(), smooth=True, sharp_angle=None)


def jaw(rig, m, surf, rnd):
    """Unterkiefer als eigenes Teil am Jaw-Empty (Godot klappt ihn beim Lachen auf)."""
    jaw_e = rig.marker("Jaw", rig.head, HINGE)
    parts = []
    # Hufeisen entlang der Zahnreihe (vorne), hinten zu den aufsteigenden Ästen
    path, radii = [], []
    arc = []
    for k in range(21):
        x = (k / 20 * 2 - 1) * 0.056
        p, n = surf(x, GUM_Z + 0.012, 0.0)
        out = Vector((n.x, n.y, 0)).normalized()
        arc.append(Vector((p.x, p.y, 0)) - out * 0.002)
    back_l = C + Vector((-0.064, 0.02, 0)) - C
    back_r = C + Vector((0.064, 0.02, 0)) - C
    ring = [Vector((back_l.x, back_l.y + 0.0, 0)), Vector((-0.06, arc[0].y + 0.03 - C.y, 0))] + \
           [a - Vector((0, C.y, 0)) for a in arc] + [Vector((0.06, arc[-1].y + 0.03 - C.y, 0)), back_r]
    for i, q in enumerate(ring):
        t = abs(i / (len(ring) - 1) * 2 - 1)
        path.append(C + Vector((q.x, q.y, TEETH_Z - 0.022 - 0.008 * (1 - t))))
        radii.append(0.013 + 0.003 * (1 - t))
    jb = ch.geo.tube(path, radii, seg=16)
    for v in jb.verts:  # hoch und schmal
        z0 = C.z + TEETH_Z - 0.022
        v.co.z = z0 + (v.co.z - z0) * 1.35
    parts.append(jb)
    # Kinn
    chin = arc[10] + Vector((0, 0, 0))
    parts.append(ch.geo.ellipsoid(Vector((0.026, 0.014, 0.017)), Vector((0, chin.y + 0.004, C.z + TEETH_Z - 0.036)),
                                  20, 12))
    # aufsteigende Äste zum Gelenk
    for s in (-1, 1):
        parts.append(ch.geo.tube([C + Vector((s * 0.064, 0.02, TEETH_Z - 0.025)), C + Vector((s * 0.069, 0.03, -0.07)),
                                  C + Vector((s * 0.072, 0.034, -0.04))], [0.014, 0.012, 0.009], seg=14))
        parts.append(ch.geo.ellipsoid(Vector((0.007, 0.009, 0.006)), C + Vector((s * 0.073, 0.036, -0.036)), 12, 8))
    bm = ch.geo.merge(*parts)
    ob = rig.headpart("Jaw_Bone", bm, m["bone"], smooth=True, sharp_angle=None)
    hd.organic(ob, voxel=0.0014, smooth=2, faces=9000, uv_tile=0.12)
    # untere Zähne
    lower = []
    for s in (-1, 1):
        for k, (xx, w) in enumerate(zip(TOOTH_X, TOOTH_W)):
            x = s * xx * 0.97
            h = (0.02 if k < 3 else 0.017) * rnd.uniform(0.92, 1.05)
            p, nrm = surf(x, GUM_Z + 0.012, 0.0)
            out = Vector((nrm.x, nrm.y, 0)).normalized()
            base = Vector((p.x, p.y, C.z + TEETH_Z - 0.0008 - h * 0.5)) - out * 0.0055
            lower.append(_tooth(base, Vector((0, 0, 1)), out, w * 0.95, h, 0.0085, rnd, crown_down=False))
    lt = rig.headpart("Jaw_Teeth", ch.geo.merge(*lower), m["teeth"], smooth=True, sharp_angle=None)
    # Mesh-Daten in Gelenk-Koordinaten, dann unter das Jaw-Empty hängen
    for o in (ob, lt):
        o.data.transform(Matrix.Translation(-HINGE))
        o.parent = jaw_e
        o.location = (0, 0, 0)


def top_hat(rig, m, tree, rnd):
    """Abgegriffener Zylinder, leicht nach hinten gekippt, rotes Band, Kerze auf der Krempe."""
    hc = C + Vector((0.0, 0.012, 0.062))  # Unterkante der Krone (tief über der Stirn)
    tilt = Matrix.Translation(hc) @ Matrix.Rotation(math.radians(-9), 4, "X") @ Matrix.Rotation(
        math.radians(6), 4, "Y")
    # Krone (Lathe, oben leicht ausgestellt), elliptisch, verbeult
    prof = [(0.118, -0.012), (0.116, 0.0), (0.114, 0.035), (0.116, 0.085), (0.121, 0.135), (0.124, 0.168),
            (0.118, 0.173), (0.0, 0.175)]  # von unten nach oben (Normalen nach außen)
    crown = ch.geo.lathe(prof, 56, 0.02)
    for v in crown.verts:
        v.co.y *= 1.1
        k = v.co
        v.co += Vector((k.x, k.y, 0)).normalized() * 0.007 * noise.noise(Vector((k.x * 9, k.y * 9, k.z * 6)))
        if k.z > 0.15:
            v.co.z -= 0.012 * _g(k.x + 0.03, 0.05) * _g(k.y + 0.05, 0.06)  # eingedrückt vorne oben
            v.co.x += 0.006 * (k.z - 0.15) / 0.025  # leicht schief
    ch.geo.transform(crown, tilt)
    rig.headpart("Hat_Crown", crown, m["hat"], smooth=True, sharp_angle=None)
    # Hutband
    band = ch.geo.lathe([(0.1192, 0.0), (0.1204, 0.02), (0.1194, 0.04)], 56, 0.02)
    for v in band.verts:
        v.co.y *= 1.1
    ch.geo.transform(band, tilt @ Matrix.Translation((0, 0, 0.002)))
    rig.headpart("Hat_Band", band, m["band"], smooth=True, sharp_angle=None)
    # Krempe: seitlich hochgebogen, vorn und hinten leicht gesenkt
    mb = hd.MeshBuilder()
    rows, uvs = [], []
    for i in range(7):
        r_t = i / 6
        row, uvr = [], []
        for j in range(72):
            a = j / 72 * math.tau
            rx = 0.115 + 0.085 * r_t
            ry = (0.115 + 0.09 * r_t) * 1.1
            x, y = rx * math.cos(a), ry * math.sin(a)
            z = -0.012 + 0.03 * r_t ** 2 * math.cos(a) ** 2 - 0.008 * r_t ** 2 * math.sin(a) ** 2
            z += 0.004 * r_t * noise.noise(Vector((x * 14, y * 14, 0.3)))
            row.append(Vector((x, y, z)))
            uvr.append((j / 72 * 4, r_t))
        rows.append(row)
        uvs.append(uvr)
    mb.grid(rows, uvs, close=True)
    brim = mb.finish("Hat_Brim", m["hat"], parent=rig.head)
    brim.data.transform(tilt)
    mod = brim.modifiers.new("Dicke", "SOLIDIFY")
    mod.thickness = 0.006
    mod.offset = 0.0
    # Kerze auf der Krempe (vom Spieler aus links vorne): Höhe der Krempe per Strahl
    verts = [v for row in rows for v in row]
    nj = len(rows[0])
    polys = [(i * nj + j, i * nj + (j + 1) % nj, (i + 1) * nj + (j + 1) % nj, (i + 1) * nj + j)
             for i in range(len(rows) - 1) for j in range(nj)]
    bt = BVHTree.FromPolygons(verts, polys)
    hit = bt.ray_cast(Vector((-0.14, -0.085, 0.3)), Vector((0, 0, -1)))
    local = hit[0] + Vector((0, 0, 0.003)) if hit[0] is not None else Vector((-0.158, -0.045, 0.0))
    candle(rig, m, tilt @ local, rnd)


def candle(rig, m, base: Vector, rnd):
    H, R = 0.085, 0.021
    prof = [(0.0, 0.0), (R * 1.25, 0.0), (R * 1.1, 0.006), (R, 0.012), (R, H - 0.008), (R * 0.96, H - 0.003),
            (R * 0.7, H), (R * 0.35, H - 0.004), (0.0, H - 0.005)]
    body = ch.geo.lathe(prof, 28, 0.15)
    for v in body.verts:  # ungleichmäßig abgebrannt
        a = math.atan2(v.co.y, v.co.x)
        if v.co.z > H - 0.012:
            v.co.z += 0.006 * math.sin(a * 2 + 1.0) + 0.003 * math.sin(a * 5)
        v.co.x += 0.0012 * noise.noise(Vector((v.co.x * 60, v.co.y * 60, v.co.z * 30)))
    ch.geo.transform(body, Matrix.Translation(base))
    parts = [body]
    # Wachsnasen: laufen außen herunter, teils über die Krempe
    for k in range(7):
        a = k / 7 * math.tau + rnd.uniform(-0.3, 0.3)
        L = rnd.uniform(0.02, 0.06) if k not in (2, 5) else rnd.uniform(0.07, 0.1)
        pts, rr = [], []
        for i in range(9):
            t = i / 8
            z = H - 0.004 - t * L
            r_out = R + 0.0015
            if z < 0.0:  # über die Krempe nach außen und dann herunter
                over = -z
                pts.append(base + Vector((math.cos(a) * (r_out + over * 1.2), math.sin(a) * (r_out + over * 1.2),
                                          -over * 0.25)))
            else:
                pts.append(base + Vector((math.cos(a) * r_out, math.sin(a) * r_out, z)))
            rr.append(0.0032 * (1 - 0.35 * t) * (1 + 0.25 * math.sin(t * 7 + k)))
        parts.append(ch.geo.tube(pts, rr, seg=8))
        parts.append(ch.geo.ellipsoid(Vector((rr[-1] * 1.3, rr[-1] * 1.3, rr[-1] * 1.6)),
                                      pts[-1] + Vector((0, 0, -rr[-1] * 0.8)), 10, 8))
    # Wachspfütze auf der Krempe
    parts.append(ch.geo.ellipsoid(Vector((0.032, 0.028, 0.004)), base + Vector((0.004, -0.002, 0.001)), 24, 8))
    rig.headpart("Candle", ch.geo.merge(*parts), m["wax"], smooth=True, sharp_angle=None)
    top = base + Vector((0, 0, H - 0.002))
    rig.headpart("Candle_Wick", ch.geo.tube([top, top + Vector((0.001, 0, 0.007)), top + Vector((0.002, 0, 0.011))],
                                             [0.0011, 0.001, 0.0008], seg=6), m["wick"], smooth=True)
    # Flamme: Tropfenform, Kern innen
    fc = top + Vector((0.002, 0, 0.024))
    fl = ch.geo.ellipsoid(Vector((0.0062, 0.0062, 0.016)), fc, 16, 12)
    for v in fl.verts:
        k = (v.co.z - fc.z) / 0.016
        s = 1.0 - 0.75 * max(0.0, k) ** 1.4
        v.co.x = fc.x + (v.co.x - fc.x) * s
        v.co.y = fc.y + (v.co.y - fc.y) * s
    rig.headpart("Glow_Flame", fl, m["flame"], smooth=True, sharp_angle=None)
    rig.headpart("Glow_FlameCore", ch.geo.ellipsoid(Vector((0.0028, 0.0028, 0.007)), fc + Vector((0, 0, -0.006)),
                                                    10, 8), m["flamecore"], smooth=True)
    rig.marker("FlameLight", rig.head, fc + Vector((0, -0.01, 0.01)))


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
    mb.finish("Body", m["coat"], parent=tb)
    for side in (-1, 1):
        rig.marker("Shoulder_L" if side < 0 else "Shoulder_R", tb, Vector((side * 0.335, 0.02, 0.95)))

    # Dunkle Tiefe im V-Ausschnitt (zwischen den Rippen sieht man ins Leere)
    vd = hd.MeshBuilder()
    rows, uvs = [], []
    for i in range(16):
        z = 0.58 + i * 0.033
        w = 0.04 + (z - 0.58) * 0.32
        rows.append([B.front_point(x, z, -0.004) for x in (-w, -w * 0.5, 0.0, w * 0.5, w)])
        uvs.append([(u, z * 2) for u in (0, 0.25, 0.5, 0.75, 1.0)])
    vd.grid(rows, uvs)
    vd.finish("Void_Chest", ch.void(), parent=tb)
    ribcage(rig, m, rnd)

    # Revers aus rotem Futterstoff
    inner = [(0.105, 1.07), (0.105, 1.0), (0.1, 0.95), (0.09, 0.88), (0.075, 0.8), (0.052, 0.71), (0.028, 0.63)]
    outer = [(0.2, 1.05), (0.25, 1.0), (0.262, 0.95), (0.225, 0.9), (0.18, 0.82), (0.11, 0.71), (0.036, 0.62)]
    for s in (-1, 1):
        lp = hd.MeshBuilder()
        rows, uvs = [], []
        n_v, n_u = 16, 7
        for i in range(n_v):
            t = i / (n_v - 1)
            a = B._lerp_poly(inner, t)
            b = B._lerp_poly(outer, t)
            row, uvr = [], []
            for j in range(n_u):
                u = j / (n_u - 1)
                x = a[0] + (b[0] - a[0]) * u
                z = a[1] + (b[1] - a[1]) * u
                lift = 0.013 + 0.016 * u ** 2 + 0.008 * math.sin(t * math.pi) + 0.004 * math.sin(u * math.pi)
                row.append(B.front_point(s * x, z, lift))
                uvr.append((u * 0.4, t * 1.2))
            if s < 0:
                row.reverse()
                uvr.reverse()
            rows.append(row)
            uvs.append(uvr)
        lp.grid(rows, uvs)
        ob = lp.finish("Body_Lapel" + ("L" if s < 0 else "R"), m["lining"], parent=tb)
        mod = ob.modifiers.new("Dicke", "SOLIDIFY")
        mod.thickness = 0.008
        mod.offset = -1.0
        # Kante: dunkler Rockstoff als schmaler Wulst entlang der Außenkante
        edge = [B.front_point(s * B._lerp_poly(outer, k / 20)[0], B._lerp_poly(outer, k / 20)[1],
                              0.013 + 0.016 + 0.004) for k in range(21)]
        rig.body("Body_LapelEdge" + ("L" if s < 0 else "R"), ch.geo.tube(edge, [0.004] * 21, seg=8), m["coat"],
                 smooth=True, sharp_angle=None)

    # Hoher Stehkragen: außen Rockstoff, innen rot
    for name, mat, r_add, thick in (("Body_Collar", m["coat"], 0.0, 0.012), ("Body_CollarLining", m["lining"],
                                                                            -0.011, 0.003)):
        col = hd.MeshBuilder()
        rows, uvs = [], []
        for i in range(10):
            t = i / 9
            z = 0.99 + t * 0.2
            row, uvr = [], []
            for j in range(37):
                th = math.radians(-32 + j * (244 / 36))  # hinten herum, vorne offen
                r = 0.15 + 0.06 * t + r_add
                flare = 0.05 * t * t * max(0.0, -math.sin(th) + 0.2)  # vorne aufgeschlagen
                row.append(Vector((r * 1.15 * math.cos(th) * (1 + flare), 0.04 + r * 0.95 * math.sin(th)
                                   - 0.02 * t * max(0.0, -math.sin(th) + 0.3), z)))
                uvr.append((j / 36 * 2, t))
            rows.append(row)
            uvs.append(uvr)
        col.grid(rows, uvs)
        co = col.finish(name, mat, parent=tb)
        mod = co.modifiers.new("Dicke", "SOLIDIFY")
        mod.thickness = thick

    # zwei dunkle Knöpfe unten am Rock
    btn = []
    for z in (0.56, 0.46):
        p = B.front_point(0.075, z, 0.006)
        b = ch.geo.lathe([(0.0, 0.0), (0.013, 0.0), (0.014, 0.004), (0.01, 0.007), (0.0, 0.008)], 20, 0.1)
        ch.geo.transform(b, Matrix.Translation(p) @ Matrix.Rotation(math.pi / 2, 4, "X"))
        btn.append(b)
    rig.body("Body_Buttons", ch.geo.merge(*btn), m["button"], smooth=True, sharp_angle=None)


def ribcage(rig, m, rnd):
    """Brustbein, Rippen (verschwinden seitlich unter dem Revers), Schlüsselbeine, Halswirbel."""
    parts = []
    # Brustbein
    st = [B.front_point(0.0, z, 0.006) for z in (0.74, 0.8, 0.88, 0.95, 1.0)]
    sb = ch.geo.tube(st, [0.009, 0.011, 0.012, 0.012, 0.014], seg=12)
    for v in sb.verts:  # flach
        v.co.y = v.co.y * 0.6 + st[2].y * 0.4
    parts.append(sb)
    # Rippen
    for k in range(7):
        z0 = 0.97 - k * 0.042
        pts, rr = [], []
        for s in (-1, 1):
            seg_pts = []
            for i in range(10):
                t = i / 9
                x = s * (0.012 + t * 0.2)
                z = z0 - 0.05 * t - 0.055 * t * t + 0.006 * k * t
                seg_pts.append(B.front_point(x, z, 0.004 + 0.006 * math.sin(t * math.pi)))
            parts.append(ch.geo.tube(seg_pts, [0.0068 - 0.0016 * (i / 9) for i in range(10)], seg=10))
    # Schlüsselbeine
    for s in (-1, 1):
        cl = [B.front_point(s * 0.015, 1.02, 0.008), B.front_point(s * 0.08, 1.04, 0.01),
              B.front_point(s * 0.16, 1.03, 0.006)]
        parts.append(ch.geo.tube(cl, [0.0075, 0.0065, 0.0065], seg=10))
    # Halswirbel (hinter dem Brustbein nach oben zum Schädel)
    for k in range(6):
        z = 1.0 + k * 0.03
        c = Vector((0.0, 0.025, z))
        parts.append(ch.geo.ellipsoid(Vector((0.024, 0.02, 0.011)), c, 18, 10))
        parts.append(ch.geo.ellipsoid(Vector((0.009, 0.014, 0.006)), c + Vector((0, -0.016, 0.0)), 12, 8))
        for s in (-1, 1):
            parts.append(ch.geo.ellipsoid(Vector((0.009, 0.006, 0.005)), c + Vector((s * 0.024, 0.002, 0)), 10, 6))
    ob = rig.body("Body_Ribs", ch.geo.merge(*parts), m["bone"], smooth=True, sharp_angle=None)
    hd.organic(ob, voxel=0.0016, smooth=2, faces=16000, uv_tile=0.12)


# =====================================================================================
#  Knochenhände
# =====================================================================================

def bone_hand(side: int, mat, size=1.1, curl=(0.6, 0.85, 0.6), roll=72.0, pitch=-0.45,
              wrist_back=0.07, wrist_up=0.0):
    """Skeletthand in derselben Greifhaltung wie hd.grip_hand: Mittelhandknochen, Fingerglieder
    mit knotigen Gelenken und kleinen Lücken, Handwurzel als Knöchelchen, Elle und Speiche."""
    s = size
    parts = []
    lens = ((0.044, 0.028, 0.022), (0.048, 0.031, 0.024), (0.045, 0.029, 0.022), (0.035, 0.023, 0.019))
    xs = (0.03, 0.01, -0.01, -0.029)

    def bone(a: Vector, b: Vector, r0, r1, knob=1.45):
        d = (b - a).normalized()
        gap = 0.0016 * s
        a2, b2 = a + d * gap, b - d * gap
        mid = (a2 + b2) * 0.5
        out = [ch.geo.tube([a2, mid, b2], [r0, (r0 + r1) * 0.38, r1], seg=10)]
        out.append(ch.geo.ellipsoid(Vector((r0 * knob,) * 3), a2 + d * r0 * 0.4, 10, 8))
        out.append(ch.geo.ellipsoid(Vector((r1 * knob,) * 3), b2 - d * r1 * 0.4, 10, 8))
        return out

    for f in range(4):
        x = -side * xs[f] * s
        knuckle = Vector((x, -0.088 * s, 0.004 * s))
        root = Vector((x * 0.55, -0.02 * s, 0.002 * s))
        r = 0.0052 * s * (0.85 if f == 3 else 1.0)
        parts += bone(root, knuckle, r * 1.1, r * 1.15)  # Mittelhand
        d = Vector((side * 0.06 * (f - 1.5), -1, 0)).normalized()
        p = knuckle
        ang = 0.0
        for k in range(3):
            ang += curl[k] * (1.0 + 0.08 * f)
            seg_d = Matrix.Rotation(ang, 3, "X") @ d
            q = p + seg_d * lens[f][k] * s
            rr = r * (1.0 - 0.17 * k)
            parts += bone(p, q, rr, rr * 0.85, knob=1.5 if k < 2 else 1.2)
            p = q
        parts.append(ch.geo.ellipsoid(Vector((r * 0.7, r * 0.9, r * 0.55)), p, 10, 8))  # Fingerspitze
    # Daumen
    t0 = Vector((-side * 0.026 * s, -0.018 * s, -0.006 * s))
    td = Vector((-side * 0.35, -1, 0.35)).normalized()
    t1 = t0 + td * 0.034 * s
    td2 = (Matrix.Rotation(0.35, 3, "X") @ Vector((-side * 0.15, -1, 0.25))).normalized()
    t2 = t1 + td2 * 0.03 * s
    t3 = t2 + (Matrix.Rotation(0.6, 3, "X") @ td2) * 0.024 * s
    rt = 0.0062 * s
    parts += bone(t0, t1, rt * 1.1, rt)
    parts += bone(t1, t2, rt, rt * 0.85)
    parts += bone(t2, t3, rt * 0.85, rt * 0.7, knob=1.2)
    # Handwurzel
    rng = random.Random(side)
    for k in range(8):
        c = Vector((rng.uniform(-0.022, 0.022) * s, rng.uniform(-0.016, 0.004) * s, rng.uniform(-0.004, 0.006) * s))
        rr = rng.uniform(0.0055, 0.008) * s
        parts.append(ch.geo.ellipsoid(Vector((rr, rr * 1.1, rr * 0.8)), c, 10, 8))
    # Elle und Speiche (verschwinden im Ärmel)
    for xx in (-0.011, 0.011):
        parts += bone(Vector((xx * s, 0.006 * s, 0.002)), Vector((xx * s * 0.8, 0.09 * s, 0.004)), 0.0085 * s,
                      0.0065 * s, knob=1.3)

    orient = Matrix.Translation(Vector((0, wrist_back, wrist_up))) @ \
        Matrix.Rotation(math.radians(side * roll), 4, "Y") @ Matrix.Rotation(pitch, 4, "X")
    bm = ch.geo.merge(*parts)
    ch.geo.transform(bm, orient)
    name = "Hand_L" if side < 0 else "Hand_R"
    ob = ch.geo.to_object(name, bm, mat, smooth=True, sharp_angle=None)
    me = ob.data
    uv = me.uv_layers.new() if not me.uv_layers else me.uv_layers[0]
    for poly in me.polygons:  # einfache Box-Projektion für die Knochentextur
        n = poly.normal
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if abs(n.x) > abs(n.y) and abs(n.x) > abs(n.z):
                uv.data[li].uv = (co.y / 0.08, co.z / 0.08)
            elif abs(n.y) > abs(n.z):
                uv.data[li].uv = (co.x / 0.08, co.z / 0.08)
            else:
                uv.data[li].uv = (co.x / 0.08, co.y / 0.08)
    return ob


def hands_and_sleeve(rig, m, rnd):
    hands = [bone_hand(side, m["handbone"]) for side in (-1, 1)]
    for side, h in zip((-1, 1), hands):
        h.location = G(side * 0.085, 0.9, 0.22)  # Ruhelage: beide Hände halten den Fächer unten
    upper = hd.sleeve_segment("SleeveUpper", m["coat"], 0.088, 0.074, folds=1.0, bunch_end=1.0, seed=1)
    fore = hd.sleeve_segment("SleeveFore", m["coat"], 0.074, 0.066, cuff=0.018, folds=0.8, seed=2)
    hd.preview_arms(upper, fore, hands[0], hands[1])


# =====================================================================================

def scale_head(rig, s):
    """Kopf als Ganzes vergrößern (um die Schädelmitte), Marker mit. Teile unter dem Jaw-Empty
    liegen in Gelenk-Koordinaten: dort nur die Mesh-Daten skalieren."""
    for ob in rig.head.children:
        ob.location = C + (Vector(ob.location) - C) * s
        if ob.type == "MESH":
            ob.data.transform(Matrix.Scale(s, 4))
        for sub in ob.children:
            if sub.type == "MESH":
                sub.data.transform(Matrix.Scale(s, 4))
            sub.location = Vector(sub.location) * s


def build(steps=("head", "body", "hands"), seed=31):
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
