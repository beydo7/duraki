"""Die Krähe – Überarbeitung (Konzeptbild „Am Spieltisch“, Feld 3).

Rabenkopf (Schnabel, Federbrauen, Glut-Augen) kommt aus `hd_crow.py`; neu sind der Oberkörper mit
echten Schultern im dunklen Mantel, der Federkragen (Unterlage + Alpha-Federn, auf den Schultern
lang und abstehend), der gefiederte Hals, Goldketten und Fibeln auf der neuen Form, die Ärmel und
dunkle, schuppige Hände mit Krallen.

    import dk_crow; dk_crow.build()
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
import hd_crow as alt

MACRO = dict(gender=1.0, age=0.6, muscle=0.5, weight=0.4, height=0.55, proportions=0.5,
             race={"asian": 0.1, "caucasian": 0.9, "african": 0.0})
TARGETS = {**dk.both("hand-fingers-length-incr", 0.7), **dk.both("hand-fingers-diameter-decr", 0.3),
           "measure-shoulder-dist-incr": 0.5}


def feathers(fig, m, shell, nc, rnd):
    """Federkarten auf der Kragen-Unterlage: Schultern lang und abstehend, Brust klein und anliegend."""
    tb = fig.rig.torso
    bm = bmesh.new()
    bm.from_mesh(shell.data)
    big, bs = hd.MeshBuilder(), []
    small, ss = hd.MeshBuilder(), []
    pts = hd.sample_surface(bm, 2300, rnd)
    pts.sort(key=lambda pn: pn[0].z)  # von unten nach oben: obere Federn überdecken die Ansätze
    for p, n in pts:
        shoulder = math.exp(-((abs(p.x) - 0.34) / 0.13) ** 2) * math.exp(-((p.z - 0.95) / 0.16) ** 2)
        out = Vector((n.x, n.y, 0))
        out = out.normalized() if out.length > 1e-4 else n
        flow = Vector((0, 0, -1)) + out * (0.15 + 0.4 * shoulder) + Vector((p.x, 0, 0)) * 0.6
        front = p.y < nc.y and abs(p.x) < 0.17
        if front and p.z < nc.z - 0.05:
            L = rnd.uniform(0.05, 0.075)
            alt.card(small, ss, p + n * 0.003, n, flow, L, L * 0.36, lift=rnd.uniform(0.04, 0.1), curl=0.03, cup=0.14,
                     twist=rnd.uniform(-0.2, 0.2), sink=0.002)
        else:
            L = (0.095 + 0.14 * shoulder) * rnd.uniform(0.75, 1.25)
            alt.card(big, bs, p + n * 0.003, n, flow, L, L * rnd.uniform(0.26, 0.33),
                     lift=rnd.uniform(0.12, 0.25) + 0.24 * shoulder, curl=rnd.uniform(-0.06, 0.04), cup=0.12,
                     twist=rnd.uniform(-0.35, 0.35), sink=0.004, along=6, across=3)
    bm.free()
    hd.shade_like(alt.finish_cards(big, bs, "Body_Plumes", m["plume"], tb), shell, 0.55)
    hd.shade_like(alt.finish_cards(small, ss, "Body_Feathers", m["feather"], tb), shell, 0.7)


def build():
    rnd = random.Random(7)
    hd.clear_scene()
    alt.surf_hit._tree = None
    body, mrig, parts = dk.make_human(MACRO, TARGETS, brows=None, lashes=None, teeth=None, eyes=None)
    for sfx, s in ((".L", 1), (".R", -1)):
        dk.aim_arm(mrig, sfx, Vector((s * 0.3, -0.72, -0.62)))
        dk.grip_pose(mrig, sfx, curl=(34, 58, 42))
    m = alt.materials()
    for key, f in (("feather", 1.5), ("plume", 1.55), ("hackle", 1.5), ("plumage", 1.5), ("coat", 1.3)):
        dk.brighten(m[key], f)
    fig = dk.Figure(body, mrig, parts, waist=0.42)
    tb = fig.rig.torso
    nc = dk.old_head(fig, alt, rnd, m, build="head")
    skin_ob = fig.torso(m["skin"], arm_stub=0.055)
    dk.part_of(skin_ob, "Body", m["coat"], lambda c, n: c.z < nc.z - 0.02, grow=0.014, tile=0.3)
    # Federkragen: geschlossene Unterlage über Schultern, Brust und Rücken
    shell = dk.part_of(skin_ob, "Body_Mantle", m["plumage"],
                       lambda c, n: c.z > 0.66 + 0.1 * max(0.0, -n.y) * math.exp(-(c.x / 0.3) ** 2), grow=0.03, tile=0.16)
    tree = dk.bvh(shell)
    feathers(fig, m, shell, nc, rnd)
    # Hals: Gefieder-Säule mit schmalen, abstehenden Halsfedern
    top = alt.HEAD_Y + 0.08
    neck = geo.tube([Vector((0, nc.y + 0.01, nc.z - 0.08)), Vector((0, nc.y, nc.z + 0.03)), Vector((0, nc.y - 0.04, top))],
                    [0.15, 0.125, 0.1], seg=28)
    geo.box_uv(neck, 0.16)
    nbm = neck.copy()
    neck_ob = fig.rig.body("Body_Neck", neck, m["plumage"], smooth=True, sharp_angle=None)
    hk, hs = hd.MeshBuilder(), []
    for p, n in hd.sample_surface(nbm, 900, rnd, lambda p, n: abs(n.z) < 0.7):
        L = rnd.uniform(0.07, 0.12)
        alt.card(hk, hs, p, n, Vector((rnd.uniform(-0.3, 0.3), 0.15, -1)), L, L * 0.2, lift=rnd.uniform(0.08, 0.2),
                 curl=0.04, cup=0.08, twist=rnd.uniform(-0.3, 0.3), along=6, across=2)
    nbm.free()
    hd.shade_like(alt.finish_cards(hk, hs, "Body_Neck_Hackles", m["hackle"], tb), neck_ob, 0.6)
    # Ketten und Fibeln: die alten Funktionen arbeiten auf der neuen Oberfläche
    def on(xz, z, out=0.0, folds=True):
        hit = dk.surface(tree, xz[0], xz[1], lift=out * 0.45)
        return hit[0] if hit else Vector((xz[0], nc.y - 0.2, xz[1]))

    def normal(xz, z):
        hit = dk.surface(tree, xz[0], xz[1])
        return hit[1] if hit else Vector((0, -1, 0))
    alt.theta_front = lambda x, z: (x, z)
    alt.body_point = on
    alt.body_normal = normal
    alt.BROOCH = (0.2, nc.z - 0.07)
    alt.NECK_R = 0.105
    alt.chains(fig.rig, m, rnd)
    for s in (-1, 1):
        alt.brooch(fig.rig, m, s)
    bpy.data.objects.remove(skin_ob, do_unlink=True)
    hands = fig.hands(m["skin"], scale=1.28, claws=(0.02, m["claw"]), uv_tile=0.09)
    upper = dk.sleeve("SleeveUpper", m["coat"], [(0, 0.11), (0.5, 0.1), (1, 0.086)], fold0=0.4, fold1=1.0, seed=5)
    fore = dk.sleeve("SleeveFore", m["coat"], [(0, 0.086), (0.4, 0.08), (1, 0.062)], cap1=False, fold0=1.0, seed=6,
                     lining=True)
    for ob in (body, mrig, *parts.values()):
        bpy.data.objects.remove(ob, do_unlink=True)
    hd.preview_arms(upper, fore, hands[0], hands[1])
    return fig
