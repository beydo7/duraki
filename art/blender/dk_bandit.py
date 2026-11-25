"""Der Bandit – Überarbeitung (nach dem Konzeptbild „Am Spieltisch“, Feld 1).

Grobschlächtiger Kerl mit schwerer Stirn, breiter Nase und stechendem Blick; Fellmütze (Uschanka),
rotes Halstuch über Mund und Nase, Strickpullover, Lammfellmantel mit Fellkragen, große Hände.

    import dk_bandit; dk_bandit.build()
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
import numpy as np
from mathutils import Vector, noise

import dk
import geo
import hd

MACRO = dict(gender=1.0, age=0.64, muscle=0.7, weight=0.66, height=0.5, proportions=0.45,
             race={"asian": 0.1, "caucasian": 0.9, "african": 0.0})
TARGETS = {
    # schwere, zusammengezogene Stirn
    "eyebrows-angle-down": 1.0, "eyebrows-trans-down": 0.8, "eyebrows-trans-forward": 0.7,
    "forehead-trans-forward": 0.3, "forehead-scale-vert-decr": 0.4,
    **dk.both("eye-eyefold-down", 0.45), **dk.both("eye-bag-incr", 0.6), **dk.both("eye-corner2-up", 0.3),
    # breite, knollige Nase mit Höcker
    "nose-volume-incr": 1.0, "nose-width2-incr": 0.9, "nose-width3-incr": 0.9, "nose-hump-incr": 0.6,
    "nose-point-width-incr": 1.0, "nose-scale-depth-incr": 0.45, "nose-flaring-incr": 0.6, "nose-point-down": 0.35,
    # kantiger Schädel, kräftige Wangenknochen und Kiefer
    "head-square": 0.7, "head-fat-incr": 0.25, **dk.both("cheek-bones-incr", 0.8), "chin-width-incr": 0.6,
    "chin-bones-incr": 0.6, "chin-prominent-incr": 0.3, "mouth-angles-down": 0.6, "mouth-scale-horiz-incr": 0.3,
    "neck-scale-horiz-incr": 0.6, "neck-scale-depth-incr": 0.4, **dk.both("ear-scale-incr", 0.3),
    # große, kräftige Hände
    **dk.both("hand-fingers-diameter-incr", 1.0), **dk.both("hand-scale-incr", 0.6),
    "asym-nose-1-l": 0.2, "asym-brown-1-r": 0.3,
}


def materials(parts):
    m = {}
    try:
        bump = dk.data_file("skins/middleage_caucasian_male/*bump*.png")
    except FileNotFoundError:
        bump = None
    c, n = dk.skin_textures("skin", dk.data_file("skins/middleage_caucasian_male/*diffuse*.png"),
                            tint=(0.56, 0.43, 0.36), gain=0.72, contrast=1.25, saturation=0.9, bump_path=bump, bump=3.5,
                            pores=1.2)
    m["skin"] = hd.material("Bandit_Haut", c, n, rough=0.74, normal_strength=1.2, spec=0.22)
    try:
        eye = bpy.data.images.load(dk.data_file("eyes/**/*ice*.png"), check_existing=True)
    except FileNotFoundError:
        eye = dk.part_image(parts["eyes"])
    m["eye"] = hd.material("Bandit_Auge", eye, rough=0.12, spec=0.7)
    m["brow"] = hd.material("Bandit_Braue", dk.part_image(parts["brows"]), rough=0.8, spec=0.1, alpha_clip=True,
                            double_sided=True)
    c, n = hd.tex_cloth("scarf", (0.5, 0.07, 0.05), (0.2, 0.02, 0.02), seed=21, weave=110, rag=0.15)
    m["scarf"] = hd.material("Bandit_Halstuch", c, n, rough=0.88, normal_strength=0.8, spec=0.2, double_sided=True)
    c, n = dk.tex_knit("knit", (0.62, 0.55, 0.42), (0.25, 0.2, 0.14))
    m["knit"] = hd.material("Bandit_Strick", c, n, rough=0.92, normal_strength=1.4, spec=0.2)
    c, n = hd.tex_leather("coat", (0.4, 0.26, 0.13), (0.2, 0.12, 0.06), seed=31, crease=0.6, wear=0.5)
    m["coat"] = hd.material("Bandit_Mantel", c, n, rough=0.78, normal_strength=0.9, spec=0.25, double_sided=True)
    m["hat_imgs"] = dk.tex_fur_shells("hatfur", (0.17, 0.11, 0.065), (0.47, 0.34, 0.21), shells=14, seed=11)
    m["wool_imgs"] = dk.tex_fur_shells("wool", (0.4, 0.32, 0.2), (0.78, 0.68, 0.5), shells=10, clumps=520, radius=7.5,
                                      seed=12)
    m["scar"] = hd.material("Bandit_Narbe", color=(0.3, 0.15, 0.13, 1), rough=0.8, spec=0.1)
    m["tooth"] = hd.material("Bandit_Zahn", color=(0.62, 0.5, 0.26, 1), rough=0.45, spec=0.4)
    m["plain"] = hd.material("Bandit_Unterfell", color=(0.1, 0.06, 0.03, 1), rough=0.95)
    return m


def hat(fig, m, hm):
    """Uschanka: Kuppel, dicke Stirnkrempe, herabhängende Ohrenklappen – ganz aus Fell."""
    c = Vector((0, hm["yc"], hm["eye"] + 0.115))
    Rx, Ry, Rz = hm["x"] + 0.03, (hm["yb"] - hm["yf"]) * 0.5 + 0.03, hm["top"] - c.z + 0.05
    dome = geo.ellipsoid(Vector((Rx, Ry, Rz)), c, 48, 32)
    for v in dome.verts:
        if v.co.z < c.z:
            back = max(0.0, (v.co.y - c.y) / Ry)
            v.co.z = c.z - (c.z - v.co.z) * (0.12 + 0.5 * back)
    parts = [dome]
    pts, rad = [], []
    for k in range(25):
        a = math.radians(-98 + k * 196 / 24)
        pts.append(c + Vector(((Rx + 0.012) * math.sin(a), -(Ry + 0.012) * math.cos(a), 0.03 + 0.02 * math.cos(a))))
        rad.append(0.028 + 0.02 * math.sin(math.pi * k / 24) ** 0.5)
    parts.append(geo.tube(pts, rad, seg=14))
    for s in (-1, 1):
        parts.append(geo.ellipsoid(Vector((0.04, 0.09, 0.16)), c + Vector((s * (Rx + 0.002), 0.03, -0.15)), 20, 16))
    base = geo.to_object("Hat", geo.merge(*parts), m["plain"], smooth=True, sharp_angle=None)
    base.parent = fig.rig.head
    hd.organic(base, voxel=0.008, smooth=4, faces=2600, uv_tile=0.09)
    dk.shell_fur(base, "Hat_Fur", "Bandit_Fell", m["hat_imgs"], length=0.034, lean=(0, 0.05, -0.3))
    bpy.data.objects.remove(base, do_unlink=True)


def bandana(fig, m, hm, tree):
    """Rotes Halstuch: spannt sich vom Nasenrücken über das Kinn und fällt in Falten auf die Brust."""
    axis = Vector((0, hm["yc"] - 0.02, 0))
    ze, zc = hm["eye"], hm["chin"]
    n_a, n_t = 80, 44
    amax = math.radians(118)
    z0 = ze - 0.36 * (ze - zc)
    R = np.full((n_t + 1, n_a + 1), np.nan)
    Z = np.zeros_like(R)
    A = np.zeros_like(R)
    for j in range(n_a + 1):
        a = -amax + 2 * amax * j / n_a
        d = Vector((math.sin(a), -math.cos(a), 0))
        zt = z0 + 0.085 * (1 - math.cos(a))
        zb = zc - 0.075 - 0.05 * max(0.0, math.cos(a * 0.75)) ** 2
        for i in range(n_t + 1):
            z = zt + (zb - zt) * i / n_t
            Z[i, j], A[i, j] = z, a
            if z > zc - 0.012:
                hit = tree.ray_cast(axis + d * 0.7 + Vector((0, 0, z)), -d)
                if hit[0] is not None:
                    R[i, j] = 0.7 - hit[3]
    fallback = hm["x"] * 0.8
    for j in range(n_a + 1):  # unter dem Kinn hängt das Tuch gerade herab
        last = fallback
        for i in range(n_t + 1):
            if np.isnan(R[i, j]):
                R[i, j] = last
            else:
                last = R[i, j]
    P = np.pad(R, ((3, 3), (1, 1)), mode="edge")  # Zelt: Tuch spannt über Mulden (Nase → Kinn)
    R = np.max([P[3 + di:3 + di + n_t + 1, 1 + dj:1 + dj + n_a + 1] for di in range(-3, 4) for dj in (-1, 0, 1)], axis=0)
    for _ in range(3):
        P = np.pad(R, 1, mode="edge")
        R = (P[1:-1, 1:-1] * 2 + P[:-2, 1:-1] + P[2:, 1:-1] + P[1:-1, :-2] + P[1:-1, 2:]) / 6
    drape = np.clip((zc - Z) / 0.08, 0, 1)
    fold = 0.0035 * np.sin(Z * 75 + A * 2.5) * (1 - drape) + 0.006 * drape * np.sin(A * 7 + 1.0 * np.sin(Z * 14))
    rr = (R + 0.007 + fold) * (1 - 0.3 * drape ** 2)  # unten in den Kragen gesteckt
    mb = hd.MeshBuilder()
    rows = [[axis + Vector((math.sin(A[i, j]) * rr[i, j], -math.cos(A[i, j]) * rr[i, j], Z[i, j])) for j in range(n_a + 1)]
            for i in range(n_t + 1)]
    uvs = [[(j / n_a * 6, i / n_t * 4) for j in range(n_a + 1)] for i in range(n_t + 1)]
    mb.grid(rows, uvs)
    # Riss über dem Mund: ausgefranstes Loch, dahinter gefletschte Zähne
    zm = mouth_z(tree, ze)

    def torn(a, z):
        u = a / 0.5
        if abs(u) >= 1:
            return False
        half = 0.021 * (1 - u * u) ** 0.6 + 0.007 * noise.noise(Vector((a * 14, z * 30, 2.0)))
        mid = zm - 0.004 - 0.012 * u * u + 0.004 * math.sin(a * 23)
        return abs(z - mid) < half
    doomed = []
    for f in mb.bm.faces:
        c = f.calc_center_median() - axis
        if torn(math.atan2(c.x, -c.y), c.z):
            doomed.append(f)
    bmesh.ops.delete(mb.bm, geom=doomed, context="FACES")
    mouth(fig, m, tree, zm)
    ob = mb.finish("Scarf", m["scarf"], parent=fig.rig.head)
    ob.modifiers.new("Dicke", "SOLIDIFY").thickness = 0.004
    hem = geo.tube([p + Vector((0, 0, 0.001)) for p in rows[0]], [0.006] * (n_a + 1), seg=8)
    fig.rig.headpart("Scarf_Hem", hem, m["scarf"], smooth=True, sharp_angle=None)


def mouth_z(tree, ze):
    """Höhe der Mundspalte: Profil in der Gesichtsmitte abtasten (Nasenspitze → Oberlippe)."""
    zs = [ze - 0.002 * i for i in range(130)]
    ys = []
    for z in zs:
        hit = dk.surface(tree, 0.0, z)
        ys.append(hit[0].y if hit else 9.0)
    i = min(range(len(ys)), key=lambda k: ys[k])        # Nasenspitze
    while i < len(ys) - 2 and ys[i + 1] >= ys[i]:        # zurück bis unter die Nase
        i += 1
    while i < len(ys) - 2 and ys[i + 1] <= ys[i]:        # vor bis zur Oberlippe
        i += 1
    return zs[i] - 0.014


def mouth(fig, m, tree, zm):
    """Hinter dem Riss: dunkler Mund und ein schiefes Gebiss (Unterkiefer vorgeschoben, zwei Hauer)."""
    hb = fig.rig.head
    bm = bmesh.new()
    cols = []
    for k in range(17):
        x = (k / 16 * 2 - 1) * 0.062
        col = []
        for dz in (0.03, 0.01, -0.012, -0.034):
            hit = dk.surface(tree, x, zm + dz, lift=0.002)
            col.append(bm.verts.new(hit[0] if hit else Vector((x, -0.2, zm + dz))))
        cols.append(col)
    for k in range(16):
        for r in range(3):
            bm.faces.new((cols[k][r], cols[k + 1][r], cols[k + 1][r + 1], cols[k][r + 1]))
    fig.rig.headpart("Void_Mouth", bm, dk.ch.void(), smooth=True, sharp_angle=None)
    rnd = random.Random(5)
    teeth = []
    for k in range(9):
        u = k / 8 * 2 - 1
        x = u * 0.047 + rnd.uniform(-0.002, 0.002)
        big = k in (2, 6)
        h = (0.03 if big else rnd.uniform(0.013, 0.02))
        w = 0.0062 if big else rnd.uniform(0.0045, 0.0058)
        hit = dk.surface(tree, x, zm - 0.02, lift=0.0055)
        if not hit:
            continue
        p, n = hit
        tip = p + Vector((rnd.uniform(-0.003, 0.003), 0, h)) + n * 0.002
        teeth.append(geo.tube([p - Vector((0, 0, 0.004)), p.lerp(tip, 0.55), tip], [w, w * 0.85, w * (0.35 if big else 0.55)],
                              seg=8))
    for k in range(7):  # obere Reihe, kürzer, halb vom Tuch verdeckt
        u = k / 6 * 2 - 1
        hit = dk.surface(tree, u * 0.04, zm + 0.014, lift=0.004)
        if hit:
            p = hit[0]
            teeth.append(geo.tube([p + Vector((0, 0, 0.004)), p - Vector((0, 0, rnd.uniform(0.008, 0.013)))],
                                  [0.0052, 0.004], seg=8))
    fig.rig.headpart("Mouth_Teeth", geo.merge(*teeth), m["tooth"], smooth=True, sharp_angle=None)


def scar(fig, m, tree, eye):
    """Alte Narbe über dem linken Auge (vom Spieler aus): von der Stirn durch die Braue bis auf die Wange."""
    parts = []
    for pts in ([(-0.03, 0.085), (-0.027, 0.072), (-0.022, 0.06), (-0.017, 0.047), (-0.012, 0.035), (-0.006, 0.02)],
                [(0.004, -0.022), (0.008, -0.034), (0.012, -0.045), (0.015, -0.058), (0.016, -0.07), (0.014, -0.09)]):
        path = []
        for dx, dz in pts:
            hit = dk.surface(tree, eye.x + dx + 0.002 * math.sin(dz * 190), eye.z + dz, lift=-0.0009)
            if hit:
                path.append(hit[0])
        if len(path) > 2:
            n = len(path)
            parts.append(geo.tube(path, [0.0012 + 0.0016 * math.sin(math.pi * (k + 0.5) / n) for k in range(n)], seg=8))
    if parts:
        fig.rig.headpart("Face_Scar", geo.merge(*parts), m["scar"], smooth=True, sharp_angle=None)


def clothes(fig, m, skin_ob):
    tb = fig.rig.torso
    pb = fig.mrig.pose.bones
    nc = dk.to_torso(pb["neck01"].head)
    # Strickpullover: eng anliegend
    bm = bmesh.new()
    bm.from_mesh(skin_ob.data)
    dk.inflate(bm, 0.012, 1)
    geo.box_uv(bm, 0.2)
    dk.to_object("Body", bm, m["knit"], tb)
    ring = [nc + Vector((0.125 * math.cos(a), 0.01 + 0.13 * math.sin(a), 0.045)) for a in
            (k / 32 * math.tau for k in range(33))]
    roll = geo.tube(ring, [0.034] * 33, seg=12, cap_start=False)
    geo.box_uv(roll, 0.2)
    fig.rig.body("Body_Rollkragen", roll, m["knit"], smooth=True, sharp_angle=None)
    # Mantel: weiter, vorne offen
    bm = bmesh.new()
    bm.from_mesh(skin_ob.data)
    dk.inflate(bm, 0.036, 3)

    def open_w(z):
        return 0.05 + 0.13 * min(1.0, max(0.0, (z - 0.6) / 0.5)) ** 1.4

    def keep(f):
        c = f.calc_center_median()
        if c.y < nc.y + 0.02 and abs(c.x) < open_w(c.z):
            return False
        return not (c.z > nc.z - 0.03 and math.hypot(c.x, c.y - nc.y) < 0.21)
    dk.keep_faces(bm, keep)
    dk.smooth_boundary(bm)
    geo.box_uv(bm, 0.3)
    coat = dk.to_object("Body_Coat", bm, m["coat"], tb)
    tree = dk.bvh(coat)
    coat.modifiers.new("Dicke", "SOLIDIFY").thickness = -0.014
    # Fellkragen: entlang der Öffnung und um den Nacken
    left = []
    z1 = nc.z - 0.04
    for k in range(9):
        z = 0.62 + (z1 - 0.62) * k / 8
        x = open_w(z) + 0.012
        hit = tree.ray_cast(Vector((x, -1.5, z)), Vector((0, 1, 0)))
        y = hit[0].y if hit[0] is not None else nc.y - 0.12
        left.append(Vector((x, y - 0.012, z)))
    arc = []
    for k in range(13):
        phi = math.radians(108 + k * (144 / 12))  # von rechts-vorn über den Nacken nach links-vorn
        arc.append(nc + Vector((0.2 * math.sin(phi), -0.19 * math.cos(phi) + 0.01, 0.035)))
    path = left + [left[-1].lerp(arc[0], 0.5) + Vector((0.01, 0, 0.02))] + arc
    mirror = [Vector((-p.x, p.y, p.z)) for p in reversed(left)]
    path += [arc[-1].lerp(mirror[0], 0.5) + Vector((-0.01, 0, 0.02))] + mirror
    n = len(path)
    rad = [0.03 + 0.03 * math.sin(math.pi * k / (n - 1)) ** 0.4 for k in range(n)]
    base = geo.to_object("Collar", geo.tube(path, rad, seg=14), m["plain"], smooth=True, sharp_angle=None)
    base.parent = tb
    hd.organic(base, voxel=0.009, smooth=3, faces=2200, uv_tile=0.1)
    dk.shell_fur(base, "Body_Collar_Fur", "Bandit_Lammfell", m["wool_imgs"], length=0.026, lean=(0, 0, -0.2))
    bpy.data.objects.remove(base, do_unlink=True)


def build():
    hd.clear_scene()
    body, mrig, parts = dk.make_human(MACRO, TARGETS, brows="eyebrow010", lashes=None, teeth=None, eyes="low-poly")
    for sfx, s in ((".L", 1), (".R", -1)):
        dk.aim_arm(mrig, sfx, Vector((s * 0.3, -0.72, -0.62)))
        dk.grip_pose(mrig, sfx)
    m = materials(parts)
    fig = dk.Figure(body, mrig, parts, head_scale=1.12)
    face = fig.head(m["skin"])
    fig.eye_markers()
    fig.head_part("eyes", "Eye_Balls", m["eye"])
    fig.head_part("brows", "Face_Brows", m["brow"])
    hm = dk.head_metrics(face, bpy.data.objects["EyeL"].location.z)
    hat(fig, m, hm)
    ftree = dk.bvh(face)
    bandana(fig, m, hm, ftree)
    scar(fig, m, ftree, bpy.data.objects["EyeL"].location)
    skin_ob = fig.torso(m["skin"], arm_stub=0.055)
    clothes(fig, m, skin_ob)
    bpy.data.objects.remove(skin_ob, do_unlink=True)
    hands = fig.hands(m["skin"], scale=1.3)
    upper = dk.sleeve("SleeveUpper", m["coat"], [(0, 0.132), (0.5, 0.122), (1, 0.106)], fold0=0.5, fold1=1.0, seed=3)
    fore = dk.sleeve("SleeveFore", m["coat"], [(0, 0.106), (0.35, 0.098), (1, 0.066)], cap1=False, fold0=1.0, seed=4,
                     cuff=(0.72, 0.016, m["wool_imgs"], "Bandit_Lammfell", 0.022))
    for ob in (body, mrig, *parts.values()):
        bpy.data.objects.remove(ob, do_unlink=True)
    hd.preview_arms(upper, fore, hands[0], hands[1])
    return fig
