"""Der Bandit in HD (nach dem Konzeptbild „Am Spieltisch“, Feld 1):
Pelzmütze (Uschanka) mit Ohrenklappen und hochgeklappter Stirnklappe aus echten Fellbüscheln,
wettergegerbtes Gesicht mit schwerer Stirn, buschigen, zornigen Brauen und großer Nase,
rotes Tuch über Mund und Kinn, abgewetzter brauner Ledermantel mit breitem Revers,
helles Hemd darunter, große raue Hände.

    import hd_bandit; hd_bandit.build()
    hd_bandit.build(steps=("head",))    # nur Teile
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

import characters as ch
import hd
from geo import G

C = Vector((0, 0, 0.1))  # Schädelmitte (Head-Koordinaten)
HEAD_Y = 1.2
HEAD_SCALE = 1.4


# =====================================================================================
#  Materialien
# =====================================================================================

def materials():
    m = {}
    c, n = hd.tex_skin("skin", (0.52, 0.35, 0.25), seed=61, pores=1.1, blotch=0.8)
    m["skin"] = hd.material("Bandit_Haut", c, n, rough=0.55, normal_strength=1.1, spec=0.4)
    c, n = hd.tex_skin("hands", (0.34, 0.225, 0.16), seed=62, pores=1.0, blotch=1.3)
    m["hands"] = hd.material("Bandit_Haende", c, n, rough=0.72, normal_strength=1.0, spec=0.25)
    c, n = hd.tex_fur("fur", (0.06, 0.04, 0.025), (0.36, 0.27, 0.18), seed=81)
    m["fur"] = hd.material("Bandit_Fell", c, n, rough=0.85, normal_strength=0.6, double_sided=True, spec=0.2)
    c, n = hd.tex_cloth("furbase", (0.2, 0.14, 0.09), (0.05, 0.035, 0.022), size=512, seed=82, weave=140, rag=0.1)
    m["furbase"] = hd.material("Bandit_Fellgrund", c, n, rough=0.95, normal_strength=1.2, spec=0.15)
    c, n = hd.tex_fur("brow", (0.03, 0.022, 0.016), (0.1, 0.075, 0.055), w=64, h=128, seed=83)
    m["brow"] = hd.material("Bandit_Braue", c, n, rough=0.8, double_sided=True, spec=0.2)
    c, n = hd.tex_cloth("scarf", (0.5, 0.075, 0.055), (0.16, 0.02, 0.015), seed=84, weave=110, rag=0.55)
    m["scarf"] = hd.material("Bandit_Tuch", c, n, rough=0.9, normal_strength=0.9, double_sided=True, spec=0.2)
    c, n = hd.tex_leather("coat", (0.34, 0.21, 0.115), (0.1, 0.06, 0.032), seed=71, crease=1.3, wear=0.45)
    m["coat"] = hd.material("Bandit_Mantel", c, n, rough=0.62, normal_strength=1.0, double_sided=True, spec=0.35)
    c, n = hd.tex_cloth("shirt", (0.62, 0.55, 0.42), (0.25, 0.2, 0.13), seed=85, rag=0.4)
    m["shirt"] = hd.material("Bandit_Hemd", c, n, rough=0.92, spec=0.2)
    m["eyewhite"] = hd.material("Bandit_Augenweiss", color=(0.62, 0.56, 0.46, 1), rough=0.15, spec=0.8)
    m["iris"] = hd.material("Bandit_Iris", color=(0.12, 0.07, 0.035, 1), rough=0.1, spec=0.9)
    m["pupil"] = hd.material("Bandit_Pupille", color=(0.005, 0.004, 0.004, 1), rough=0.05, spec=1.0)
    m["nail"] = hd.material("Bandit_Nagel", color=(0.3, 0.24, 0.17, 1), rough=0.6, spec=0.2)
    m["brass"] = hd.material("Bandit_Messing", color=(0.42, 0.3, 0.12, 1), rough=0.38, metal=0.85)
    m["thread"] = hd.material("Bandit_Faden", color=(0.12, 0.1, 0.07, 1), rough=0.9)
    return m


# =====================================================================================
#  Kopf (Head-Koordinaten, vorne = -Y)
# =====================================================================================

RX, RY, RZ = 0.132, 0.145, 0.168
EYES = [(-0.05, 0.022), (0.05, 0.022)]


def _g(a, s):
    return math.exp(-(a * a) / (2 * s * s))


def face_shape(c: Vector, d: Vector) -> Vector:
    """Verformt die Kopfkugel zu einem kantigen Männergesicht (c = Punkt relativ zur Mitte)."""
    x, z = c.x, c.z
    front = max(0.0, -d.y)
    off = Vector()
    # Kiefer breiter, Schädel oben etwas schmaler
    off.x += c.x * (0.12 * max(0.0, -z) / RZ - 0.06 * max(0.0, z) / RZ)
    # Stirnwulst, zur Mitte hin abgesenkt (zorniger Blick)
    brow_z = 0.05 - 0.016 * _g(x, 0.03)
    off.y -= 0.03 * front ** 2 * _g(z - brow_z, 0.016) * _g(abs(x) - 0.045, 0.045)
    # Zornesfalte zwischen den Brauen
    off.y += 0.006 * front * _g(x, 0.006) * _g(z - 0.04, 0.012)
    # Augenhöhlen
    for ex, ez in EYES:
        off.y += 0.036 * front * _g(x - ex, 0.021) * _g(z - ez, 0.017)
    # Nase: Rücken von der Stirn bis zur dicken Spitze
    if front > 0.2:
        t = min(1.0, max(0.0, (0.035 - z) / 0.085))  # 0 = Nasenwurzel, 1 = Spitze
        top = 1.0 if z < 0.04 else _g(z - 0.04, 0.012)
        amp = (0.014 + 0.055 * t ** 1.3) * top
        if z < -0.05:
            amp *= _g(z + 0.05, 0.012)
        width = 0.013 + 0.014 * t ** 2
        off.y -= amp * _g(x, width) * front
        # Nasenflügel
        for s in (-1, 1):
            off.y -= 0.016 * front * _g(x - s * 0.024, 0.01) * _g(z + 0.04, 0.012)
    # Wangenknochen und Tränensäcke
    for s in (-1, 1):
        off += Vector((s * 0.008, -0.012 * front, 0)) * _g(x - s * 0.072, 0.025) * _g(z + 0.012, 0.022)
        off.y -= 0.006 * front * _g(x - s * 0.05, 0.018) * _g(z + 0.004, 0.006)
    # Schläfen leicht eingezogen
    for s in (-1, 1):
        off.x -= s * 0.008 * _g(x - s * RX, 0.03) * _g(z - 0.06, 0.03)
    return c + off


def build_head(rig, m, rnd):
    head = ch.Head((RX, RY, RZ), u=96, v=64)
    head.deform(face_shape)
    ch.eye_sockets(rig, head, EYES, size=(0.022, 0.012, 0.014), slant=0.2, inset=0.006)
    eyeballs(rig, m)
    face = rig.headpart("Face", head.bm.copy(), m["skin"], smooth=True, sharp_angle=None)
    tree = BVHTree.FromBMesh(head.bm)

    def surf(x, z, lift=0.0):
        """Punkt auf der Gesichtsvorderseite (Strahl von vorne)."""
        hit = tree.ray_cast(C + Vector((x, -0.5, z)), Vector((0, 1, 0)))
        if hit[0] is None:
            return C + Vector((x, -RY, z)), Vector((0, -1, 0))
        return hit[0] + hit[1] * lift, hit[1]

    lids(rig, m, surf)
    brows(rig, m, surf, rnd)
    scarf(rig, m, tree, rnd)
    hat(rig, m, rnd)
    return face


def eyeballs(rig, m):
    """Echte Augen (Augapfel, Iris, Pupille) an den Augen-Markern – der Bandit glüht nicht."""
    whites, irises, pupils = [], [], []
    look = Vector((0, -1, 0.18)).normalized()  # leicht nach oben: Blick über den Tisch zum Spieler
    for mk in [o for o in rig.head.children if o.type == "EMPTY" and o.name.startswith("Eye")]:
        c = Vector(mk.location) + Vector((0, 0.012, 0.001))
        whites.append(ch.geo.ellipsoid(Vector((0.0135, 0.0125, 0.0115)), c, 20, 14))
        rot = Vector((0, -1, 0)).rotation_difference(look).to_matrix().to_4x4()
        iris = ch.geo.ellipsoid(Vector((0.0068, 0.0018, 0.0068)), Vector((0, 0, 0)), 16, 8)
        ch.geo.transform(iris, Matrix.Translation(c + look * 0.0118) @ rot)
        irises.append(iris)
        pup = ch.geo.ellipsoid(Vector((0.003, 0.0012, 0.003)), Vector((0, 0, 0)), 12, 6)
        ch.geo.transform(pup, Matrix.Translation(c + look * 0.0133) @ rot)
        pupils.append(pup)
    rig.headpart("Augapfel", ch.geo.merge(*whites), m["eyewhite"], smooth=True, sharp_angle=None)
    rig.headpart("Augapfel_Iris", ch.geo.merge(*irises), m["iris"], smooth=True, sharp_angle=None)
    rig.headpart("Augapfel_Pupille", ch.geo.merge(*pupils), m["pupil"], smooth=True, sharp_angle=None)


def lids(rig, m, surf):
    """Schwere Oberlider und Tränensäcke als Wülste um die Augenhöhlen."""
    parts = []
    for ex, ez in EYES:
        side = 1 if ex > 0 else -1
        up = []
        for k in range(9):
            t = k / 8
            x = ex + (t - 0.5) * 0.05
            z = ez + 0.012 - 0.012 * (2 * t - 1) ** 2 - side * 0.004 * (t - 0.5)
            up.append(surf(x, z, 0.002)[0])
        parts.append(ch.geo.tube(up, [0.003, 0.006, 0.008, 0.009, 0.009, 0.009, 0.008, 0.006, 0.003], seg=10))
        low = []
        for k in range(7):
            t = k / 6
            x = ex + (t - 0.5) * 0.042
            z = ez - 0.013 + 0.006 * (2 * t - 1) ** 2
            low.append(surf(x, z, 0.001)[0])
        parts.append(ch.geo.tube(low, [0.002, 0.004, 0.005, 0.005, 0.005, 0.004, 0.002], seg=8))
    rig.headpart("Face_Lids", ch.geo.merge(*parts), m["skin"], smooth=True, sharp_angle=None)


def brows(rig, m, surf, rnd):
    """Buschige Brauen aus vielen Haarbüscheln, innen nach unten gezogen."""
    mb = hd.MeshBuilder()
    for ex, ez in EYES:
        side = 1 if ex > 0 else -1
        for k in range(70):
            t = rnd.random()
            x = ex + side * (t - 0.45) * 0.06
            z = ez + 0.03 - 0.012 * (1 - t) + 0.004 * math.sin(t * 3) + rnd.uniform(-0.004, 0.004)
            p, n = surf(x, z, -0.001)
            direction = Vector((side * 1.0, 0, 0.25 - 0.6 * (1 - t)))
            L = rnd.uniform(0.012, 0.022)
            hd.add_feather(mb, p, n, direction, L, L * 0.35, lift=rnd.uniform(0.2, 0.5), curl=0.1, cup=0.1,
                           twist=rnd.uniform(-0.4, 0.4), along=4, across=3)
    rig_ob = mb.finish("Face_Brows", m["brow"], parent=rig.head)
    return rig_ob


def scarf(rig, m, tree, rnd):
    """Rotes Tuch: liegt ab knapp unter der Nase eng um Mund und Kinn, fällt in den Kragen."""
    mb = hd.MeshBuilder()
    seg = 72
    rows, uvs = [], []
    zs = [-0.36 + i * 0.009 for i in range(36)]  # unter dem Kinn bis Halsansatz
    top_front, top_side = -0.074, -0.025
    n_rows = 34
    for i in range(n_rows + 1):
        t = i / n_rows
        row, uvr = [], []
        for j in range(seg):
            th = j / seg * math.tau
            dirv = Vector((math.cos(th), math.sin(th), 0))
            front = max(0.0, -dirv.y)
            z_top = top_side + (top_front - top_side) * front ** 1.5
            z_top += 0.025 * max(0.0, dirv.y)  # hinten höher (Knoten)
            z = -0.22 + (z_top + 0.22) * t
            if z > -0.15:
                hit = tree.ray_cast(C + Vector((0, 0, z)) + dirv * 0.4, -dirv)
                r = (hit[0] - C - Vector((0, 0, z))).length if hit[0] is not None else 0.12
            else:
                r = 0.105
            # unter dem Kinn nicht zu tief in den Hals, Übergang weich
            # unten bauscht sich das Tuch über Kragen und Schultern
            r_neck = 0.112 + 0.012 * min(1.0, max(0.0, (-0.17 - z) / 0.08)) + 0.006 * math.sin(th * 3)
            k = min(1.0, max(0.0, (z + 0.15) / 0.06))
            r = r_neck * (1 - k) + r * k
            warp = 1.6 * noise.noise(Vector((math.cos(th) * 2, math.sin(th) * 2, z * 3)))
            fold = 0.011 * math.sin(z * 55 + warp + th * 0.6) + 0.004 * math.sin(z * 140 + warp * 2)
            bulge = 0.012 * front * _g(z + 0.12, 0.05)  # Stoff wölbt sich über Mund und Kinn
            rr = r + 0.009 + fold + bulge + 0.003 * t
            row.append(C + Vector((0, 0, z)) + dirv * rr)
            uvr.append((j / seg * 3.0, t * 1.6))
        rows.append(row)
        uvs.append(uvr)
    mb.grid(rows, uvs, close=True)
    # Saum oben: leicht umgeschlagener Wulst
    hem = [r for r in rows[-1]]
    ob = mb.finish("Scarf", m["scarf"], parent=rig.head)
    mod = ob.modifiers.new("Dicke", "SOLIDIFY")
    mod.thickness = 0.006
    mod.offset = 1.0
    hb = ch.geo.tube(hem + [hem[0]], [0.007] * (len(hem) + 1), seg=8, cap_start=False)
    rig.headpart("Scarf_Hem", hb, m["scarf"], smooth=True, sharp_angle=None)


def _ellipse_ring(cx, cy, cz, rx, ry, n):
    return [Vector((cx + rx * math.cos(a), cy + ry * math.sin(a), cz)) for a in (k / n * math.tau for k in range(n))]


def hat(rig, m, rnd):
    """Uschanka: Lederkappe, Fellband rundum, Ohrenklappen, hochgeklappte Stirnklappe; Fell aus Büscheln."""
    base_parts = []
    hc = C + Vector((0, 0.012, 0.0))
    # Kappe (Krone)
    crown = ch.geo.ellipsoid(Vector((RX + 0.03, RY + 0.03, 0.15)), hc + Vector((0, 0, 0.105)), 48, 28)
    kill = [f for f in crown.faces if (f.calc_center_median() - hc).z < 0.1]
    bmesh.ops.delete(crown, geom=kill, context="FACES")
    for v in crown.verts:
        k = v.co - hc
        v.co.z += 0.012 * noise.noise(Vector((k.x * 12, k.y * 12, 0.5)))
    base_parts.append(crown)
    # Fellband rundum
    band_z = 0.115
    ring = []
    for k in range(64):
        a = k / 64 * math.tau
        ring.append(hc + Vector(((RX + 0.035) * math.cos(a), (RY + 0.035) * math.sin(a), band_z)))
    band = ch.geo.tube(ring + [ring[0]], [0.044] * 65, seg=16, cap_start=False)
    base_parts.append(band)
    # Ohrenklappen
    for s in (-1, 1):
        flap = bmesh.new()
        rows = []
        for i in range(10):
            t = i / 9
            z = band_z - 0.02 - t * 0.19
            row = []
            for j in range(7):
                u = j / 6 - 0.5
                y = u * 0.15 * (1 - 0.2 * t) + 0.01
                x = s * (RX + 0.04 + 0.025 * t + 0.025 * (1 - 4 * u * u))
                row.append(flap.verts.new(hc + Vector((x, y, z))))
            rows.append(row)
        for i in range(9):
            for j in range(6):
                flap.faces.new((rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]))
        bmesh.ops.solidify(flap, geom=flap.faces[:], thickness=0.05)
        base_parts.append(flap)
    # Stirnklappe hochgeklappt
    front = bmesh.new()
    rows = []
    for i in range(8):
        t = i / 7
        row = []
        for j in range(13):
            u = j / 12 - 0.5
            x = u * (0.25 - 0.03 * t)
            y = -(RY + 0.06) + 0.035 * t + 0.03 * (u * 2) ** 2
            z = band_z + 0.02 + t * 0.1
            row.append(front.verts.new(hc + Vector((x, y, z))))
        rows.append(row)
    for i in range(7):
        for j in range(12):
            front.faces.new((rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]))
    bmesh.ops.solidify(front, geom=front.faces[:], thickness=0.035)
    base_parts.append(front)
    base = ch.geo.merge(*base_parts)
    ch.geo.box_uv(base, 0.2)
    sample_bm = base.copy()
    base_ob = rig.headpart("Hat", base, m["furbase"], smooth=True, sharp_angle=None)

    # Fellbüschel
    mb = hd.MeshBuilder()
    pts = hd.sample_surface(sample_bm, 11000, rnd)
    sample_bm.free()
    for p, nrm in pts:
        k = p - hc
        if k.z > 0.24 and abs(nrm.z) > 0.8:
            L = rnd.uniform(0.016, 0.026)  # oben kürzer
        else:
            L = rnd.uniform(0.024, 0.042)
        direction = nrm * 0.35 + Vector((rnd.uniform(-0.4, 0.4), rnd.uniform(-0.4, 0.4), -1.0))
        hd.add_feather(mb, p - nrm * 0.004, nrm, direction, L, L * rnd.uniform(0.3, 0.45),
                       lift=rnd.uniform(0.15, 0.4), curl=rnd.uniform(0.05, 0.2), cup=0.2,
                       twist=rnd.uniform(-0.6, 0.6), along=4, across=3, shape=1.4)
    fur = mb.finish("Hat_Fur", m["fur"], parent=rig.head)
    hd.shade_like(fur, base_ob, 0.65)


# =====================================================================================
#  Körper (Torso-Koordinaten)
# =====================================================================================

PROFILE = [(0.25, -0.15), (0.27, 0.1), (0.278, 0.45), (0.29, 0.72), (0.29, 0.82), (0.275, 0.9),
           (0.245, 0.96), (0.19, 1.02), (0.13, 1.06), (0.07, 1.085), (0.03, 1.09)]
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
        amp = 0.01 * min(1.0, max(0.0, (0.95 - z) / 0.5)) + 0.002
        fold = amp * (0.7 * math.sin(th * 9 + warp) + 0.3 * math.sin(th * 19 + warp * 2))
    rr = r + fold + out
    x = rr * SX * math.cos(th)
    y = rr * SY * math.sin(th)
    if z > 0.72:
        t = min(1.0, (z - 0.72) / 0.4)
        y -= HUNCH * t * max(0.0, 1 - abs(x) / 0.5)
    bump = math.exp(-((abs(x) - 0.33) ** 2) / (2 * 0.075 ** 2)) * math.exp(-((z - 0.98) ** 2) / (2 * 0.07 ** 2))
    return Vector((x, y, z + 0.025 * bump))


def front_point(x, z, out=0.0):
    """Punkt vorne auf dem (faltenlosen) Mantel an Stelle x, z."""
    r = _radius(z) + out
    cx = max(-0.999, min(0.999, x / (r * SX)))
    th = -math.acos(cx)  # Vorderseite: sin(th) < 0
    return body_point(th, z, out, folds=False)


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
    mb.finish("Body", m["coat"], parent=tb)

    # Schultergelenke für die Arme (in Godot: opponent_figure.gd → _update_arms)
    for side in (-1, 1):
        rig.marker("Shoulder_L" if side < 0 else "Shoulder_R", tb, Vector((side * 0.335, 0.02, 0.95)))

    # Hemd im V-Ausschnitt
    sh = hd.MeshBuilder()
    rows, uvs = [], []
    for i in range(14):
        z = 0.6 + i * 0.035
        w = 0.02 + (z - 0.6) * 0.17
        rows.append([front_point(x, z, 0.004) for x in (-w, -w * 0.5, 0.0, w * 0.5, w)])
        uvs.append([(u, z * 2) for u in (0, 0.25, 0.5, 0.75, 1.0)])
    sh.grid(rows, uvs)
    sh.finish("Body_Shirt", m["shirt"], parent=tb)

    # Revers (rechts, gespiegelt links) – liegt auf der Brust, Außenkante leicht aufgestellt
    inner = [(0.03, 1.06), (0.04, 0.95), (0.034, 0.8), (0.018, 0.63)]
    outer = [(0.17, 1.03), (0.215, 0.93), (0.16, 0.8), (0.03, 0.62)]
    for s in (-1, 1):
        lp = hd.MeshBuilder()
        rows, uvs = [], []
        n_v, n_u = 16, 7
        for i in range(n_v):
            t = i / (n_v - 1)
            a = _lerp_poly(inner, t)
            b = _lerp_poly(outer, t)
            row, uvr = [], []
            for j in range(n_u):
                u = j / (n_u - 1)
                x = a[0] + (b[0] - a[0]) * u
                z = a[1] + (b[1] - a[1]) * u
                lift = 0.014 + 0.03 * u ** 2 + 0.01 * math.sin(t * math.pi)
                row.append(front_point(s * x, z, lift))
                uvr.append((u * 0.4, t * 1.2))
            if s < 0:
                row.reverse()
                uvr.reverse()
            rows.append(row)
            uvs.append(uvr)
        lp.grid(rows, uvs)
        ob = lp.finish("Body_Lapel" + ("L" if s < 0 else "R"), m["coat"], parent=tb)
        mod = ob.modifiers.new("Dicke", "SOLIDIFY")
        mod.thickness = 0.008
        mod.offset = -1.0
        # Steppnaht entlang der Außenkante
        seam = [front_point(s * (_lerp_poly(outer, k / 20)[0] - 0.012), _lerp_poly(outer, k / 20)[1],
                            0.014 + 0.03 * 0.85 + 0.003) for k in range(21)]
        rig.body("Body_Seam" + ("L" if s < 0 else "R"), ch.geo.tube(seam, [0.0016] * 21, seg=6), m["thread"])

    # Aufgestellter Kragen hinten und seitlich um den Hals (verdeckt, wo das Tuch hineingeht)
    col = hd.MeshBuilder()
    rows, uvs = [], []
    for i in range(8):
        t = i / 7
        z = 1.0 + t * 0.13
        row, uvr = [], []
        for j in range(33):
            th = math.radians(-25 + j * (230 / 32))  # hinten herum, vorne offen
            r = 0.15 + 0.035 * t
            row.append(Vector((r * 1.12 * math.cos(th), 0.035 + r * 0.95 * math.sin(th) - 0.03 * t * max(0.0, -math.sin(th) + 0.3), z)))
            uvr.append((j / 32 * 2, t))
        rows.append(row)
        uvs.append(uvr)
    col.grid(rows, uvs)
    co = col.finish("Body_Collar", m["coat"], parent=tb)
    mod = co.modifiers.new("Dicke", "SOLIDIFY")
    mod.thickness = 0.014

    # Knöpfe (zweireihig)
    btn = []
    for z in (0.56, 0.46):
        for s in (-1, 1):
            p = front_point(s * 0.07, z, 0.006)
            b = ch.geo.lathe([(0.0, 0.0), (0.016, 0.0), (0.017, 0.004), (0.012, 0.008), (0.0, 0.009)], 20, 0.1)
            ch.geo.transform(b, Matrix.Translation(p) @ Matrix.Rotation(math.pi / 2, 4, "X"))
            btn.append(b)
    rig.body("Body_Buttons", ch.geo.merge(*btn), m["brass"], smooth=True, sharp_angle=None)

    # Flicken auf der linken Schulter
    patch = hd.MeshBuilder()
    rows, uvs = [], []
    for i in range(6):
        z = 0.82 + i * 0.022
        rows.append([front_point(x, z, 0.003) for x in (-0.26, -0.235, -0.21, -0.185, -0.16)])
        uvs.append([(u, i / 5) for u in (0, 0.25, 0.5, 0.75, 1.0)])
    patch.grid(rows, uvs)
    patch.finish("Body_Patch", m["furbase"], parent=tb)


def _lerp_poly(pts, t):
    t = max(0.0, min(1.0, t)) * (len(pts) - 1)
    i = min(int(t), len(pts) - 2)
    f = t - i
    a, b = pts[i], pts[i + 1]
    return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)


def hands_and_sleeve(rig, m, rnd):
    """Greifende Hände + Arme aus Ober- und Unterarm (Godot knickt sie per IK am Ellbogen)."""
    hands = [hd.grip_hand(side, m["hands"], m["nail"], size=1.12, thick=1.12, knobby=0.4, pitch=-0.45,
                          wrist_back=0.06, wrist_up=0.0) for side in (-1, 1)]
    for side, h in zip((-1, 1), hands):
        h.location = G(side * 0.085, 0.9, 0.22)  # Ruhelage: beide Hände halten den Fächer unten
    upper = hd.sleeve_segment("SleeveUpper", m["coat"], 0.088, 0.074, folds=1.0, bunch_end=1.0, seed=1)
    fore = hd.sleeve_segment("SleeveFore", m["coat"], 0.076, 0.064, cuff=0.016, folds=0.8, seed=2)
    hd.preview_arms(upper, fore, hands[0], hands[1])


# =====================================================================================

def scale_head(rig, s):
    """Kopf als Ganzes vergrößern (um die Schädelmitte), Augen-Marker mit."""
    for ob in rig.head.children:
        ob.location = C + (Vector(ob.location) - C) * s
        if ob.type == "MESH":
            ob.data.transform(Matrix.Scale(s, 4))


def build(steps=("head", "body", "hands"), seed=11):
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
