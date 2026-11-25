"""Die Wölfin – Überarbeitung (Konzeptbild „Am Spieltisch“, Feld 4).

Wolfskopf mit roter Kapuze kommt aus `hd_wolf.py`; neu sind der weibliche Oberkörper im Mieder,
dichtes Schalen-Fell an Brust und Hals, der rote Umhang auf echten Schultern, die Ärmel und
befellte Hände mit Krallen.

    import dk_wolf; dk_wolf.build()
"""
from __future__ import annotations

import math
import random

import bpy
import numpy as np
from mathutils import Vector

import dk
import geo
import hd
import hd_wolf as alt

MACRO = dict(gender=0.0, age=0.45, muscle=0.45, weight=0.45, height=0.5, proportions=0.6, cupsize=0.55,
             firmness=0.7, race={"asian": 0.1, "caucasian": 0.9, "african": 0.0})
TARGETS = {**dk.both("hand-fingers-diameter-incr", 0.5), **dk.both("hand-fingers-length-incr", 0.3),
           "neck-scale-horiz-incr": 0.6, "neck-scale-depth-incr": 0.5}


GREY, LIGHT, DARK = (0.42, 0.39, 0.37), (0.8, 0.76, 0.69), (0.19, 0.18, 0.18)


def _ss(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def face_fur(rig, m, sample_bm, face, rnd):
    """Gesichtsfell als Schalen: Zeichnung (hell/grau/dunkel/schwarz) als Vertexfarbe, kurz an
    Schnauze und Augen, lang an den Wangen; Strich von der Nase weg nach außen und hinten."""
    base = dk.fur_base(face, "FurBase", faces=9000)
    co, no = dk.verts(base)
    k = co - np.array(alt.C[:], dtype=np.float32)
    x, y, z = k[:, 0], k[:, 1], k[:, 2]
    ax = np.abs(x)
    white, dark, black = alt.face_masks(x, z)
    side = _ss(0.0, 0.06, y)[:, None]  # hinter den Wangen: einfach grau (die Maske gilt nur von vorn)
    lin = [np.array(hd.srgb_to_linear(c), dtype=np.float32) for c in (GREY, LIGHT, DARK)]
    col = lin[0][None, :] * (1 - white[:, None]) + lin[1][None, :] * white[:, None]
    col = col * (1 - dark[:, None]) + lin[2][None, :] * dark[:, None]
    col = col * (1 - 0.93 * black[:, None])
    col = col * (1 - side) + lin[0][None, :] * side
    cheek = _ss(0.04, 0.095, ax) * _ss(0.045, -0.03, z)
    muzzle = _ss(-0.1, -0.14, y)
    eye = np.zeros_like(x)
    for ex, ez in alt.EYES:
        eye = np.maximum(eye, np.exp(-((x - ex) ** 2 + (z - ez) ** 2) / (2 * 0.02 ** 2)) * (y < -0.02))
    L = 0.008 + 0.017 * cheek + 0.004 * _ss(0.06, 0.12, z)
    L = L * (1 - muzzle) + 0.0032 * muzzle
    L = L * (1 - eye) + 0.0018 * eye
    L = np.maximum(L * (1 - black), 0.0012)
    flow = np.stack([np.sign(x) * np.minimum(1, ax / 0.04) * 0.9, 0.55 + 0 * x, 0.45 * _ss(0.03, 0.09, z) - 0.7 * cheek], axis=1)
    lean = dk.tangent(flow.astype(np.float32), no) * 1.1
    dk.shell_fur(base, "Face_Fur", "Wolf_Fell", m["shells"], lengths=L, leans=lean, colors=col, uneven=0.35)
    bpy.data.objects.remove(base, do_unlink=True)
    ruff(rig, m, rnd)


def ruff(rig, m, rnd):
    """Wangenkrause: spitze Fellzacken entlang des Kiefers, die unter der Kapuze hervorstehen."""
    C = alt.C
    parts = []
    for s in (-1, 1):
        for row, (out, scale) in enumerate(((0.0, 1.0), (-0.012, 0.75))):
            for i in range(7):
                t = (i + 0.5 * row) / 6.5
                p = C + Vector((s * (0.1 - 0.055 * t + out), -0.035 - 0.05 * t, 0.012 - 0.105 * t))
                d = Vector((s * (0.95 - 0.6 * t), -0.25, -(0.3 + 0.75 * t))).normalized()
                Ln = (0.05 + 0.02 * math.sin(math.pi * t)) * scale * rnd.uniform(0.85, 1.15)
                r = 0.02 * scale
                parts.append(geo.tube([p - d * 0.02, p + d * Ln * 0.45, p + d * Ln], [r, r * 0.7, 0.002], seg=10))
    ob = rig.headpart("Face_Ruff", geo.merge(*parts), m["furskin"], smooth=True, sharp_angle=None)
    hd.organic(ob, voxel=0.004, smooth=2, faces=2600, uv_tile=0.09)
    co, no = dk.verts(ob)
    k = co - np.array(C[:], dtype=np.float32)
    tipness = _ss(0.02, -0.1, k[:, 2])
    lin = [np.array(hd.srgb_to_linear(c), dtype=np.float32) for c in (LIGHT, GREY)]
    col = lin[0][None, :] * (1 - 0.35 * tipness[:, None]) + lin[1][None, :] * 0.35 * tipness[:, None]
    flow = np.stack([np.sign(k[:, 0]) * 0.7, -0.1 + 0 * k[:, 0], -0.8 + 0 * k[:, 0]], axis=1).astype(np.float32)
    dk.shell_fur(ob, "Face_Ruff_Fur", "Wolf_Fell", m["shells"], lengths=np.full(len(co), 0.014), leans=dk.tangent(flow, no) * 1.3,
                 colors=col, uneven=0.4)


def neck_fur(rig, m, tree, rnd):
    """Kehle und Hals: helle Säule unter dem Kinn, das Fell fällt zur Brust."""
    C = alt.C
    nb = geo.tube([C + Vector((0, 0.0, -0.04)), C + Vector((0, 0.01, -0.14)), C + Vector((0, 0.02, -0.26))],
                  [0.085, 0.092, 0.1], seg=32)
    geo.box_uv(nb, 0.09)
    neck = rig.headpart("Neck", nb, m["chest"], smooth=True, sharp_angle=None)
    co, no = dk.verts(neck)
    front = _ss(0.3, -0.4, no[:, 1])
    lin = [np.array(hd.srgb_to_linear(c), dtype=np.float32) for c in (LIGHT, GREY)]
    col = lin[1][None, :] * (1 - front[:, None]) + lin[0][None, :] * front[:, None]
    flow = np.tile(np.array([[0.0, -0.15, -1.0]], dtype=np.float32), (len(co), 1))
    dk.shell_fur(neck, "Neck_Fur", "Wolf_Fell", m["shells"], lengths=np.full(len(co), 0.022), leans=dk.tangent(flow, no) * 0.8,
                 colors=col, uneven=0.4)


def build():
    rnd = random.Random(17)
    hd.clear_scene()
    body, mrig, parts = dk.make_human(MACRO, TARGETS, brows=None, lashes=None, teeth=None, eyes=None)
    for sfx, s in ((".L", 1), (".R", -1)):
        dk.aim_arm(mrig, sfx, Vector((s * 0.3, -0.72, -0.62)))
        dk.grip_pose(mrig, sfx, curl=(36, 60, 42))
    m = alt.materials()
    m["shells"] = dk.tex_fur_shells("fell", (0.42, 0.42, 0.42), (1.0, 1.0, 1.0), shells=12, clumps=1000, radius=4.8, seed=71)
    paw = dk.tex_fur_shells("paw", (0.14, 0.135, 0.13), (0.5, 0.49, 0.47), shells=8, clumps=2200, radius=3.2, seed=72)
    fig = dk.Figure(body, mrig, parts, waist=0.42)
    tb = fig.rig.torso
    # Kopf: Schädel, Augen, Nase, Ohren und Kapuze aus hd_wolf – Fell neu (Schalen statt Karten)
    alt.face_fur, alt.neck_fur, alt.brows = face_fur, neck_fur, (lambda *a, **k: None)
    nc = dk.old_head(fig, alt, rnd, m)
    skin_ob = fig.torso(m["furskin"], arm_stub=0.055)

    def neckline(c):  # tiefer, runder Ausschnitt vorn; hinten hochgeschlossen
        if c.y > nc.y:
            return nc.z - 0.05
        return nc.z - 0.27 + 2.6 * c.x * c.x
    bodice = dk.part_of(skin_ob, "Body", m["bodice"], lambda c, n: c.z < neckline(c), grow=0.008, tile=0.22)
    pelt = dk.part_of(skin_ob, "Pelt", m["furskin"], lambda c, n: c.z > neckline(c) - 0.03, tile=0.09)
    co, no = dk.verts(pelt)
    center = np.exp(-(co[:, 0] / 0.11) ** 2) * (no[:, 1] < 0.2)
    lin = [np.array(hd.srgb_to_linear(c), dtype=np.float32) for c in (GREY, LIGHT)]
    col = lin[0][None, :] * (1 - center[:, None]) + lin[1][None, :] * center[:, None]
    flow = np.stack([co[:, 0] * 1.5, -0.1 + 0 * co[:, 0], -1.0 + 0 * co[:, 0]], axis=1).astype(np.float32)
    dk.shell_fur(pelt, "Body_Chest_Fur", "Wolf_Fell", m["shells"], lengths=np.full(len(co), 0.034),
                 leans=dk.tangent(flow, no) * 1.3, colors=col, uneven=0.4)
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
