"""Die Krähe in HD: Rabenkopf mit echten, überlappenden Federn, gelofteter Hakenschnabel,
zerlumpte violett-schwarze Kutte mit Kapuzenwulst, Ketten mit Knochen-Anhängern,
schuppige Krallenhände.

    import hd_crow; hd_crow.build()            # alles neu
    hd_crow.build(steps=("head",))             # nur Teile (zum Ausprobieren)
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

import characters as ch
import geo
import hd
from geo import G

# --- Rumpf (Torso-Koordinaten) ------------------------------------------------------

PROFILE = [(0.25, -0.15), (0.265, 0.1), (0.27, 0.45), (0.278, 0.72), (0.282, 0.88), (0.265, 0.98),
           (0.21, 1.05), (0.15, 1.085), (0.09, 1.1), (0.02, 1.105)]
SX, SY, HUNCH, BUMP = 1.4, 0.8, 0.1, 0.02


def _radius(z: float) -> float:
    prof = PROFILE
    if z <= prof[0][1]:
        return prof[0][0]
    for (r0, z0), (r1, z1) in zip(prof, prof[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            t = t * t * (3 - 2 * t)
            return r0 + (r1 - r0) * t
    return prof[-1][0]


def body_point(th: float, z: float, out: float = 0.0, folds: bool = True) -> Vector:
    """Punkt auf der Kutte. th: Winkel (3π/2 = vorne, -Y), out: Abstand nach außen."""
    r = _radius(z)
    fold = 0.0
    if folds:
        amp = 0.016 * min(1.0, max(0.0, (0.98 - z) / 0.55)) + 0.003
        warp = noise.noise(Vector((math.cos(th) * 2.0, math.sin(th) * 2.0, z * 1.3))) * 1.6
        fold = amp * (0.65 * math.sin(th * 11 + warp) + 0.35 * math.sin(th * 23 + warp * 1.7 + 1.0))
        fold += 0.006 * noise.noise(Vector((math.cos(th) * 6, math.sin(th) * 6, z * 6)))
    rr = r + fold + out
    x = rr * SX * math.cos(th)
    y = rr * SY * math.sin(th)
    zz = z
    ax = abs(x)
    if z > 0.72:
        t = min(1.0, (z - 0.72) / 0.4)
        y -= HUNCH * t * max(0.0, 1 - ax / 0.5)
    bump = math.exp(-((ax - 0.33) ** 2) / (2 * 0.075 ** 2)) * math.exp(-((z - 1.0) ** 2) / (2 * 0.07 ** 2))
    zz += BUMP * bump
    return Vector((x, y, zz))


def body_normal(th: float, z: float) -> Vector:
    e = 0.004
    p = body_point(th, z, folds=False)
    a = body_point(th + e, z, folds=False) - p
    b = body_point(th, z + e, folds=False) - p
    n = a.cross(b).normalized()
    return n if n.dot(Vector((p.x, p.y, 0))) >= 0 else -n


def theta_front(x: float, z: float) -> float:
    r = _radius(z) * SX
    c = max(-0.999, min(0.999, x / r))
    return math.tau - math.acos(c)


# --- Materialien ---------------------------------------------------------------------

def materials():
    m = {}
    c, n = hd.tex_cloth("robe", (0.075, 0.052, 0.09), (0.01, 0.007, 0.015), seed=11, rag=0.6)
    m["robe"] = hd.material("Kraehe_Kutte", c, n, rough=0.93, normal_strength=0.8, spec=0.25)
    c, n = hd.tex_cloth("rags", (0.075, 0.048, 0.088), (0.01, 0.006, 0.014), seed=12, weave=70, rag=0.9)
    m["rags"] = hd.material("Kraehe_Lumpen", c, n, rough=0.92, normal_strength=0.9, double_sided=True, spec=0.25)
    c, n = hd.tex_feather("feather", seed=4)
    m["feather"] = hd.material("Kraehe_Feder", c, n, rough=0.6, normal_strength=0.6, double_sided=True, spec=0.35)
    c, n = hd.tex_feather("hackle", base=(0.025, 0.023, 0.032), sheen=(0.1, 0.08, 0.16), seed=8)
    m["hackle"] = hd.material("Kraehe_Halsfeder", c, n, rough=0.68, normal_strength=0.6, double_sided=True, spec=0.3)
    c, n = hd.tex_keratin("beak", (0.075, 0.072, 0.08), seed=21)
    m["beak"] = hd.material("Kraehe_Schnabel", c, n, rough=0.5, normal_strength=0.5, spec=0.4)
    c, n = hd.tex_scales("skin", (0.06, 0.056, 0.06), seed=31, cells=44)
    m["skin"] = hd.material("Kraehe_Haut", c, n, rough=0.68, normal_strength=1.0, spec=0.35)
    c, n = hd.tex_keratin("claw", (0.03, 0.028, 0.03), seed=22, streak=1.5)
    m["claw"] = hd.material("Kraehe_Kralle", c, n, rough=0.28, spec=0.7)
    c, n = hd.tex_keratin("bone", (0.3, 0.27, 0.21), seed=41, streak=0.6)
    m["bone"] = hd.material("Kraehe_Knochen", c, n, rough=0.7, normal_strength=0.8, spec=0.3)
    c, n = hd.tex_cloth("cord", (0.16, 0.11, 0.08), (0.04, 0.03, 0.02), size=256, seed=51, weave=40, rag=0.2)
    m["cord"] = hd.material("Kraehe_Schnur", c, n, rough=0.9)
    m["metal"] = hd.material("Kraehe_Messing", color=(0.22, 0.16, 0.08, 1), rough=0.55, metal=0.8)
    m["dark"] = hd.material("Kraehe_Dunkel", color=(0.012, 0.011, 0.014, 1), rough=0.7)
    m["eye"] = hd.material("Kraehe_Auge", color=(0.02, 0.012, 0.006, 1), rough=0.05, spec=1.0)
    return m


# =====================================================================================
#  Kopf (Head-Koordinaten)
# =====================================================================================

EYES = [Vector((-0.079, -0.05, 0.12)), Vector((0.079, -0.05, 0.12))]
GAPE = 0.074          # Höhe der Schnabelspalte an der Wurzel
BEAK_ROOT = -0.088    # Y der Schnabelwurzel
BEAK_LEN = 0.22


def cranium() -> bmesh.types.BMesh:
    """Schädel unter den Federn: flacher Scheitel, Stirn läuft in die Schnabelwurzel."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=64, v_segments=40, radius=1.0)
    c = Vector((0, 0.012, 0.11))
    for v in bm.verts:
        d = v.co.copy()
        p = c + Vector((d.x * 0.098, d.y * 0.118, d.z * 0.1))
        # Scheitel abflachen, Hinterkopf etwas voller
        if d.z > 0:
            p.z -= 0.012 * d.z ** 2
        if d.y > 0:
            p.y += 0.012 * d.y * (1 - abs(d.z))
        # Stirn nach vorne zur Schnabelwurzel ziehen
        front = max(0.0, -d.y)
        pull = front ** 2.2 * math.exp(-((p.z - GAPE - 0.02) ** 2) / (2 * 0.04 ** 2)) * math.exp(-(p.x ** 2) / (2 * 0.05 ** 2))
        p.y -= 0.045 * pull
        # Kehle hängt nach unten in den Hals
        if d.z < -0.3:
            p.z -= 0.035 * (-d.z - 0.3) * max(0.0, 1 - abs(d.x))
            p.y -= 0.01 * (-d.z - 0.3)
        v.co = p
    bm.normal_update()
    return bm


def beak_sections(lower: bool, n_len=30, n_round=20):
    secs = []
    L = BEAK_LEN * (0.8 if lower else 1.0)
    for i in range(n_len):
        t = i / (n_len - 1)
        tt = t * (0.8 if lower else 1.0)
        y = BEAK_ROOT - L * t
        gape = GAPE - 0.014 * tt - 0.018 * max(0.0, tt - 0.6) ** 2 / 0.16
        hook = -0.026 * (max(0.0, t - 0.72) / 0.28) ** 1.6 if not lower else 0.0
        w = 0.05 * (1 - tt) ** 0.75 + 0.0015
        if lower:
            h_top, h_bot = 0.004 * (1 - t), 0.036 * (1 - t) ** 0.75 + 0.002
        else:
            h_top = 0.07 * (1 - t) ** 0.65 + 0.002 + 0.006 * math.sin(math.pi * t)
            h_bot = 0.008 * (1 - t) + 0.001
        sec = []
        for j in range(n_round):
            a = j / n_round * math.tau
            sa, ca = math.sin(a), math.cos(a)
            if sa >= 0:
                z = gape + hook + h_top * (sa ** 0.85) * (1 if not lower else 1)
                x = w * ca * (1 - (0.3 if not lower else 0.0) * sa ** 2)
            else:
                z = gape + hook - h_bot * ((-sa) ** 0.9)
                x = w * ca * (1 - (0.0 if not lower else 0.25) * sa ** 2)
            if lower:
                z -= 0.002
                x *= 0.92
            sec.append(Vector((x, y, z)))
        secs.append(sec)
    return secs


def head(rig, m, rnd):
    hb = rig.head
    # Schädel
    cr = cranium()
    skull_bm = cr.copy()
    ob = hd.MeshBuilder()
    ob.bm.free()
    ob.bm = skull_bm
    ob.uv = skull_bm.loops.layers.uv.verify()
    ob.finish("Face", m["dark"], parent=hb)

    # Oberschnabel
    mb = hd.MeshBuilder()
    hd.loft(mb, beak_sections(False), uv_scale=(1.0, 2.0))
    beak = mb.finish("Beak", m["beak"], parent=hb)
    beak.data.polygons.foreach_set("use_smooth", [True] * len(beak.data.polygons))

    # Unterschnabel als Jaw (dreht beim Lachen um die Wurzel)
    mb = hd.MeshBuilder()
    secs = beak_sections(True)
    pivot = Vector((0, BEAK_ROOT + 0.01, GAPE - 0.004))
    secs = [[p - pivot for p in s] for s in secs]
    hd.loft(mb, secs, uv_scale=(1.0, 1.6))
    mb.finish("Jaw", m["beak"], parent=hb, location=pivot)

    # Augen: glänzend dunkel, Godot setzt die glühende Pupille an EyeL/EyeR
    for i, e in enumerate(EYES):
        side = -1 if e.x < 0 else 1
        n = Vector((side * 0.9, -0.45, 0.05)).normalized()
        b = bmesh.new()
        bmesh.ops.create_uvsphere(b, u_segments=20, v_segments=14, radius=0.0135)
        bmesh.ops.translate(b, verts=b.verts, vec=e - n * 0.006)
        mb = hd.MeshBuilder()
        mb.bm.free()
        mb.bm = b
        mb.uv = b.loops.layers.uv.verify()
        mb.finish("Eye_" + ("L" if side < 0 else "R"), m["eye"], parent=hb)
        rig.marker("EyeL" if side < 0 else "EyeR", hb, e + n * 0.004)

    # Federkleid: kleine Federn vorne/um die Augen, größere nach hinten und zur Kehle
    flow_back = Vector((0, 1, -0.22))
    feathers = hd.MeshBuilder()
    hackles = hd.MeshBuilder()

    def keep(p, nrm):
        if p.y < BEAK_ROOT + 0.012 and abs(p.x) < 0.035 and abs(p.z - GAPE - 0.01) < 0.05:
            return False  # unter dem Schnabel
        return all((p - e).length > 0.017 for e in EYES)

    for p, nrm in hd.sample_surface(cr, 2600, rnd, keep):
        front = max(0.0, min(1.0, (-p.y + 0.02) / 0.12))
        throat = max(0.0, min(1.0, (0.06 - p.z) / 0.06))
        flow = flow_back.lerp(Vector((0, 0.25, -1)), throat * 0.8)
        backness = max(0.0, min(1.0, (p.y - 0.0) / 0.1))
        L = (0.034 - 0.016 * front + 0.03 * backness ** 2) * rnd.uniform(0.85, 1.2)
        W = L * rnd.uniform(0.45, 0.58)
        hd.add_feather(feathers, p, nrm, flow, L, W, lift=rnd.uniform(0.07, 0.15) + 0.12 * backness ** 2,
                       curl=0.04, cup=0.16, twist=rnd.uniform(-0.15, 0.15), sink=0.002, shape=1.0 + 0.6 * backness)
    # Ring winziger Federn um die Augen
    for e in EYES:
        side = -1 if e.x < 0 else 1
        n = Vector((side * 0.9, -0.45, 0.05)).normalized()
        d, s, _ = hd.frame(n, Vector((0, 0, 1)))
        for k in range(16):
            a = k / 16 * math.tau
            p = e + (d * math.cos(a) + s * math.sin(a)) * 0.0175 - n * 0.002
            hd.add_feather(feathers, p, n, d * math.cos(a) + s * math.sin(a), 0.012, 0.008, lift=0.25, curl=0.0, cup=0.1)
    # Nasenborsten auf der Schnabelwurzel (typisch Rabe)
    for k in range(46):
        t = rnd.uniform(0.0, 0.3)
        x = rnd.uniform(-0.028, 0.028) * (1 - t)
        y = BEAK_ROOT - BEAK_LEN * t + 0.015
        z = GAPE + 0.058 * (1 - t) ** 0.9 + 0.004 - (x / 0.03) ** 2 * 0.02
        p = Vector((x, y, z))
        nrm = Vector((x * 8, -0.1, 1)).normalized()
        hd.add_feather(feathers, p, nrm, Vector((x * 2, -1, -0.15)), rnd.uniform(0.035, 0.055), 0.012,
                       lift=0.08, curl=0.02, cup=0.15, shape=1.5)
    # zottige Kehlfedern
    for p, nrm in hd.sample_surface(cr, 420, rnd, lambda p, n: p.z < 0.07 and n.z < 0.2):
        L = rnd.uniform(0.05, 0.09)
        hd.add_feather(hackles, p, nrm, Vector((rnd.uniform(-0.2, 0.2), 0.15, -1)), L, L * 0.16,
                       lift=rnd.uniform(0.08, 0.22), curl=0.04, cup=0.08, shape=1.8, twist=rnd.uniform(-0.3, 0.3))
    cr.free()
    face = hb.children[0] if hb.children[0].name == "Face" else bpy.data.objects["Face"]
    hd.shade_like(feathers.finish("Head_Feathers", m["feather"], parent=hb), face, 0.85)
    hd.shade_like(hackles.finish("Head_Hackles", m["hackle"], parent=hb), face, 0.7)


# =====================================================================================
#  Rumpf
# =====================================================================================

def body(rig, m, rnd):
    tb = rig.torso
    zs = [-0.15 + i * 0.0105 for i in range(120)] + [1.1, 1.105]
    rows, uvs = [], []
    seg = 128
    for z in zs:
        row, uvr = [], []
        for j in range(seg):
            th = j / seg * math.tau
            row.append(body_point(th, z))
            uvr.append((j / seg * 5.0, z * 2.5))
        rows.append(row)
        uvs.append(uvr)
    mb = hd.MeshBuilder()
    mb.grid(rows, uvs, close=True)
    mb.finish("Body", m["robe"], parent=tb)

    # Hals mit Federn (überdeckt die Fuge zum Kopf)
    neck = hd.MeshBuilder()
    nrows, nuvs = [], []
    for i in range(14):
        t = i / 13
        z = 1.0 + t * 0.32
        r = 0.1 - 0.02 * t
        cy = 0.0 - 0.03 * t
        nrows.append([Vector((r * math.cos(a), cy + r * 0.9 * math.sin(a), z)) for a in
                      (k / 24 * math.tau for k in range(24))])
        nuvs.append([(k / 24 * 2, t) for k in range(24)])
    neck.grid(nrows, nuvs, close=True)
    nbm = neck.bm.copy()
    neck_ob = neck.finish("Neck", m["dark"], parent=tb)
    hk = hd.MeshBuilder()
    for p, nrm in hd.sample_surface(nbm, 700, rnd, lambda p, n: p.z > 1.1):
        L = rnd.uniform(0.06, 0.1)
        hd.add_feather(hk, p, nrm, Vector((rnd.uniform(-0.3, 0.3), 0.2, -1)), L, L * 0.16,
                       lift=rnd.uniform(0.08, 0.2), curl=0.04, cup=0.08, shape=1.8, twist=rnd.uniform(-0.3, 0.3))
    nbm.free()
    hd.shade_like(hk.finish("Neck_Hackles", m["hackle"], parent=tb), neck_ob, 0.7)

    cowl(rig, m, rnd)
    rags(rig, m, rnd)
    necklaces(rig, m, rnd)


def cowl(rig, m, rnd):
    """Hoher, zerknautschter Kragen der zurückgeschlagenen Kapuze: umschließt den Hals,
    hinten hoch, vorne V-förmig offen, oben ausgefranst. Doppelwandig (innen/außen)."""
    mb = hd.MeshBuilder()
    n_around, n_up = 96, 14
    gap = math.radians(38)  # halbe Öffnung vorne
    outer, inner, uvo, uvi = [], [], [], []
    phase = rnd.random() * 10
    for k in range(n_up + 1):
        t = k / n_up
        ro, ri, uo, ui = [], [], [], []
        for i in range(n_around + 1):
            u = i / n_around
            # Winkel: vorne = -90°; Bogen läuft von vorne rechts über hinten nach vorne links
            ang = math.radians(-90) + gap + (math.tau - 2 * gap) * u
            back = 0.5 + 0.5 * math.sin(ang)           # 1 = hinten
            front_edge = min(1.0, min(u, 1 - u) / 0.22)
            front_edge = front_edge * front_edge * (3 - 2 * front_edge)
            bottom = 0.98 + 0.03 * back
            top = 1.13 + 0.15 * back ** 1.3 + 0.012 * noise.noise(Vector((u * 8 + phase, 0.5, 0)))
            top = bottom + 0.03 + (top - bottom - 0.03) * front_edge
            z = bottom + (top - bottom) * t
            rag = 0.012 * abs(math.sin(u * 47 + phase)) ** 3 if t > 0.92 else 0.0
            z -= rag
            r = 0.21 - 0.075 * t ** 0.8 + 0.035 * back * t
            fold = 0.014 * math.sin(u * 31 + phase + t * 2) + 0.008 * noise.noise(Vector((u * 20, t * 3, phase)))
            r += fold * (0.5 + t)
            # Kragen kippt oben nach außen
            r += 0.03 * t ** 3
            cx, cy = 0.0, 0.03
            p = Vector((cx + r * 1.12 * math.cos(ang), cy + r * math.sin(ang), z))
            q = Vector((cx + (r - 0.018) * 1.12 * math.cos(ang), cy + (r - 0.018) * math.sin(ang), z))
            ro.append(p)
            ri.append(q)
            uo.append((u * 6, t))
            ui.append((u * 6, t))
        outer.append(ro)
        inner.append(ri)
        uvo.append(uo)
        uvi.append(ui)
    mb.grid(outer, uvo)
    mb.grid(list(reversed(inner)), list(reversed(uvi)))
    mb.grid([outer[-1], inner[-1]], [uvo[-1], uvi[-1]])
    mb.finish("Body_Cowl", m["robe"], parent=rig.torso)


def rag_strip(mb, th, z_top, length, width, out, rnd, flare=0.03, notch=True):
    """Ein Stofffetzen, der der Kutte folgt und unten gezackt ausfranst."""
    r = _radius(z_top - length * 0.5) * SX
    dth = width / max(r, 0.05)
    along, across = 12, 6
    tip_a = rnd.uniform(0.3, 0.7)
    tip_b = rnd.uniform(0.0, 1.0)
    rows, uvs = [], []
    for i in range(along):
        t = i / (along - 1)
        z = z_top - length * t
        row, uvr = [], []
        for j in range(across):
            a = j / (across - 1)
            # unten zackig: zwei Spitzen bzw. eine, Seiten ausgefranst
            jag = 0.0
            if notch:
                jag = 0.35 * abs(math.sin((a + tip_b) * math.pi * 1.5)) + 0.15 * rnd.random() * t
            else:
                jag = 0.6 * abs(a - tip_a)
            zz = z_top - length * t * (1 - jag * t ** 3)
            thh = th + (a - 0.5) * dth * (1 - 0.35 * t ** 2)
            bulge = 0.006 * math.sin(a * math.pi)
            p = body_point(thh, zz, out=out + flare * t ** 2 + bulge)
            row.append(p)
            uvr.append((a * width * 4, t * length * 4))
        rows.append(row)
        uvs.append(uvr)
    mb.grid(rows, uvs)


def rags(rig, m, rnd):
    mb = hd.MeshBuilder()
    layers = [(1.095, 0.12, 0.2, 30, 0.05), (1.075, 0.2, 0.3, 26, 0.04), (0.97, 0.22, 0.34, 24, 0.03), (0.84, 0.24, 0.36, 22, 0.02),
              (0.7, 0.2, 0.3, 20, 0.012)]
    for k, (z_top, lmin, lmax, count, out) in enumerate(layers):
        off = rnd.random() * math.tau
        for i in range(count):
            th = off + i / count * math.tau + rnd.uniform(-0.08, 0.08)
            w = rnd.uniform(0.07, 0.11)
            rag_strip(mb, th, z_top + rnd.uniform(-0.02, 0.02), rnd.uniform(lmin, lmax), w,
                      out + rnd.uniform(0.0, 0.006), rnd)
    mb.finish("Body_Rags", m["rags"], parent=rig.torso)


def necklaces(rig, m, rnd):
    tb = rig.torso
    cords = []
    pendants_bone = hd.MeshBuilder()
    pendants_metal = hd.MeshBuilder()
    for k, (z_mid, span, sag, out) in enumerate([(1.0, 0.13, 0.05, 0.085), (0.93, 0.16, 0.11, 0.085),
                                                 (0.86, 0.17, 0.15, 0.08)]):
        pts = []
        for i in range(41):
            t = i / 40
            x = -span + 2 * span * t
            z = z_mid + 0.05 - sag * math.sin(t * math.pi)
            th = theta_front(x, z)
            pts.append(body_point(th, z, out=out, folds=False))
        cords.append(geo.tube(pts, [0.0026] * len(pts), seg=6, tile=0.05))
        # Anhänger
        for t in (0.36, 0.61) if k == 0 else ((0.3, 0.5, 0.68) if k == 1 else (0.42, 0.57)):
            p = pts[int(t * 40)]
            n = body_normal(theta_front(p.x, p.z), p.z)
            down = Vector((0, 0, -1))
            if k == 1 and abs(t - 0.5) < 0.01:
                amulet(pendants_metal, pendants_bone, p, n)
                continue
            kind = rnd.choice(("tooth", "shard", "talon"))
            L = rnd.uniform(0.028, 0.045)
            if kind == "shard":
                hd.add_feather(pendants_bone, p - n * 0.002, n, down, L, 0.016, lift=0.05, curl=0.0, cup=-0.2, shape=0.6)
            pts_t = [p, p + down * L * 0.5 + n * 0.006, p + down * L + n * (0.012 if kind == "talon" else 0.004)]
            b = geo.tube(pts_t, [0.007, 0.005, 0.0005], seg=8, tile=0.05)
            pendants_bone.bm.from_mesh(_tmp_mesh(b))
    mb = hd.MeshBuilder()
    for c in cords:
        mb.bm.from_mesh(_tmp_mesh(c))
    mb.finish("Body_Cords", m["cord"], parent=tb)
    pendants_bone.finish("Body_Bones", m["bone"], parent=tb)
    pendants_metal.finish("Body_Amulet", m["metal"], parent=tb)


def _tmp_mesh(bm):
    me = bpy.data.meshes.new("_tmp")
    bm.to_mesh(me)
    bm.free()
    return me


def amulet(metal_mb, bone_mb, p, n):
    """Rundes Messingamulett mit kleinem Vogelschädel davor."""
    d, s, nn = hd.frame(n, Vector((0, 0, -1)))
    c = p + d * 0.03 + nn * 0.004
    rows, uvs = [], []
    for ring in range(3):
        r = (0.026, 0.03, 0.022)[ring]
        h = (0.0, 0.004, 0.008)[ring]
        rows.append([c + (d * math.cos(a) + s * math.sin(a)) * r + nn * h for a in (k / 32 * math.tau for k in range(32))])
        uvs.append([(k / 32, ring / 2) for k in range(32)])
    metal_mb.grid(rows, uvs, close=True)
    # Vogelschädel
    sk = bmesh.new()
    bmesh.ops.create_uvsphere(sk, u_segments=16, v_segments=12, radius=1.0)
    for v in sk.verts:
        q = v.co
        v.co = c + nn * 0.016 + d * (-0.004 + q.z * 0.013) + s * (q.x * 0.011) + nn * (q.y * -0.01)
    bone_mb.bm.from_mesh(_tmp_mesh(sk))
    tip = c + nn * 0.016 + d * 0.035
    b = geo.tube([c + nn * 0.016 + d * 0.006, c + nn * 0.017 + d * 0.022, tip], [0.006, 0.003, 0.0004], seg=8)
    bone_mb.bm.from_mesh(_tmp_mesh(b))


# =====================================================================================
#  Hände und Ärmel
# =====================================================================================

def hands_and_sleeve(rig, m, rnd):
    for side in (-1, 1):
        h = ch.hand(side, m["skin"], claw_mat=m["claw"], length=1.5, thick=0.68, claw=0.04, knobby=0.25)
        for ob in [h] + list(h.children):
            ob.data.transform(Matrix.Scale(1.3, 4))
    sleeve(m, rnd)


def sleeve(m, rnd):
    """Ärmel (Länge 1 entlang Z, +0.5 = Handgelenk): Stoff mit Längsfalten, darüber
    lose Fetzen, die am Handgelenk ausfransen. Godot streckt ihn zwischen Schulter und Hand."""
    mb = hd.MeshBuilder()
    rows, uvs = [], []
    n_r, n_z = 40, 30
    for i in range(n_z + 1):
        z = -0.5 + i / n_z
        t = i / n_z
        r = 0.064 - 0.006 * t + 0.012 * max(0.0, t - 0.82) / 0.18
        row, uvr = [], []
        for j in range(n_r):
            a = j / n_r * math.tau
            fold = 0.006 * math.sin(a * 7 + 1.3 * noise.noise(Vector((z * 3, 0.2, 0.4)))) + 0.003 * math.sin(a * 13)
            rr = r + fold
            row.append(Vector((rr * math.cos(a), rr * math.sin(a), z)))
            uvr.append((j / n_r * 2, t * 2.5))
        rows.append(row)
        uvs.append(uvr)
    vs = mb.grid(rows, uvs, close=True)
    mb.bm.faces.new(list(reversed(vs[0])))
    mb.bm.faces.new(vs[-1])
    # Fetzen
    for k in range(22):
        a0 = rnd.random() * math.tau
        z0 = rnd.uniform(-0.2, 0.35)
        L = rnd.uniform(0.18, 0.3)
        w = rnd.uniform(0.3, 0.6)
        rows, uvs = [], []
        for i in range(8):
            t = i / 7
            z = min(0.62, z0 + L * t)
            row, uvr = [], []
            for j in range(4):
                u = j / 3
                a = a0 + (u - 0.5) * w * (1 - 0.6 * t ** 2)
                rr = 0.07 + 0.004 * k / 22 + 0.025 * t ** 2
                zz = z - 0.08 * t ** 3 * abs(math.sin((u + k) * 2.1))
                row.append(Vector((rr * math.cos(a), rr * math.sin(a), zz)))
                uvr.append((u * 0.4, t * L * 3))
            rows.append(row)
            uvs.append(uvr)
        mb.grid(rows, uvs)
    ob = mb.finish("Sleeve", m["rags"])
    shoulder = G(0.40, 1.04, -0.34)
    hand_pos = G(0.15, 0.86, 0.15)
    d = hand_pos - shoulder
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    ob.matrix_world = Matrix.Translation((shoulder + hand_pos) * 0.5) @ rot @ Matrix.Diagonal((1, 1, d.length, 1))
    return ob


# =====================================================================================

HEAD_SCALE = 1.3
HEAD_Y = 1.22


def scale_head(rig, s):
    """Kopf als Ganzes vergrößern (um die Schädelmitte), Jaw-Drehpunkt und Augen-Marker mit."""
    c = Vector((0, 0, 0.1))
    for ob in rig.head.children:
        ob.location = c + (Vector(ob.location) - c) * s
        if ob.type == "MESH":
            ob.data.transform(Matrix.Scale(s, 4))


def build(steps=("head", "body", "hands"), seed=7):
    rnd = random.Random(seed)
    if set(steps) >= {"head", "body", "hands"}:
        hd.clear_scene()
    rig = ch.Rig(HEAD_Y)
    m = materials()
    if "head" in steps:
        head(rig, m, rnd)
        scale_head(rig, HEAD_SCALE)
    if "body" in steps:
        body(rig, m, rnd)
    if "hands" in steps:
        hands_and_sleeve(rig, m, rnd)
    return rig
