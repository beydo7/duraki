"""Der Knochenmann – Überarbeitung (Konzeptbild „Am Spieltisch“, Feld 6).

Schädel mit Zylinder und Kerze sowie die Knochenhände kommen aus `hd_bone_man.py`; neu sind der
schmale Oberkörper mit echten Schultern unter dem Gehrock, das rote Revers mit Stehkragen, der
Brustkorb in der Mantelöffnung und die Ärmel.

    import dk_bone_man; dk_bone_man.build()
"""
from __future__ import annotations

import math
import random

import bpy
from mathutils import Vector

import characters as ch
import dk
import geo
import hd
import hd_bone_man as alt
from geo import G

MACRO = dict(gender=1.0, age=0.7, muscle=0.15, weight=0.05, height=0.6, proportions=0.5,
             race={"asian": 0.1, "caucasian": 0.9, "african": 0.0})
TARGETS = {"torso-scale-horiz-decr": 0.3, "measure-shoulder-dist-incr": 0.4, "stomach-tone-incr": 0.5}


def open_w(z):
    return 0.04 + 0.15 * min(1.0, max(0.0, (z - 0.56) / 0.42)) ** 1.2


def clothes(fig, m, skin_ob, nc, rnd):
    tb = fig.rig.torso
    inner = dk.part_of(skin_ob, "Void_Chest", ch.void(), lambda c, n: c.z < nc.z - 0.02, grow=0.004)
    itree = dk.bvh(inner)
    coat, tree = dk.open_coat(skin_ob, "Body", m["coat"], nc, grow=0.03, open_w=open_w, neck_r=0.16, tile=0.3)
    # Brustkorb: Brustbein, Rippenbögen, Schlüsselbeine
    parts = []
    st = [dk.surface(itree, 0.0, nc.z - d, lift=0.02)[0] for d in (0.46, 0.36, 0.26, 0.16, 0.07)]
    parts.append(geo.tube(st, [0.011, 0.014, 0.015, 0.016, 0.019], seg=10))
    for k in range(8):  # oberste Rippe dicht unter den Schlüsselbeinen
        z0 = nc.z - 0.095 - k * 0.048
        for s in (-1, 1):
            pts = []
            for i in range(9):
                t = i / 8
                hit = dk.surface(itree, s * (0.012 + 0.2 * t), z0 - 0.045 * t * t + 0.012 * math.sin(t * math.pi),
                                 lift=0.022 + 0.004 * math.sin(t * math.pi))
                if hit:
                    pts.append(hit[0])
            if len(pts) > 2:
                parts.append(geo.tube(pts, [0.0115 - 0.003 * i / len(pts) for i in range(len(pts))], seg=8))
    for s in (-1, 1):
        cl = [dk.surface(itree, s * x, nc.z - 0.045 + dz, lift=0.02)[0] for x, dz in ((0.016, 0.0), (0.09, 0.012), (0.19, 0.0))]
        parts.append(geo.tube(cl, [0.011, 0.009, 0.01], seg=10))
    ribs = fig.rig.body("Body_Ribs", geo.merge(*parts), m["bone"], smooth=True, sharp_angle=None)
    hd.organic(ribs, voxel=0.003, smooth=2, faces=9000, uv_tile=0.12)
    # Revers (rotes Futter) entlang der Öffnung und hoher Stehkragen
    for s in (-1, 1):
        mb = hd.MeshBuilder()
        rows, uvs = [], []
        for i in range(25):
            z = 0.56 + (nc.z - 0.05 - 0.56) * i / 24
            wide = 0.04 + 0.085 * math.sin(math.pi * min(1.0, i / 24 * 1.15)) ** 0.7
            row, uvr = [], []
            for j in range(5):
                x = open_w(z) + 0.006 + wide * j / 4
                hit = dk.surface(tree, s * x, z, lift=0.012 + 0.006 * math.sin(math.pi * j / 4))
                row.append(hit[0] if hit else Vector((s * x, nc.y - 0.15, z)))
                uvr.append((j / 4 * 0.5, z * 3))
            rows.append(row)
            uvs.append(uvr)
        mb.grid(rows, uvs)
        ob = mb.finish("Body_Lapel" + ("L" if s < 0 else "R"), m["lining"], parent=tb)
        ob.modifiers.new("Dicke", "SOLIDIFY").thickness = 0.006
    for name, mat, off in (("Body_Collar", m["coat"], 0.0), ("Body_CollarLining", m["lining"], -0.005)):
        mb = hd.MeshBuilder()
        rows, uvs = [], []
        for i in range(9):
            t = i / 8
            row, uvr = [], []
            for j in range(41):
                a = math.radians(-118 + 236 * j / 40)  # 0 = hinten
                edge = min(1.0, (1 - abs(j / 20 - 1)) / 0.3)
                r = 0.165 + 0.05 * t ** 1.5 + off
                h = (0.2 * t) * (0.45 + 0.55 * edge ** 0.6)
                row.append(Vector((r * 1.08 * math.sin(a), nc.y + 0.01 + r * math.cos(a), nc.z - 0.045 + h)))
                uvr.append((j / 40 * 3, t))
            rows.append(row)
            uvs.append(uvr)
        mb.grid(rows, uvs)
        mb.finish(name, mat, parent=tb).modifiers.new("Dicke", "SOLIDIFY").thickness = 0.004
    btn = []
    for z in (0.44, 0.5):
        hit = dk.surface(tree, 0.045, z, lift=0.004)
        if hit:
            btn.append(geo.ellipsoid(Vector((0.013, 0.006, 0.013)), hit[0], 14, 8))
    if btn:
        fig.rig.body("Body_Buttons", geo.merge(*btn), m["button"], smooth=True, sharp_angle=None)


def build():
    rnd = random.Random(31)
    hd.clear_scene()
    body, mrig, parts = dk.make_human(MACRO, TARGETS, brows=None, lashes=None, teeth=None, eyes=None)
    m = alt.materials()
    m["lining"].use_backface_culling = False  # Revers und Kragen sind von beiden Seiten zu sehen
    m["coat"].use_backface_culling = False
    fig = dk.Figure(body, mrig, parts, waist=0.5)
    nc = dk.old_head(fig, alt, rnd, m)
    skin_ob = fig.torso(m["bone"], arm_stub=0.05)
    clothes(fig, m, skin_ob, nc, rnd)
    bpy.data.objects.remove(skin_ob, do_unlink=True)
    neck = geo.tube([Vector((0, nc.y + 0.01, nc.z - 0.06)), Vector((0, nc.y, nc.z + 0.05)), Vector((0, nc.y - 0.02, alt.HEAD_Y + 0.03))],
                    [0.034, 0.03, 0.032], seg=14)
    fig.rig.body("Body_Spine", neck, m["bone"], smooth=True, sharp_angle=None)
    hands = [alt.bone_hand(side, m["handbone"]) for side in (-1, 1)]
    for side, h in zip((-1, 1), hands):
        h.location = G(side * 0.085, 0.9, 0.22)
    upper = dk.sleeve("SleeveUpper", m["coat"], [(0, 0.102), (0.5, 0.092), (1, 0.08)], fold0=0.4, fold1=1.0, seed=1)
    fore = dk.sleeve("SleeveFore", m["coat"], [(0, 0.08), (0.4, 0.074), (1, 0.058)], cap1=False, fold0=1.0, seed=2,
                     lining=True)
    for ob in (body, mrig, *parts.values()):
        bpy.data.objects.remove(ob, do_unlink=True)
    hd.preview_arms(upper, fore, hands[0], hands[1])
    return fig
