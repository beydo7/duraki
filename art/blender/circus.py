"""Raum „Zirkuswagen“ als Blender-Modelle.

    import sys; sys.path.insert(0, r"<Repo>/art/blender")
    import circus; circus.build_all(); circus.export_all()

Design, Maße und Positionen stammen 1:1 aus scenes/match/rooms/circus_room.gd und
balloon_lives.gd; besser wird nur die Machart. Koordinaten sind Godot-Koordinaten.

    circus.glb     Deckenbretter, Leisten, Vorhang mit Stange, Kostüme, Hüte, Schminkspiegel mit
                   Birnen, Schminktisch, Spieltisch auf der Trommel, Lichterkette
                   („Lichterkette_00…21“ blinken einzeln)
    music_box.glb  Spieluhr („Spieluhr“ mit „Deckel“, „Taenzerin“, „Springteufel“, „Key“)
    balloon.glb    Vorlagen „Ballon“ und „Ballonknoten“ für die Leben

Im Code bleiben: Boden, Bretterwände, Rückwand, Zelt und Manege draußen, Plakat, Schnüre der
Ballons, Konfetti, Lichter, Geräusche.
"""
from __future__ import annotations

import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import geo  # noqa: E402
from room_kit import *  # noqa: E402,F401,F403
from room_kit import MODEL_TEX, REPO  # noqa: E402

ROOM_TEX = os.path.join(REPO, "assets", "rooms", "circus")
OUT_DIR = ROOM_TEX

# Maße wie in circus_room.gd
ROOM_W = 4.4
BACK_Z = -2.1
WALL_H = 2.1
VAULT = 0.55
TOP = (1.84, 1.3)
GAP_X = -1.2
GAP_W = 0.7
BOX_POS = (0.74, 0.0, -0.5)
FRONT_Z = 3.6
BALLOON_R = 0.052
COSTUME_COLORS = ((0.9, 0.75, 0.2), (0.2, 0.55, 0.45), (0.85, 0.3, 0.55), (0.9, 0.9, 0.85))
LIGHT_COLORS = ((1, 0.3, 0.2), (1, 0.85, 0.3), (0.3, 0.6, 1), (0.4, 1, 0.5))

FILES = {"circus.glb": ["Zirkus"], "music_box.glb": ["Spieluhr"], "balloon.glb": ["Luftballon"]}
PLACES = {
    "Spieluhr": ((BOX_POS[0], TABLE_Y, BOX_POS[2]), 0.5, 1.0),
    "Luftballon": ((-0.66, TABLE_Y + 0.42, -0.58), 0.0, 1.0),
}


def M():
    wood_c = os.path.join(MODEL_TEX, "table_wood_color.png")
    wood_n = os.path.join(MODEL_TEX, "table_wood_normal.png")
    d = {}
    d["Decke_Dunkel"] = mat("Decke_Dunkel", (0.42, 0.26, 0.16), 0.8)
    d["Decke_Hell"] = mat("Decke_Hell", (0.75, 0.66, 0.5), 0.8)
    d["Goldleiste"] = mat("Goldleiste", (0.75, 0.55, 0.15), 0.45, 0.6)
    d["Vorhang"] = mat("Vorhang", (0.55, 0.05, 0.08), 0.85)
    d["Gold"] = mat("Gold", (0.85, 0.65, 0.2), 0.35, 0.9)
    d["Holz_Dunkel"] = mat("Holz_Dunkel", (0.35, 0.22, 0.12), 0.7, normal=wood_n, scale=2.0)
    d["Haken"] = mat("Haken", (0.6, 0.5, 0.3), 0.4, 0.8)
    for k, c in enumerate(COSTUME_COLORS):
        d["Kostuem_%d" % k] = mat("Kostuem_%d" % k, c, 0.7)
    d["Kragen"] = mat("Kragen", (0.95, 0.95, 0.92), 0.8)
    d["Pailletten"] = mat("Pailletten", (1, 0.85, 0.4), 0.3, emission=(1, 0.85, 0.4), energy=1.2)
    d["Zylinderhut"] = mat("Zylinderhut", (0.08, 0.08, 0.1), 0.5)
    d["Clownshut"] = mat("Clownshut", (0.2, 0.5, 0.9), 0.6)
    d["Bommel"] = mat("Bommel", (0.95, 0.3, 0.2), 0.6)
    d["Spiegelrahmen"] = mat("Spiegelrahmen", (0.2, 0.12, 0.08), 0.5)
    d["Spiegelglas"] = mat("Spiegelglas", (0.55, 0.6, 0.62), 0.08, 1.0)
    d["Spiegelbirne"] = mat("Spiegelbirne", (1.0, 0.9, 0.7), 0.3, emission=(1.0, 0.9, 0.7), energy=3.0)
    d["Schminktisch"] = mat("Schminktisch", (0.4, 0.24, 0.14), 0.7, normal=wood_n, scale=2.0)
    d["Puderdose"] = mat("Puderdose", (0.95, 0.75, 0.75), 0.4)
    d["Lippenstift"] = mat("Lippenstift", (0.9, 0.1, 0.15), 0.4)
    d["Tischholz"] = mat("Tischholz", (0.36, 0.2, 0.12), 0.6, normal=wood_n, scale=1.5)
    d["Tischtuch"] = mat("Tischtuch", (0.07, 0.17, 0.12), 0.95)
    d["Tischgold"] = mat("Tischgold", (0.85, 0.65, 0.2), 0.4, 0.7)
    d["Trommel"] = mat("Trommel", (0.75, 0.1, 0.1), 0.5)
    d["Trommelseil"] = mat("Trommelseil", (0.9, 0.86, 0.72), 0.8)
    d["Kabel"] = mat("Kabel", (0.1, 0.1, 0.1), 0.6)
    d["Lichterkette"] = mat("Lichterkette", (1, 0.85, 0.3), 0.3, emission=(1, 0.85, 0.3), energy=1.6)
    # Spieluhr
    d["Spieluhr_Holz"] = mat("Spieluhr_Holz", (0.5, 0.25, 0.14), 0.45, normal=wood_n, scale=10.0)
    d["Spieluhr_Gold"] = mat("Spieluhr_Gold", (0.9, 0.7, 0.3), 0.3, 0.9)
    d["Taenzerin_Kleid"] = mat("Taenzerin_Kleid", (1.0, 0.7, 0.8), 0.6)
    d["Taenzerin_Haut"] = mat("Taenzerin_Haut", (0.95, 0.85, 0.75), 0.5)
    d["Taenzerin_Haar"] = mat("Taenzerin_Haar", (0.25, 0.14, 0.08), 0.6)
    d["Feder"] = mat("Feder", (0.7, 0.7, 0.72), 0.3, 0.9)
    d["Teufel_Gesicht"] = mat("Teufel_Gesicht", (0.98, 0.92, 0.85), 0.5)
    d["Teufel_Nase"] = mat("Teufel_Nase", (0.95, 0.1, 0.1), 0.4)
    d["Teufel_Auge"] = mat("Teufel_Auge", (0.05, 0.05, 0.05), 0.4)
    d["Kappe_Gelb"] = mat("Kappe_Gelb", (0.95, 0.75, 0.15), 0.5)
    d["Kappe_Blau"] = mat("Kappe_Blau", (0.2, 0.45, 0.9), 0.5)
    d["Kappe_Bommel"] = mat("Kappe_Bommel", (0.95, 0.2, 0.2), 0.5)
    d["Teufel_Kragen"] = mat("Teufel_Kragen", (0.95, 0.95, 0.9), 0.7)
    # Luftballon (Farbe setzt das Spiel je Leben)
    d["Ballon"] = mat("Ballon", (0.85, 0.12, 0.12), 0.25)
    return d


def aim(bm, direction, at=(0, 0, 0)):
    q = Z.rotation_difference(Vector(direction).normalized())
    return geo.transform(bm, Matrix.Translation(Vector(at)) @ q.to_matrix().to_4x4())


def rounded_rect(hx, hz, r, seg=6):
    pts = []
    for cx, cy, a0 in ((hx - r, -hz + r, -90), (hx - r, hz - r, 0), (-hx + r, hz - r, 90), (-hx + r, -hz + r, 180)):
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append(Vector((cx + r * math.cos(a), cy + r * math.sin(a), 0.0)))
    return pts


def pleated(base, pleat, folds, seg, flat=1.0, phase=0.0):
    """Drehkörper mit Falten: base = [(radius, höhe), ...] von unten nach oben, pleat = Anteil der
    Faltentiefe je Höhe (gleiche Länge). `flat` staucht entlang Blender-X (flach an der Wand)."""
    bm = bmesh.new()
    uv = uv_layer(bm)
    rings = []
    for (r, h), p in zip(base, pleat):
        ring = []
        for k in range(seg):
            a = TAU * k / seg
            rr = r * (1.0 + p * math.cos(folds * a + phase))
            ring.append(bm.verts.new((math.cos(a) * rr * flat, math.sin(a) * rr, h)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for k in range(seg):
            k1 = (k + 1) % seg
            f = bm.faces.new((a[k], a[k1], b[k1], b[k]))
            for loop in f.loops:
                c = loop.vert.co
                loop[uv].uv = (math.atan2(c.y, c.x) / TAU * 4.0, c.z * 4.0)
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bm.normal_update()
    return bm


# =====================================================================================
#  Decke, Leisten, Vorhang
# =====================================================================================

def build_shell(col, m, root):
    hw = ROOM_W * 0.5
    n = 14
    dark, light = [], []
    for i in range(n):  # Tonnengewölbe aus Brettern mit Fugen, abwechselnd dunkel und hell
        a0, a1 = PI * i / n, PI * (i + 1) / n
        p0 = (-math.cos(a0) * hw, WALL_H + math.sin(a0) * VAULT)
        p1 = (-math.cos(a1) * hw, WALL_H + math.sin(a1) * VAULT)
        length = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
        b = rot(box((length - 0.004, 0.04, 6.0), (0, 0, 0)), -ang, "Y")
        move(b, gl((p0[0] + p1[0]) * 0.5, (p0[1] + p1[1]) * 0.5, 0.6))
        (dark if i % 2 else light).append(b)
    ob("Decke_Dunkel", join(*dark), m["Decke_Dunkel"], col, root, bevel=0.005, seg=2)
    ob("Decke_Hell", join(*light), m["Decke_Hell"], col, root, bevel=0.005, seg=2)
    # goldene Leisten oben an den Wänden, mit Profil
    prof = [(0.0, WALL_H - 0.075), (0.012, WALL_H - 0.075), (0.02, WALL_H - 0.066), (0.024, WALL_H - 0.05), (0.036, WALL_H - 0.04),
            (0.05, WALL_H - 0.03), (0.054, WALL_H - 0.012), (0.05, WALL_H - 0.002), (0.0, WALL_H)]
    trims = [sweep([gl(-hw, 0, FRONT_Z), gl(-hw, 0, BACK_Z)], prof, closed=False),
             sweep([gl(hw, 0, BACK_Z), gl(hw, 0, FRONT_Z)], prof, closed=False)]
    ob("Wandleisten", join(*trims), m["Goldleiste"], col, root, sharp=40)


def _curtain(side):
    """Eine Samtbahn am Vorhangspalt, zur Seite gerafft (side = -1 links, +1 rechts)."""
    height = 1.95
    nu, nv, folds = 60, 30, 5
    x_in, x_out = GAP_X + side * 0.105, GAP_X + side * 0.445
    z0 = BACK_Z + 0.07
    bm = bmesh.new()
    uv = uv_layer(bm)
    grid = []
    for j in range(nv + 1):
        yy = 0.01 + (height - 0.01) * j / nv
        open_ = 1.0 + 0.55 * smooth01((1.2 - yy) / 1.2)  # unten weiter zur Seite gezogen
        row = []
        for i in range(nu + 1):
            u = i / nu
            x = x_out + (x_in + side * 0.06 * (open_ - 1.0) - x_out) * u
            amp = 0.026 * (0.85 + 0.15 * math.sin(5.0 * u + side))
            z = z0 + amp * math.sin(TAU * folds * u + 0.5 * math.sin(3.0 * u + yy)) * smooth01(u / 0.05) * smooth01((1 - u) / 0.05)
            row.append(bm.verts.new(gl(x, yy, z)))
        grid.append(row)
    for j in range(nv):
        for i in range(nu):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            for loop, (ii, jj) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                loop[uv].uv = (ii / nu * 0.6, height * jj / nv)
    return face_room(bm, FRONT)


def build_curtain(col, m, root):
    ob("Vorhang", join(_curtain(-1.0), _curtain(1.0)), m["Vorhang"], col, root, sharp=None)
    half = (GAP_W + 0.3) * 0.5
    gold = [pipe([gl(GAP_X - half, 1.97, BACK_Z + 0.08), gl(GAP_X + half, 1.97, BACK_Z + 0.08)], 0.015, 12)]
    for s in (-1.0, 1.0):
        gold.append(geo.ellipsoid(Vector((0.03, 0.03, 0.03)), gl(GAP_X + s * (half + 0.02), 1.97, BACK_Z + 0.08), 14, 10))
        gold.append(box((0.03, 0.05, 0.08), (GAP_X + s * (half - 0.05), 1.97, BACK_Z + 0.04)))
        for k in range(5):
            x = GAP_X + s * (0.13 + k * 0.07)
            ring = pipe([Vector((0, math.cos(TAU * i / 14) * 0.024, math.sin(TAU * i / 14) * 0.024)) for i in range(14)], 0.004, 5, closed=True)
            gold.append(move(ring, gl(x, 1.962, BACK_Z + 0.08)))
    ob("Vorhangstange", join(*gold), m["Gold"], col, root, sharp=40)


# =====================================================================================
#  Kostüme und Hüte an der linken Wand
# =====================================================================================

def build_costumes(col, m, root):
    x = -ROOM_W * 0.5 + 0.12
    wood = [box((0.04, 0.06, 1.6), (x - 0.04 - 0.058, 1.75, -0.9)),
            box((0.32, 0.03, 1.0), (x + 0.035, 1.95, -0.3))]
    for zz in (-0.72, 0.12):  # Konsolen unter dem Hutbord
        wood.append(box((0.2, 0.14, 0.025), (x - 0.02, 1.865, zz)))
    ob("Kostuemleiste", join(*wood), m["Holz_Dunkel"], col, root, bevel=0.006, seg=2)
    hooks, ruffs, sequins = [], [], []
    base = [(0.2, 0.0), (0.195, 0.02), (0.17, 0.2), (0.14, 0.4), (0.115, 0.56), (0.105, 0.64), (0.1, 0.685), (0.085, 0.71), (0.045, 0.73), (0.03, 0.745)]
    fold = [0.14, 0.14, 0.11, 0.08, 0.05, 0.03, 0.015, 0.0, 0.0, 0.0]
    for k in range(4):
        zz = -1.5 + k * 0.38
        peg = gl(x - 0.1, 1.75, zz)
        hooks.append(pipe([peg, gl(x - 0.02, 1.75, zz), gl(x, 1.762, zz)], 0.008, 8))
        # Bügel mit Haken
        hooks.append(pipe([gl(x - 0.01, 1.755, zz), gl(x + 0.03, 1.775, zz), gl(x + 0.07, 1.762, zz), gl(x + 0.08, 1.735, zz)], 0.004, 6))
        hooks.append(pipe([gl(x + 0.08, 1.72, zz - 0.115), gl(x + 0.08, 1.74, zz), gl(x + 0.08, 1.72, zz + 0.115)], 0.006, 6))
        dress = pleated(base, fold, 9, 36, flat=0.55, phase=k * 1.3)
        ob("Kostuem_%d" % k, move(dress, gl(x + 0.08, 1.33 - 0.375, zz)), m["Kostuem_%d" % k], col, root, sharp=None)
        ruff = pleated([(0.05, -0.012), (0.085, -0.004), (0.085, 0.004), (0.05, 0.012)], [0.0, 0.16, 0.16, 0.0], 14, 56, flat=0.6)
        ruffs.append(move(ruff, gl(x + 0.08, 1.695, zz)))
        if k == 2:  # Pailletten
            for j in range(12):
                yy, dz = 1.05 + (j % 4) * 0.15, -0.09 + (j // 4) * 0.09
                hh = yy - 0.955
                rr = next(r0 + (r1 - r0) * (hh - h0) / (h1 - h0) for (r0, h0), (r1, h1) in zip(base, base[1:]) if h0 <= hh <= h1)
                front = 0.55 * math.sqrt(max(rr * rr - dz * dz, 0.0)) + 0.006
                sequins.append(geo.ellipsoid(Vector((0.004, 0.009, 0.009)), gl(x + 0.08 + front, yy, zz + dz), 8, 6))
    ob("Kostuemhaken", join(*hooks), m["Haken"], col, root)
    ob("Kostuemkragen", join(*ruffs), m["Kragen"], col, root, sharp=None)
    ob("Pailletten", join(*sequins), m["Pailletten"], col, root, shadow=False)
    # Ringmeister-Zylinder und Clownshut auf dem Bord
    hat = [(0.0, 0.0), (0.118, 0.0), (0.124, 0.006), (0.118, 0.012), (0.074, 0.012), (0.071, 0.02), (0.07, 0.09), (0.074, 0.168),
           (0.07, 0.172), (0.0, 0.174)]
    ob("Zylinderhut", move(lathe(hat, 28, 0.2), gl(x + 0.08, 1.965, -0.55)), m["Zylinderhut"], col, root, sharp=40)
    cone = [(0.0, 0.0), (0.075, 0.0), (0.078, 0.006), (0.07, 0.014), (0.045, 0.07), (0.02, 0.135), (0.006, 0.172), (0.0, 0.176)]
    ob("Clownshut", move(lathe(cone, 24, 0.2), gl(x + 0.08, 1.965, -0.15)), m["Clownshut"], col, root, sharp=40)
    poms = [geo.ellipsoid(Vector((0.02, 0.02, 0.02)), gl(x + 0.08, 2.15, -0.15), 12, 8)]
    for hh, rr in ((0.05, 0.056), (0.1, 0.036)):
        poms.append(geo.ellipsoid(Vector((0.012, 0.012, 0.012)), gl(x + 0.08 + rr, 1.965 + hh, -0.15), 10, 6))
    ob("Clownshut_Bommel", join(*poms), m["Bommel"], col, root)


# =====================================================================================
#  Schminkspiegel und Schminktisch an der rechten Wand
# =====================================================================================

def build_mirror(col, m, root):
    x = ROOM_W * 0.5 - 0.05
    # lokal gebaut (Vorderseite +Z Godot), dann zur Raummitte gedreht
    T = Matrix.Translation(gl(x, 1.35, -1.2)) @ Matrix.Rotation(-PI * 0.5, 4, "Z")
    frame = [box((0.75, 0.6, 0.02), (0, 0, -0.005))]
    prof = [(0.0, 0.005), (0.004, 0.014), (0.012, 0.018), (0.03, 0.018), (0.04, 0.03), (0.055, 0.032), (0.066, 0.024), (0.075, 0.02)]
    frame.append(move(panel_moulding(-0.375, 0.375, -0.3, 0.3, 0.0, prof), (0, 0, 0)))
    ob("Spiegelrahmen", geo.transform(join(*frame), T), m["Spiegelrahmen"], col, root, sharp=35)
    glass = quad((-0.3, -0.0195, -0.225), (0.3, -0.0195, -0.225), (0.3, -0.0195, 0.225), (-0.3, -0.0195, 0.225), [(0, 0), (1, 0), (1, 1), (0, 1)])
    ob("Spiegelglas", geo.transform(glass, T), m["Spiegelglas"], col, root, smooth=False, shadow=False)
    spots = [(-0.3 + k * 0.15, 0.27) for k in range(5)] + [(s * 0.345, 0.15 - k * 0.12) for k in range(4) for s in (-1.0, 1.0)]
    bulbs, sockets = [], []
    for px, py in spots:
        c = gl(px, py, 0.03)
        bulbs.append(move(rot(bulb(0.022, seg=12), PI * 0.5, "X"), c))
        sockets.append(move(rot(lathe([(0.0, 0.0), (0.02, 0.0), (0.02, 0.006), (0.016, 0.01), (0.0, 0.01)], 12, 0.05), PI * 0.5, "X"), gl(px, py, 0.0)))
    ob("Spiegelbirnen", geo.transform(join(*bulbs), T), m["Spiegelbirne"], col, root, shadow=False)
    ob("Spiegelfassungen", geo.transform(join(*sockets), T), m["Gold"], col, root, shadow=False)
    # Schminktisch darunter: Platte, zwei Wangen, Schubkastenblende mit Knauf, Puderdose, Lippenstift
    wood = [box((0.35, 0.04, 0.9), (x - 0.17, 0.85, -1.2)), box((0.3, 0.83, 0.04), (x - 0.17, 0.415, -1.62)), box((0.3, 0.83, 0.04), (x - 0.17, 0.415, -0.78)),
            box((0.02, 0.12, 0.8), (x - 0.31, 0.77, -1.2))]
    ob("Schminktisch", join(*wood), m["Schminktisch"], col, root, bevel=0.006, seg=2)
    knob = lathe([(0.0, 0.0), (0.008, 0.0), (0.008, 0.01), (0.016, 0.014), (0.016, 0.022), (0.008, 0.028), (0.0, 0.029)], 14, 0.05)
    ob("Schminktisch_Knauf", aim(knob, (-1, 0, 0), gl(x - 0.32, 0.77, -1.2)), m["Gold"], col, root)
    box_ = [(0.0, 0.0), (0.05, 0.0), (0.052, 0.004), (0.052, 0.02), (0.05, 0.024), (0.052, 0.027), (0.05, 0.034), (0.02, 0.04), (0.008, 0.041),
            (0.008, 0.046), (0.012, 0.05), (0.008, 0.055), (0.0, 0.056)]
    ob("Puderdose", move(lathe(box_, 24, 0.1), gl(x - 0.15, 0.87, -1.0)), m["Puderdose"], col, root, sharp=40)
    ob("Lippenstift_Huelse", move(lathe([(0.0, 0.0), (0.0125, 0.0), (0.0125, 0.06), (0.011, 0.062), (0.011, 0.078), (0.0, 0.078)], 14, 0.05),
                                    gl(x - 0.2, 0.87, -1.35)), m["Gold"], col, root)
    ob("Lippenstift", move(lathe([(0.0, 0.078), (0.009, 0.078), (0.009, 0.105), (0.006, 0.117), (0.0, 0.12)], 14, 0.05),
                             gl(x - 0.2, 0.87, -1.35)), m["Lippenstift"], col, root)


# =====================================================================================
#  Spieltisch auf der Trommel
# =====================================================================================

def build_table(col, m, root):
    y = TABLE_Y
    hx, hz = TOP[0] * 0.5, TOP[1] * 0.5
    # grünes Tuch eingelassen (Oberkante wie bisher 0,5 mm über TABLE_Y), Holzrand mit runder Kante
    cloth_path = rounded_rect(hx - 0.06, hz - 0.06, 0.01)
    ob("Tischtuch", ngon([p + Z * (y + 0.0005) for p in cloth_path]), m["Tischtuch"], col, root, smooth=False)
    path = [p + Z * y for p in rounded_rect(hx - 0.012, hz - 0.012, 0.012)]
    wood = [sweep(path, [(0.0, -0.04), (0.004, -0.04), (0.01, -0.036), (0.012, -0.028), (0.012, -0.008), (0.009, -0.002), (0.004, 0.0), (0.0, 0.0)])]
    # Rand zwischen Tuch und Kante
    rim = bmesh.new()
    uv = uv_layer(rim)
    inner = [rim.verts.new(p + Z * y) for p in cloth_path]
    outer = [rim.verts.new(p) for p in path]
    n = len(inner)
    for i in range(n):
        j = (i + 1) % n
        f = rim.faces.new((inner[i], outer[i], outer[j], inner[j]))
        for loop in f.loops:
            loop[uv].uv = (loop.vert.co.x, loop.vert.co.y)
    wood.append(face_room(rim, Z))
    wood.append(ngon([p + Z * (y - 0.04) for p in rounded_rect(hx - 0.012, hz - 0.012, 0.012)], flip=True))
    ob("Tischplatte", join(*wood), m["Tischholz"], col, root, sharp=50)
    gold_path = [p + Z * (y - 0.03) for p in rounded_rect(hx + 0.001, hz + 0.001, 0.014)]
    ob("Tischkante", pipe(gold_path, 0.006, 8, closed=True), m["Tischgold"], col, root)
    # Trommel als Podest: roter Kessel, goldene Spannreifen, Schnürung im Zickzack
    top = y - 0.04
    shell = [(0.0, 0.0), (0.44, 0.0), (0.45, 0.01), (0.45, top - 0.01), (0.44, top), (0.0, top)]
    ob("Trommel", lathe(shell, 56, 1.0), m["Trommel"], col, root, sharp=40)
    hoops = []
    for hh in (0.06, top - 0.06):
        hoops.append(lathe([(0.45, hh - 0.026), (0.458, hh - 0.026), (0.464, hh - 0.018), (0.464, hh + 0.018), (0.458, hh + 0.026), (0.45, hh + 0.026)], 56, 0.5))
    ob("Trommel_Reifen", join(*hoops), m["Tischgold"], col, root, sharp=40)
    ropes = []
    nrope = 12
    for k in range(nrope):
        a0, a1, a2 = TAU * k / nrope, TAU * (k + 0.5) / nrope, TAU * (k + 1) / nrope
        lo, hi = 0.086, top - 0.086
        pts = [(a0, hi), (a1, lo), (a2, hi)]
        line = []
        for (ang_a, h_a), (ang_b, h_b) in zip(pts, pts[1:]):
            for i in range(6):
                t = i / 6
                ang = ang_a + (ang_b - ang_a) * t
                line.append(Vector((math.cos(ang) * 0.456, math.sin(ang) * 0.456, h_a + (h_b - h_a) * t)))
        line.append(Vector((math.cos(a2) * 0.456, math.sin(a2) * 0.456, hi)))
        ropes.append(pipe(line, 0.005, 5, caps=False))
    ob("Trommel_Schnuerung", join(*ropes), m["Trommelseil"], col, root, shadow=False)


# =====================================================================================
#  Lichterkette unter der Decke
# =====================================================================================

def build_string_lights(col, m, root):
    hw = ROOM_W * 0.5
    cable, sockets = [], []
    idx = 0
    for zz in (-1.4, -0.2):
        n = 11
        line = []
        for i in range(41):
            u = i / 40
            line.append(gl(-hw + 0.1 + (ROOM_W - 0.2) * u, WALL_H + 0.05 - 0.25 * math.sin(PI * u) + 0.03, zz))
        cable.append(pipe(line, 0.003, 5))
        for i in range(n):
            u = i / (n - 1)
            px = -hw + 0.1 + (ROOM_W - 0.2) * u
            py = WALL_H + 0.05 - 0.25 * math.sin(PI * u)
            lamp = lathe([(0.007, 0.02), (0.012, 0.012), (0.02, 0.0), (0.022, -0.012), (0.018, -0.024), (0.008, -0.03), (0.0, -0.031)][::-1], 12, 0.05)
            o = ob("Lichterkette_%02d" % idx, lamp, m["Lichterkette"], col, root, shadow=False)
            o.location = gl(px, py, zz)
            sockets.append(move(lathe([(0.0, 0.018), (0.009, 0.018), (0.009, 0.03), (0.005, 0.034), (0.0, 0.034)], 8, 0.05), gl(px, py, zz)))
            idx += 1
    cable += sockets
    ob("Lichterkette_Kabel", join(*cable), m["Kabel"], col, root, shadow=False)


# =====================================================================================
#  Spieluhr mit Tänzerin, Springteufel und Aufziehschlüssel
# =====================================================================================

def build_music_box(col, m):
    root = empty("Spieluhr", col, size=0.08)
    ob("Kasten", box((0.12, 0.06, 0.09), (0, 0.03, 0)), m["Spieluhr_Holz"], col, root, bevel=0.003, seg=2)
    gold = [sweep([Vector((-0.06, -0.045, 0.056)), Vector((0.06, -0.045, 0.056)), Vector((0.06, 0.045, 0.056)), Vector((-0.06, 0.045, 0.056))],
                  [(0.0, -0.004), (0.0015, -0.004), (0.0028, 0.0), (0.0015, 0.004), (0.0, 0.004)])]
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            gold.append(geo.ellipsoid(Vector((0.007, 0.007, 0.005)), gl(sx * 0.05, 0.002, sz * 0.036), 10, 6))
    gold.append(aim(lathe([(0.0, 0.0), (0.009, 0.0), (0.009, 0.0015), (0.004, 0.003), (0.0, 0.003)], 12, 0.02), FRONT, gl(0, 0.032, 0.045)))
    ob("Kasten_Gold", join(*gold), m["Spieluhr_Gold"], col, root, sharp=40)
    # Deckel hängt hinten am Scharnier (Knoten „Deckel“ klappt im Spiel auf)
    lid = empty("Deckel", col, (0, 0.062, -0.045), parent=root, size=0.03)
    ob("Deckel_Holz", box((0.12, 0.012, 0.09), (0, 0.006, 0.045)), m["Spieluhr_Holz"], col, lid, bevel=0.003, seg=2)
    hinge = [pipe([gl(sx * 0.035 - 0.012, 0.0, -0.001), gl(sx * 0.035 + 0.012, 0.0, -0.001)], 0.003, 8) for sx in (-1.0, 1.0)]
    ob("Deckel_Scharnier", join(*hinge), m["Spieluhr_Gold"], col, lid)
    # Tänzerin (Knoten dreht sich): Sockel, Tutu, Mieder, Kopf mit Dutt, Arme über dem Kopf
    dancer = empty("Taenzerin", col, (0, 0.075, 0), parent=root, size=0.03)
    dress = [pleated([(0.004, 0.022), (0.02, 0.0245), (0.024, 0.026), (0.02, 0.0275), (0.004, 0.03)], [0.0, 0.08, 0.12, 0.08, 0.0], 10, 30),
             lathe([(0.0, 0.026), (0.0055, 0.026), (0.0048, 0.033), (0.006, 0.04), (0.0045, 0.044), (0.0, 0.044)], 10, 0.02)]
    ob("Taenzerin_Kleid", join(*dress), m["Taenzerin_Kleid"], col, dancer)
    skin = [lathe([(0.0, 0.004), (0.0028, 0.004), (0.0036, 0.016), (0.0032, 0.026), (0.0, 0.026)], 8, 0.02),
            lathe([(0.0, 0.044), (0.0022, 0.044), (0.0022, 0.047), (0.0, 0.047)], 8, 0.02),
            geo.ellipsoid(Vector((0.0058, 0.0058, 0.0065)), Vector((0, 0, 0.0525)), 12, 8)]
    for s in (-1.0, 1.0):
        skin.append(pipe([Vector((s * 0.0045, 0, 0.042)), Vector((s * 0.013, 0, 0.047)), Vector((s * 0.012, 0, 0.058)), Vector((s * 0.003, 0, 0.066))], 0.0014, 5))
    ob("Taenzerin_Haut", join(*skin), m["Taenzerin_Haut"], col, dancer)
    hair = [geo.ellipsoid(Vector((0.006, 0.0062, 0.005)), Vector((0, 0.0012, 0.0545)), 10, 6), geo.ellipsoid(Vector((0.003, 0.003, 0.003)), Vector((0, 0.003, 0.06)), 8, 6)]
    ob("Taenzerin_Haar", join(*hair), m["Taenzerin_Haar"], col, dancer)
    ob("Taenzerin_Sockel", lathe([(0.0, 0.0), (0.012, 0.0), (0.012, 0.002), (0.006, 0.004), (0.0, 0.004)], 14, 0.02), m["Spieluhr_Gold"], col, dancer)
    # Springteufel (im Spiel versteckt, schnellt aus dem Kasten): Feder, Kopf, Kappe mit zwei Zipfeln
    jack = empty("Springteufel", col, (0, 0.06, 0), parent=root, size=0.03)
    coil = [Vector((math.cos(TAU * 6 * i / 96) * 0.016, math.sin(TAU * 6 * i / 96) * 0.016, 0.006 + 0.064 * i / 96)) for i in range(97)]
    ob("Teufel_Feder", pipe(coil, 0.0028, 6), m["Feder"], col, jack)
    ob("Teufel_Gesicht", geo.ellipsoid(Vector((0.03, 0.03, 0.03)), Vector((0, 0, 0.1)), 20, 14), m["Teufel_Gesicht"], col, jack)
    ob("Teufel_Nase", geo.ellipsoid(Vector((0.009, 0.009, 0.009)), gl(0, 0.098, 0.03), 12, 8), m["Teufel_Nase"], col, jack)
    dark = [geo.ellipsoid(Vector((0.004, 0.003, 0.0055)), gl(s * 0.011, 0.11, 0.027), 8, 6) for s in (-1.0, 1.0)]
    smile = []
    for a in [-0.9 + 1.8 * i / 10 for i in range(11)]:
        sx, sy = math.sin(a) * 0.02, -math.cos(a) * 0.016
        smile.append(gl(sx, 0.1 + sy, math.sqrt(0.03 ** 2 - sx * sx - sy * sy) + 0.0004))
    dark.append(pipe(smile, 0.0013, 5))
    ob("Teufel_Augen", join(*dark), m["Teufel_Auge"], col, jack)
    for s, name in ((-1.0, "Kappe_Gelb"), (1.0, "Kappe_Blau")):
        horn = lathe([(0.0, 0.0), (0.015, 0.0), (0.013, 0.012), (0.008, 0.028), (0.003, 0.04), (0.0, 0.042)], 10, 0.02)
        cap = geo.ellipsoid(Vector((0.0316, 0.0316, 0.032)), Vector((0, 0, 0)), 16, 12)
        bmesh.ops.delete(cap, geom=[v for v in cap.verts if v.co.z < 0.011 or v.co.x * s < -0.001], context="VERTS")
        parts = [move(cap, gl(0, 0.1, 0)), aim(horn, (s * 0.56, 0, 0.83), gl(s * 0.018, 0.122, 0))]
        ob("Teufel_" + name, join(*parts), m[name], col, jack)
    balls = [geo.ellipsoid(Vector((0.006, 0.006, 0.006)), gl(s * 0.043, 0.158, 0), 10, 6) for s in (-1.0, 1.0)]
    ob("Teufel_Bommel", join(*balls), m["Kappe_Bommel"], col, jack)
    ruff = pleated([(0.016, -0.006), (0.034, -0.002), (0.034, 0.002), (0.016, 0.006)], [0.0, 0.18, 0.18, 0.0], 10, 40)
    ob("Teufel_Kragen", move(ruff, gl(0, 0.07, 0)), m["Teufel_Kragen"], col, jack, sharp=None)
    # Aufziehschlüssel an der Seite (Knoten „Key“ dreht sich um seine Achse)
    key = empty("Key", col, (0.068, 0.03, 0), parent=root, size=0.02)
    kp = [pipe([Vector((-0.008, 0, 0)), Vector((0.02, 0, 0))], 0.0035, 8)]
    for s in (-1.0, 1.0):
        loop_pts = [Vector((0.027 + math.cos(TAU * i / 14) * 0.007, 0.0, s * 0.009 + math.sin(TAU * i / 14) * 0.008)) for i in range(14)]
        kp.append(pipe(loop_pts, 0.0022, 5, closed=True))
    ob("Key_Gold", join(*kp), m["Spieluhr_Gold"], col, key)
    return root


# =====================================================================================
#  Luftballon (Vorlage für die Leben)
# =====================================================================================

def build_balloon(col, m):
    R = BALLOON_R
    root = empty("Luftballon", col, size=0.05)
    # Tropfenform; das Spiel streckt den Ballon wie bisher um 1,2 in der Höhe
    prof = [(0.0, -R * 1.06), (R * 0.1, -R * 1.04), (R * 0.3, -R * 0.93), (R * 0.58, -R * 0.72), (R * 0.84, -R * 0.4), (R * 0.97, -R * 0.08),
            (R, R * 0.2), (R * 0.93, R * 0.5), (R * 0.76, R * 0.76), (R * 0.5, R * 0.93), (R * 0.22, R * 1.0), (0.0, R * 1.01)]
    ob("Ballon", lathe(prof, 24, 0.1), m["Ballon"], col, root, sharp=None, shadow=False)
    knot = [(0.0, -0.009), (0.011, -0.009), (0.012, -0.006), (0.008, -0.002), (0.004, 0.002), (0.0035, 0.008), (0.0, 0.009)]
    k = ob("Ballonknoten", pleated([(r, h) for r, h in knot[1:-1]], [0.2, 0.2, 0.1, 0.0, 0.0], 6, 18), m["Ballon"], col, root, sharp=None, shadow=False)
    k.location = gl(0, -R * 1.12, 0)  # nur für die Ansicht; das Spiel setzt Ballon und Knoten selbst
    return root


# =====================================================================================
#  Kulisse (nur Blender) und Aufbau
# =====================================================================================

def _preview(col, m):
    boards = mat("Preview_Bretter", (0.75, 0.7, 0.68), 0.75, tex=os.path.join(ROOM_TEX, "boards.png"), scale=0.55)
    floor = mat("Preview_Boden", (1, 1, 1), 0.8, tex=os.path.join(ROOM_TEX, "floor.png"), scale=0.8)
    tent = mat("Preview_Zelt", (0.5, 0.42, 0.4), 0.9, tex=os.path.join(ROOM_TEX, "tent.png"), scale=0.6)
    hw = ROOM_W * 0.5
    h = WALL_H + VAULT
    g0, g1 = GAP_X - GAP_W * 0.5, GAP_X + GAP_W * 0.5
    ob("Preview_Boden", ngon([gl(-hw, 0, FRONT_Z), gl(hw, 0, FRONT_Z), gl(hw, 0, BACK_Z - 3), gl(-hw, 0, BACK_Z - 3)]), floor, col, smooth=False)
    walls = [quad(gl(-hw, 0, FRONT_Z), gl(-hw, 0, BACK_Z), gl(-hw, WALL_H, BACK_Z), gl(-hw, WALL_H, FRONT_Z), [(FRONT_Z, 0), (BACK_Z, 0), (BACK_Z, WALL_H), (FRONT_Z, WALL_H)]),
             quad(gl(hw, 0, BACK_Z), gl(hw, 0, FRONT_Z), gl(hw, WALL_H, FRONT_Z), gl(hw, WALL_H, BACK_Z), [(BACK_Z, 0), (FRONT_Z, 0), (FRONT_Z, WALL_H), (BACK_Z, WALL_H)])]
    for a, b, lo in ((-hw, g0, 0.0), (g1, hw, 0.0), (g0, g1, 1.95)):
        walls.append(quad(gl(a, lo, BACK_Z), gl(b, lo, BACK_Z), gl(b, h, BACK_Z), gl(a, h, BACK_Z), [(a, lo), (b, lo), (b, h), (a, h)]))
    ob("Preview_Waende", join(*walls), boards, col, smooth=False)
    ob("Preview_Zelt", quad(gl(GAP_X - 2.5, 0, BACK_Z - 2.4), gl(GAP_X + 2.5, 0, BACK_Z - 2.4), gl(GAP_X + 2.5, 3.4, BACK_Z - 2.4), gl(GAP_X - 2.5, 3.4, BACK_Z - 2.4),
                            [(0, 0), (5, 0), (5, 1.6), (0, 1.6)]), tent, col, smooth=False)
    preview_light(col, "Preview_Licht_Decke", "POINT", (0, WALL_H + 0.1, -0.6), (1.0, 0.78, 0.56), 60.0, shadow_soft_size=0.3)
    preview_light(col, "Preview_Licht_Spiegel", "POINT", (hw - 0.4, 1.45, -1.2), (1.0, 0.88, 0.69), 20.0)
    preview_light(col, "Preview_Licht_Spalt", "POINT", (GAP_X + 0.3, 1.6, BACK_Z + 0.4), (1.0, 0.6, 0.48), 25.0)
    world_color((0.02, 0.01, 0.01))


def build_all(preview=True):
    """Ganze Szene neu aufbauen (löscht alles in der aktuellen Datei)."""
    clear_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    m = M()
    col = geo.collection("Zirkus")
    root = empty("Zirkus", col)
    build_shell(col, m, root)
    build_curtain(col, m, root)
    build_costumes(col, m, root)
    build_mirror(col, m, root)
    build_table(col, m, root)
    build_string_lights(col, m, root)
    build_music_box(geo.collection("Spieluhr"), m)
    build_balloon(geo.collection("Luftballon"), m)
    place(PLACES, True)
    if preview:
        _preview(geo.collection("Kulisse"), m)
    return "ok"


def export_all(out_dir=None):
    return export_files(FILES, out_dir or OUT_DIR, PLACES)
