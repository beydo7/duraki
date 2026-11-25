"""Die Krähe in HD (nach dem Konzeptbild „Am Spieltisch“, Feld 3): Rabenkopf mit großem,
gebogenem Hakenschnabel, finster gesenkte Federbrauen, weißlich glühende Augen; ein riesiger,
gezackter Federkragen über Schultern und Brust (dunkelbraun mit violettem Schimmer),
schwere Goldketten quer über der Brust, runde Zierfibeln auf beiden Schultern, dunkler
Mantel, dunkle, geschuppte Hände mit spitzen Krallen.

    import hd_crow; hd_crow.build()
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, noise

import characters as ch
import hd
from geo import G

C = Vector((0, 0, 0.1))  # Schädelmitte (Head-Koordinaten)
HEAD_Y = 1.22
HEAD_SCALE = 1.45
SKULL_C = Vector((0, 0.012, 0.112))
SKULL_R = Vector((0.1, 0.12, 0.102))
EYES = [Vector((-0.064, -0.074, 0.128)), Vector((0.064, -0.074, 0.128))]
GAPE = 0.072          # Höhe der Schnabelspalte an der Wurzel
BEAK_ROOT = -0.094    # Y der Schnabelwurzel
BEAK_LEN = 0.235
# Brauenwulst je Seite (x, z) innen → außen: innen tief, außen hoch = finsterer Blick
BROW = [((0.026, 0.142), (0.094, 0.168))]


def _g(a, s):
    return math.exp(-(a * a) / (2 * s * s))


def eye_normal(side):
    return Vector((side * 0.62, -0.78, 0.06)).normalized()


# =====================================================================================
#  Texturen und Materialien
# =====================================================================================

def tex_feather_card(name, base, sheen, w=128, h=256, seed=3, narrow=1.0, splits=5, ragged=1.0):
    """Einzelfeder mit Alpha (Alpha-Clip): spitz-ovale Fahne mit Kiel, schräge Äste,
    ausgefranster Rand und ein paar Spalten. U quer, V entlang (0 = Kiel, 1 = Spitze)."""
    rng = np.random.default_rng(seed)
    v, u = np.mgrid[0:h, 0:w]
    u = u / (w - 1)
    v = v / (h - 1)
    x = (u - 0.5) * 2
    ax = np.abs(x)
    prof = np.sin(np.pi * np.clip(0.06 + v * 0.94, 0, 1)) ** 0.5 * (1 - v) ** 0.15 * 0.92 * narrow
    prof = np.where(v > 0.55, prof * (1 - 0.35 * ((v - 0.55) / 0.45) ** 2), prof)
    b = v - ax * 0.24 * narrow  # Äste laufen schräg zur Spitze
    edge = hd.fractal(128, 1.4, seed)
    bi = (np.clip(b, 0, 0.999) * 127).astype(int)
    rag = edge[bi, np.where(x > 0, 20, 90)]
    hw = prof * (0.86 + 0.3 * ragged * (rag - 0.5))
    alpha = (ax < hw).astype(np.float32)
    for _ in range(splits):
        side = rng.choice([-1, 1])
        b0 = rng.uniform(0.25, 0.85)
        wid = rng.uniform(0.006, 0.013)
        alpha[(np.abs(b - b0) < wid) & (x * side > 0.12)] = 0.0
    alpha[(v < 0.12) & (ax > hw * 0.55)] = 0.0  # dünner Ansatz
    rachis = np.exp(-(x / 0.03) ** 2) * (v < 0.93)
    alpha = np.maximum(alpha, (rachis > 0.5) * (v < 0.9))
    barbs = 0.5 + 0.5 * np.sin(b * 95 * math.tau)
    rel = np.clip(ax / np.maximum(hw, 1e-3), 0, 1)
    base_l, sheen_l = hd.srgb_to_linear(base), hd.srgb_to_linear(sheen)
    shade = (0.62 + 0.38 * barbs ** 1.6) * (1 - 0.35 * rel ** 2) * (0.75 + 0.35 * v)
    col = base_l[None, None, :] * shade[..., None]
    col += sheen_l[None, None, :] * (0.55 * v ** 1.2 * (0.4 + 0.6 * rel) * (0.7 + 0.3 * barbs))[..., None]
    col += base_l[None, None, :] * (0.9 * rachis)[..., None]
    height = barbs * 0.35 + rachis * 1.1 - rel * 0.4
    return (hd.to_image(name + "_color", col ** (1 / 2.2), alpha=alpha),
            hd.to_image(name + "_normal", hd.height_to_normal(height, 4.0), non_color=True))


def tex_plumage(name, base, sheen, size=512, seed=7, cols=10, rows=14):
    """Gekachelter Untergrund aus dachziegelartig liegenden Federn (Spitzen nach unten)."""
    v, u = np.mgrid[0:size, 0:size] / size
    r = v * rows
    ri = np.floor(r)
    c = u * cols + 0.5 * (ri % 2)
    fu = c - np.floor(c) - 0.5
    fv = r - ri
    arc = 0.45 * (1 - np.sqrt(np.clip(1 - (2 * fu) ** 2, 0, 1)))
    s = np.where(fv >= arc, fv - arc, fv - arc + 1.0)  # 0 = Federspitze, 1 = unter der nächsten
    n = hd.fractal(size, 1.8, seed)
    barbs = 0.5 + 0.5 * np.sin((fu * 22 + s * 6 + n * 3) * math.tau)
    shade = (1.0 - 0.6 * s) * (0.75 + 0.25 * barbs) * (0.8 + 0.4 * n)
    gapl = np.clip(1 - s / 0.04, 0, 1)
    shade *= 1 - 0.6 * gapl
    base_l, sheen_l = hd.srgb_to_linear(base), hd.srgb_to_linear(sheen)
    col = base_l[None, None, :] * shade[..., None] + sheen_l[None, None, :] * (0.5 * (1 - s) ** 3)[..., None]
    height = (1 - s) * 0.8 + barbs * 0.2 - gapl * 0.6
    return (hd.to_image(name + "_color", col ** (1 / 2.2)),
            hd.to_image(name + "_normal", hd.height_to_normal(height, 3.0), non_color=True))


def materials():
    m = {}
    base, sheen = (0.12, 0.092, 0.078), (0.24, 0.13, 0.32)
    c, n = tex_feather_card("feather", base, sheen, seed=4)
    m["feather"] = hd.material("Kraehe_Feder", c, n, rough=0.62, normal_strength=0.8, double_sided=True,
                               spec=0.08, alpha_clip=True)
    c, n = tex_feather_card("plume", (0.115, 0.088, 0.075), (0.22, 0.12, 0.3), w=128, h=320, seed=9, splits=13,
                            ragged=1.9)
    m["plume"] = hd.material("Kraehe_Kragenfeder", c, n, rough=0.62, normal_strength=0.8, double_sided=True,
                             spec=0.08, alpha_clip=True)
    c, n = tex_feather_card("hackle", (0.1, 0.078, 0.068), sheen, w=64, h=256, seed=8, narrow=0.55, splits=6,
                            ragged=1.6)
    m["hackle"] = hd.material("Kraehe_Halsfeder", c, n, rough=0.66, normal_strength=0.7, double_sided=True,
                              spec=0.08, alpha_clip=True)
    c, n = tex_plumage("plumage", (0.08, 0.062, 0.054), (0.14, 0.08, 0.19), seed=12)
    m["plumage"] = hd.material("Kraehe_Gefieder", c, n, rough=0.7, normal_strength=1.0, spec=0.25)
    c, n = hd.tex_keratin("beak", (0.11, 0.092, 0.076), seed=21, streak=1.3)
    m["beak"] = hd.material("Kraehe_Schnabel", c, n, rough=0.62, normal_strength=0.9, spec=0.3)
    c, n = hd.tex_leather("coat", (0.075, 0.058, 0.052), (0.02, 0.016, 0.015), seed=31, crease=1.1, wear=0.8)
    m["coat"] = hd.material("Kraehe_Mantel", c, n, rough=0.72, normal_strength=1.0, spec=0.25)
    c, n = hd.tex_scales("skin", (0.085, 0.07, 0.062), seed=33, cells=40)
    m["skin"] = hd.material("Kraehe_Haut", c, n, rough=0.55, normal_strength=1.2, spec=0.35)
    c, n = hd.tex_keratin("claw", (0.03, 0.026, 0.026), seed=22, streak=1.5)
    m["claw"] = hd.material("Kraehe_Kralle", c, n, rough=0.3, spec=0.6)
    c, n = hd.tex_leather("gold", (0.62, 0.45, 0.18), (0.22, 0.13, 0.05), size=512, seed=41, crease=0.2, wear=1.6)
    m["gold"] = hd.material("Kraehe_Gold", c, n, rough=0.34, normal_strength=0.8, metal=0.92)
    m["eye"] = hd.material("Kraehe_Auge", color=(0.95, 0.92, 0.85, 1), rough=0.3,
                           emission=(0.95, 0.92, 0.82, 1), emission_strength=1.2)
    m["eyecore"] = hd.material("Kraehe_Augenkern", color=(1.0, 1.0, 0.95, 1), rough=0.3,
                               emission=(1.0, 0.98, 0.92, 1), emission_strength=2.5)
    return m


def finish_cards(mb, spans, name, mat, parent, location=(0, 0, 0)):
    """Federkarten so drehen, dass ihre Vorderseite nach außen zeigt (gleichmäßige Schattierung)."""
    mb.bm.faces.ensure_lookup_table()
    flip = []
    for a0, b0, n in spans:
        if b0 > a0:
            mb.bm.faces[a0].normal_update()
            if mb.bm.faces[a0].normal.dot(n) < 0:
                flip.extend(mb.bm.faces[i] for i in range(a0, b0))
    bmesh.ops.reverse_faces(mb.bm, faces=flip)
    return mb.finish(name, mat, parent=parent, location=location)


def card(mb, spans, p, n, d, L, W, **kw):
    first = len(mb.bm.faces)
    hd.add_feather(mb, p, n, d, L, W, **kw)
    spans.append((first, len(mb.bm.faces), n.copy()))


# =====================================================================================
#  Kopf (Head-Koordinaten, vorne = -Y)
# =====================================================================================

def _seg_dist(x, z, a, b):
    ax_, az = a
    bx, bz = b
    dx, dz = bx - ax_, bz - az
    t = max(0.0, min(1.0, ((x - ax_) * dx + (z - az) * dz) / (dx * dx + dz * dz)))
    return math.hypot(x - (ax_ + t * dx), z - (az + t * dz)), t


def cranium() -> bmesh.types.BMesh:
    """Schädel unter den Federn: flacher Scheitel, Stirn läuft in die Schnabelwurzel,
    kräftiger, schräger Brauenwulst, Augenhöhlen, Kehle hängt in den Hals."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=96, v_segments=64, radius=1.0)
    for v in bm.verts:
        d = v.co.copy()
        p = SKULL_C + Vector((d.x * SKULL_R.x, d.y * SKULL_R.y, d.z * SKULL_R.z))
        if d.z > 0:
            p.z -= 0.014 * d.z ** 2
        if d.y > 0:
            p.y += 0.014 * d.y * (1 - abs(d.z))
        front = max(0.0, -d.y)
        pull = front ** 2.2 * _g(p.z - GAPE - 0.022, 0.042) * _g(p.x, 0.05)
        p.y -= 0.05 * pull
        # Brauenwulst
        for (a, b) in BROW:
            for s in (-1, 1):
                dist, t = _seg_dist(p.x * s, p.z, a, b)
                p += d * 0.016 * front ** 0.7 * _g(dist, 0.011) * (0.7 + 0.3 * t)
        for e in EYES:
            p += -d * 0.008 * _g((p - e).length, 0.013)
        if d.z < -0.3:
            p.z -= 0.04 * (-d.z - 0.3) * max(0.0, 1 - abs(d.x))
            p.y -= 0.012 * (-d.z - 0.3)
        p += d * 0.002 * noise.noise(p * 30)
        v.co = p
    bm.normal_update()
    return bm


def beak_sections(lower: bool, n_len=36, n_round=24):
    secs = []
    L = BEAK_LEN * (0.8 if lower else 1.0)
    for i in range(n_len):
        t = i / (n_len - 1)
        tt = t * (0.8 if lower else 1.0)
        y = BEAK_ROOT - L * t
        droop = -0.052 * tt ** 2
        gape = GAPE + droop - 0.006 * tt
        hook = 0.0
        if not lower:
            k = max(0.0, t - 0.7) / 0.3
            hook = -0.036 * k ** 1.7
            y += 0.012 * max(0.0, t - 0.86) / 0.14 * k
        w = 0.054 * (1 - tt) ** 0.7 + 0.002
        if lower:
            h_top, h_bot = 0.004 * (1 - t), 0.034 * (1 - t) ** 0.7 + 0.002
            w *= 0.92
        else:
            h_top = 0.074 * (1 - t) ** 0.62 + 0.003 + 0.01 * math.sin(math.pi * t)
            h_bot = 0.007 * (1 - t) + 0.0015
        sec = []
        for j in range(n_round):
            a = j / n_round * math.tau
            sa, ca = math.sin(a), math.cos(a)
            if sa >= 0:
                z = gape + hook + h_top * (sa ** 0.85)
                x = w * ca * (1 - (0.32 if not lower else 0.0) * sa ** 2)
            else:
                z = gape + hook - h_bot * ((-sa) ** 0.9)
                x = w * ca * (1 - (0.0 if not lower else 0.25) * sa ** 2)
            if lower:
                z -= 0.003
            sec.append(Vector((x, y, z)))
        secs.append(sec)
    return secs


def head(rig, m, rnd):
    hb = rig.head
    cr = cranium()
    mb = hd.MeshBuilder()
    mb.bm.free()
    mb.bm = cr.copy()
    mb.uv = mb.bm.loops.layers.uv.verify()
    for f in mb.bm.faces:  # Kugel-UVs fürs gekachelte Gefieder
        for loop in f.loops:
            q = loop.vert.co - SKULL_C
            loop[mb.uv].uv = (math.atan2(q.x, -q.y) / math.pi * 2.0, q.z * 9.0)
    face = mb.finish("Face", m["plumage"], parent=hb)

    # Oberschnabel
    mb = hd.MeshBuilder()
    hd.loft(mb, beak_sections(False), uv_scale=(1.0, 2.0))
    mb.finish("Beak", m["beak"], parent=hb)
    # Unterschnabel als Jaw (dreht beim Lachen um die Wurzel)
    mb = hd.MeshBuilder()
    pivot = Vector((0, BEAK_ROOT + 0.01, GAPE - 0.004))
    hd.loft(mb, [[p - pivot for p in s] for s in beak_sections(True)], uv_scale=(1.0, 1.6))
    mb.finish("Jaw", m["beak"], parent=hb, location=pivot)
    # dunkler Rachen zwischen den Schnabelhälften, Nasenlöcher
    voids = [ch.geo.ellipsoid(Vector((0.03, 0.06, 0.007)), Vector((0, BEAK_ROOT - 0.035, GAPE - 0.003)), 20, 10)]
    for s in (-1, 1):
        nb = ch.geo.ellipsoid(Vector((0.004, 0.011, 0.0035)), Vector((0, 0, 0)), 12, 8)
        ch.geo.transform(nb, Matrix.Translation(Vector((s * 0.031, BEAK_ROOT - 0.04, GAPE + 0.042)))
                         @ Matrix.Rotation(s * 0.5, 4, "Y") @ Matrix.Rotation(-0.25, 4, "X"))
        voids.append(nb)
    rig.headpart("Void_Beak", ch.geo.merge(*voids), ch.void(), smooth=True, sharp_angle=None)

    eyes(rig, m)
    head_feathers(rig, m, rnd, cr, face)
    cr.free()


def eyes(rig, m):
    voids, glow, core = [], [], []
    for i, e in enumerate(EYES):
        side = -1 if e.x < 0 else 1
        n = eye_normal(side)
        rot = Vector((0, -1, 0)).rotation_difference(n).to_matrix().to_4x4()
        for lst, radii, off in ((voids, (0.0185, 0.006, 0.0165), -0.002), (glow, (0.0125, 0.006, 0.0115), 0.0005),
                                (core, (0.005, 0.003, 0.005), 0.0045)):
            b = ch.geo.ellipsoid(Vector(radii), Vector((0, 0, 0)), 20, 12)
            ch.geo.transform(b, Matrix.Translation(e + n * off) @ rot)
            lst.append(b)
        rig.marker("EyeL" if side < 0 else "EyeR", rig.head, e + n * 0.003)
    rig.headpart("Void_Sockets", ch.geo.merge(*voids), ch.void(), smooth=True, sharp_angle=None)
    rig.headpart("Glow_Eyes", ch.geo.merge(*glow), m["eye"], smooth=True, sharp_angle=None)
    rig.headpart("Glow_EyeCores", ch.geo.merge(*core), m["eyecore"], smooth=True, sharp_angle=None)


def head_feathers(rig, m, rnd, cr, face):
    hb = rig.head
    fe, fs = hd.MeshBuilder(), []
    hk, hs = hd.MeshBuilder(), []

    def keep(p, nrm):
        if p.y < BEAK_ROOT + 0.016 and abs(p.x) < 0.04 and abs(p.z - GAPE - 0.01) < 0.05:
            return False  # Schnabelwurzel
        return all((p - e).length > 0.021 for e in EYES)

    for p, nrm in hd.sample_surface(cr, 2600, rnd, keep):
        q = p - SKULL_C
        front = max(0.0, min(1.0, (-q.y + 0.02) / 0.12))
        back = max(0.0, min(1.0, q.y / 0.11))
        top = max(0.0, min(1.0, (q.z - 0.04) / 0.07))
        throat = max(0.0, min(1.0, (0.0 - q.z) / 0.07))
        flow = Vector((0, 1, -0.25)).lerp(Vector((0, 0.25, -1)), throat * 0.85)
        flow += Vector((q.x * 2.0, 0, 0))
        L = (0.03 - 0.012 * front + 0.03 * back ** 1.5 + 0.035 * (top * back) ** 1.2) * rnd.uniform(0.85, 1.2)
        lift = rnd.uniform(0.06, 0.13) + 0.25 * (top * back) ** 1.5 + 0.1 * back ** 2
        card(fe, fs, p, nrm, flow, L, L * rnd.uniform(0.3, 0.38), lift=lift, curl=0.04, cup=0.14,
             twist=rnd.uniform(-0.2, 0.2), sink=0.002, along=5, across=3)
    # finstere Brauen: zwei Reihen kurzer Federn entlang des Wulsts, nach außen-hinten gekämmt
    for (a, b) in BROW:
        for s in (-1, 1):
            for row in range(2):
                for k in range(11):
                    t = k / 10
                    x = s * (a[0] + (b[0] - a[0]) * t)
                    z = a[1] + (b[1] - a[1]) * t + 0.004 - row * 0.008
                    p = surf_hit(cr, Vector((x, -0.3, z)), Vector((0, 1, 0)))
                    if p is None:
                        continue
                    pp, nn = p
                    dirv = Vector((s * 1.0, 0.55, 0.25 + 0.2 * t))
                    L = (0.024 + 0.014 * t) * rnd.uniform(0.9, 1.15) * (1.0 if row == 0 else 0.8)
                    card(fe, fs, pp, nn, dirv, L, L * 0.38, lift=0.18 + 0.08 * row, curl=0.02, cup=0.12,
                         twist=rnd.uniform(-0.15, 0.15), sink=0.001)
    # winzige Federn rund um die Augen
    for e in EYES:
        side = -1 if e.x < 0 else 1
        n = eye_normal(side)
        dd, ss, _ = hd.frame(n, Vector((0, 0, 1)))
        for k in range(18):
            a = k / 18 * math.tau
            r = dd * math.cos(a) + ss * math.sin(a)
            card(fe, fs, e + r * 0.0195 - n * 0.002, n, r, 0.011, 0.005, lift=0.2, curl=0.0, cup=0.08)
    # Nasenborsten über der Schnabelwurzel
    for k in range(60):
        t = rnd.uniform(0.0, 0.3)
        x = rnd.uniform(-0.03, 0.03) * (1 - t)
        y = BEAK_ROOT - BEAK_LEN * t + 0.016
        z = GAPE - 0.052 * t * t + 0.06 * (1 - t) ** 0.9 + 0.004 - (x / 0.032) ** 2 * 0.022
        nrm = Vector((x * 8, -0.1, 1)).normalized()
        L = rnd.uniform(0.035, 0.055)
        card(fe, fs, Vector((x, y, z)), nrm, Vector((x * 2, -1, -0.2)), L, L * 0.28, lift=0.07, curl=0.02,
             cup=0.12)
    # zottige Kehlfedern
    for p, nrm in hd.sample_surface(cr, 520, rnd, lambda p, n: p.z < SKULL_C.z - 0.03 and n.z < 0.3):
        L = rnd.uniform(0.055, 0.1)
        card(hk, hs, p, nrm, Vector((rnd.uniform(-0.25, 0.25), 0.1, -1)), L, L * 0.2, lift=rnd.uniform(0.08, 0.22),
             curl=0.04, cup=0.08, twist=rnd.uniform(-0.3, 0.3), along=6, across=2)
    hd.shade_like(finish_cards(fe, fs, "Head_Feathers", m["feather"], hb), face, 0.75)
    hd.shade_like(finish_cards(hk, hs, "Head_Hackles", m["hackle"], hb), face, 0.6)


def surf_hit(bm, origin, direction):
    from mathutils.bvhtree import BVHTree
    tree = getattr(surf_hit, "_tree", None)
    if tree is None or getattr(surf_hit, "_bm", None) is not bm:
        surf_hit._tree = tree = BVHTree.FromBMesh(bm)
        surf_hit._bm = bm
    hit = tree.ray_cast(origin, direction)
    if hit[0] is None:
        return None
    return hit[0], hit[1]


# =====================================================================================
#  Körper (Torso-Koordinaten)
# =====================================================================================

PROFILE = [(0.26, -0.15), (0.27, 0.1), (0.275, 0.45), (0.285, 0.72), (0.29, 0.86), (0.275, 0.96),
           (0.22, 1.04), (0.16, 1.08), (0.1, 1.1), (0.03, 1.105)]
SX, SY, HUNCH, BUMP = 1.45, 0.8, 0.08, 0.025


def _radius(z):
    if z <= PROFILE[0][1]:
        return PROFILE[0][0]
    for (r0, z0), (r1, z1) in zip(PROFILE, PROFILE[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            t = t * t * (3 - 2 * t)
            return r0 + (r1 - r0) * t
    return PROFILE[-1][0]


def body_point(th, z, out=0.0, folds=True):
    """Punkt auf dem Mantel. th: Winkel (3π/2 = vorne, -Y), out: Abstand nach außen."""
    r = _radius(z)
    fold = 0.0
    if folds:
        amp = 0.012 * min(1.0, max(0.0, (0.9 - z) / 0.5)) + 0.002
        warp = noise.noise(Vector((math.cos(th) * 2.0, math.sin(th) * 2.0, z * 1.3))) * 1.6
        fold = amp * (0.65 * math.sin(th * 9 + warp) + 0.35 * math.sin(th * 19 + warp * 1.7 + 1.0))
    rr = r + fold + out
    x = rr * SX * math.cos(th)
    y = rr * SY * math.sin(th)
    if z > 0.72:
        y -= HUNCH * min(1.0, (z - 0.72) / 0.4) * max(0.0, 1 - abs(x) / 0.5)
    z += BUMP * _g(abs(x) - 0.33, 0.075) * _g(z - 1.0, 0.07)
    return Vector((x, y, z))


def body_normal(th, z):
    e = 0.004
    p = body_point(th, z, folds=False)
    a = body_point(th + e, z, folds=False) - p
    b = body_point(th, z + e, folds=False) - p
    n = a.cross(b).normalized()
    return n if n.dot(Vector((p.x, p.y, 0))) >= 0 else -n


def theta_front(x, z):
    r = _radius(z) * SX
    return math.tau - math.acos(max(-0.999, min(0.999, x / r)))


def mantle_bottom(th):
    x = math.cos(th)
    center = max(0.0, -math.sin(th)) * _g(x, 0.45)
    return 0.6 + 0.1 * center, center


MANTLE_OUT = 0.022


NECK_Z, NECK_R = 1.19, 0.092


def shell_point(th, u):
    """Unterlage des Federkragens: u = 0 Unterkante, u = 1 oben am Hals (schmiegt sich an)."""
    z0, _c = mantle_bottom(th)
    z = z0 + (1.06 - z0) * min(1.0, u / 0.8)
    p = body_point(th, z, out=MANTLE_OUT * (0.4 + 0.6 * u) + 0.012 * (1 - u), folds=False)
    w = max(0.0, (u - 0.65) / 0.35)
    w = w * w * (3 - 2 * w)
    q = Vector((NECK_R * 1.05 * math.cos(th), -0.03 + NECK_R * 0.92 * math.sin(th), NECK_Z))
    return p.lerp(q, w)


def shell_normal(th, u):
    e = 0.003
    p = shell_point(th, u)
    a = shell_point(th + e, u) - p
    b = shell_point(th, u + e) - p
    n = a.cross(b).normalized()
    return n if n.dot(Vector((p.x, p.y + 0.02, 0))) >= 0 else -n


def body(rig, m, rnd):
    tb = rig.torso
    zs = [-0.15 + i * 0.0105 for i in range(120)] + [1.1, 1.105]
    seg = 128
    rows, uvs = [], []
    for z in zs:
        rows.append([body_point(j / seg * math.tau, z) for j in range(seg)])
        uvs.append([(j / seg * 5.0, z * 2.5) for j in range(seg)])
    mb = hd.MeshBuilder()
    mb.grid(rows, uvs, close=True)
    mb.finish("Body", m["coat"], parent=tb)
    for side in (-1, 1):
        rig.marker("Shoulder_L" if side < 0 else "Shoulder_R", tb, Vector((side * 0.34, 0.02, 0.95)))

    # Hals (Gefieder) bis unter den Kopf
    neck = hd.MeshBuilder()
    nrows, nuvs = [], []
    for i in range(16):
        t = i / 15
        z = 0.98 + t * 0.32
        r = 0.115 - 0.025 * t
        cy = -0.035 * t
        nrows.append([Vector((r * math.cos(a), cy + r * 0.9 * math.sin(a), z)) for a in
                      (k / 32 * math.tau for k in range(32))])
        nuvs.append([(k / 32 * 3, t * 3) for k in range(32)])
    neck.grid(nrows, nuvs, close=True)
    nbm = neck.bm.copy()
    neck_ob = neck.finish("Body_Neck", m["plumage"], parent=tb)
    hk, hs = hd.MeshBuilder(), []
    for p, nrm in hd.sample_surface(nbm, 800, rnd, lambda p, n: p.z > 1.04):
        L = rnd.uniform(0.07, 0.12)
        card(hk, hs, p, nrm, Vector((rnd.uniform(-0.3, 0.3), 0.15, -1)), L, L * 0.2, lift=rnd.uniform(0.08, 0.2),
             curl=0.04, cup=0.08, twist=rnd.uniform(-0.3, 0.3), along=6, across=2)
    nbm.free()
    hd.shade_like(finish_cards(hk, hs, "Body_Neck_Hackles", m["hackle"], tb), neck_ob, 0.6)

    mantle(rig, m, rnd)
    chains(rig, m, rnd)
    for s in (-1, 1):
        brooch(rig, m, s)


def mantle(rig, m, rnd):
    """Federkragen: geschlossene Unterlage (Gefieder) plus viele Federkarten in Lagen –
    an den Schultern lang, gezackt und abstehend, auf der Brust klein und anliegend."""
    tb = rig.torso
    mb = hd.MeshBuilder()
    rows, uvs = [], []
    n_a, n_t = 128, 26
    for i in range(n_t + 1):
        t = i / n_t
        row, uvr = [], []
        for j in range(n_a):
            th = j / n_a * math.tau
            p = shell_point(th, t)
            row.append(p)
            uvr.append((j / n_a * 6, p.z * 3.5))
        rows.append(row)
        uvs.append(uvr)
    mb.grid(rows, uvs, close=True)
    shell = mb.finish("Body_Mantle", m["plumage"], parent=tb)
    mod = shell.modifiers.new("Dicke", "SOLIDIFY")
    mod.thickness = 0.008

    big, bs = hd.MeshBuilder(), []
    small, ss = hd.MeshBuilder(), []
    # Lagen von unten nach oben; jede Lage überdeckt die Ansätze der darunter
    layers = 15
    for k in range(layers):
        u = k / (layers - 1)  # 0 = unterste Lage
        count = int(150 - 50 * u)
        for i in range(count):
            th = (i + rnd.random() * 0.8) / count * math.tau
            z0, center = mantle_bottom(th)
            uu = min(0.97, 0.06 + 0.92 * u + rnd.uniform(-0.015, 0.015))
            n = shell_normal(th, uu)
            p = shell_point(th, uu) + n * 0.003
            z = p.z
            ax = abs(p.x)
            shoulder = _g(ax - 0.36, 0.13) * _g(z - 0.92, 0.18)
            down = Vector((0, 0, -1))
            out_dir = Vector((n.x, n.y, 0)).normalized() if Vector((n.x, n.y, 0)).length > 1e-4 else n
            flow = down + out_dir * (0.15 + 0.35 * shoulder) + Vector((p.x, 0, 0)) * 0.6
            if uu > 0.82:  # Halskrause: lang, schmal, steht etwas ab
                L = rnd.uniform(0.08, 0.12)
                card(small, ss, p, n, flow, L, L * 0.26, lift=rnd.uniform(0.1, 0.2), curl=0.03, cup=0.1,
                     twist=rnd.uniform(-0.3, 0.3), sink=0.002, along=6)
                continue
            if center > 0.3 and z < 1.0:
                L = rnd.uniform(0.045, 0.07)
                card(small, ss, p, n, flow, L, L * 0.36, lift=rnd.uniform(0.03, 0.07), curl=0.03, cup=0.14,
                     twist=rnd.uniform(-0.2, 0.2), sink=0.002)
                continue
            L = (0.09 + 0.13 * shoulder + 0.03 * (1 - u)) * rnd.uniform(0.75, 1.25)
            lift = rnd.uniform(0.12, 0.25) + 0.22 * shoulder
            card(big, bs, p, n, flow, L, L * rnd.uniform(0.26, 0.33), lift=lift, curl=rnd.uniform(-0.06, 0.04),
                 cup=0.12, twist=rnd.uniform(-0.35, 0.35), sink=0.004, along=6, across=3)
    hd.shade_like(finish_cards(big, bs, "Body_Plumes", m["plume"], tb), shell, 0.55)
    hd.shade_like(finish_cards(small, ss, "Body_Feathers", m["feather"], tb), shell, 0.7)


def _chain_link(c, tan, axis2, L, W, wire):
    pts = [c + tan * math.cos(a) * L * 0.5 + axis2 * math.sin(a) * W * 0.5
           for a in (k / 24 * math.tau for k in range(25))]
    return ch.geo.tube(pts, [wire] * 25, seg=8, cap_start=False)


def chain_along(path_pts, normals, L, W, wire):
    """Glieder entlang einer Kurve, abwechselnd stehend und liegend, ineinander greifend."""
    seglen = [(b - a).length for a, b in zip(path_pts, path_pts[1:])]
    total = sum(seglen)
    step = L - wire * 2.6
    links = []
    s, k = step * 0.5, 0
    while s < total - step * 0.5:
        acc, i = 0.0, 0
        while i < len(seglen) - 1 and acc + seglen[i] < s:
            acc += seglen[i]
            i += 1
        t = (s - acc) / max(seglen[i], 1e-6)
        c = path_pts[i].lerp(path_pts[i + 1], t)
        n = normals[i].lerp(normals[i + 1], t).normalized()
        tan = (path_pts[i + 1] - path_pts[i]).normalized()
        side = tan.cross(n).normalized()
        links.append(_chain_link(c, tan, n if k % 2 else side, L, W, wire))
        s += step
        k += 1
    return links


BROOCH = (0.205, 0.99)


def chains(rig, m, rnd):
    """Drei schwere Goldketten von Fibel zu Fibel, unterschiedlich tief durchhängend."""
    links = []
    for k, (sag, L, W, wire, out) in enumerate(((0.06, 0.036, 0.023, 0.0048, 0.05), (0.11, 0.032, 0.021, 0.0042, 0.055),
                                                (0.16, 0.03, 0.019, 0.004, 0.052))):
        pts, nrm = [], []
        span = BROOCH[0] - 0.01 - 0.012 * k
        for i in range(61):
            t = i / 60
            x = -span + 2 * span * t
            z = BROOCH[1] - 0.025 - sag * math.sin(t * math.pi) ** 1.15
            th = theta_front(x, z)
            pts.append(body_point(th, z, out=out + 0.045 * (abs(x) / span) ** 3, folds=False))
            nrm.append(body_normal(th, z))
        links += chain_along(pts, nrm, L, W, wire)
    # kürzere Kette eng um den Hals
    pts, nrm = [], []
    for i in range(61):
        t = i / 60
        a = math.radians(-160 + 140 * t)
        r = NECK_R + 0.05
        p = Vector((r * 1.05 * math.cos(a), -0.03 + r * 0.92 * math.sin(a), 1.1 - 0.05 * math.sin(t * math.pi)))
        pts.append(p)
        nrm.append(Vector((math.cos(a), math.sin(a), 0.3)).normalized())
    links += chain_along(pts, nrm, 0.026, 0.017, 0.0036)
    rig.body("Body_Chains", ch.geo.merge(*links), m["gold"], smooth=True, sharp_angle=None)


def brooch(rig, m, side):
    """Runde Zierfibel: gewölbte Scheibe, Perlrand, Ring, Spiralranken, Buckel in der Mitte."""
    x, z = side * BROOCH[0], BROOCH[1]
    th = theta_front(x, z)
    p = body_point(th, z, out=0.1, folds=False)
    n = body_normal(th, z)
    n = (n + Vector((0, -0.35, 0.1))).normalized()
    parts = [ch.geo.lathe([(0.0, -0.006), (0.047, -0.006), (0.049, 0.0), (0.046, 0.004), (0.03, 0.007),
                           (0.0, 0.008)], 48, 0.1)]
    for k in range(22):
        a = k / 22 * math.tau
        parts.append(ch.geo.ellipsoid(Vector((0.0042,) * 3), Vector((math.cos(a) * 0.043, math.sin(a) * 0.043, 0.005)),
                                      10, 6))
    ring = [Vector((math.cos(a) * 0.031, math.sin(a) * 0.031, 0.008)) for a in (k / 40 * math.tau for k in range(41))]
    parts.append(ch.geo.tube(ring, [0.0028] * 41, seg=8, cap_start=False))
    for k in range(6):
        a0 = k / 6 * math.tau
        sp = []
        for i in range(12):
            t = i / 11
            a = a0 + t * 2.2
            r = 0.012 + 0.015 * t
            sp.append(Vector((math.cos(a) * r, math.sin(a) * r, 0.009 + 0.002 * math.sin(t * math.pi))))
        parts.append(ch.geo.tube(sp, [0.0022 + 0.0008 * math.sin(t * math.pi) for t in (i / 11 for i in range(12))],
                                 seg=6))
    parts.append(ch.geo.ellipsoid(Vector((0.012, 0.012, 0.009)), Vector((0, 0, 0.01)), 18, 10))
    bm = ch.geo.merge(*parts)
    rot = Vector((0, 0, 1)).rotation_difference(n).to_matrix().to_4x4()
    ch.geo.transform(bm, Matrix.Translation(p) @ rot @ Matrix.Rotation(side * 0.3, 4, "Z"))
    rig.body("Body_Brooch_" + ("L" if side < 0 else "R"), bm, m["gold"], smooth=True, sharp_angle=None)


# =====================================================================================
#  Hände und Ärmel
# =====================================================================================

def hands_and_sleeve(rig, m, rnd):
    hands = [hd.grip_hand(side, m["skin"], None, size=1.14, thick=1.0, knobby=0.6, finger_len=1.2,
                          claw=0.015, claw_mat=m["claw"], bony=False, pitch=-0.45, wrist_back=0.06, wrist_up=0.0)
             for side in (-1, 1)]
    for side, h in zip((-1, 1), hands):
        h.location = G(side * 0.09, 0.9, 0.22)
    upper = hd.sleeve_segment("SleeveUpper", m["coat"], 0.1, 0.088, folds=1.2, bunch_end=1.0, seed=5)
    fore = hd.sleeve_segment("SleeveFore", m["coat"], 0.082, 0.07, cuff=0.014, folds=1.0, seed=6)
    hd.preview_arms(upper, fore, hands[0], hands[1])


# =====================================================================================

def scale_head(rig, s):
    for ob in rig.head.children:
        ob.location = C + (Vector(ob.location) - C) * s
        if ob.type == "MESH":
            ob.data.transform(Matrix.Scale(s, 4))


def build(steps=("head", "body", "hands"), seed=7):
    rnd = random.Random(seed)
    if set(steps) >= {"head", "body", "hands"}:
        hd.clear_scene()
    surf_hit._tree = None
    rig = ch.Rig(HEAD_Y)
    m = materials()
    if "head" in steps:
        head(rig, m, rnd)
        scale_head(rig, HEAD_SCALE)
    if "body" in steps:
        body(rig, m, rnd)
    if "hands" in steps:
        hands_and_sleeve(rig, m, rnd)
    return rig
