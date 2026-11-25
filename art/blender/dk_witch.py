"""Die Hexe – Überarbeitung (Konzeptbild „Am Spieltisch“, Feld 7).

Uralte Frau mit Hakennase, spitzem Kinn und eingefallenen Wangen; rotes Kopftuch, strähniges
graues Haar, goldgelb glühende Augen, violettes Wolltuch über dunklem Kleid, Kette aus Zähnen,
knochige Hände, Laterne auf dem Tisch.

    import dk_witch; dk_witch.build()
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Vector

import dk
import geo
import hd
import hd_witch as alt

MACRO = dict(gender=0.0, age=1.0, muscle=0.25, weight=0.3, height=0.35, proportions=0.4,
             race={"asian": 0.1, "caucasian": 0.9, "african": 0.0})
TARGETS = {
    "head-age-incr": 1.0, "head-triangular": 0.5,
    # Hakennase
    "nose-hump-incr": 1.4, "nose-point-down": 1.3, "nose-scale-vert-incr": 0.8, "nose-scale-depth-incr": 1.0,
    "nose-greek-incr": 0.5, "nose-base-down": 0.6, "nose-width1-decr": 0.4, "nose-nostrils-angle-down": 0.6,
    # spitzes, vorstehendes Kinn, eingefallene Wangen
    "chin-prominent-incr": 1.3, "chin-triangle": 1.0, "chin-height-incr": 0.6, "chin-bones-decr": 0.4,
    **dk.both("cheek-volume-decr", 1.0), **dk.both("cheek-bones-incr", 1.0), **dk.both("cheek-inner-decr", 0.7),
    # tief liegende Augen, hängende Lider, schmaler Mund mit schiefem Grinsen
    **dk.both("eye-bag-incr", 1.0), **dk.both("eye-eyefold-down", 0.8), **dk.both("eye-push2-in", 0.5),
    "eyebrows-angle-up": 0.4, "eyebrows-trans-down": 0.5,
    "mouth-upperlip-volume-decr": 1.0, "mouth-lowerlip-volume-decr": 0.8, "mouth-angles-up": 0.7,
    "mouth-scale-horiz-incr": 0.7, "mouth-laugh-lines-out": 1.0, "mouth-trans-backward": 0.5,
    **dk.both("ear-scale-incr", 0.6), **dk.both("ear-lobe-incr", 0.8), "neck-scale-horiz-decr": 0.6,
    "neck-double-decr": 0.5, "asym-mouth-1-l": 0.5, "asym-brown-1-l": 0.4,
    # knochige, lange Finger
    **dk.both("hand-fingers-diameter-decr", 0.6), **dk.both("hand-fingers-length-incr", 0.8),
}


def materials(parts):
    m = {}
    c, n = dk.skin_textures("skin", dk.data_file("skins/old_caucasian_female/*diffuse*.png"),
                            tint=(0.5, 0.43, 0.3), gain=0.56, contrast=1.7, saturation=0.8, bump=4.0, pores=1.6)
    m["skin"] = hd.material("Hexe_Haut", c, n, rough=0.78, normal_strength=1.3, spec=0.2)
    c, n = hd.tex_cloth("scarf", (0.5, 0.06, 0.05), (0.22, 0.02, 0.02), seed=21, weave=100, rag=0.25)
    m["scarf"] = hd.material("Hexe_Kopftuch", c, n, rough=0.86, normal_strength=1.0, double_sided=True, spec=0.2)
    c, n = alt.tex_shawl("shawl", (0.3, 0.14, 0.38), (0.1, 0.045, 0.14))
    m["shawl"] = hd.material("Hexe_Tuch", c, n, rough=0.92, normal_strength=1.2, double_sided=True, spec=0.15)
    c, n = hd.tex_cloth("robe", (0.1, 0.06, 0.13), (0.03, 0.02, 0.04), seed=23, weave=120, rag=0.3)
    m["robe"] = hd.material("Hexe_Kleid", c, n, rough=0.9, normal_strength=1.0, spec=0.15, double_sided=True)
    c, n = hd.tex_hair("hair", (0.22, 0.2, 0.18), (0.62, 0.6, 0.56), w=96, h=384, seed=185, strands=34)
    m["hair"] = hd.material("Hexe_Haar", c, n, rough=0.8, normal_strength=0.5, double_sided=True, spec=0.15,
                            alpha_clip=True)
    m["brow"] = hd.material("Hexe_Braue", dk.tint_image("brow", dk.part_image(parts["brows"]), (0.5, 0.48, 0.44)), rough=0.8, spec=0.1, alpha_clip=True,
                            double_sided=True)
    m["gold"] = hd.material("Hexe_Gold", color=(0.75, 0.52, 0.2, 1), rough=0.3, metal=0.9)
    c, n = hd.tex_keratin("tooth", (0.62, 0.55, 0.4), seed=41, streak=0.6)
    m["tooth"] = hd.material("Hexe_Zahn", c, n, rough=0.5, normal_strength=0.6, spec=0.35)
    m["cord"] = hd.material("Hexe_Schnur", color=(0.1, 0.07, 0.05, 1), rough=0.9)
    m["iron"] = hd.material("Hexe_Laterne", color=(0.12, 0.1, 0.08, 1), rough=0.45, metal=0.85)
    m["lglass"] = hd.material("Hexe_Laternenglas", color=(1.0, 0.7, 0.3, 1), rough=0.2,
                              emission=(1.0, 0.62, 0.22, 1), emission_strength=3.0)
    return m


def head_dress(fig, m, hm, tree, rnd):
    hb = fig.rig.head
    kw = dict(margin=0.016, front=0.075, back=-0.1)
    _ob, rim = dk.head_cover("Scarf", m["scarf"], hb, hm, tree, **kw)
    hem = geo.tube(rim + [rim[0]], [0.008 + 0.003 * math.sin(k * 0.7) for k in range(len(rim) + 1)], seg=10,
                   cap_start=False)
    fig.rig.headpart("Scarf_Hem", hem, m["scarf"], smooth=True, sharp_angle=None)
    knot_c = dk.cover_point(hm, math.radians(150), 0.0, **kw)[0] + Vector((-0.01, 0.02, 0.0))
    parts = [geo.ellipsoid(Vector((0.032, 0.028, 0.026)), knot_c, 20, 14)]
    for dx, L in ((-0.03, 0.15), (0.015, 0.11)):
        pts = [knot_c + Vector((dx * t * 2 - 0.02 * t * t, 0.03 * t, -L * t)) for t in (i / 6 for i in range(7))]
        parts.append(geo.tube(pts, [0.014, 0.019, 0.021, 0.021, 0.019, 0.015, 0.007], seg=12))
    fig.rig.headpart("Scarf_Knot", geo.merge(*parts), m["scarf"], smooth=True, sharp_angle=None)
    starts = []
    for _ in range(460):
        a = rnd.uniform(-math.pi, math.pi)
        if abs(a) < 0.8:
            continue
        p, n = dk.cover_point(hm, a, 0.0, **kw)
        starts.append((p - Vector((0, 0, 0.004)) - n * 0.006, n))
    dk.hanging_hair("Hair_Fur", m["hair"], hb, starts, rnd, length=(0.24, 0.4))
    rings = []
    for s in (-1, 1):
        c = Vector((s * (hm["x"] * 0.96), hm["yc"] + 0.01, hm["eye"] - 0.085))
        ring = [c + Vector((0, 0.022 * math.cos(t), -0.022 + 0.022 * math.sin(t))) for t in
                (k / 20 * math.tau for k in range(21))]
        rings.append(geo.tube(ring, [0.0032] * 21, seg=8, cap_start=False))
    fig.rig.headpart("Ears_Rings", geo.merge(*rings), m["gold"], smooth=True, sharp_angle=None)


def clothes(fig, m, skin_ob, rnd):
    tb = fig.rig.torso
    nc = dk.to_torso(fig.mrig.pose.bones["neck01"].head)
    bm = bmesh.new()
    bm.from_mesh(skin_ob.data)
    dk.inflate(bm, 0.012, 1)
    dk.keep_faces(bm, lambda f: f.calc_center_median().z < nc.z - 0.03)
    dk.smooth_boundary(bm)
    geo.box_uv(bm, 0.22)
    robe = dk.to_object("Body", bm, m["robe"], tb)
    tree = dk.bvh(robe)
    bm = bmesh.new()
    bm.from_mesh(skin_ob.data)
    dk.inflate(bm, 0.034, 3)

    def keep(f):
        c = f.calc_center_median()
        if c.z < 0.62 + 0.03 * math.sin(c.x * 40):
            return False
        if c.y < nc.y + 0.02 and abs(c.x) < 0.035 + 0.1 * min(1.0, max(0.0, (c.z - 0.7) / 0.4)) ** 1.5:
            return False
        return not (c.z > nc.z - 0.02 and math.hypot(c.x, c.y - nc.y) < 0.17)
    dk.keep_faces(bm, keep)
    dk.smooth_boundary(bm)
    geo.box_uv(bm, 0.26)
    shawl = dk.to_object("Body_Shawl", bm, m["shawl"], tb)
    shawl.modifiers.new("Dicke", "SOLIDIFY").thickness = -0.012
    # Kette aus Zähnen
    pts, teeth = [], []
    for k in range(25):
        u = k / 24 * 2 - 1
        hit = dk.surface(tree, u * 0.12, nc.z - 0.05 - 0.11 * (1 - u * u), lift=0.006)
        if hit:
            pts.append(hit[0])
            if k % 2 == 0 and 2 <= k <= 22:
                L = rnd.uniform(0.028, 0.046)
                p = hit[0]
                teeth.append(geo.tube([p, p + Vector((0, -0.006, -L * 0.55)), p + Vector((0, -0.003, -L))],
                                      [0.0075, 0.0058, 0.0008], seg=8))
    fig.rig.body("Body_Necklace", geo.tube(pts, [0.003] * len(pts), seg=6), m["cord"], smooth=True, sharp_angle=None)
    fig.rig.body("Body_Trinkets", geo.merge(*teeth), m["tooth"], smooth=True, sharp_angle=None)


def build():
    rnd = random.Random(41)
    hd.clear_scene()
    body, mrig, parts = dk.make_human(MACRO, TARGETS, brows="eyebrow003", lashes=None, teeth=None, eyes="low-poly")
    for sfx, s in ((".L", 1), (".R", -1)):
        dk.aim_arm(mrig, sfx, Vector((s * 0.3, -0.72, -0.62)))
        dk.grip_pose(mrig, sfx, curl=(34, 58, 40))
    m = materials(parts)
    fig = dk.Figure(body, mrig, parts, head_scale=1.14)
    face = fig.head(m["skin"])
    fig.eye_markers(0.9)
    dk.glow_eyes(fig, "Hexe_Auge", (1.0, 0.45, 0.05))
    fig.head_part("brows", "Face_Brows", m["brow"])
    hm = dk.head_metrics(face, bpy.data.objects["EyeL"].location.z)
    head_dress(fig, m, hm, dk.bvh(face), rnd)
    skin_ob = fig.torso(m["skin"], arm_stub=0.055)
    clothes(fig, m, skin_ob, rnd)
    bpy.data.objects.remove(skin_ob, do_unlink=True)
    alt.lantern(fig.rig, m)
    hands = fig.hands(m["skin"], scale=1.22)
    upper = dk.sleeve("SleeveUpper", m["shawl"], [(0, 0.115), (0.5, 0.108), (1, 0.094)], fold0=0.4, fold1=1.0, seed=5)
    fore = dk.sleeve("SleeveFore", m["robe"], [(0, 0.094), (0.4, 0.088), (1, 0.07)], cap1=False, fold0=1.0, seed=6,
                     lining=True)
    for ob in (body, mrig, *parts.values()):
        bpy.data.objects.remove(ob, do_unlink=True)
    hd.preview_arms(upper, fore, hands[0], hands[1])
    return fig
