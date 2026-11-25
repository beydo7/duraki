"""Der Riese – Überarbeitung (Konzeptbild „Am Spieltisch“, Feld 8, Boss).

Massiger, kahler Koloss aus grauem, steinartigem Fleisch: schwere Stirn, breite Nase, schwerer
Kiefer, kleine goldgelb glühende Augen; genähte Narben an Kopf und Brust, schwerer Eisenring mit
Nieten und Kette um den Hals, nackter Oberkörper und Arme, Eisenschellen an den Handgelenken.

    import dk_giant; dk_giant.build()
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

import dk
import geo
import hd
import hd_giant as alt

MACRO = dict(gender=1.0, age=0.6, muscle=1.0, weight=0.9, height=0.9, proportions=0.3,
             race={"asian": 0.2, "caucasian": 0.6, "african": 0.2})
TARGETS = {
    "head-square": 0.4, "head-round": 0.3, "head-fat-incr": 0.8, "head-scale-horiz-incr": 0.5, "forehead-scale-vert-decr": 0.6,
    "eyebrows-angle-down": 1.0, "eyebrows-trans-down": 1.0, "eyebrows-trans-forward": 1.0,
    "forehead-trans-forward": 0.5, **dk.both("eye-scale-decr", 0.8), **dk.both("eye-eyefold-down", 0.6),
    **dk.both("eye-push2-in", 0.5),
    "nose-volume-incr": 1.0, "nose-width1-incr": 1.0, "nose-width2-incr": 1.2, "nose-width3-incr": 1.2,
    "nose-compression-compress": 0.6, "nose-flaring-incr": 0.8, "nose-point-width-incr": 1.0, "nose-scale-vert-decr": 0.3,
    "chin-width-incr": 1.2, "chin-bones-incr": 1.2, "chin-prognathism-incr": 0.5, "chin-jaw-drop-incr": 0.5,
    "mouth-angles-down": 1.2, "mouth-scale-horiz-incr": 0.8, "mouth-lowerlip-volume-incr": 0.8,
    "mouth-upperlip-volume-decr": 0.3, "mouth-trans-forward": 0.4,
    **dk.both("cheek-bones-incr", 0.6), **dk.both("cheek-volume-incr", 0.6), **dk.both("ear-scale-decr", 0.6),
    "neck-scale-horiz-incr": 1.3, "neck-scale-depth-incr": 1.0, "neck-scale-vert-incr": 0.3,
    "torso-muscle-pectoral-incr": 1.0, "torso-muscle-dorsi-incr": 1.0, "torso-vshape-incr": 0.8,
    "torso-scale-horiz-incr": 0.8, "torso-scale-depth-incr": 0.6, "measure-shoulder-dist-incr": 0.8,
    **dk.both("upperarm-shoulder-muscle-incr", 1.0), **dk.both("upperarm-muscle-incr", 1.0),
    **dk.both("hand-fingers-diameter-incr", 1.2), **dk.both("hand-scale-incr", 1.0),
    "asym-jaw-1-l": 0.3,
}
FACE_SCARS = [[(0.012, 0.2), (0.004, 0.16), (0.01, 0.12), (0.002, 0.085)],
              [(-0.105, 0.0), (-0.09, -0.035), (-0.07, -0.07)],
              [(0.075, 0.13), (0.095, 0.1), (0.108, 0.065)]]


def materials():
    m = {}
    c, n = dk.skin_textures("skin", dk.data_file("skins/middleage_caucasian_male/*diffuse*.png"),
                            tint=(0.47, 0.46, 0.42), gain=0.6, contrast=1.45, saturation=0.22, bump=4.5, pores=2.2)
    m["skin"] = hd.material("Riese_Haut", c, n, rough=0.8, normal_strength=1.5, spec=0.2)
    c2, n2 = dk.skin_tile("armskin", c)
    m["arm"] = hd.material("Riese_Arm", c2, n2, rough=0.8, normal_strength=1.2, spec=0.2)
    m["scar"] = hd.material("Riese_Narbe", color=(0.2, 0.12, 0.1, 1), rough=0.6, spec=0.25)
    m["thread"] = hd.material("Riese_Faden", color=(0.04, 0.03, 0.025, 1), rough=0.8, spec=0.15)
    c, n = hd.tex_leather("iron", (0.2, 0.17, 0.14), (0.06, 0.05, 0.04), size=512, seed=231, crease=0.3, wear=1.4)
    m["iron"] = hd.material("Riese_Eisen", c, n, rough=0.55, normal_strength=1.2, metal=0.75)
    m["rust"] = hd.material("Riese_Niete", color=(0.16, 0.11, 0.07, 1), rough=0.55, metal=0.5)
    return m


def collar(fig, m, face, hm):
    """Eisenring: sitzt wie ein Halsband am Halsansatz, vorn Öse mit Kettenrest."""
    tb = fig.rig.torso
    co = np.empty(len(face.data.vertices) * 3, dtype=np.float32)
    face.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    zmin = float(co[:, 2].min())
    low = co[(co[:, 2] > zmin + 0.03) & (co[:, 2] < zmin + 0.075)]
    hl = Vector(fig.rig.head.location)
    R = float(np.abs(low[:, 0]).max()) * 0.97
    cy = float((low[:, 1].min() + low[:, 1].max()) * 0.5) + hl.y
    ry = float(low[:, 1].max() - low[:, 1].min()) * 0.5 * 0.97
    zc = min(zmin + 0.055, hm["chin"] - 0.058) + hl.z
    h, th = 0.075, 0.022
    ring = geo.lathe([(R - 0.004, -h / 2), (R + th * 0.8, -h / 2), (R + th, -h / 2 + 0.008), (R + th, h / 2 - 0.008),
                      (R + th * 0.8, h / 2), (R - 0.004, h / 2), (R - 0.004, -h / 2)], 72, 0.1)
    M = Matrix.Translation(Vector((0, cy, zc))) @ Matrix.Rotation(math.radians(-7), 4, "X") @ \
        Matrix.Diagonal((1, ry / R, 1, 1))
    geo.transform(ring, M)
    fig.rig.body("Body_Collar", ring, m["iron"], smooth=True, sharp_angle=None)
    bits = []
    for k in range(16):
        a = (k + 0.5) / 16 * math.tau
        for dz in (-0.024, 0.024):
            rv = geo.ellipsoid(Vector((0.008,) * 3), Vector((math.cos(a) * (R + th), math.sin(a) * (R + th), dz)), 10, 6)
            geo.transform(rv, M)
            bits.append(rv)
    fig.rig.body("Body_CollarRivets", geo.merge(*bits), m["rust"], smooth=True, sharp_angle=None)
    eye_c = Vector((0, -(R + th + 0.012), -0.015))
    links = [alt._link(eye_c, 0.026, 0.007, math.pi / 2)]
    c = eye_c + Vector((0, -0.006, -0.045))
    for k in range(4):
        links.append(alt._link(c, 0.022, 0.006, (k % 2) * math.pi / 2))
        c += Vector((0, 0.004, -0.036))
    for b in links:
        geo.transform(b, M)
    fig.rig.body("Body_Chain", geo.merge(*links), m["iron"], smooth=True, sharp_angle=None)


def build():
    rnd = random.Random(51)
    hd.clear_scene()
    body, mrig, parts = dk.make_human(MACRO, TARGETS, brows=None, lashes=None, teeth=None, eyes="low-poly")
    for sfx, s in ((".L", 1), (".R", -1)):
        dk.aim_arm(mrig, sfx, Vector((s * 0.34, -0.7, -0.62)))
        dk.grip_pose(mrig, sfx, curl=(40, 64, 44))
    m = materials()
    fig = dk.Figure(body, mrig, parts, head_scale=1.08, waist=0.42)
    face = fig.head(m["skin"])
    fig.eye_markers(0.9)
    dk.glow_eyes(fig, "Riese_Auge", (1.0, 0.45, 0.05))
    hm = dk.head_metrics(face, bpy.data.objects["EyeL"].location.z)
    ftree = dk.bvh(face)
    scars = [[s for s in (dk.surface(ftree, x, hm["eye"] + z) for x, z in line) if s] for line in FACE_SCARS]
    alt.stitches(fig.rig, m, [s for s in scars if len(s) > 1], "Face_Stitches", fig.rig.head, rnd, ridge=0.004)
    torso = fig.torso(m["skin"], arm_stub=0.075)
    torso.name = "Body"
    ttree = dk.bvh(torso)
    scars = []
    for k in range(7):
        x0 = rnd.choice((-1, 1)) * rnd.uniform(0.08, 0.32)
        z0 = rnd.uniform(0.66, 1.0)
        ang, L = rnd.uniform(-0.9, 0.9), rnd.uniform(0.06, 0.11)
        pts = [dk.surface(ttree, x0 + math.cos(ang) * L * t, z0 + math.sin(ang) * L * t + 0.008 * math.sin(t * 7))
               for t in (i / 4 - 0.5 for i in range(5))]
        if all(pts):
            scars.append(pts)
    alt.stitches(fig.rig, m, scars, "Body_Stitches", fig.rig.torso, rnd, ridge=0.0045)
    collar(fig, m, face, hm)
    hands = fig.hands(m["skin"], scale=1.5, corner=0.06)
    upper = dk.sleeve("SleeveUpper", m["arm"], [(0, 0.132), (0.4, 0.142), (1, 0.104)], seed=1, uv_u=1.6, tile=0.5)
    fore = dk.sleeve("SleeveFore", m["arm"], [(0, 0.104), (0.3, 0.114), (1, 0.078)], seed=2, uv_u=1.4, tile=0.5,
                     band=(0.8, 0.95, 0.012, m["iron"]))
    for ob in (body, mrig, *parts.values()):
        bpy.data.objects.remove(ob, do_unlink=True)
    hd.preview_arms(upper, fore, hands[0], hands[1])
    return fig
