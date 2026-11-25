"""Der Knochenmann – Überarbeitung (Konzeptbild „Am Spieltisch“, Feld 6).

Schädel mit Zylinder und Kerze sowie die Knochenhände kommen aus `hd_bone_man.py`; neu sind der
schmale Oberkörper mit echten Schultern unter dem Gehrock, das rote Revers mit Stehkragen, der
Brustkorb in der Mantelöffnung und die Ärmel.

    import dk_bone_man; dk_bone_man.build()
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

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


def _box(lo, hi):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    lo, hi = Vector(lo), Vector(hi)
    for v in bm.verts:
        v.co = Vector(((lo.x + hi.x) / 2 + v.co.x * (hi.x - lo.x), (lo.y + hi.y) / 2 + v.co.y * (hi.y - lo.y),
                       (lo.z + hi.z) / 2 + v.co.z * (hi.z - lo.z)))
    return bm


def head(fig, m, rnd):
    """Schädel mit echten Höhlen: Hirnschädel, Brauenbogen, Augenhöhlen mit Rand, birnenförmige
    Nasenöffnung, Jochbeine mit Jochbogen, eingezogene Schläfen, Oberkiefer bis zur Zahnreihe;
    Unterkiefer als eigenes Teil (klappt beim Lachen auf). Zylinder und Kerze aus hd_bone_man."""
    rig, hb, C = fig.rig, fig.rig.head, alt.C
    parts = [geo.ellipsoid(Vector((0.108, 0.132, 0.118)), C + Vector((0, 0.0, 0.04)), 64, 44),
             geo.ellipsoid(Vector((0.062, 0.05, 0.06)), C + Vector((0, -0.075, -0.035)), 32, 22),
             geo.ellipsoid(Vector((0.012, 0.012, 0.022)), C + Vector((0, -0.126, -0.004)), 14, 10)]
    brow = [C + Vector((u * 0.088, -0.124 + 0.04 * u * u, 0.036 - 0.006 * abs(u))) for u in (k / 8 * 2 - 1 for k in range(9))]
    parts.append(geo.tube(brow, [0.012 - 0.003 * abs(k / 8 * 2 - 1) for k in range(9)], seg=12))
    for s in (-1, 1):
        ec = C + Vector((s * 0.042, -0.123, 0.006))
        ring = [ec + Vector((0.03 * math.cos(a), 0.012 * abs(math.cos(a)) * 0.6, 0.027 * math.sin(a))) for a in
                (k / 20 * math.tau for k in range(21))]
        parts.append(geo.tube(ring, [0.0075] * 21, seg=10, cap_start=False))
        parts.append(geo.ellipsoid(Vector((0.026, 0.022, 0.02)), C + Vector((s * 0.068, -0.095, -0.022)), 18, 12))
        parts.append(geo.tube([C + Vector((s * 0.085, -0.08, -0.022)), C + Vector((s * 0.104, -0.02, -0.018)),
                               C + Vector((s * 0.105, 0.03, -0.012))], [0.009, 0.008, 0.009], seg=10))
    skull = rig.headpart("Face", geo.merge(*parts), m["bone"], smooth=True, sharp_angle=None)
    hd.organic(skull, voxel=0.0022, smooth=3, faces=10 ** 7, uv_tile=0.12)
    cut = [_box(C + Vector((-0.2, -0.3, -0.3)), C + Vector((0.2, 0.012, alt.GUM_Z - 0.004)))]
    for s in (-1, 1):
        so = geo.ellipsoid(Vector((0.027, 0.042, 0.025)), Vector((0, 0, 0)), 26, 18)
        geo.transform(so, Matrix.Translation(C + Vector((s * 0.042, -0.128, 0.006))) @ Matrix.Rotation(s * -0.14, 4, "Y"))
        cut.append(so)
        no = geo.ellipsoid(Vector((0.0105, 0.032, 0.021)), Vector((0, 0, 0)), 16, 12)
        geo.transform(no, Matrix.Translation(C + Vector((s * 0.0065, -0.13, -0.04))) @ Matrix.Rotation(s * 0.28, 4, "Y"))
        cut.append(no)
        cut.append(geo.ellipsoid(Vector((0.025, 0.05, 0.04)), C + Vector((s * 0.124, -0.035, 0.03)), 18, 12))
        cut.append(geo.ellipsoid(Vector((0.018, 0.03, 0.016)), C + Vector((s * 0.076, -0.07, -0.049)), 16, 10))
    cut.append(geo.ellipsoid(Vector((0.007, 0.032, 0.014)), C + Vector((0, -0.13, -0.024)), 14, 10))
    dk.carve(skull, cut)
    dk.rebox(skull, 0.12)
    tree = dk.bvh(skull)

    def surf(x, z, lift=0.0):
        hit = tree.ray_cast(C + Vector((x, -0.6, z)), Vector((0, 1, 0)))
        if hit[0] is None:
            return C + Vector((x, -alt.RY, z)), Vector((0, -1, 0))
        return hit[0] + hit[1] * lift, hit[1]
    voids = [geo.ellipsoid(Vector((0.011, 0.01, 0.02)), C + Vector((0, -0.094, -0.036)), 12, 8)]
    glow, core = [], []
    for i, s in enumerate((-1, 1)):
        voids.append(geo.ellipsoid(Vector((0.025, 0.01, 0.023)), C + Vector((s * 0.042, -0.094, 0.006)), 18, 10))
        c = C + Vector((s * 0.042, -0.106, 0.004))
        glow.append(geo.ellipsoid(Vector((0.0125, 0.008, 0.0125)), c, 18, 12))
        core.append(geo.ellipsoid(Vector((0.0055, 0.003, 0.0055)), c + Vector((0, -0.007, 0)), 12, 8))
        rig.marker("EyeL" if i == 0 else "EyeR", hb, c + Vector((0, -0.006, 0)))
    rig.headpart("Void_Sockets", geo.merge(*voids), dk.ch.void(), smooth=True, sharp_angle=None)
    rig.headpart("Glow_Eyes", geo.merge(*glow), m["eye"], smooth=True, sharp_angle=None)
    rig.headpart("Glow_EyeCores", geo.merge(*core), m["eyecore"], smooth=True, sharp_angle=None)
    alt.upper_teeth(rig, m, surf, rnd)
    jaw(rig, m, surf, rnd)
    alt.top_hat(rig, m, tree, rnd)
    alt.scale_head(rig, alt.HEAD_SCALE)


def jaw(rig, m, surf, rnd):
    """Unterkiefer: schlanker Bogen unter der Zahnreihe, Kinn, Kieferwinkel, aufsteigende Äste mit
    Gelenkkopf und Muskelfortsatz – hängt am Jaw-Empty."""
    C, TZ = alt.C, alt.TEETH_Z
    jaw_e = rig.marker("Jaw", rig.head, alt.HINGE)
    arc = []
    for k in range(21):
        x = (k / 20 * 2 - 1) * 0.054
        p, n = surf(x, alt.GUM_Z + 0.012)
        out = Vector((n.x, n.y, 0))
        out = out.normalized() if out.length > 1e-4 else Vector((0, -1, 0))
        arc.append(Vector((p.x, p.y, 0)) - out * 0.003)
    zc = C.z + TZ - 0.03
    ring = [Vector((-0.061, 0.03, 0)), Vector((-0.057, arc[0].y + 0.04, 0))] + arc + \
           [Vector((0.057, arc[-1].y + 0.04, 0)), Vector((0.061, 0.03, 0))]
    path, radii = [], []
    for i, q in enumerate(ring):
        t = abs(i / (len(ring) - 1) * 2 - 1)
        path.append(Vector((q.x, q.y, zc)))
        radii.append(0.0078 + 0.0015 * (1 - t))
    body = geo.tube(path, radii, seg=14)
    for v in body.verts:  # hoch und schmal, vorn am Kinn höher
        front = max(0.0, 1 - abs(v.co.x) / 0.05)
        v.co.z = zc + (v.co.z - zc) * (1.9 + 0.5 * front) - 0.004 * front
    parts = [body]
    cy = arc[10].y
    parts.append(geo.ellipsoid(Vector((0.02, 0.01, 0.014)), Vector((0, cy + 0.001, zc - 0.014)), 18, 12))
    for s in (-1, 1):
        parts.append(geo.ellipsoid(Vector((0.008, 0.007, 0.008)), Vector((s * 0.014, cy + 0.0, zc - 0.02)), 10, 8))
        ramus = geo.tube([Vector((s * 0.061, 0.03, zc - 0.006)), Vector((s * 0.064, 0.036, C.z - 0.075)),
                          Vector((s * 0.067, 0.038, C.z - 0.04))], [0.013, 0.011, 0.008], seg=12)
        for v in ramus.verts:
            v.co.x = s * 0.064 + (v.co.x - s * 0.064) * 0.5
        parts.append(ramus)
        parts.append(geo.ellipsoid(Vector((0.006, 0.008, 0.006)), Vector((s * 0.067, 0.039, C.z - 0.036)), 10, 8))
        parts.append(geo.tube([Vector((s * 0.063, 0.03, C.z - 0.085)), Vector((s * 0.062, 0.012, C.z - 0.062)),
                               Vector((s * 0.061, 0.004, C.z - 0.048))], [0.006, 0.005, 0.003], seg=8))
    ob = rig.headpart("Jaw_Bone", geo.merge(*parts), m["bone"], smooth=True, sharp_angle=None)
    hd.organic(ob, voxel=0.0016, smooth=2, faces=9000, uv_tile=0.12)
    lower = []
    for s in (-1, 1):
        for k, (xx, w) in enumerate(zip(alt.TOOTH_X, alt.TOOTH_W)):
            x = s * xx * 0.97
            h = (0.02 if k < 3 else 0.017) * rnd.uniform(0.92, 1.05)
            p, nrm = surf(x, alt.GUM_Z + 0.012)
            out = Vector((nrm.x, nrm.y, 0))
            out = out.normalized() if out.length > 1e-4 else Vector((0, -1, 0))
            base = Vector((p.x, p.y, C.z + TZ - 0.0008 - h * 0.5)) - out * 0.0055
            lower.append(alt._tooth(base, Vector((0, 0, 1)), out, w * 0.95, h, 0.0085, rnd, crown_down=False))
    lt = rig.headpart("Jaw_Teeth", geo.merge(*lower), m["teeth"], smooth=True, sharp_angle=None)
    for o in (ob, lt):
        o.data.transform(Matrix.Translation(-alt.HINGE))
        o.parent = jaw_e
        o.location = (0, 0, 0)


def build():
    rnd = random.Random(31)
    hd.clear_scene()
    body, mrig, parts = dk.make_human(MACRO, TARGETS, brows=None, lashes=None, teeth=None, eyes=None)
    m = alt.materials()
    m["lining"].use_backface_culling = False  # Revers und Kragen sind von beiden Seiten zu sehen
    m["coat"].use_backface_culling = False
    fig = dk.Figure(body, mrig, parts, waist=0.5)
    nc = dk.to_torso(mrig.pose.bones["neck01"].head)
    fig.rig.head.location = Vector((0, nc.y - 0.03, alt.HEAD_Y))
    head(fig, m, rnd)
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
