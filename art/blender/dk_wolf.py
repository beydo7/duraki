"""Die Wölfin – Überarbeitung (Konzeptbild „Am Spieltisch“, Feld 4).

Wolfskopf mit roter Kapuze kommt aus `hd_wolf.py`; neu sind der weibliche Oberkörper im Mieder,
dichtes Schalen-Fell an Brust und Hals, der rote Umhang auf echten Schultern, die Ärmel und
befellte Hände mit Krallen.

    import dk_wolf; dk_wolf.build()
"""
from __future__ import annotations

import random

import bpy
from mathutils import Vector

import dk
import geo
import hd
import hd_wolf as alt

MACRO = dict(gender=0.0, age=0.45, muscle=0.45, weight=0.45, height=0.5, proportions=0.6, cupsize=0.55,
             firmness=0.7, race={"asian": 0.1, "caucasian": 0.9, "african": 0.0})
TARGETS = {**dk.both("hand-fingers-diameter-incr", 0.5), **dk.both("hand-fingers-length-incr", 0.3),
           "neck-scale-horiz-incr": 0.6, "neck-scale-depth-incr": 0.5}


def build():
    rnd = random.Random(17)
    hd.clear_scene()
    body, mrig, parts = dk.make_human(MACRO, TARGETS, brows=None, lashes=None, teeth=None, eyes=None)
    for sfx, s in ((".L", 1), (".R", -1)):
        dk.aim_arm(mrig, sfx, Vector((s * 0.3, -0.72, -0.62)))
        dk.grip_pose(mrig, sfx, curl=(36, 60, 42))
    m = alt.materials()
    fur = dk.tex_fur_shells("pelt", (0.2, 0.19, 0.185), (0.74, 0.72, 0.68), shells=14, clumps=1100, radius=4.5, seed=71)
    paw = dk.tex_fur_shells("paw", (0.14, 0.135, 0.13), (0.5, 0.49, 0.47), shells=8, clumps=2200, radius=3.2, seed=72)
    fig = dk.Figure(body, mrig, parts, waist=0.42)
    tb = fig.rig.torso
    nc = dk.old_head(fig, alt, rnd, m)
    for ob in list(fig.rig.head.children):  # alte Halsfell-Karten: das Brustfell übernimmt
        if "Neck" in ob.name:
            bpy.data.objects.remove(ob, do_unlink=True)
    skin_ob = fig.torso(m["furskin"], arm_stub=0.055)

    def neckline(c):  # tiefer, runder Ausschnitt vorn; hinten hochgeschlossen
        if c.y > nc.y:
            return nc.z - 0.05
        return nc.z - 0.27 + 2.6 * c.x * c.x
    bodice = dk.part_of(skin_ob, "Body", m["bodice"], lambda c, n: c.z < neckline(c), grow=0.008, tile=0.22)
    pelt = dk.part_of(skin_ob, "Pelt", m["furskin"], lambda c, n: c.z > neckline(c) - 0.03, tile=0.1)
    dk.shell_fur(pelt, "Body_Chest_Fur", "Wolf_Pelz", fur, length=0.038, lean=(0, -0.04, -0.12))
    bpy.data.objects.remove(pelt, do_unlink=True)
    # Saum am Ausschnitt
    btree = dk.bvh(bodice)
    hem = [h[0] for h in (dk.surface(btree, x, neckline(Vector((x, nc.y - 0.1, 0))) - 0.012, lift=0.004)
                          for x in (i / 30 * 0.32 - 0.16 for i in range(31))) if h]
    if len(hem) > 3:
        fig.rig.body("Body_Hem", geo.tube(hem, [0.006] * len(hem), seg=8), m["brass"], smooth=True, sharp_angle=None)
    # Umhang: weit, vorn offen, mit Kordel
    cape, ctree = dk.open_coat(skin_ob, "Body_Cape", m["cloth"], nc, grow=0.04, neck_r=0.15, tile=0.3,
                               open_w=lambda z: 0.1 + 0.12 * min(1.0, max(0.0, (z - 0.55) / 0.5)))
    knots = []
    for s in (-1, 1):
        hit = dk.surface(ctree, s * 0.2, nc.z - 0.1, lift=0.006)
        if hit:
            knots.append(hit[0])
            fig.rig.body("Body_Clasp" + ("L" if s < 0 else "R"), geo.ellipsoid(Vector((0.02, 0.01, 0.02)), hit[0], 16, 10),
                         m["brass"], smooth=True, sharp_angle=None)
    if len(knots) == 2:
        mid = (knots[0] + knots[1]) * 0.5 + Vector((0, -0.05, -0.035))
        fig.rig.body("Body_Cord", geo.tube([knots[0], knots[0].lerp(mid, 0.6) + Vector((0, 0, -0.01)), mid,
                                            knots[1].lerp(mid, 0.6) + Vector((0, 0, -0.01)), knots[1]], [0.006] * 5, seg=8),
                     m["cord"], smooth=True, sharp_angle=None)
    bpy.data.objects.remove(skin_ob, do_unlink=True)
    hands = fig.hands(m["hands"], scale=1.26, claws=(0.016, m["claw"]), uv_tile=0.1)
    for h in hands:
        dk.shell_fur(h, h.name + "_Fur", "Wolf_Pfote", paw, length=0.0065, lean=(0, 0.0, 0.0), child=True, uneven=0.2)
    upper = dk.sleeve("SleeveUpper", m["cloth"], [(0, 0.112), (0.5, 0.104), (1, 0.09)], fold0=0.5, fold1=1.0, seed=1)
    fore = dk.sleeve("SleeveFore", m["cloth"], [(0, 0.09), (0.4, 0.084), (1, 0.066)], cap1=False, fold0=1.0, seed=2,
                     lining=True)
    for ob in (body, mrig, *parts.values()):
        bpy.data.objects.remove(ob, do_unlink=True)
    hd.preview_arms(upper, fore, hands[0], hands[1])
    return fig
