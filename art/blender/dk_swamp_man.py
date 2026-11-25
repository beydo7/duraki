"""Der Sumpfmann – Überarbeitung (Konzeptbild „Am Spieltisch“, Feld 2).

Kopf (Schlammgesicht mit Glut-Augen, Zweigen, Pilzen) kommt aus `hd_swamp_man.py`; neu sind der
massige Körper mit echter Anatomie aus Schlamm, dichte Moospolster (Schalen statt gestreuter
Blättchen) auf Schultern, Nacken und Armen, Pilzgruppen auf den neuen Schultern, die Arme und
große Schlammhände.

    import dk_swamp_man; dk_swamp_man.build()
"""
from __future__ import annotations

import math
import random

import bpy
from mathutils import Vector, noise

import dk
import geo
import hd
import hd_swamp_man as alt

MACRO = dict(gender=1.0, age=0.6, muscle=0.6, weight=1.0, height=0.6, proportions=0.3,
             race={"asian": 0.1, "caucasian": 0.9, "african": 0.0})
TARGETS = {"torso-scale-horiz-incr": 0.8, "torso-scale-depth-incr": 0.6, "measure-shoulder-dist-incr": 0.8,
           "neck-scale-horiz-incr": 1.0, "neck-scale-depth-incr": 1.0,
           **dk.both("upperarm-shoulder-muscle-incr", 0.8), **dk.both("hand-fingers-diameter-incr", 1.2),
           **dk.both("hand-scale-incr", 0.8)}


def mossy(c, n, bias=0.0):
    """Moos wächst oben auf den Flächen, in zusammenhängenden Polstern."""
    return n.z > 0.32 + bias and noise.noise(c * 5.5) + 0.7 * n.z > 0.5 + bias


def build():
    rnd = random.Random(21)
    hd.clear_scene()
    body, mrig, parts = dk.make_human(MACRO, TARGETS, brows=None, lashes=None, teeth=None, eyes=None)
    for sfx, s in ((".L", 1), (".R", -1)):
        dk.aim_arm(mrig, sfx, Vector((s * 0.34, -0.7, -0.62)))
        dk.grip_pose(mrig, sfx, curl=(40, 62, 44))
    m = alt.materials()
    moss = dk.tex_fur_shells("moss", (0.03, 0.045, 0.012), (0.2, 0.27, 0.07), shells=12, clumps=700, radius=6.5, seed=61)
    fig = dk.Figure(body, mrig, parts, waist=0.42)
    tb = fig.rig.torso
    nc = dk.old_head(fig, alt, rnd, m)
    skin_ob = fig.torso(m["mud"], arm_stub=0.07)
    torso = dk.part_of(skin_ob, "Body", m["mud"], lambda c, n: True, tile=0.3)
    tree = dk.bvh(torso)
    pad = dk.part_of(skin_ob, "MossPad", m["mud"], lambda c, n: c.z > 0.7 and mossy(c, n), grow=0.004, tile=0.12)
    dk.shell_fur(pad, "Body_Moss_Fur", "Sumpf_Moospolster", moss, length=0.03, lean=(0, 0, -0.15), uneven=0.6)
    bpy.data.objects.remove(pad, do_unlink=True)
    bpy.data.objects.remove(skin_ob, do_unlink=True)
    # dicker Schlammnacken bis unter den Kopf
    neck = geo.tube([Vector((0, nc.y + 0.02, nc.z - 0.08)), Vector((0, nc.y, nc.z + 0.04)), Vector((0, nc.y - 0.02, alt.HEAD_Y + 0.06))],
                    [0.22, 0.19, 0.16], seg=28)
    nob = fig.rig.body("Body_Neck", neck, m["mud"], smooth=True, sharp_angle=None)
    hd.organic(nob, voxel=0.012, smooth=3, faces=1800, uv_tile=0.3)
    # Pilzgruppen auf den Schultern (rechts mehr, wie im Konzept)
    caps, stems, gills = [], [], []
    for (x, n_sh, s) in ((0.36, 5, 1.1), (-0.38, 3, 0.85)):
        for k in range(n_sh):
            xx = x + rnd.uniform(-0.08, 0.08)
            hit = tree.ray_cast(Vector((xx, nc.y + rnd.uniform(-0.04, 0.08), 2.0)), Vector((0, 0, -1)))
            if hit[0] is None:
                continue
            alt.mushroom(hit[0] - Vector((0, 0, 0.004)), hit[1] * 0.3 + Vector((math.copysign(0.15, x), 0, 1.0)),
                         s * rnd.uniform(0.6, 1.15), rnd, caps, stems, gills)
    if caps:
        fig.rig.body("Body_ShroomCaps", geo.merge(*caps), m["cap"], smooth=True, sharp_angle=None)
        fig.rig.body("Body_ShroomStems", geo.merge(*stems), m["stem"], smooth=True, sharp_angle=None)
        fig.rig.body("Body_ShroomGills", geo.merge(*gills), m["gills"], smooth=True, sharp_angle=None)
    hands = fig.hands(m["mud"], scale=1.5, corner=0.06, uv_tile=0.22)
    upper = dk.sleeve("SleeveUpper", m["mud"], [(0, 0.135), (0.45, 0.14), (1, 0.108)], seed=1, uv_u=1.6, tile=0.3)
    fore = dk.sleeve("SleeveFore", m["mud"], [(0, 0.108), (0.3, 0.114), (1, 0.08)], seed=2, uv_u=1.4, tile=0.3)
    # Moos auf der Oberseite der Arme (wandert mit, weil es Teil des Arm-Objekts ist)
    for arm, key in ((upper, 0.3), (fore, 0.1)):
        top = dk.part_of(arm, "ArmMoss", m["mud"], lambda c, n: n.y > 0.35 and noise.noise(c * 7 + Vector((key, 0, 0))) > -0.15,
                         grow=0.003, tile=0.12)
        top.parent = None
        fur = dk.shell_fur(top, "ArmMossFur", "Sumpf_Moospolster", moss, length=0.02, lean=(0, 0, 0), uneven=0.6)
        bpy.data.objects.remove(top, do_unlink=True)
        base = len(arm.data.materials)
        for mat in fur.data.materials:
            arm.data.materials.append(mat)
        for p in fur.data.polygons:
            p.material_index += base
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(arm.data)
        bm.from_mesh(fur.data)
        bm.to_mesh(arm.data)
        bm.free()
        bpy.data.objects.remove(fur, do_unlink=True)
        for p in arm.data.polygons:
            p.use_smooth = True
    for ob in (body, mrig, *parts.values()):
        bpy.data.objects.remove(ob, do_unlink=True)
    hd.preview_arms(upper, fore, hands[0], hands[1])
    return fig
