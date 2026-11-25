"""Der Riese in HD (nach dem Konzeptbild „Am Spieltisch“, Feld 8, Boss):
riesiger, kahler Kopf aus grauem, steinartigem Fleisch, wulstige Stirn, kleine gelb glühende
Augen, breite Nase, schwerer Unterkiefer mit wulstigen, zusammengepressten Lippen; überall
genähte Narben mit Klammern; ein schwerer Eisenring mit Nieten um den Hals, vorne eine Öse mit
Kette; nackter, massiger Oberkörper voller Narben, Eisenschellen an den Handgelenken,
riesige Hände.

    import hd_giant; hd_giant.build()
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
HEAD_SCALE = 1.3
RX, RY, RZ = 0.142, 0.14, 0.152
EYES = [(-0.044, 0.02), (0.044, 0.02)]
FACE_HW, FACE_HH = 0.2, 0.25
MOUTH_Z = -0.082
# genähte Narben im Gesicht (x, z): Stirn senkrecht, über die linke Wange, am Kinn
FACE_SCARS = [[(0.004, 0.1), (-0.002, 0.085), (0.0, 0.066)],
              [(-0.11, 0.02), (-0.095, -0.02), (-0.08, -0.05)],
              [(0.08, 0.085), (0.096, 0.06), (0.108, 0.035)]]


def _g(a, s):
    return math.exp(-(a * a) / (2 * s * s))


# =====================================================================================
#  Texturen und Materialien
# =====================================================================================

def _paint_lines(x, z, lines, width):
    """Abstand-Feld zu Polylinien → 0..1 (für Narben)."""
    out = np.zeros_like(x)
    for pts in lines:
        for (x0, z0), (x1, z1) in zip(pts, pts[1:]):
            dx, dz = x1 - x0, z1 - z0
            t = np.clip(((x - x0) * dx + (z - z0) * dz) / (dx * dx + dz * dz + 1e-12), 0, 1)
            d = np.hypot(x - (x0 + t * dx), z - (z0 + t * dz))
            out = np.maximum(out, np.exp(-(d / width) ** 2))
    return out


def tex_face(size=1024, seed=211):
    """Graue, steinartige Haut, fleckig; tiefe Zornesfalten, Stirnfurchen; rötlich-dunkle Narben."""
    r, c = np.mgrid[0:size, 0:size] / (size - 1)
    x = c * 2 * FACE_HW - FACE_HW
    z = r * 2 * FACE_HH - FACE_HH
    g = lambda a, s: np.exp(-(a * a) / (2 * s * s))
    big = hd.fractal(size, 2.8, seed)
    mid = hd.fractal(size, 2.0, seed + 1)
    fine = hd.fractal(size, 0.8, seed + 2)
    wob = hd.fractal(size, 2.3, seed + 3) - 0.5
    ax = np.abs(x)
    base = hd.srgb_to_linear((0.36, 0.32, 0.27))
    col = base[None, None, :] * (0.72 + 0.4 * big + 0.15 * mid)[..., None]
    height = big * 0.25 + mid * 0.25 + fine * 0.15
    # Furchen: Stirn quer, Zornesfalten, Nasolabial, unter der Unterlippe
    wr = np.zeros_like(x)
    for k in range(4):
        zz = 0.075 + k * 0.02 + 0.006 * np.sin(x * 30 + k) + 0.01 * wob
        wr += g(z - zz, 0.0025) * np.clip(1 - (ax / 0.1) ** 2, 0, 1)
    for sx in (-1, 1):
        wr += 1.2 * g(x - sx * 0.012, 0.0022) * g(z - 0.045, 0.018)
        wr += 0.9 * g(np.abs(np.hypot(x - sx * 0.01, (z + 0.05) * 1.2) - 0.05), 0.0025) * (sx * x > 0.02) * (z < 0.0)
    wr += 0.8 * g(z - MOUTH_Z + 0.03, 0.003) * g(x, 0.025)
    col *= (1 - 0.4 * np.clip(wr, 0, 1))[..., None]
    height -= 1.5 * wr
    # dunkle Augenhöhlen
    for ex, ez in EYES:
        col *= (1 - 0.5 * g(x - ex, 0.024) * g(z - ez, 0.016))[..., None]
    # Narben: dunkler Rand, rötlich-heller Wulst
    sc = _paint_lines(x, z, FACE_SCARS, 0.004)
    edge = _paint_lines(x, z, FACE_SCARS, 0.009) - sc
    pink = hd.srgb_to_linear((0.5, 0.33, 0.3))
    col = col * (1 - 0.55 * sc[..., None]) + pink[None, None, :] * 0.55 * sc[..., None]
    col *= (1 - 0.35 * np.clip(edge, 0, 1))[..., None]
    height += 0.8 * sc - 0.4 * edge
    for _ in range(2):
        height = (height + np.roll(height, 1, 0) + np.roll(height, -1, 0) + np.roll(height, 1, 1)
                  + np.roll(height, -1, 1)) / 5.0
    return (hd.to_image("face_color", col ** (1 / 2.2)),
            hd.to_image("face_normal", hd.height_to_normal(height, 3.0), non_color=True))


def tex_body(size=1024, seed=221):
    """Körperhaut (gekachelt): grau-braun, fleckig, mit kleinen Rissen und Poren."""
    big = hd.fractal(size, 2.6, seed)
    mid = hd.fractal(size, 1.9, seed + 1)
    fine = hd.fractal(size, 0.8, seed + 2)
    cr = hd.ridged(hd.fractal(size, 2.2, seed + 3))
    cracks = np.clip((cr - 0.9) * 8, 0, 1)
    base = hd.srgb_to_linear((0.36, 0.31, 0.26))
    dark = hd.srgb_to_linear((0.14, 0.12, 0.1))
    t = np.clip(0.55 * big + 0.3 * mid + 0.15 * fine, 0, 1)
    col = dark + (base - dark) * (0.35 + 0.65 * t)[..., None]
    col *= (1 - 0.3 * cracks)[..., None]
    height = big * 0.4 + mid * 0.3 + fine * 0.2 - cracks * 0.6
    return (hd.to_image("body_color", col ** (1 / 2.2)),
            hd.to_image("body_normal", hd.height_to_normal(height, 3.0), non_color=True))


def materials():
    m = {}
    c, n = tex_face()
    m["face"] = hd.material("Riese_Gesicht", c, n, rough=0.72, normal_strength=1.8, spec=0.3)
    c, n = tex_body()
    m["skin"] = hd.material("Riese_Haut", c, n, rough=0.74, normal_strength=1.8, spec=0.3)
    m["scar"] = hd.material("Riese_Narbe", color=(0.24, 0.15, 0.12, 1), rough=0.6, spec=0.3)
    m["thread"] = hd.material("Riese_Faden", color=(0.06, 0.045, 0.035, 1), rough=0.8, spec=0.15)
    c, n = hd.tex_leather("iron", (0.2, 0.17, 0.14), (0.06, 0.05, 0.04), size=512, seed=231, crease=0.3, wear=1.4)
    m["iron"] = hd.material("Riese_Eisen", c, n, rough=0.55, normal_strength=1.2, metal=0.75)
    m["rust"] = hd.material("Riese_Niete", color=(0.16, 0.11, 0.07, 1), rough=0.55, metal=0.5)
    m["nail"] = hd.material("Riese_Nagel", color=(0.22, 0.18, 0.14, 1), rough=0.6, spec=0.2)
    m["lip"] = hd.material("Riese_Lippe", color=(0.33, 0.25, 0.22, 1), rough=0.6, spec=0.3)
    m["eye"] = hd.material("Riese_Auge", color=(1.0, 0.6, 0.12, 1), rough=0.3,
                           emission=(1.0, 0.52, 0.06, 1), emission_strength=1.0)
    m["eyecore"] = hd.material("Riese_Augenkern", color=(1.0, 0.85, 0.45, 1), rough=0.3,
                               emission=(1.0, 0.8, 0.35, 1), emission_strength=2.0)
    return m


# =====================================================================================
#  Kopf (Head-Koordinaten, vorne = -Y)
# =====================================================================================

def face_shape(c: Vector, d: Vector) -> Vector:
    x, z = c.x, c.z
    front = max(0.0, -d.y)
    off = Vector()
    # Schädel oben flacher, Kiefer breit und schwer
    off.z -= 0.035 * max(0.0, z / RZ) ** 2
    off.x += c.x * 0.06 * max(0.0, z / RZ)  # breiter, eckiger Schädel
    off.x += c.x * 0.24 * max(0.0, -z) / RZ
    off.y += c.y * 0.05 * max(0.0, -z) / RZ * (1 if c.y < 0 else 0)
    # massiver Stirnwulst, zur Mitte hin gesenkt
    zb = 0.042 - 0.012 * _g(x, 0.025)
    off.y -= 0.034 * front ** 2 * _g(z - zb, 0.016) * _g(abs(x) - 0.04, 0.05)
    # kleine, tiefe Augen
    for ex, ez in EYES:
        off.y += 0.032 * front * _g(x - ex, 0.017) * _g(z - ez, 0.012)
    # Wangen breit, Kaumuskeln
    for s in (-1, 1):
        off += Vector((s * 0.014, -0.012 * front, 0)) * _g(x - s * 0.085, 0.03) * _g(z + 0.03, 0.03)
    # schwerer Unterkiefer, vorgeschoben
    if z < -0.07:
        t = min(1.0, (-0.07 - z) / 0.07)
        off.y -= 0.02 * front * t
    # Unebenheiten
    off += d * (0.003 * noise.noise(c * 22) + 0.002 * noise.noise(c * 60))
    return c + off


def nose_and_mouth():
    parts = []
    bridge = [Vector((0.0, -0.128, 0.03)), Vector((0.0, -0.14, 0.005)), Vector((0.0, -0.155, -0.02)),
              Vector((0.0, -0.165, -0.035))]
    parts.append(ch.geo.tube([C + p for p in bridge], [0.012, 0.014, 0.017, 0.02], seg=16))
    parts.append(ch.geo.ellipsoid(Vector((0.024, 0.02, 0.019)), C + Vector((0.0, -0.163, -0.04)), 22, 14))
    for sx in (-1, 1):
        parts.append(ch.geo.ellipsoid(Vector((0.016, 0.016, 0.013)), C + Vector((sx * 0.026, -0.148, -0.046)), 16, 10))
    # Lippen: wulstig, zusammengepresst, Mundwinkel nach unten
    for z0, thick, sag, yy in ((MOUTH_Z + 0.007, 0.0065, 0.006, -0.138), (MOUTH_Z - 0.009, 0.0085, 0.01, -0.134)):
        pts = []
        for k in range(13):
            u = k / 12 * 2 - 1
            x = u * 0.045
            pts.append(C + Vector((x, yy + 0.03 * u * u, z0 - sag * u * u)))
        parts.append(ch.geo.tube(pts, [thick * (0.5 + 0.5 * (1 - abs(k / 12 * 2 - 1) ** 2)) for k in range(13)],
                                 seg=12))
    # Kinn
    parts.append(ch.geo.ellipsoid(Vector((0.058, 0.03, 0.032)), C + Vector((0, -0.112, -0.125)), 24, 14))
    return ch.geo.merge(*parts)


def build_head(rig, m, rnd):
    head = ch.Head((RX, RY, RZ), u=100, v=72)
    head.deform(face_shape)
    face = rig.headpart("Face", ch.geo.merge(head.bm.copy(), nose_and_mouth()), m["face"], smooth=True,
                        sharp_angle=None)
    hd.organic(face, voxel=0.0016, smooth=3, faces=26000)
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
    mouth_line(rig, surf)
    ears(rig, m)
    stitches(rig, m, [[surf(x, z) for x, z in sc] for sc in FACE_SCARS], "Face_Stitches", rig.head, rnd)
    return face


def eyes(rig, m, surf):
    voids, glow, core = [], [], []
    for i, (ex, ez) in enumerate(EYES):
        s = 1 if ex > 0 else -1
        p, _n = surf(ex, ez)
        voids.append(ch.geo.ellipsoid(Vector((0.017, 0.005, 0.009)), p + Vector((0, 0.001, 0)), 22, 12))
        c = p + Vector((0, -0.003, 0))
        glow.append(ch.geo.ellipsoid(Vector((0.01, 0.005, 0.0065)), c, 20, 12))
        core.append(ch.geo.ellipsoid(Vector((0.0045, 0.0025, 0.0042)), c + Vector((-s * 0.001, -0.004, 0)), 12, 8))
        rig.marker("EyeL" if i == 0 else "EyeR", rig.head, c + Vector((0, 0.002, 0)))
    rig.headpart("Void_Sockets", ch.geo.merge(*voids), ch.void(), smooth=True, sharp_angle=None)
    rig.headpart("Glow_Eyes", ch.geo.merge(*glow), m["eye"], smooth=True, sharp_angle=None)
    rig.headpart("Glow_EyeCores", ch.geo.merge(*core), m["eyecore"], smooth=True, sharp_angle=None)


def mouth_line(rig, surf):
    """Schmale, dunkle Fuge zwischen den zusammengepressten Lippen."""
    bm = bmesh.new()
    cols = []
    for k in range(21):
        u = k / 20 * 2 - 1
        x = u * 0.044
        z = MOUTH_Z - 0.0015 - 0.009 * u * u
        h = 0.0012 + 0.0012 * (1 - u * u)
        cols.append([bm.verts.new(surf(x, z + dz, 0.0005)[0]) for dz in (h, 0.0, -h)])
    for k in range(20):
        for r in range(2):
            bm.faces.new((cols[k][r], cols[k + 1][r], cols[k + 1][r + 1], cols[k][r + 1]))
    rig.headpart("Void_Mouth", bm, ch.void(), smooth=True, sharp_angle=None)


def ears(rig, m):
    parts = []
    for s in (-1, 1):
        ear = ch.geo.ellipsoid(Vector((0.012, 0.03, 0.04)), Vector((0, 0, 0)), 20, 14)
        for v in ear.verts:
            if v.co.x * s > 0:
                v.co.x -= s * 0.006 * _g(v.co.y, 0.014) * _g(v.co.z, 0.02)
        M = Matrix.Translation(C + Vector((s * (RX + 0.012), 0.012, 0.0))) @ Matrix.Rotation(s * -0.4, 4, "Z")
        ch.geo.transform(ear, M)
        parts.append(ear)
    ob = rig.headpart("Ears", ch.geo.merge(*parts), m["face"], smooth=True, sharp_angle=None)
    hd.organic(ob, voxel=0.0016, smooth=2, faces=3000, uv_tile=0.1)


def stitches(rig, m, scars, name, parent, rnd, ridge=0.0035):
    """Genähte Narben: wulstige Narbe (Röhre) mit quer darübergelegten Fäden.
    scars: Liste von Listen (Punkt, Normale) auf der Oberfläche."""
    ridges, threads = [], []
    for pts in scars:
        path = []
        for (p0, n0), (p1, n1) in zip(pts, pts[1:]):
            for k in range(6):
                t = k / 6
                path.append((p0.lerp(p1, t), n0.lerp(n1, t).normalized()))
        path.append(pts[-1])
        ridges.append(ch.geo.tube([p + n * ridge * 0.2 for p, n in path], [ridge] * len(path), seg=8))
        for k in range(1, len(path) - 1, 2):
            p, n = path[k]
            tang = (path[k + 1][0] - path[k - 1][0]).normalized()
            side = tang.cross(n).normalized()
            L = ridge * rnd.uniform(2.6, 3.4)
            a = p - side * L + n * ridge * 0.3
            b = p + side * L + n * ridge * 0.3
            mid = p + n * ridge * 1.3
            threads.append(ch.geo.tube([a, mid, b], [ridge * 0.36] * 3, seg=6))
    scar = ch.geo.to_object(name, ch.geo.merge(*ridges), m["scar"], smooth=True, sharp_angle=None)
    scar.parent = parent
    th = ch.geo.to_object(name + "_Thread", ch.geo.merge(*threads), m["thread"], smooth=True, sharp_angle=None)
    th.parent = parent


def top_scar(rig, m, tree, rnd):
    """Naht quer über den Schädel (von der Stirnnarbe nach hinten)."""
    pts = []
    for k in range(9):
        d = Vector((0.0, -math.cos(math.radians(70 - k * 15)), math.sin(math.radians(70 - k * 15)))).normalized()
        hit = tree.ray_cast(C + d * 0.5, -d)
        if hit[0] is not None:
            pts.append((hit[0], hit[1]))
    if len(pts) > 2:
        stitches(rig, m, [pts], "Head_Stitches", rig.head, rnd)


# =====================================================================================
#  Körper (Torso-Koordinaten): nackt, massig
# =====================================================================================

PROFILE = [(0.33, -0.15), (0.34, 0.1), (0.35, 0.45), (0.37, 0.7), (0.38, 0.82), (0.37, 0.9),
           (0.33, 0.97), (0.26, 1.03), (0.19, 1.07), (0.14, 1.1)]
SX, SY = 1.55, 0.82


def _radius(z):
    if z <= PROFILE[0][1]:
        return PROFILE[0][0]
    for (r0, z0), (r1, z1) in zip(PROFILE, PROFILE[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            t = t * t * (3 - 2 * t)
            return r0 + (r1 - r0) * t
    return PROFILE[-1][0]


def body_point(th, z):
    r = _radius(z)
    x = r * SX * math.cos(th)
    y = r * SY * math.sin(th)
    front = max(0.0, -math.sin(th))
    # Brustmuskeln, Trapez, Schultern, Bauch
    pec = _g(abs(x) - 0.16, 0.09) * _g(z - 0.8, 0.07) * front
    y -= 0.04 * pec
    y += 0.02 * front * _g(x, 0.02) * _g(z - 0.8, 0.12)  # Brustbein-Rinne
    sh = _g(abs(x) - 0.44, 0.1) * _g(z - 0.92, 0.08)
    z += 0.06 * sh
    trap = _g(abs(x) - 0.17, 0.08) * _g(z - 1.02, 0.05)
    z += 0.04 * trap
    belly = _g(x, 0.16) * _g(z - 0.5, 0.15) * front
    y -= 0.03 * belly
    n = noise.noise(Vector((math.cos(th) * 3, math.sin(th) * 3, z * 3)))
    return Vector((x, y, z)) * 1.0 + Vector((math.cos(th), math.sin(th), 0)) * 0.008 * n


def build_body(rig, m, rnd):
    tb = rig.torso
    mb = hd.MeshBuilder()
    zs = [-0.15 + i * 0.0105 for i in range(120)] + [1.1, 1.11]
    seg = 112
    rows, uvs = [], []
    for z in zs:
        rows.append([body_point(j / seg * math.tau, z) for j in range(seg)])
        uvs.append([(j / seg * 3.0, z * 1.6) for j in range(seg)])
    mb.grid(rows, uvs, close=True)
    sample = mb.bm.copy()
    body = mb.finish("Body", m["skin"], parent=tb)
    for side in (-1, 1):
        rig.marker("Shoulder_L" if side < 0 else "Shoulder_R", tb, Vector((side * 0.44, 0.02, 0.96)))
    # dicker Nacken bis unter den Kopf
    neck = ch.geo.tube([Vector((0, 0.0, 0.96)), Vector((0, -0.01, 1.08)), Vector((0, -0.02, 1.2))],
                       [0.2, 0.18, 0.16], seg=32)
    rig.body("Body_Neck", neck, m["skin"], smooth=True, sharp_angle=None)

    btree = BVHTree.FromBMesh(sample)
    sample.free()

    def bsurf(x, z):
        hit = btree.ray_cast(Vector((x, -1.0, z)), Vector((0, 1, 0)))
        if hit[0] is None:
            return Vector((x, -0.3, z)), Vector((0, -1, 0))
        return hit[0], hit[1]

    # Narben auf Brust und Schultern (genäht)
    scars = []
    for k in range(16):
        x0 = rnd.choice((-1, 1)) * rnd.uniform(0.06, 0.42)
        z0 = rnd.uniform(0.66, 1.0)
        ang = rnd.uniform(-0.9, 0.9)
        L = rnd.uniform(0.08, 0.17)
        pts = []
        for i in range(5):
            t = i / 4 - 0.5
            pts.append(bsurf(x0 + math.cos(ang) * L * t, z0 + math.sin(ang) * L * t + 0.01 * math.sin(t * 6)))
        scars.append(pts)
    stitches(rig, m, scars, "Body_Stitches", tb, rnd, ridge=0.0065)
    collar(rig, m, rnd)


def collar(rig, m, rnd):
    """Schwerer Eisenring um den Hals, Nieten, seitliche Laschen, vorne Öse mit Kettenrest."""
    zc, R, H = 1.02, 0.31, 0.085
    ring = ch.geo.lathe([(R - 0.03, -H * 0.5), (R + 0.005, -H * 0.5), (R + 0.012, 0.0), (R + 0.005, H * 0.5),
                         (R - 0.03, H * 0.5), (R - 0.035, 0.0), (R - 0.03, -H * 0.5)], 64, 0.1)
    tilt = Matrix.Translation(Vector((0, 0.01, zc))) @ Matrix.Rotation(math.radians(-10), 4, "X")
    for v in ring.verts:
        v.co.y *= 0.82
        v.co += Vector((v.co.x, v.co.y, 0)).normalized() * 0.004 * noise.noise(v.co * 25)
    ch.geo.transform(ring, tilt)
    rig.body("Body_Collar", ring, m["iron"], smooth=True, sharp_angle=None)
    rivets = []
    for k in range(18):
        a = k / 18 * math.tau
        for dz in (-0.032, 0.032):
            p = Vector((math.cos(a) * (R + 0.011), math.sin(a) * (R + 0.011) * 0.82, dz))
            rv = ch.geo.ellipsoid(Vector((0.007, 0.007, 0.007)), p, 10, 6)
            ch.geo.transform(rv, tilt)
            rivets.append(rv)
    # Laschen seitlich (Scharnier) und vorne Öse mit Kettengliedern
    for s in (-1, 1):
        b = ch.geo.ellipsoid(Vector((0.02, 0.028, 0.06)), Vector((s * (R + 0.018), 0.0, 0.0)), 14, 10)
        ch.geo.transform(b, tilt)
        rivets.append(b)
    eye_c = Vector((0, -(R * 0.82 + 0.02), -0.06))
    links = [_link(eye_c, 0.022, 0.006, 0.0)]
    c = eye_c + Vector((0, 0, -0.04))
    for k in range(3):
        links.append(_link(c, 0.02, 0.0055, (k % 2) * math.pi / 2))
        c += Vector((0, -0.004, -0.034))
    for b in links:
        ch.geo.transform(b, tilt)
    rig.body("Body_CollarRivets", ch.geo.merge(*rivets), m["rust"], smooth=True, sharp_angle=None)
    rig.body("Body_Chain", ch.geo.merge(*links), m["iron"], smooth=True, sharp_angle=None)


def _link(c: Vector, r: float, t: float, rot: float):
    pts = []
    for k in range(25):
        a = k / 24 * math.tau
        pts.append(Vector((math.cos(a) * r * 0.6, 0, math.sin(a) * r)))
    bm = ch.geo.tube(pts, [t] * 25, seg=8, cap_start=False)
    ch.geo.transform(bm, Matrix.Translation(c) @ Matrix.Rotation(rot, 4, "Z"))
    return bm


# =====================================================================================
#  Arme und Hände
# =====================================================================================

def bare_limb(name, mat, r0, r1, seed=0, bulge=0.15):
    mb = hd.MeshBuilder()
    rows, uvs = [], []
    n_r, n_z = 40, 36
    for i in range(n_z + 1):
        t = i / n_z
        z = -0.5 + t
        r = (r0 + (r1 - r0) * t) * (1 + bulge * math.sin(math.pi * t) ** 2)
        row, uvr = [], []
        for j in range(n_r):
            a = j / n_r * math.tau
            lump = noise.noise(Vector((math.cos(a) * 1.5, math.sin(a) * 1.5, z * 3 + seed)))
            rr = r * (1 + 0.05 * lump)
            row.append(Vector((rr * math.cos(a), rr * math.sin(a), z)))
            uvr.append((j / n_r * 1.2, t * 0.6))
        rows.append(row)
        uvs.append(uvr)
    vs = mb.grid(rows, uvs, close=True)
    mb.bm.faces.new(list(reversed(vs[0])))
    mb.bm.faces.new(vs[-1])
    return mb.finish(name, mat)


HAND_KW = dict(size=1.26, thick=1.3, knobby=0.55, pitch=-0.45, wrist_back=0.07, wrist_up=0.0, roll=72.0)


def shackle(hand, side, m):
    """Eisenschelle ums Handgelenk, in denselben Hand-Koordinaten wie hd.grip_hand."""
    s = HAND_KW["size"]
    orient = Matrix.Translation(Vector((0, HAND_KW["wrist_back"], HAND_KW["wrist_up"]))) @ \
        Matrix.Rotation(math.radians(side * HAND_KW["roll"]), 4, "Y") @ Matrix.Rotation(HAND_KW["pitch"], 4, "X")
    R = 0.038 * s * HAND_KW["thick"] * 0.95
    band = ch.geo.lathe([(R, -0.016), (R + 0.008, -0.014), (R + 0.01, 0.0), (R + 0.008, 0.014), (R, 0.016),
                         (R - 0.002, 0.0), (R, -0.016)], 40, 0.1)
    ch.geo.transform(band, Matrix.Translation(Vector((0, 0.06 * s, 0.0))) @ Matrix.Rotation(math.pi / 2, 4, "X"))
    ch.geo.transform(band, orient)
    ob = ch.geo.to_object(hand.name + "_Shackle", band, m["iron"], smooth=True, sharp_angle=None)
    ob.parent = hand


def hands_and_arms(rig, m, rnd):
    hands = [hd.grip_hand(side, m["skin"], m["nail"], **HAND_KW) for side in (-1, 1)]
    for side, h in zip((-1, 1), hands):
        h.location = G(side * 0.11, 0.9, 0.22)
        shackle(h, side, m)
    upper = bare_limb("SleeveUpper", m["skin"], 0.12, 0.1, seed=1, bulge=0.18)
    fore = bare_limb("SleeveFore", m["skin"], 0.1, 0.075, seed=2, bulge=0.14)
    hd.preview_arms(upper, fore, hands[0], hands[1])


# =====================================================================================

def scale_head(rig, s):
    for ob in rig.head.children:
        ob.location = C + (Vector(ob.location) - C) * s
        if ob.type == "MESH":
            ob.data.transform(Matrix.Scale(s, 4))


def build(steps=("head", "body", "hands"), seed=51):
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
        hands_and_arms(rig, m, rnd)
    return rig
