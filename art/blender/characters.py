"""Die acht Gegner aus dem Konzept „Gegner-Konzept“ als Blender-Modelle.

Jeder Charakter wird in eine eigene .blend gebaut (art/blender/opponents/<id>.blend)
und als assets/models/opponents/<id>.glb exportiert. Alle folgen derselben Struktur,
damit Godot (opponent_figure.gd) sie gleich zusammensetzen und animieren kann:

    Torso (Empty)        – Oberkörper, alle Kinder bewegen sich mit (Atmen, Vorbeugen)
      Head (Empty)       – Kopf, alle Kinder drehen sich mit
        EyeL, EyeR       – Marker für glühende Augen (optional EyeX1…)
        Jaw              – (optional) Unterkiefer, dreht sich beim Lachen
    Hand_L, Hand_R       – Hände (Ursprung = Handgelenk, Finger zeigen zum Spieler)
    Sleeve               – Ärmel, Länge 1 entlang lokal Z (Blender), +0.5 = Handgelenk
    Props (Empty)        – (optional) Dinge auf dem Tisch, z. B. die Laterne der Hexe
      PropLight          – Marker für ein Licht

Objekte, deren Name mit „Void“ beginnt (Augenhöhlen, Mäuler), zeigt Godot pechschwarz.
Koordinaten: geo.G(x, y, z) rechnet Godot → Blender um. Kopf-Koordinaten: Schädelmitte
bei Blender (0, 0, 0.1), vorne = -Y.
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

import geo
from geo import G

HEAD_CENTER = Vector((0, 0, 0.1))


# =====================================================================================
#  Bausteine
# =====================================================================================

class Rig:
    """Legt die Grundstruktur (Torso, Head) an und hängt Teile ein."""

    def __init__(self, head_y: float = 1.33) -> None:
        self.torso = self.empty("Torso", None, G(0, 0.02, -0.34))
        self.head = self.empty("Head", self.torso, G(0, head_y, 0.03))
        self.props = None

    @staticmethod
    def empty(name, parent, loc):
        e = bpy.data.objects.new(name, None)
        e.empty_display_size = 0.04
        bpy.context.scene.collection.objects.link(e)
        e.parent = parent
        e.location = loc
        return e

    def body(self, name, bm, mat, **kw):
        ob = geo.to_object(name, bm, mat, **kw)
        ob.parent = self.torso
        return ob

    def headpart(self, name, bm, mat, **kw):
        ob = geo.to_object(name, bm, mat, **kw)
        ob.parent = self.head
        return ob

    def prop(self, name, bm, mat, **kw):
        if self.props is None:
            self.props = self.empty("Props", None, (0, 0, 0))
        ob = geo.to_object(name, bm, mat, **kw)
        ob.parent = self.props
        return ob

    def marker(self, name, parent, loc):
        return self.empty(name, parent, loc)


def mat(name, tex=None, color=(1, 1, 1, 1), rough=0.85, metal=0.0, **kw):
    return geo.material(name, tex, color=color, rough=rough, metal=metal, **kw)


def void():
    return mat("Leere", color=(0.01, 0.005, 0.008, 1), rough=1.0)


# --- Körper -----------------------------------------------------------------------

def robe(profile=None, sx=1.5, sy=0.78, hunch=0.05, shoulder_bump=0.03, tile=0.3):
    """Rumpf als Drehkörper (Torso-Koordinaten), elliptisch gestaucht, leicht gebeugt."""
    profile = profile or [(0.25, -0.15), (0.27, 0.1), (0.275, 0.45), (0.285, 0.75), (0.29, 0.9), (0.27, 0.99),
                          (0.2, 1.06), (0.12, 1.11), (0.08, 1.15), (0.07, 1.2)]
    bm = geo.lathe(profile, 40, tile)
    bmesh.ops.scale(bm, vec=Vector((sx, sy, 1.0)), verts=bm.verts)
    for v in bm.verts:
        ax = abs(v.co.x)
        if v.co.z > 0.75:
            t = min(1.0, (v.co.z - 0.75) / 0.35)
            v.co.y -= hunch * t * (1 - ax / 0.5)
        bump = math.exp(-((ax - 0.32) ** 2) / (2 * 0.07 ** 2)) * math.exp(-((v.co.z - 1.0) ** 2) / (2 * 0.07 ** 2))
        v.co.z += shoulder_bump * bump
    geo.box_uv(bm, tile)
    return bm


def body_front(profile, sx, sy, x, z):
    """Vorderseite (Blender-Y) des Rumpfs an Stelle x, z (für Gurte, Schmuck …)."""
    for (r0, z0), (r1, z1) in zip(profile, profile[1:]):
        if z0 <= z <= z1:
            r = r0 + (r1 - r0) * (z - z0) / max(z1 - z0, 1e-6)
            break
    else:
        r = profile[-1][0]
    rx, ry = r * sx, r * sy
    k = max(0.0, 1 - (x / rx) ** 2) if rx > 0 else 0.0
    return -math.sqrt(k) * ry


DEFAULT_PROFILE = [(0.25, -0.15), (0.27, 0.1), (0.275, 0.45), (0.285, 0.75), (0.29, 0.9), (0.27, 0.99),
                   (0.2, 1.06), (0.12, 1.11), (0.08, 1.15), (0.07, 1.2)]


def cape(profile=None, sx=1.5, sy=0.78, hunch=0.05, shoulder_bump=0.03, z_bottom=0.75, offset=0.025,
         teeth=11, jag=0.08, drip=0.0, seed=0, open_front=0.0, tile=0.3, flare=0.04):
    """Umhang/Kragen, der eng über den Schultern liegt (folgt dem Rumpfprofil) und
    unten gezackt ausfranst. open_front = Öffnung vorne (Bogenmaß)."""
    profile = profile or DEFAULT_PROFILE
    rnd = random.Random(seed)
    sub = []
    for (r0, z0), (r1, z1) in zip(profile, profile[1:]):
        if z1 < z_bottom:
            continue
        if z0 < z_bottom <= z1:
            r0 = r0 + (r1 - r0) * (z_bottom - z0) / (z1 - z0)
            z0 = z_bottom
        if not sub:
            sub.append((r0, z0))
        sub.append((r1, z1))
    top_z = sub[-1][1]
    prof = []
    for r, z in sub:
        t = (z - z_bottom) / max(top_z - z_bottom, 1e-6)
        prof.append((r + offset + flare * (1 - t) ** 2, z))
    prof.append((prof[-1][0] + 0.012, top_z + 0.04))  # Kragen oben leicht abstehend
    angle = math.tau - open_front
    bm = geo.lathe(prof, 56, tile, angle=angle)
    if open_front > 0:
        geo.transform(bm, Matrix.Rotation(-math.pi / 2 + open_front / 2, 4, "Z"))
    bmesh.ops.scale(bm, vec=Vector((sx, sy, 1.0)), verts=bm.verts)
    offsets = [rnd.uniform(0.5, 1.5) for _ in range(teeth * 4)]
    for v in bm.verts:
        ax = abs(v.co.x)
        if v.co.z > 0.75:
            t = min(1.0, (v.co.z - 0.75) / 0.35)
            v.co.y -= hunch * t * (1 - ax / 0.5)
        bump = math.exp(-((ax - 0.32) ** 2) / (2 * 0.07 ** 2)) * math.exp(-((v.co.z - 1.0) ** 2) / (2 * 0.07 ** 2))
        v.co.z += shoulder_bump * bump
        if v.co.z < z_bottom + 0.005:
            ang = math.atan2(v.co.y, v.co.x)
            u = (ang / math.tau + 0.5) * teeth
            saw = abs((u % 1.0) - 0.5) * 2
            idx = int(u * 4) % len(offsets)
            v.co.z -= jag * (1 - saw) * offsets[idx] + drip * offsets[idx] * (1 - saw) ** 3
    geo.box_uv(bm, tile)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def neck(rig, material, r=0.05, ridges=0.0, tile=0.15):
    """Hals vom Rumpf in den Kopf (Torso-Koordinaten)."""
    prof = []
    for k in range(13):
        t = k / 12
        rr = r * (1.15 - 0.25 * t) + ridges * abs(math.sin(t * math.pi * 5))
        prof.append((rr, 1.02 + t * 0.38))
    bm = geo.lathe(prof, 18, tile)
    geo.translate(bm, Vector((0, -0.04, 0)))
    return rig.body("Neck", bm, material, smooth=True, sharp_angle=None)


def strip_on_body(profile, sx, sy, a, b, width=0.05, lift=0.012, steps=16):
    """Flaches Band (Gurt) quer über die Vorderseite des Rumpfs von a=(x,z) nach b=(x,z)."""
    bm = bmesh.new()
    rows = []
    d = Vector((b[0] - a[0], b[1] - a[1])).normalized()
    perp = Vector((-d.y, d.x)) * width * 0.5
    for i in range(steps + 1):
        t = i / steps
        x = a[0] + (b[0] - a[0]) * t
        z = a[1] + (b[1] - a[1]) * t
        row = []
        for s in (-1, 1):
            px, pz = x + perp.x * s, z + perp.y * s
            row.append(bm.verts.new((px, body_front(profile, sx, sy, px, pz) - lift, pz)))
        rows.append(row)
    for i in range(steps):
        bm.faces.new((rows[i][0], rows[i + 1][0], rows[i + 1][1], rows[i][1]))
    geo.box_uv(bm, 0.15)
    return bm


def sleeve(r_top=0.07, r_mid=0.064, r_cuff=0.074, ragged=0.0, seed=0):
    """Ärmel: Länge 1 entlang Z (-0.5 … +0.5), +0.5 = Handgelenk, mit Deckel innen."""
    bm = geo.lathe([(0.0, -0.5), (r_top, -0.5), (r_top * 0.97, -0.2), (r_mid, 0.25), (r_mid * 0.95, 0.41),
                    (r_cuff, 0.44), (r_cuff * 1.06, 0.5), (r_mid * 0.75, 0.47), (0.0, 0.47)], 28, 0.25)
    rnd = random.Random(seed)
    phase = rnd.uniform(0, 6)
    for v in bm.verts:
        if v.co.z > 0.49 and math.hypot(v.co.x, v.co.y) > r_cuff:
            ang = math.atan2(v.co.y, v.co.x)
            v.co.z += ragged * abs(math.sin(ang * 4.5 + phase)) ** 2
    geo.box_uv(bm, 0.25)
    return bm


# --- Kopf ---------------------------------------------------------------------------

class Head:
    """Verformbarer Kopf (Ellipsoid) mit Abfrage der Oberfläche für Augen, Mund, Nähte."""

    def __init__(self, radii, center=HEAD_CENTER, u=56, v=40):
        self.center = Vector(center)
        self.bm = geo.ellipsoid(Vector(radii), self.center, u, v)

    def deform(self, fn):
        for vert in self.bm.verts:
            c = vert.co - self.center
            vert.co = self.center + fn(c, c.normalized())
        self.bm.normal_update()
        geo.sphere_uv(self.bm, self.center)

    def surface(self, x, z):
        """Punkt + Normale vorne an x, z (relativ zur Kopfmitte)."""
        best = None
        for v in self.bm.verts:
            c = v.co - self.center
            if c.y > 0:
                continue
            dist = (c.x - x) ** 2 + (c.z - z) ** 2
            if best is None or dist < best[0]:
                best = (dist, v)
        return best[1].co.copy(), best[1].normal.copy()

    def near(self, p):
        p = Vector(p)
        best = min(self.bm.verts, key=lambda v: (v.co - p).length)
        return best.co.copy(), best.normal.copy()

    def on_surface(self, bm, x, z, lift=0.0, spin=0.0):
        p, n = self.surface(x, z)
        rot = Vector((0, -1, 0)).rotation_difference(n).to_matrix().to_4x4()
        return geo.transform(bm, Matrix.Translation(p + n * lift) @ rot @ Matrix.Rotation(spin, 4, "Y"))


def gauss(a, sigma):
    return math.exp(-(a * a) / (2 * sigma * sigma))


def socket_dent(c, d, ex, ez, depth, sigma, slant=0.0):
    side = 1 if ex > 0 else -1
    dx = c.x - ex
    dz = (c.z - ez) - dx * side * slant
    w = math.exp(-(dx * dx + (dz * 0.85) ** 2) / (2 * sigma * sigma))
    return d * depth * w * max(0.0, -d.y)


def eye_sockets(rig, head, eyes, size=(0.05, 0.03, 0.04), slant=0.3, inset=0.014, name="Void_Sockets"):
    parts = []
    for i, (ex, ez) in enumerate(eyes):
        p, _n = head.surface(ex, ez)
        side = 1 if ex > 0 else -1
        s_bm = geo.ellipsoid(Vector(size), Vector((0, 0, 0)), 28, 18)
        geo.transform(s_bm, Matrix.Rotation(side * -slant, 4, "Y"))
        geo.translate(s_bm, p + Vector((0, inset, 0)))
        parts.append(s_bm)
        rig.marker("EyeL" if i == 0 else ("EyeR" if i == 1 else f"EyeX{i - 1}"), rig.head,
                   p + Vector((0, inset - size[1] - 0.002, -0.002)))
    rig.headpart(name, geo.merge(*parts), void(), smooth=True)


def grin(rig, head, width, height, zc, lift_corners, teeth_mat=None, teeth=True, jaw=True, fang_scale=1.0):
    """Breites Maul: schwarze Fläche auf der Oberfläche, oben Zähne, unten Kiefer mit Zähnen."""
    def mid(x):
        return zc + lift_corners * (x / width) ** 2

    def half(x):
        return 0.004 + height * max(0.0, 1 - (x / width) ** 2)

    g = bmesh.new()
    cols = 28
    rows = []
    for k in range(cols + 1):
        x = -width + 2 * width * k / cols
        col = []
        for r in (-1, 0, 1):
            p, n = head.surface(x, mid(x) + r * half(x))
            col.append(g.verts.new(p + n * 0.0015))
        rows.append(col)
    for k in range(cols):
        for r in range(2):
            g.faces.new((rows[k][r], rows[k + 1][r], rows[k + 1][r + 1], rows[k][r + 1]))
    rig.headpart("Void_Mouth", g, void(), smooth=True)
    if not teeth:
        return

    def tooth(x, z_edge, down, size):
        p, n = head.surface(x, z_edge)
        p2, _ = head.surface(x, z_edge + (-0.01 if down else 0.01))
        direction = (p2 - p).normalized()
        base = p + n * 0.003
        tip = base + direction * size + n * 0.002
        return geo.tube([base, base.lerp(tip, 0.5), tip], [size * 0.28, size * 0.17, 0.0008], seg=8)

    upper, lower = [], []
    n_up = 13
    for k in range(n_up):
        x = -width * 0.85 + 1.7 * width * k / (n_up - 1)
        size = (0.034 * fang_scale if k in (3, 9) else 0.02 + 0.005 * ((k * 7) % 3))
        upper.append(tooth(x, mid(x) + half(x) * 0.92, True, size * max(0.45, 1 - abs(x) / (width * 1.1))))
    for k in range(12):
        x = -width * 0.78 + 1.56 * width * k / 11
        size = (0.028 * fang_scale if k in (2, 9) else 0.017 + 0.004 * ((k * 5) % 3))
        lower.append(tooth(x, mid(x) - half(x) * 0.92, False, size * max(0.45, 1 - abs(x) / (width * 1.1))))
    tm = teeth_mat or mat("Zahn", color=(0.86, 0.8, 0.64, 1), rough=0.35)
    rig.headpart("Teeth", geo.merge(*upper), tm, smooth=True)
    low = geo.merge(*lower)
    if jaw:
        pivot = Vector((0, 0.06, HEAD_CENTER.z + zc))
        geo.translate(low, -pivot)
        ob = rig.headpart("Jaw", low, tm, smooth=True)
        ob.location = pivot
    else:
        rig.headpart("TeethLow", low, tm, smooth=True)


def strands(head, count, region, length, radius, seed, gravity=1.0, curl=0.0):
    """Hängende Strähnen (Haare, Moos) von zufälligen Punkten der Kopfoberfläche."""
    rnd = random.Random(seed)
    out = []
    verts = [v for v in head.bm.verts if region(v.co - head.center)]
    for _ in range(count):
        v = rnd.choice(verts)
        p = v.co.copy()
        n = v.normal.copy()
        pts = [p - n * 0.005]
        L = length * rnd.uniform(0.6, 1.3)
        steps = 7
        for i in range(1, steps + 1):
            t = i / steps
            q = p + n * 0.025 * math.sin(t * math.pi * 0.5) + Vector((0, 0, -L * t * gravity))
            q += Vector((math.sin(t * 5 + p.x * 40) * curl, math.cos(t * 4 + p.y * 30) * curl, 0))
            pts.append(q)
        r0 = radius * rnd.uniform(0.7, 1.3)
        out.append(geo.tube(pts, [r0 * (1 - 0.85 * i / steps) + 0.001 for i in range(steps + 1)], seg=6, tile=0.1))
    return geo.merge(*out) if out else bmesh.new()


def hood(rig, material, radii=(0.235, 0.245, 0.27), opening=(0.15, 0.2), drape=0.2, point=0.06, seed=0):
    """Kapuze als Schale um den Kopf mit Gesichtsöffnung, fällt nach unten auf die Schultern."""
    c = HEAD_CENTER + Vector((0, 0.025, 0.03))
    bm = geo.ellipsoid(Vector(radii), c, 48, 32)
    rnd = random.Random(seed)
    kill = []
    for f in bm.faces:
        m = f.calc_center_median() - c
        if m.y < -0.04 and abs(m.x) < opening[0] and -0.2 < m.z < opening[1]:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    for v in bm.verts:
        k = v.co - c
        if k.z < -0.05:  # nach unten und außen auf die Schultern fallen
            t = min(1.0, (-k.z - 0.05) / 0.2)
            v.co.z -= drape * t
            v.co.x *= 1 + 0.6 * t
            v.co.y *= 1 + 0.25 * t
            v.co.z += rnd.uniform(-0.015, 0.015) * t
        if k.z > 0.15 and k.y > 0.0:  # Zipfel hinten oben
            v.co.y += point * (k.z - 0.15) / 0.12
            v.co.z += point * 0.5 * (k.z - 0.15) / 0.12
    geo.box_uv(bm, 0.3)
    ob = rig.headpart("Hood", bm, material, smooth=True, sharp_angle=None)
    mod = ob.modifiers.new("Dicke", "SOLIDIFY")
    mod.thickness = 0.012
    mod.offset = 1.0
    return ob


# --- Hände --------------------------------------------------------------------------

def hand(side, skin, claw_mat=None, length=1.0, thick=1.0, claw=0.0, knobby=0.0, palm=1.0, bony=False):
    """Hand mit 4 Fingern + Daumen (Hand-Koordinaten, Finger zeigen nach -Y).
    claw = Krallenlänge (0 = keine), knobby = knorrige Gelenke, bony = Skelett."""
    pieces = []
    claws = []
    if not bony:
        pieces.append(geo.ellipsoid(Vector((0.034 * palm * thick, 0.044 * palm, 0.017 * thick)), Vector((0, 0, 0)), 20, 14))
    else:
        for f in range(4):  # Mittelhandknochen
            x = side * (0.024 - f * 0.016)
            pieces.append(geo.tube([Vector((x * 0.6, 0.02, 0.0)), Vector((x, -0.034, 0.003))], [0.0045, 0.004], seg=8))
            pieces.append(geo.ellipsoid(Vector((0.0065, 0.0065, 0.006)), Vector((x, -0.034, 0.003)), 8, 6))
        pieces.append(geo.ellipsoid(Vector((0.02, 0.016, 0.01)), Vector((0, 0.022, 0)), 12, 8))
    base_len = (0.045, 0.054, 0.058, 0.05)
    for f in range(4):
        x = side * (0.026 - f * 0.017) * palm * thick
        L = base_len[f] * length
        r = (0.0062 if bony else 0.0078) * thick
        k0 = Vector((x, -0.033 * palm, 0.004))
        spread = side * -0.004 * (f - 1.5)
        k1 = k0 + Vector((spread, -L * 0.42, 0.006))
        k2 = k1 + Vector((spread * 0.5, -L * 0.33, -0.012))
        k3 = k2 + Vector((0, -L * 0.25, -0.016))
        for a, b, ra, rb in ((k0, k1, r, r * 0.88), (k1, k2, r * 0.86, r * 0.76), (k2, k3, r * 0.74, r * 0.66)):
            pieces.append(geo.tube([a, b], [ra, rb], seg=10))
        joint = 1.25 + knobby
        for k, rr in ((k0, r * joint), (k1, r * joint * 0.95), (k2, r * joint * 0.88)):
            pieces.append(geo.ellipsoid(Vector((rr, rr, rr)), k, 10, 6))
        if claw > 0:
            d = (k3 - k2).normalized()
            c0 = k3 - d * 0.003
            c1 = k3 + d * claw * 0.55 + Vector((0, 0, -claw * 0.15))
            c2 = c1 + d * claw * 0.45 + Vector((0, 0, -claw * 0.45))
            claws.append(geo.tube([c0, c1, c2], [r * 0.75, r * 0.5, 0.0006], seg=8))
        else:
            pieces.append(geo.ellipsoid(Vector((r * 0.66, r * 0.66, r * 0.66)), k3, 8, 6))
    t0 = Vector((-side * 0.028 * palm * thick, -0.008, -0.004))
    t1 = t0 + Vector((-side * 0.022, -0.026 * length, -0.004))
    t2 = t1 + Vector((-side * 0.008, -0.026 * length, -0.008))
    r = (0.007 if bony else 0.0095) * thick
    pieces += [geo.tube([t0, t1], [r, r * 0.85], seg=10), geo.tube([t1, t2], [r * 0.8, r * 0.66], seg=10),
               geo.ellipsoid(Vector((r * 0.9,) * 3), t1, 10, 6)]
    if claw > 0:
        d = (t2 - t1).normalized()
        claws.append(geo.tube([t2 - d * 0.003, t2 + d * claw * 0.6, t2 + d * claw + Vector((0, 0, -claw * 0.4))],
                              [r * 0.65, r * 0.45, 0.0006], seg=8))
    else:
        pieces.append(geo.ellipsoid(Vector((r * 0.66,) * 3), t2, 8, 6))
    bm = geo.merge(*pieces)
    geo.box_uv(bm, 0.15)
    name = "Hand_L" if side < 0 else "Hand_R"
    ob = geo.to_object(name, bm, skin, smooth=True, sharp_angle=None)
    ob.location = G(side * 0.15, 0.86, 0.2)
    if claws:
        cl = geo.to_object(name + "_Claws", geo.merge(*claws), claw_mat or mat("Kralle", color=(0.06, 0.045, 0.04, 1), rough=0.25),
                           smooth=True, sharp_angle=None)
        cl.parent = ob
    return ob


def hands(**kw):
    for side in (-1, 1):
        hand(side, **kw)


def place_sleeve(bm, material):
    ob = geo.to_object("Sleeve", bm, material, smooth=True, sharp_angle=50)
    shoulder = G(0.40, 1.04, -0.34)
    hand_pos = G(0.15, 0.86, 0.15)
    d = hand_pos - shoulder
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    ob.matrix_world = Matrix.Translation((shoulder + hand_pos) * 0.5) @ rot @ Matrix.Diagonal((1, 1, d.length, 1))
    return ob


# =====================================================================================
#  Die acht Charaktere
# =====================================================================================

def bandit():
    rig = Rig()
    cloth = mat("Kutte", "cloth_brown", rough=0.95)
    leather = mat("Leder", "leather_dark", rough=0.55)
    mask_cloth = mat("Tuch", "cloth_black", rough=0.95)
    metal = mat("Schnalle", "metal", color=(0.6, 0.5, 0.35, 1), rough=0.35, metal=0.9)
    prof = [(0.25, -0.15), (0.27, 0.1), (0.275, 0.45), (0.285, 0.75), (0.29, 0.9), (0.27, 0.99),
            (0.2, 1.06), (0.12, 1.11), (0.08, 1.15), (0.07, 1.2)]
    rig.body("Body", robe(prof, 1.5, 0.78, 0.06), cloth, smooth=True, sharp_angle=None, subsurf=1)
    neck(rig, leather, 0.05)
    rig.body("Body_Cape", cape(prof, 1.5, 0.78, 0.06, z_bottom=0.8, teeth=9, jag=0.1, seed=1, open_front=0.9), cloth,
             smooth=True, sharp_angle=None)
    straps = geo.merge(strip_on_body(prof, 1.5, 0.78, (-0.33, 0.98), (0.3, 0.4), 0.055),
                       strip_on_body(prof, 1.5, 0.78, (0.33, 0.98), (0.15, 0.7), 0.04))
    rig.body("Body_Straps", straps, leather)
    buckle = geo.box(Vector((0.04, 0.012, 0.03)), Vector((0.0, body_front(prof, 1.5, 0.78, 0.0, 0.69) - 0.018, 0.69)))
    rig.body("Body_Buckle", buckle, metal, bevel=0.003)
    for i, z in enumerate((0.84, 0.76, 0.6, 0.52)):  # Messer/Taschen am Gurt
        x = -0.33 + (0.98 - z) / 0.58 * 0.63
        bm = geo.box(Vector((0.03, 0.02, 0.06)), Vector((x, body_front(prof, 1.5, 0.78, x, z) - 0.025, z)))
        rig.body(f"Body_Pouch{i}", bm, leather, bevel=0.004)

    head = Head((0.15, 0.155, 0.19))
    head.deform(lambda c, d: c + socket_dent(c, d, -0.06, 0.03, 0.03, 0.035, 0.3) + socket_dent(c, d, 0.06, 0.03, 0.03, 0.035, 0.3))
    eye_sockets(rig, head, [(-0.06, 0.03), (0.06, 0.03)], size=(0.04, 0.02, 0.022), slant=0.35, inset=0.012)
    # Tuch über Nase und Mund
    cloth_mask = geo.ellipsoid(Vector((0.162, 0.166, 0.2)), HEAD_CENTER, 40, 28)
    kill = [f for f in cloth_mask.faces if (f.calc_center_median() - HEAD_CENTER).z > -0.005 or
            (f.calc_center_median() - HEAD_CENTER).y > 0.05]
    bmesh.ops.delete(cloth_mask, geom=kill, context="FACES")
    for v in cloth_mask.verts:
        k = v.co - HEAD_CENTER
        if k.z < -0.12:
            v.co.z -= 0.04 * min(1, (-k.z - 0.12) / 0.06)
    geo.box_uv(cloth_mask, 0.2)
    rig.headpart("FaceCloth", cloth_mask, mask_cloth, smooth=True, sharp_angle=None)
    rig.headpart("Face", head.bm, leather, smooth=True, sharp_angle=None)
    hood(rig, cloth, opening=(0.135, 0.17), drape=0.22, point=0.05, seed=2)

    hands(skin=leather, length=1.0, thick=1.05)
    place_sleeve(sleeve(0.07, 0.066, 0.078, ragged=0.03, seed=1), cloth)


def swamp_man():
    rig = Rig(1.34)
    bark_m = mat("Rinde", "bark", rough=0.95)
    moss_m = mat("Moos", "moss", rough=1.0)
    shroom = mat("Pilz", "skin_pale", color=(1, 1, 1, 1), rough=0.7)
    prof = [(0.27, -0.15), (0.29, 0.1), (0.3, 0.45), (0.31, 0.75), (0.32, 0.92), (0.29, 1.0),
            (0.2, 1.07), (0.12, 1.12), (0.09, 1.16), (0.08, 1.21)]
    body = robe(prof, 1.55, 0.82, 0.08, 0.05)
    rnd = random.Random(5)
    for v in body.verts:  # knorrig
        v.co += v.normal * rnd.uniform(-0.008, 0.012)
    rig.body("Body", body, bark_m, smooth=True, sharp_angle=None, subsurf=1)
    neck(rig, bark_m, 0.055, ridges=0.006)
    rig.body("Body_Moss", cape(prof, 1.55, 0.82, 0.08, 0.05, z_bottom=0.82, teeth=17, jag=0.07, drip=0.12, seed=3), moss_m,
             smooth=True, sharp_angle=None)
    # Pilze auf der rechten Schulter
    caps, stems = [], []
    for i, (x, y, z, s) in enumerate(((0.36, -0.02, 1.03, 1.0), (0.42, 0.04, 1.0, 0.7), (0.3, 0.06, 1.06, 0.55),
                                      (0.45, -0.06, 0.96, 0.5), (-0.38, 0.02, 1.0, 0.6))):
        base = Vector((x, y, z))
        stems.append(geo.translate(geo.lathe([(0.0, 0.0), (0.012 * s, 0.0), (0.009 * s, 0.06 * s), (0.0, 0.06 * s)], 10, 0.1), base))
        caps.append(geo.translate(geo.lathe([(0.0, 0.05 * s), (0.045 * s, 0.05 * s), (0.04 * s, 0.07 * s),
                                             (0.02 * s, 0.085 * s), (0.0, 0.088 * s)], 16, 0.1), base))
    rig.body("Body_Shrooms", geo.merge(*caps, *stems), shroom, smooth=True, sharp_angle=None)

    head = Head((0.15, 0.16, 0.235))

    def shape(c, d):
        c = c.copy()
        if c.z < 0:
            c.x *= 1 - 0.25 * min(1, -c.z / 0.2)
        c += socket_dent(c, d, -0.06, 0.04, 0.05, 0.035, 0.1) + socket_dent(c, d, 0.06, 0.04, 0.05, 0.035, 0.1)
        c -= d * 0.03 * gauss(c.x, 0.05) * gauss(c.z + 0.11, 0.045) * max(0, -d.y)  # offenes Maul
        c += d * 0.012 * gauss(c.x, 0.012) * gauss(c.z + 0.02, 0.02) * max(0, -d.y)
        return c
    head.deform(shape)
    eye_sockets(rig, head, [(-0.06, 0.04), (0.06, 0.04)], size=(0.04, 0.025, 0.032), slant=0.15, inset=0.016)
    grin(rig, head, 0.06, 0.03, -0.11, 0.0, teeth=False)
    # Moosbart und hängende Strähnen
    rig.headpart("MossStrands", strands(head, 46, lambda c: c.z > -0.05 and abs(c.x) > 0.02 or c.z < -0.13,
                                        0.22, 0.01, seed=7, curl=0.006), moss_m, smooth=True, sharp_angle=None)
    twigs = []
    for i in range(7):
        rr = random.Random(20 + i)
        p, n = head.near(HEAD_CENTER + Vector((rr.uniform(-0.1, 0.1), rr.uniform(-0.05, 0.12), 0.25)))
        pts = [p - n * 0.01]
        q = p.copy()
        for k in range(5):
            q = q + n * 0.03 + Vector((rr.uniform(-0.02, 0.02), rr.uniform(-0.01, 0.03), 0.025))
            pts.append(q)
        twigs.append(geo.tube(pts, [0.012, 0.01, 0.008, 0.006, 0.004, 0.001], seg=6))
    rig.headpart("Twigs", geo.merge(*twigs), bark_m, smooth=True, sharp_angle=None)
    rig.headpart("Face", head.bm, moss_m, smooth=True, sharp_angle=None)

    hands(skin=bark_m, length=1.45, thick=0.95, knobby=0.6, claw=0.012, claw_mat=bark_m)
    place_sleeve(sleeve(0.075, 0.068, 0.08, ragged=0.06, seed=2), moss_m)


def crow():
    rig = Rig(1.36)
    robe_m = mat("Robe", "cloth_black", rough=0.95)
    feather = mat("Federn", "feathers_black", rough=0.6)
    beak_m = mat("Schnabel", "leather_dark", color=(1, 1, 1, 1), rough=0.3)
    charm = mat("Anhaenger", "bone", rough=0.6)
    gold = mat("Messing", "metal", color=(0.6, 0.48, 0.25, 1), rough=0.35, metal=0.9)
    prof = [(0.24, -0.15), (0.26, 0.1), (0.265, 0.45), (0.275, 0.75), (0.28, 0.9), (0.26, 0.99),
            (0.19, 1.06), (0.11, 1.11), (0.075, 1.15), (0.065, 1.2)]
    rig.body("Body", robe(prof, 1.45, 0.78, 0.09, 0.05), robe_m, smooth=True, sharp_angle=None, subsurf=1)
    neck(rig, feather, 0.06)
    rig.body("Body_Feathers", cape(prof, 1.45, 0.78, 0.09, 0.05, z_bottom=0.8, teeth=22, jag=0.09, seed=4), feather,
             smooth=True, sharp_angle=None)
    # Kette mit Anhängern
    pts = []
    for i in range(21):
        t = i / 20
        x = -0.17 + 0.34 * t
        z = 0.95 - 0.12 * math.sin(t * math.pi)
        pts.append(Vector((x, body_front(prof, 1.45, 0.78, x, z) - 0.06, z)))
    rig.body("Body_Chain", geo.tube(pts, [0.004] * len(pts), seg=6), gold, smooth=True)
    charms = []
    for i, t in enumerate((0.25, 0.5, 0.75)):
        p = pts[int(t * 20)]
        if i == 1:
            charms.append(geo.translate(geo.ellipsoid(Vector((0.022, 0.006, 0.03)), Vector((0, 0, 0)), 12, 8), p + Vector((0, -0.004, -0.035))))
        else:
            charms.append(geo.tube([p, p + Vector((0, -0.004, -0.03)), p + Vector((0, -0.002, -0.055))], [0.008, 0.006, 0.001], seg=8))
    rig.body("Body_Charms", geo.merge(*charms), charm, smooth=True)

    head = Head((0.135, 0.145, 0.165))
    head.deform(lambda c, d: c + d * 0.02 * gauss(c.z - 0.06, 0.03) * max(0, -d.y))
    eye_sockets(rig, head, [(-0.07, 0.03), (0.07, 0.03)], size=(0.022, 0.012, 0.02), slant=0.4, inset=0.004)
    # Schnabel: Oberschnabel gebogen, Unterschnabel kürzer
    top = [Vector((0, -0.08, 0.12)), Vector((0, -0.17, 0.115)), Vector((0, -0.26, 0.095)), Vector((0, -0.32, 0.055)),
           Vector((0, -0.345, 0.01)), Vector((0, -0.335, -0.025))]
    upper = geo.tube(top, [0.062, 0.05, 0.036, 0.022, 0.012, 0.001], seg=14)
    bmesh.ops.scale(upper, vec=Vector((0.8, 1.0, 0.9)), verts=upper.verts)
    low_pts = [Vector((0, -0.08, 0.075)), Vector((0, -0.17, 0.07)), Vector((0, -0.25, 0.06)), Vector((0, -0.3, 0.05))]
    lower = geo.tube(low_pts, [0.042, 0.03, 0.016, 0.001], seg=12)
    bmesh.ops.scale(lower, vec=Vector((0.7, 1.0, 0.6)), verts=lower.verts)
    geo.box_uv(upper, 0.1)
    rig.headpart("Beak", upper, beak_m, smooth=True, sharp_angle=None)
    pivot = Vector((0, -0.07, 0.08))
    geo.translate(lower, -pivot)
    jaw = rig.headpart("Jaw", lower, beak_m, smooth=True, sharp_angle=None)
    jaw.location = pivot
    # Federschopf: viele Federn nach hinten unten
    rnd = random.Random(11)
    fl = []
    for _ in range(90):
        v = rnd.choice([v for v in head.bm.verts if (v.co - HEAD_CENTER).y > -0.06])
        p, n = v.co.copy(), v.normal.copy()
        back = Vector((0, 0.7, -0.4)).normalized()
        L = rnd.uniform(0.05, 0.12)
        dirv = (n * 0.6 + back).normalized()
        f = geo.tube([p - n * 0.005, p + dirv * L * 0.5, p + dirv * L + Vector((0, 0, -0.02))], [0.012, 0.009, 0.001], seg=4)
        bmesh.ops.scale(f, vec=Vector((1.0, 1.0, 1.0)), verts=f.verts)
        fl.append(f)
    rig.headpart("Head_Feathers", geo.merge(*fl), feather, smooth=True, sharp_angle=None)
    rig.headpart("Face", head.bm, feather, smooth=True, sharp_angle=None)

    hands(skin=beak_m, length=1.25, thick=0.85, claw=0.03, knobby=0.4)
    place_sleeve(sleeve(0.07, 0.064, 0.078, ragged=0.04, seed=3), robe_m)


def wolf():
    rig = Rig(1.34)
    fur_m = mat("Fell", "fur_grey", rough=0.95)
    cape_m = mat("Umhang", "cloth_red", rough=0.9)
    nose_m = mat("Nase", color=(0.03, 0.025, 0.025, 1), rough=0.3)
    inner_ear = mat("Ohr_Innen", "skin_pale", color=(1, 1, 1, 1), rough=0.8)
    prof = [(0.26, -0.15), (0.28, 0.1), (0.29, 0.45), (0.3, 0.75), (0.31, 0.9), (0.29, 0.99),
            (0.21, 1.06), (0.13, 1.11), (0.1, 1.15), (0.09, 1.2)]
    body = robe(prof, 1.5, 0.8, 0.07, 0.04)
    rig.body("Body", body, fur_m, smooth=True, sharp_angle=None, subsurf=1)
    neck(rig, fur_m, 0.07)
    rig.body("Body_Cape", cape(prof, 1.5, 0.8, 0.07, 0.04, z_bottom=0.7, offset=0.035, teeth=8, jag=0.14, seed=6, open_front=1.3), cape_m,
             smooth=True, sharp_angle=None)
    # Fellbüschel an Brust und Hals
    rnd = random.Random(9)
    tufts = []
    for _ in range(70):
        x = rnd.uniform(-0.2, 0.2)
        z = rnd.uniform(0.85, 1.12)
        y = body_front(prof, 1.5, 0.8, x, z) - 0.005
        p = Vector((x, y, z))
        d = Vector((x * 0.6, -0.5, -1.0)).normalized()
        L = rnd.uniform(0.04, 0.09)
        tufts.append(geo.tube([p, p + d * L * 0.6, p + d * L], [0.014, 0.01, 0.001], seg=5))
    rig.body("Body_Tufts", geo.merge(*tufts), fur_m, smooth=True, sharp_angle=None)

    head = Head((0.135, 0.14, 0.15), center=HEAD_CENTER + Vector((0, 0.02, 0)))
    eye_sockets(rig, head, [(-0.058, 0.035), (0.058, 0.035)], size=(0.022, 0.012, 0.016), slant=0.45, inset=0.004)
    # Schnauze
    snout_pts = [Vector((0, -0.06, 0.08)), Vector((0, -0.14, 0.06)), Vector((0, -0.21, 0.045)), Vector((0, -0.25, 0.035))]
    snout = geo.tube(snout_pts, [0.075, 0.058, 0.04, 0.03], seg=16)
    bmesh.ops.scale(snout, vec=Vector((0.85, 1.0, 0.85)), verts=snout.verts)
    geo.box_uv(snout, 0.15)
    rig.headpart("Snout", snout, fur_m, smooth=True, sharp_angle=None)
    rig.headpart("Nose", geo.ellipsoid(Vector((0.022, 0.016, 0.016)), Vector((0, -0.272, 0.05)), 14, 10), nose_m, smooth=True)
    # Unterkiefer mit Reißzähnen
    jaw_pts = [Vector((0, -0.07, 0.03)), Vector((0, -0.15, 0.02)), Vector((0, -0.21, 0.015))]
    jaw_bm = geo.tube(jaw_pts, [0.05, 0.035, 0.018], seg=12)
    bmesh.ops.scale(jaw_bm, vec=Vector((0.8, 1.0, 0.6)), verts=jaw_bm.verts)
    fangs = []
    for side in (-1, 1):
        base = Vector((side * 0.02, -0.2, 0.025))
        fangs.append(geo.tube([base, base + Vector((0, -0.004, 0.022)), base + Vector((0, -0.006, 0.034))], [0.005, 0.0035, 0.0005], seg=6))
        base2 = Vector((side * 0.024, -0.21, 0.04))
        fangs.append(geo.tube([base2, base2 + Vector((0, -0.003, -0.02)), base2 + Vector((0, -0.004, -0.03))], [0.005, 0.0035, 0.0005], seg=6))
    tooth = mat("Zahn", color=(0.9, 0.86, 0.72, 1), rough=0.35)
    rig.headpart("Teeth", geo.merge(*[f for i, f in enumerate(fangs) if i % 2 == 1]), tooth, smooth=True)
    pivot = Vector((0, -0.05, 0.04))
    low = geo.merge(jaw_bm)
    geo.translate(low, -pivot)
    jaw = rig.headpart("Jaw", low, fur_m, smooth=True, sharp_angle=None)
    jaw.location = pivot
    lf = geo.merge(*[f for i, f in enumerate(fangs) if i % 2 == 0])
    geo.translate(lf, -pivot)
    t_ob = geo.to_object("Jaw_Teeth", lf, tooth, smooth=True)
    t_ob.parent = jaw
    rig.headpart("Void_Mouth", geo.tube([Vector((0, -0.07, 0.042)), Vector((0, -0.2, 0.035))], [0.035, 0.012], seg=10), void(), smooth=True)
    # Ohren
    ears, inner = [], []
    for side in (-1, 1):
        base = Vector((side * 0.075, 0.03, 0.2))
        tip = base + Vector((side * 0.04, 0.02, 0.13))
        e = geo.tube([base, base.lerp(tip, 0.5), tip], [0.045, 0.03, 0.002], seg=10)
        bmesh.ops.scale(e, vec=Vector((1.0, 0.45, 1.0)), verts=e.verts)
        ears.append(e)
        ib = geo.tube([base + Vector((0, -0.012, 0.01)), base.lerp(tip, 0.5) + Vector((0, -0.012, 0)), tip + Vector((0, -0.008, -0.02))],
                      [0.03, 0.02, 0.002], seg=10)
        bmesh.ops.scale(ib, vec=Vector((1.0, 0.25, 1.0)), verts=ib.verts)
        inner.append(ib)
    rig.headpart("Ears", geo.merge(*ears), fur_m, smooth=True, sharp_angle=None)
    rig.headpart("Ears_Inner", geo.merge(*inner), inner_ear, smooth=True, sharp_angle=None)
    # Wangenfell
    rig.headpart("Cheek_Fur", strands(head, 40, lambda c: abs(c.x) > 0.08 and c.z < 0.06 or c.z < -0.1, 0.07, 0.012,
                                      seed=12, gravity=0.8), fur_m, smooth=True, sharp_angle=None)
    rig.headpart("Face", head.bm, fur_m, smooth=True, sharp_angle=None)

    hands(skin=fur_m, length=1.15, thick=1.1, claw=0.03, knobby=0.3)
    place_sleeve(sleeve(0.075, 0.07, 0.082, ragged=0.05, seed=4), fur_m)


def jester():
    rig = Rig()
    suit = mat("Kostuem", "cloth_purple", rough=0.85)
    dark = mat("Kostuem_Dunkel", "cloth_dark_purple", rough=0.85)
    skin = mat("Haut", "skin_pale", rough=0.5)
    bell = mat("Schelle", "metal", color=(0.75, 0.58, 0.25, 1), rough=0.25, metal=1.0)
    paint = mat("Schminke", color=(0.05, 0.02, 0.06, 1), rough=0.6)
    prof = [(0.24, -0.15), (0.26, 0.1), (0.265, 0.45), (0.275, 0.75), (0.28, 0.9), (0.26, 0.99),
            (0.19, 1.06), (0.11, 1.11), (0.075, 1.15), (0.065, 1.2)]
    rig.body("Body", robe(prof, 1.45, 0.78, 0.07, 0.04), suit, smooth=True, sharp_angle=None, subsurf=1)
    neck(rig, skin, 0.045)
    rig.body("Body_Cape", cape(prof, 1.45, 0.78, 0.07, 0.04, z_bottom=0.86, teeth=10, jag=0.09, seed=7), dark, smooth=True, sharp_angle=None)
    rig.body("Body_Ruff", cape(prof, 1.45, 0.78, 0.07, 0.04, z_bottom=1.07, offset=0.05, flare=0.09, teeth=14, jag=0.05, seed=8), suit, smooth=True, sharp_angle=None)
    bells = []
    for k in range(10):
        ang = math.tau * k / 10
        p = Vector((math.cos(ang) * 0.33 * 1.45, math.sin(ang) * 0.33 * 0.78 - 0.02, 0.84))
        if p.y < 0.1:
            bells.append(geo.ellipsoid(Vector((0.016,) * 3), p, 10, 8))
    rig.body("Body_Bells", geo.merge(*bells), bell, smooth=True)

    head = Head((0.14, 0.145, 0.185))

    def shape(c, d):
        c = c.copy()
        if c.z < 0:
            c.x *= 1 - 0.2 * min(1, -c.z / 0.2)
        c += socket_dent(c, d, -0.055, 0.03, 0.02, 0.03, 0.4) + socket_dent(c, d, 0.055, 0.03, 0.02, 0.03, 0.4)
        c += d * 0.02 * gauss(c.x, 0.016) * gauss(c.z + 0.02, 0.025) * max(0, -d.y)  # Nase
        c += d * 0.012 * gauss(abs(c.x) - 0.08, 0.03) * gauss(c.z + 0.05, 0.03) * max(0, -d.y)  # Wangen
        return c
    head.deform(shape)
    # dunkle Augenschminke (Rauten) + Höhlen
    diamonds = []
    for ex in (-0.055, 0.055):
        dm = bmesh.new()
        pts = [(0, 0.05), (0.03, 0.0), (0, -0.06), (-0.03, 0.0)]
        vs = []
        for dx, dz in pts:
            p, n = head.surface(ex + dx, 0.03 + dz)
            vs.append(dm.verts.new(p + n * 0.001))
        dm.faces.new(vs)
        diamonds.append(dm)
    rig.headpart("Face_Paint", geo.merge(*diamonds), paint)
    eye_sockets(rig, head, [(-0.055, 0.03), (0.055, 0.03)], size=(0.026, 0.012, 0.016), slant=0.4, inset=0.006)
    grin(rig, head, 0.09, 0.018, -0.085, 0.045, fang_scale=0.6)
    # Narrenkappe: Haube + drei Zipfel mit Schellen
    cap = geo.ellipsoid(Vector((0.155, 0.16, 0.2)), HEAD_CENTER + Vector((0, 0.01, 0.025)), 40, 28)
    kill = [f for f in cap.faces if (f.calc_center_median() - HEAD_CENTER).z < 0.07 and (f.calc_center_median() - HEAD_CENTER).y < 0.06]
    kill += [f for f in cap.faces if (f.calc_center_median() - HEAD_CENTER).z < -0.08 and f not in kill]
    bmesh.ops.delete(cap, geom=kill, context="FACES")
    geo.box_uv(cap, 0.2)
    c_ob = rig.headpart("Cap", cap, dark, smooth=True, sharp_angle=None)
    c_ob.modifiers.new("Dicke", "SOLIDIFY").thickness = 0.01
    points, tips = [], []
    for i, (side, lean, m) in enumerate(((-1, 0.0, suit), (1, 0.0, suit), (0, 1.0, dark))):
        base = HEAD_CENTER + Vector((side * 0.09, 0.03 * lean, 0.16 + 0.02 * lean))
        pts = []
        for k in range(12):
            t = k / 11
            ang = t * math.pi * 0.95
            out = Vector((side * 0.22 * math.sin(ang * 0.8), 0.12 * lean * math.sin(ang), 0.17 * math.sin(ang) - 0.1 * t * t))
            pts.append(base + out)
        radii = [0.07 * (1 - t / 11) ** 1.1 + 0.006 for t in range(12)]
        points.append((geo.tube(pts, radii, seg=14), m))
        tips.append(geo.ellipsoid(Vector((0.024,) * 3), pts[-1] + (pts[-1] - pts[-2]).normalized() * 0.018, 12, 8))
    rig.headpart("Hat_Points", geo.merge(points[0][0], points[1][0]), suit, smooth=True, sharp_angle=None)
    rig.headpart("Hat_Point_Back", points[2][0], dark, smooth=True, sharp_angle=None)
    rig.headpart("Hat_Bells", geo.merge(*tips), bell, smooth=True)
    rig.headpart("Face", head.bm, skin, smooth=True, sharp_angle=None)

    hands(skin=skin, length=1.15, thick=0.9, knobby=0.2)
    place_sleeve(sleeve(0.07, 0.064, 0.085, ragged=0.07, seed=5), suit)


def bone_man():
    rig = Rig(1.35)
    robe_m = mat("Kutte", "cloth_brown", color=(1, 1, 1, 1), rough=0.95)
    bone_m = mat("Knochen", "bone", rough=0.55)
    prof = [(0.24, -0.15), (0.25, 0.1), (0.25, 0.45), (0.26, 0.75), (0.27, 0.9), (0.25, 0.99),
            (0.18, 1.06), (0.1, 1.11), (0.07, 1.15), (0.06, 1.2)]
    body = robe(prof, 1.4, 0.75, 0.08, 0.06)
    # vorne offen: Brustkorb sichtbar
    kill = [f for f in body.faces if f.calc_center_median().y < -0.05 and abs(f.calc_center_median().x) < 0.13
            and 0.45 < f.calc_center_median().z < 1.05]
    bmesh.ops.delete(body, geom=kill, context="FACES")
    rig.body("Body", body, robe_m, smooth=True, sharp_angle=None)
    neck(rig, bone_m, 0.028, ridges=0.012)
    rig.body("Body_Cape", cape(prof, 1.4, 0.75, 0.08, 0.06, z_bottom=0.76, teeth=13, jag=0.12, seed=9, open_front=0.7), robe_m,
             smooth=True, sharp_angle=None)
    # Brustkorb: Wirbelsäule, Brustbein, Rippen
    ribs = [geo.tube([Vector((0, 0.02, 0.45)), Vector((0, 0.03, 1.08))], [0.018, 0.016], seg=8)]
    ribs.append(geo.tube([Vector((0, -0.145, 0.68)), Vector((0, -0.16, 0.98))], [0.012, 0.012], seg=8))
    for i in range(7):
        z = 0.95 - i * 0.055
        for side in (-1, 1):
            pts = []
            for k in range(9):
                t = k / 8
                ang = t * math.pi * 0.95
                x = side * math.sin(ang) * (0.16 - 0.005 * i)
                y = 0.02 - math.sin(ang * 0.5 + 0.3) * 0.17 * (1 - 0.02 * i)
                pts.append(Vector((x * (1.0 if t < 0.95 else 0.9), y, z - 0.04 * t)))
            ribs.append(geo.tube(pts, [0.008] * len(pts), seg=6))
    rig.body("Body_Ribs", geo.merge(*ribs), bone_m, smooth=True, sharp_angle=None)
    rig.body("Body_Void", geo.ellipsoid(Vector((0.13, 0.05, 0.3)), Vector((0, -0.02, 0.75)), 16, 12), void(), smooth=True)

    head = Head((0.135, 0.145, 0.165))

    def shape(c, d):
        c = c.copy()
        if c.z < 0:
            c.x *= 1 - 0.3 * min(1, -c.z / 0.16)
        if c.z > 0 and c.y > 0:
            c.y *= 1.1
        f = max(0, -d.y)
        c += socket_dent(c, d, -0.052, 0.03, 0.06, 0.032, 0.05) + socket_dent(c, d, 0.052, 0.03, 0.06, 0.032, 0.05)
        c -= d * 0.035 * gauss(abs(c.x) - 0.085, 0.025) * gauss(c.z + 0.055, 0.03) * f  # Schläfen/Wangen hohl
        c += d * 0.02 * gauss(abs(c.x) - 0.105, 0.02) * gauss(c.z + 0.005, 0.02) * f  # Wangenknochen
        c -= d * 0.02 * gauss(c.x, 0.015) * gauss(c.z + 0.025, 0.02) * f  # Nasenloch
        return c
    head.deform(shape)
    eye_sockets(rig, head, [(-0.052, 0.03), (0.052, 0.03)], size=(0.038, 0.03, 0.036), slant=0.1, inset=0.02)
    nose = bmesh.new()
    vs = []
    for dx, dz in ((0, -0.005), (0.014, -0.04), (-0.014, -0.04)):
        p, n = head.surface(dx, dz)
        vs.append(nose.verts.new(p + n * 0.001))
    nose.faces.new(vs)
    rig.headpart("Void_Nose", nose, void())
    # Zähne: obere Reihe fest, Unterkiefer beweglich
    upper, lower = [], []
    for k in range(10):
        x = -0.045 + 0.01 * k
        p, n = head.surface(x, -0.075)
        upper.append(geo.translate(geo.box(Vector((0.0085, 0.008, 0.016)), Vector((0, 0, 0))), p + n * 0.002 + Vector((0, 0, -0.008))))
    rig.headpart("Teeth", geo.merge(*upper), bone_m, bevel=0.0015)
    pivot = Vector((0, 0.04, HEAD_CENTER.z - 0.07))
    jaw_parts = []
    for k in range(10):
        x = -0.045 + 0.01 * k
        p, n = head.surface(x, -0.075)
        jaw_parts.append(geo.box(Vector((0.0085, 0.008, 0.015)), p + n * 0.002 + Vector((0, 0, -0.026))))
    mand = []
    for k in range(13):
        t = k / 12
        ang = (t - 0.5) * math.pi * 0.9
        mand.append(Vector((math.sin(ang) * 0.075, -math.cos(ang) * 0.11 + 0.02, HEAD_CENTER.z - 0.115 + abs(t - 0.5) * 0.08)))
    jaw_parts.append(geo.tube(mand, [0.016] * len(mand), seg=8))
    rig.headpart("Void_Mouth", geo.box(Vector((0.1, 0.05, 0.04)), Vector((0, -0.095, HEAD_CENTER.z - 0.095))), void())
    jaw_bm = geo.merge(*jaw_parts)
    geo.translate(jaw_bm, -pivot)
    jaw = rig.headpart("Jaw", jaw_bm, bone_m, smooth=True, sharp_angle=40)
    jaw.location = pivot
    rig.headpart("Face", head.bm, bone_m, smooth=True, sharp_angle=None)
    hood(rig, robe_m, radii=(0.215, 0.225, 0.25), opening=(0.13, 0.18), drape=0.24, point=0.08, seed=10)

    hands(skin=bone_m, length=1.25, thick=0.75, bony=True)
    place_sleeve(sleeve(0.068, 0.062, 0.08, ragged=0.08, seed=6), robe_m)


def witch():
    rig = Rig()
    robe_m = mat("Robe", "cloth_dark_purple", rough=0.95)
    hat_m = mat("Hut", "cloth_black", rough=0.9)
    skin = mat("Haut", "skin_witch", rough=0.55)
    hair = mat("Haar", "cloth_black", color=(1, 1, 1, 1), rough=0.7)
    twig = mat("Zweige", "bark", rough=0.95)
    metal = mat("Laternenmetall", "metal", rough=0.4, metal=0.8)
    glass = mat("Laternenglas", color=(0.6, 0.3, 1.0, 1), rough=0.1, emission=(0.6, 0.3, 1.0, 1), emission_strength=4.0)
    prof = [(0.23, -0.15), (0.25, 0.1), (0.255, 0.45), (0.265, 0.75), (0.27, 0.9), (0.25, 0.99),
            (0.18, 1.06), (0.1, 1.11), (0.07, 1.15), (0.06, 1.2)]
    rig.body("Body", robe(prof, 1.4, 0.78, 0.09, 0.03), robe_m, smooth=True, sharp_angle=None, subsurf=1)
    neck(rig, skin, 0.04)
    rig.body("Body_Shawl", cape(prof, 1.4, 0.78, 0.09, 0.03, z_bottom=0.76, teeth=12, jag=0.12, seed=11, open_front=0.6), robe_m,
             smooth=True, sharp_angle=None)

    head = Head((0.13, 0.14, 0.175))

    def shape(c, d):
        c = c.copy()
        if c.z < 0:
            c.x *= 1 - 0.3 * min(1, -c.z / 0.18)
            c.z *= 1.08
        f = max(0, -d.y)
        c += socket_dent(c, d, -0.05, 0.035, 0.03, 0.03, 0.3) + socket_dent(c, d, 0.05, 0.035, 0.03, 0.03, 0.3)
        c -= d * 0.02 * gauss(abs(c.x) - 0.075, 0.025) * gauss(c.z + 0.05, 0.03) * f
        return c
    head.deform(shape)
    eye_sockets(rig, head, [(-0.05, 0.035), (0.05, 0.035)], size=(0.03, 0.014, 0.016), slant=0.4, inset=0.006)
    p, n = head.surface(0, 0.0)
    nose = geo.tube([p - n * 0.01, p + n * 0.04 + Vector((0, 0, -0.01)), p + n * 0.075 + Vector((0, 0, -0.035))],
                    [0.018, 0.01, 0.002], seg=10)
    rig.headpart("Nose", nose, skin, smooth=True, sharp_angle=None)
    grin(rig, head, 0.055, 0.008, -0.085, 0.03, teeth=True, jaw=False, fang_scale=0.5)
    rig.headpart("Hair", strands(head, 70, lambda c: c.y > -0.05 and c.z < 0.15 or (abs(c.x) > 0.1 and c.z < 0.1),
                                 0.32, 0.012, seed=21, curl=0.01), hair, smooth=True, sharp_angle=None)
    # Hexenhut: breite, leicht gewellte Krempe + geknickte Spitze + Zweige
    brim = geo.lathe([(0.0, 0.0), (0.38, 0.0), (0.385, 0.006), (0.37, 0.01), (0.0, 0.012)], 48, 0.3)
    for v in brim.verts:
        r = math.hypot(v.co.x, v.co.y)
        ang = math.atan2(v.co.y, v.co.x)
        v.co.z += 0.03 * (r / 0.38) ** 2 * math.sin(ang * 3) - 0.04 * (r / 0.38) ** 2 * max(0, -math.sin(ang))
    geo.translate(brim, Vector((0, 0.01, HEAD_CENTER.z + 0.135)))
    crown_pts = []
    for k in range(14):
        t = k / 13
        crown_pts.append(Vector((0.05 * t * t, 0.02 + 0.12 * t * t * t, HEAD_CENTER.z + 0.135 + 0.42 * t - 0.12 * t ** 3)))
    crown = geo.tube(crown_pts, [0.15 * (1 - t / 13) ** 0.9 + 0.004 for t in range(14)], seg=24, cap_start=True)
    geo.box_uv(crown, 0.3)
    geo.box_uv(brim, 0.3)
    rig.headpart("Hat", geo.merge(brim, crown), hat_m, smooth=True, sharp_angle=60)
    twigs = []
    rr = random.Random(31)
    for i in range(6):
        ang = rr.uniform(-0.6, 0.9) + (math.pi if i % 2 else 0)
        base = Vector((math.cos(ang) * 0.13, math.sin(ang) * 0.13 + 0.02, HEAD_CENTER.z + 0.18))
        pts = [base]
        q = base.copy()
        for k in range(4):
            q = q + Vector((math.cos(ang) * 0.03, math.sin(ang) * 0.02, 0.035 + rr.uniform(-0.01, 0.01)))
            pts.append(q)
        twigs.append(geo.tube(pts, [0.007, 0.006, 0.004, 0.003, 0.001], seg=6))
    rig.headpart("Hat_Twigs", geo.merge(*twigs), twig, smooth=True, sharp_angle=None)
    rig.headpart("Face", head.bm, skin, smooth=True, sharp_angle=None)

    # Laterne auf dem Tisch (Figur-Koordinaten: Tischkante bei z = 0.6 Richtung Spieler)
    lp = G(-0.42, 0.8, 0.22)
    frame = [geo.box(Vector((0.08, 0.08, 0.012)), lp + Vector((0, 0, 0.006))),
             geo.box(Vector((0.07, 0.07, 0.012)), lp + Vector((0, 0, 0.15)))]
    for sx in (-1, 1):
        for sy in (-1, 1):
            frame.append(geo.box(Vector((0.008, 0.008, 0.14)), lp + Vector((sx * 0.034, sy * 0.034, 0.08))))
    frame.append(geo.lathe([(0.0, 0.156), (0.04, 0.156), (0.0, 0.2)], 12, 0.1))
    geo.translate(frame[-1], Vector((lp.x, lp.y, lp.z)))
    handle = [lp + Vector((math.cos(a) * 0.03, 0, 0.2 + math.sin(a) * 0.03)) for a in [math.pi * k / 8 for k in range(9)]]
    frame.append(geo.tube(handle, [0.003] * len(handle), seg=6))
    rig.prop("Lantern", geo.merge(*frame), metal, bevel=0.002)
    rig.prop("Lantern_Glass", geo.box(Vector((0.06, 0.06, 0.13)), lp + Vector((0, 0, 0.078))), glass)
    rig.marker("PropLight", rig.props, lp + Vector((0, 0, 0.08)))

    hands(skin=skin, length=1.35, thick=0.8, knobby=0.5, claw=0.018, claw_mat=mat("Naegel", color=(0.05, 0.02, 0.06, 1), rough=0.3))
    place_sleeve(sleeve(0.07, 0.064, 0.09, ragged=0.08, seed=7), robe_m)


def giant():
    rig = Rig(1.3)
    shirt = mat("Hemd", "cloth_tan", rough=0.95)
    sack = mat("Sack", "burlap", rough=1.0)
    strap = mat("Leder", "leather_brown", rough=0.6)
    metal = mat("Schnalle", "metal", color=(0.55, 0.45, 0.3, 1), rough=0.4, metal=0.9)
    thread = mat("Faden", color=(0.1, 0.07, 0.05, 1), rough=0.9)
    prof = [(0.3, -0.15), (0.33, 0.1), (0.34, 0.45), (0.35, 0.72), (0.36, 0.88), (0.34, 0.98),
            (0.25, 1.06), (0.15, 1.11), (0.11, 1.15), (0.1, 1.2)]
    sx, sy = 1.6, 0.9
    rig.body("Body", robe(prof, sx, sy, 0.1, 0.07), shirt, smooth=True, sharp_angle=None, subsurf=1)
    neck(rig, sack, 0.085)
    straps = geo.merge(strip_on_body(prof, sx, sy, (-0.22, 1.02), (-0.2, 0.35), 0.07),
                       strip_on_body(prof, sx, sy, (0.22, 1.02), (0.2, 0.35), 0.07),
                       strip_on_body(prof, sx, sy, (-0.45, 0.62), (0.45, 0.62), 0.06))
    rig.body("Body_Straps", straps, strap)
    buckles = [geo.box(Vector((0.05, 0.015, 0.05)), Vector((x, body_front(prof, sx, sy, x, 0.62) - 0.02, 0.62))) for x in (-0.21, 0.21)]
    rig.body("Body_Buckles", geo.merge(*buckles), metal, bevel=0.004)
    rig.body("Body_Patch", geo.box(Vector((0.1, 0.012, 0.09)), Vector((0.08, body_front(prof, sx, sy, 0.08, 0.85) - 0.006, 0.85))), sack, bevel=0.003)

    head = Head((0.17, 0.165, 0.2))
    rnd = random.Random(41)
    lumps = [(Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1))).normalized(), rnd.uniform(0.006, 0.016)) for _ in range(14)]

    def shape(c, d):
        c = c.copy()
        if c.z > 0.12:  # zusammengebundener Zipfel oben
            c.x *= 1 - 0.3 * min(1, (c.z - 0.12) / 0.08)
            c.y *= 1 - 0.3 * min(1, (c.z - 0.12) / 0.08)
        for dirv, a in lumps:
            c += d * a * max(0.0, d.dot(dirv)) ** 6
        f = max(0, -d.y)
        c += socket_dent(c, d, -0.06, 0.03, 0.025, 0.03, 0.0) + socket_dent(c, d, 0.065, 0.025, 0.025, 0.03, 0.0)
        return c
    head.deform(shape)
    eye_sockets(rig, head, [(-0.06, 0.03), (0.065, 0.025)], size=(0.026, 0.015, 0.022), slant=0.0, inset=0.008)
    # Nähte: senkrecht über die Mitte und quer, plus zugenähter Mund
    stitches = []
    for k in range(10):
        z = 0.14 - k * 0.03
        stitches.append(head.on_surface(geo.box(Vector((0.004, 0.004, 0.02)), Vector((0, 0, 0))), 0.002, z, 0.001))
        stitches.append(head.on_surface(geo.box(Vector((0.018, 0.004, 0.004)), Vector((0, 0, 0))), 0.002, z - 0.008, 0.0015))
    for k in range(7):
        x = -0.045 + k * 0.015
        stitches.append(head.on_surface(geo.box(Vector((0.004, 0.004, 0.024)), Vector((0, 0, 0))), x, -0.09, 0.001))
    stitches.append(head.on_surface(geo.box(Vector((0.1, 0.004, 0.004)), Vector((0, 0, 0))), 0.0, -0.09, 0.001))
    rig.headpart("Stitches", geo.merge(*stitches), thread, bevel=0.001)
    knot = geo.tube([HEAD_CENTER + Vector((0, 0, 0.19)), HEAD_CENTER + Vector((0.02, 0.01, 0.24)), HEAD_CENTER + Vector((0.05, 0.02, 0.27))],
                    [0.03, 0.022, 0.01], seg=10)
    rig.headpart("Sack_Top", knot, sack, smooth=True, sharp_angle=None)
    rope = geo.lathe([(0.072, 0.0), (0.075, 0.006), (0.072, 0.012)], 24, 0.1)
    geo.translate(rope, HEAD_CENTER + Vector((0, 0.0, 0.165)))
    rig.headpart("Sack_Rope", rope, strap, smooth=True)
    rig.headpart("Face", head.bm, sack, smooth=True, sharp_angle=None)

    hands(skin=mat("Pranken", "leather_brown", color=(1, 1, 1, 1), rough=0.7), length=1.05, thick=1.7, palm=1.4, knobby=0.3)
    place_sleeve(sleeve(0.1, 0.095, 0.1, ragged=0.0, seed=8), shirt)


def _hd(module):
    """HD-Version aus eigenem Modul (hd_<name>.py) bauen."""
    def build():
        import importlib
        importlib.import_module(module).build()
    return build


CHARACTERS = {
    "bandit": _hd("hd_bandit"),
    "swamp_man": _hd("hd_swamp_man"),
    "crow": _hd("hd_crow"),
    "wolf": _hd("hd_wolf"),
    "jester": _hd("hd_jester"),
    "bone_man": _hd("hd_bone_man"),
    "witch": _hd("hd_witch"),
    "giant": _hd("hd_giant"),
}
