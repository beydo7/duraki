"""Der Gaukler – Überarbeitung (Konzeptbild „Am Spieltisch“, Feld 5).

Die Maske mit Kappe, Zipfeln, Schellen und Halskrause bleibt (bewusst gestaltete Maske aus
`hd_jester.py`); neu sind der anatomische Oberkörper im Rautenwams, gebauschte Ärmel mit Rüschen
und echte, hagere Hände.

    import dk_jester; dk_jester.build()
"""
from __future__ import annotations

import random

import bmesh
import bpy
from mathutils import Vector

import dk
import geo
import hd
import hd_jester as alt

MACRO = dict(gender=1.0, age=0.8, muscle=0.35, weight=0.3, height=0.5, proportions=0.5,
             race={"asian": 0.1, "caucasian": 0.9, "african": 0.0})
TARGETS = {**dk.both("hand-fingers-length-incr", 0.6), **dk.both("hand-fingers-diameter-decr", 0.2),
           "torso-scale-horiz-incr": 0.3}


def build():
    rnd = random.Random(31)
    hd.clear_scene()
    body, mrig, parts = dk.make_human(MACRO, TARGETS, brows=None, lashes=None, teeth=None, eyes=None)
    for sfx, s in ((".L", 1), (".R", -1)):
        dk.aim_arm(mrig, sfx, Vector((s * 0.3, -0.72, -0.62)))
        dk.grip_pose(mrig, sfx, curl=(36, 60, 42))
    m = alt.materials()
    c, n = dk.skin_textures("skin", dk.data_file("skins/old_caucasian_male/*diffuse*.png"),
                            tint=(0.6, 0.52, 0.4), gain=0.72, contrast=1.3, saturation=0.5, bump=3.5, pores=1.2)
    m["skin"] = hd.material("Gaukler_Haut", c, n, rough=0.7, normal_strength=1.2, spec=0.25)
    fig = dk.Figure(body, mrig, parts)
    tb = fig.rig.torso
    nc = dk.to_torso(mrig.pose.bones["neck01"].head)
    fig.rig.head.location = Vector((0, nc.y - 0.03, 1.2))
    # Wams
    skin_ob = fig.torso(m["skin"], arm_stub=0.055)
    bm = bmesh.new()
    bm.from_mesh(skin_ob.data)
    dk.inflate(bm, 0.02, 2)
    dk.keep_faces(bm, lambda f: f.calc_center_median().z < nc.z - 0.02)
    dk.close_holes(bm)
    dk.cyl_uv(bm, 6.0, 3.6)
    wams = dk.to_object("Body", bm, m["motley"], tb)
    bpy.data.objects.remove(skin_ob, do_unlink=True)
    neck = geo.lathe([(0.085, nc.z - 0.05), (0.075, 1.12), (0.068, 1.24)], 24, 0.15)
    geo.translate(neck, Vector((0, nc.y, 0)))
    fig.rig.body("Body_Neck", neck, m["red"], smooth=True, sharp_angle=None)
    # Maske, Kappe, Krause (Krause legt sich auf die neuen Schultern)
    tree = dk.bvh(wams)
    head_in_torso = Vector(fig.rig.head.location)

    def drape(p, clear):
        q = p + head_in_torso
        hit = tree.ray_cast(Vector((q.x, q.y, 2.0)), Vector((0, 0, -1)))
        if hit[0] is not None and q.z < hit[0].z + clear:
            q.z = min(hit[0].z + clear, q.z + 0.12)
        return q - head_in_torso
    alt._drape = drape
    alt.build_head(fig.rig, m, rnd)
    alt.scale_head(fig.rig, alt.HEAD_SCALE)
    alt.ruff(fig.rig, m)
    hands = fig.hands(m["skin"], scale=1.28)
    upper = dk.sleeve("SleeveUpper", m["motley"], [(0, 0.11), (0.45, 0.128), (1, 0.1)], fold0=0.4, fold1=1.0, seed=1,
                      uv_u=2.0, tile=1 / 3.6)
    fore = dk.sleeve("SleeveFore", m["motley"], [(0, 0.1), (0.4, 0.108), (0.85, 0.072), (1, 0.06)], cap1=False,
                     fold0=1.0, seed=2, uv_u=2.0, tile=1 / 3.6, ruffle=(m["ruff"], 16, 0.04))
    for ob in (body, mrig, *parts.values()):
        bpy.data.objects.remove(ob, do_unlink=True)
    hd.preview_arms(upper, fore, hands[0], hands[1])
    return fig
