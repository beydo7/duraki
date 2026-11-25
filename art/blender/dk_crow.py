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
from mathutils import Matrix, Vector

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


def eyes(rig, m):
    """Kleine, weißlich glühende Augen tief unter dem Brauenwulst, mit breitem dunklem Rand."""
    voids, glow, core = [], [], []
    for i, e in enumerate(alt.EYES):
        side = -1 if e.x < 0 else 1
        n = alt.eye_normal(side)
        rot = Vector((0, -1, 0)).rotation_difference(n).to_matrix().to_4x4()
        for lst, radii, off in ((voids, (0.021, 0.006, 0.0185), -0.002), (glow, (0.0092, 0.006, 0.0088), 0.0005),
                                (core, (0.0038, 0.003, 0.0038), 0.0045)):
            b = geo.ellipsoid(Vector(radii), Vector((0, 0, 0)), 20, 12)
            geo.transform(b, Matrix.Translation(e + n * off) @ rot)
            lst.append(b)
        rig.marker("EyeL" if side < 0 else "EyeR", rig.head, e + n * 0.003)
    rig.headpart("Void_Sockets", geo.merge(*voids), dk.ch.void(), smooth=True, sharp_angle=None)
    rig.headpart("Glow_Eyes", geo.merge(*glow), m["eye"], smooth=True, sharp_angle=None)
    rig.headpart("Glow_EyeCores", geo.merge(*core), m["eyecore"], smooth=True, sharp_angle=None)


def head_feathers(rig, m, rnd, cr, face):
    """Kopfgefieder: vorn klein und anliegend, auf Scheitel und Nacken lang und struppig aufgestellt
    (zerzauste Silhouette wie im Konzept), dazu finstere Federbrauen, Nasenborsten, Kehlfedern.
    Zwei Federtöne im Wechsel, damit die Lagen im Spiel lesbar bleiben."""
    hb = rig.head
    sets = [(hd.MeshBuilder(), []), (hd.MeshBuilder(), [])]
    hk, hs = hd.MeshBuilder(), []

    def put(*a, **kw):
        mb, sp = sets[1] if rnd.random() < 0.32 else sets[0]
        alt.card(mb, sp, *a, **kw)

    def keep(p, nrm):
        if p.y < alt.BEAK_ROOT + 0.016 and abs(p.x) < 0.04 and abs(p.z - alt.GAPE - 0.01) < 0.05:
            return False
        return all((p - e).length > 0.023 for e in alt.EYES)

    for p, nrm in hd.sample_surface(cr, 4600, rnd, keep):
        q = p - alt.SKULL_C
        front = max(0.0, min(1.0, (-q.y + 0.02) / 0.12))
        back = max(0.0, min(1.0, q.y / 0.11))
        throat = max(0.0, min(1.0, (0.0 - q.z) / 0.07))
        crest = max(0.0, min(1.0, (q.z - 0.03) / 0.06)) * max(0.0, min(1.0, (q.y + 0.05) / 0.1))
        flow = Vector((0, 1, -0.25)).lerp(Vector((0, 0.25, -1)), throat * 0.85) + Vector((q.x * 2.0, 0, 0))
        L = (0.028 - 0.01 * front + 0.022 * back ** 1.5 + 0.05 * crest) * rnd.uniform(0.8, 1.25)
        lift = rnd.uniform(0.06, 0.13) + 0.42 * crest * rnd.uniform(0.5, 1.2) + 0.1 * back ** 2
        put(p, nrm, flow, L, L * rnd.uniform(0.28, 0.36), lift=lift, curl=0.04 - 0.1 * crest, cup=0.14,
            twist=rnd.uniform(-0.25, 0.25), sink=0.002, along=5, across=3)
    for (a, b) in alt.BROW:
        for s in (-1, 1):
            for row in range(3):
                for k in range(12):
                    t = k / 11
                    x = s * (a[0] + (b[0] - a[0]) * t)
                    z = a[1] + (b[1] - a[1]) * t + 0.005 - row * 0.007
                    hit = alt.surf_hit(cr, Vector((x, -0.3, z)), Vector((0, 1, 0)))
                    if hit is None:
                        continue
                    L = (0.026 + 0.02 * t) * rnd.uniform(0.9, 1.15) * (1.0 - 0.15 * row)
                    put(hit[0], hit[1], Vector((s * 1.0, 0.5, 0.3 + 0.25 * t)), L, L * 0.36, lift=0.2 + 0.1 * row,
                        curl=0.02, cup=0.12, twist=rnd.uniform(-0.15, 0.15), sink=0.001)
    for e in alt.EYES:
        side = -1 if e.x < 0 else 1
        n = alt.eye_normal(side)
        dd, ss, _ = hd.frame(n, Vector((0, 0, 1)))
        for k in range(20):
            a = k / 20 * math.tau
            r = dd * math.cos(a) + ss * math.sin(a)
            put(e + r * 0.0215 - n * 0.002, n, r, 0.012, 0.005, lift=0.2, curl=0.0, cup=0.08)
    for k in range(70):
        t = rnd.uniform(0.0, 0.32)
        x = rnd.uniform(-0.03, 0.03) * (1 - t)
        y = alt.BEAK_ROOT - alt.BEAK_LEN * t + 0.016
        z = alt.GAPE - 0.052 * t * t + 0.06 * (1 - t) ** 0.9 + 0.004 - (x / 0.032) ** 2 * 0.022
        L = rnd.uniform(0.035, 0.06)
        put(Vector((x, y, z)), Vector((x * 8, -0.1, 1)).normalized(), Vector((x * 2, -1, -0.2)), L, L * 0.28, lift=0.07,
            curl=0.02, cup=0.12)
    for p, nrm in hd.sample_surface(cr, 650, rnd, lambda p, n: p.z < alt.SKULL_C.z - 0.03 and n.z < 0.3):
        L = rnd.uniform(0.065, 0.125)
        alt.card(hk, hs, p, nrm, Vector((rnd.uniform(-0.25, 0.25), 0.1, -1)), L, L * 0.2, lift=rnd.uniform(0.1, 0.26),
                 curl=0.04, cup=0.08, twist=rnd.uniform(-0.3, 0.3), along=6, across=2)
    hd.shade_like(alt.finish_cards(*sets[0], "Head_Feathers", m["feather"], hb), face, 0.7)
    hd.shade_like(alt.finish_cards(*sets[1], "Head_Feathers2", m["feather2"], hb), face, 0.7)
    hd.shade_like(alt.finish_cards(hk, hs, "Head_Hackles", m["hackle"], hb), face, 0.6)


def build():
    rnd = random.Random(7)
    hd.clear_scene()
    alt.surf_hit._tree = None
    body, mrig, parts = dk.make_human(MACRO, TARGETS, brows=None, lashes=None, teeth=None, eyes=None)
    for sfx, s in ((".L", 1), (".R", -1)):
        dk.aim_arm(mrig, sfx, Vector((s * 0.3, -0.72, -0.62)))
        dk.grip_pose(mrig, sfx, curl=(34, 58, 42))
    m = alt.materials()
    for key, f in (("feather", 1.5), ("plume", 1.55), ("hackle", 1.5), ("plumage", 1.5), ("coat", 1.3), ("beak", 1.2)):
        dk.brighten(m[key], f)
    c, n = alt.tex_feather_card("feather2", (0.27, 0.2, 0.16), (0.36, 0.24, 0.42), seed=14, ragged=1.3)
    m["feather2"] = hd.material("Kraehe_Feder_hell", c, n, rough=0.62, normal_strength=0.8, double_sided=True,
                                spec=0.08, alpha_clip=True)
    next(nd for nd in m["beak"].node_tree.nodes if nd.type == "BSDF_PRINCIPLED").inputs["Roughness"].default_value = 0.72
    dk.brighten(m["feather2"], 1.25)
    alt.eyes, alt.head_feathers = eyes, head_feathers
    alt.BROW = [((0.022, 0.136), (0.097, 0.172))]
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
