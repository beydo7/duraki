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
from mathutils import Matrix, Vector, noise

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


def head(fig, m, moss, rnd):
    """Kopf als hoher Schlammhügel, der ohne Hals in die Schultern übergeht: schwerer Stirnwulst,
    tiefe Augenhöhlen mit Glut, Nasenschlitze, aufgerissenes Maul mit Schlammzähnen; darüber
    senkrechte Rinnsale, Tropfen, Moos auf dem Scheitel, Zweige und Pilze."""
    rig, hb, C = fig.rig, fig.rig.head, alt.C
    dome = geo.ellipsoid(Vector((0.13, 0.135, 0.19)), C + Vector((0, 0.0, 0.03)), 72, 48)
    for v in dome.verts:
        k = v.co - C
        if k.z < -0.02:
            f = 1 + 0.6 * min(1.0, (-0.02 - k.z) / 0.14) ** 1.4
            v.co.x, v.co.y = C.x + k.x * f, C.y + k.y * f
    parts = [dome]
    brow, rad = [], []
    for i in range(11):
        u = i / 10 * 2 - 1
        x = u * 0.1
        brow.append(C + Vector((x, -0.116 + 0.05 * u * u, 0.085 - 0.02 * (1 - abs(u)) ** 1.5)))
        rad.append(0.027 - 0.011 * abs(u))
    parts.append(geo.tube(brow, rad, seg=14))
    for s in (-1, 1):
        parts.append(geo.ellipsoid(Vector((0.05, 0.045, 0.06)), C + Vector((s * 0.088, -0.088, -0.025)), 20, 14))
    parts.append(geo.ellipsoid(Vector((0.022, 0.022, 0.04)), C + Vector((0, -0.128, 0.012)), 16, 12))
    parts.append(geo.ellipsoid(Vector((0.105, 0.07, 0.06)), C + Vector((0, -0.075, -0.105)), 24, 16))
    face = rig.headpart("Face", geo.merge(*parts), m["mud"], smooth=True, sharp_angle=None)
    hd.organic(face, voxel=0.0035, smooth=3, faces=60000, uv_tile=0.3)
    # Rinnsale: senkrechte Furchen, dazu grobe Beulen
    def flow(p):
        streak = 1 - abs(noise.noise(Vector((p.x * 34, p.y * 34, p.z * 4.5))))
        return 0.006 * streak ** 2 + 0.006 * noise.noise(p * 9)
    dk.displace(face, flow)
    eyes = [C + Vector((s * 0.056, -0.128, 0.03)) for s in (-1, 1)]
    cut = [geo.ellipsoid(Vector((0.04, 0.045, 0.038)), e, 28, 18) for e in eyes]
    for s in (-1, 1):
        cut.append(geo.ellipsoid(Vector((0.0055, 0.03, 0.016)), C + Vector((s * 0.012, -0.15, -0.018)), 12, 8))
        mo = geo.ellipsoid(Vector((0.05, 0.06, 0.02)), Vector((0, 0, 0)), 24, 14)
        geo.transform(mo, Matrix.Translation(C + Vector((s * 0.03, -0.14, -0.078))) @ Matrix.Rotation(s * 0.2, 4, "Y"))
        cut.append(mo)
    dk.carve(face, cut)
    dk.rebox(face, 0.3)
    tree = dk.bvh(face)

    def surf(x, z, lift=0.0):
        hit = tree.ray_cast(C + Vector((x, -0.8, z)), Vector((0, 1, 0)))
        if hit[0] is None:
            return C + Vector((x, -0.13, z)), Vector((0, -1, 0))
        return hit[0] + hit[1] * lift, hit[1]
    # Glut-Augen tief in den Höhlen
    orbs, cores = [], []
    for i, e in enumerate(eyes):
        c = e + Vector((0, 0.03, 0))
        orbs.append(geo.ellipsoid(Vector((0.026, 0.02, 0.026)), c, 24, 16))
        cores.append(geo.ellipsoid(Vector((0.012, 0.006, 0.012)), c + Vector((0, -0.017, 0)), 16, 10))
        rig.marker("EyeL" if i == 0 else "EyeR", hb, c + Vector((0, -0.016, 0)))
    rig.headpart("Glow_Eyes", geo.merge(*orbs), m["eye"], smooth=True, sharp_angle=None)
    rig.headpart("Glow_EyeCores", geo.merge(*cores), m["eyecore"], smooth=True, sharp_angle=None)
    # Maul: schwarzer Rachen, krumme Schlammzähne oben und unten
    rig.headpart("Void_Mouth", geo.ellipsoid(Vector((0.09, 0.03, 0.03)), C + Vector((0, -0.108, -0.08)), 24, 12),
                 dk.ch.void(), smooth=True, sharp_angle=None)
    teeth = []
    for k in range(9):
        u = k / 8 * 2 - 1
        x = u * 0.062 + rnd.uniform(-0.003, 0.003)
        top = surf(x, -0.05 - 0.012 * u * u)[0]
        L = rnd.uniform(0.012, 0.024)
        teeth.append(geo.tube([top + Vector((0, 0.01, 0.004)), top + Vector((0, 0.012, -0.01)), top + Vector((rnd.uniform(-0.003, 0.003), 0.012, -0.01 - L))],
                              [0.0065, 0.0055, 0.0012], seg=8))
    for k in range(8):
        u = (k + 0.5) / 8 * 2 - 1
        x = u * 0.058 + rnd.uniform(-0.003, 0.003)
        bot = surf(x, -0.108 - 0.012 * u * u)[0]
        L = rnd.uniform(0.01, 0.02)
        teeth.append(geo.tube([bot + Vector((0, 0.01, -0.004)), bot + Vector((0, 0.012, 0.008)), bot + Vector((rnd.uniform(-0.003, 0.003), 0.012, 0.008 + L))],
                              [0.006, 0.005, 0.0012], seg=8))
    rig.headpart("Mouth_Teeth", geo.merge(*teeth), m["tooth"], smooth=True, sharp_angle=None)
    # Tropfen: unter dem Stirnwulst, über die Wangen, vom Kinn
    drips = []
    for k in range(26):
        zone = k % 3
        if zone == 0:
            x, z, L = rnd.choice((-1, 1)) * rnd.uniform(0.085, 0.125), rnd.uniform(0.02, 0.07), rnd.uniform(0.04, 0.09)
        elif zone == 1:
            x, z, L = rnd.uniform(-0.12, 0.12), rnd.uniform(-0.05, -0.02), rnd.uniform(0.03, 0.07)
            if abs(x) < 0.07:
                z = -0.112
        else:
            x, z, L = rnd.uniform(-0.09, 0.09), rnd.uniform(-0.125, -0.112), rnd.uniform(0.03, 0.08)
        drips.append(alt.drip(surf, x, z, L, rnd.uniform(0.004, 0.0065), rnd))
    rig.headpart("Face_Drips", geo.merge(*drips), m["mud"], smooth=True, sharp_angle=None)
    alt.twigs_and_shrooms(rig, m, tree, rnd)
    # Moos auf dem Scheitel und in Polstern an den Seiten
    base = dk.fur_base(face, "MoosBasis", faces=14000, tile=0.12,
                       keep=lambda c, n: n.z > 0.2 and ((c - C).z > 0.15 or ((c - C).z > 0.02 and noise.noise(c * 8) > 0.05)))
    dk.shell_fur(base, "HeadMoss_Fur", "Sumpf_Moospolster", moss, length=0.02, lean=(0, 0, -0.1), uneven=0.6)
    bpy.data.objects.remove(base, do_unlink=True)
    alt.scale_head(rig, 1.7)


def build():
    rnd = random.Random(21)
    hd.clear_scene()
    body, mrig, parts = dk.make_human(MACRO, TARGETS, brows=None, lashes=None, teeth=None, eyes=None)
    for sfx, s in ((".L", 1), (".R", -1)):
        dk.aim_arm(mrig, sfx, Vector((s * 0.34, -0.7, -0.62)))
        dk.grip_pose(mrig, sfx, curl=(40, 62, 44))
    m = alt.materials()
    dk.brighten(m["mud"], 0.82)
    for key in ("mud", "head"):  # weniger Glitzern im Lampenlicht
        bsdf = next(nd for nd in m[key].node_tree.nodes if nd.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Roughness"].default_value = 0.72
        bsdf.inputs["Specular IOR Level"].default_value = 0.3
    moss = dk.tex_fur_shells("moss", (0.03, 0.045, 0.012), (0.2, 0.27, 0.07), shells=12, clumps=700, radius=6.5, seed=61)
    fig = dk.Figure(body, mrig, parts, waist=0.42)
    tb = fig.rig.torso
    nc = dk.to_torso(mrig.pose.bones["neck01"].head)
    fig.rig.head.location = Vector((0, nc.y - 0.03, alt.HEAD_Y))
    head(fig, m, moss, rnd)
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
