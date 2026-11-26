"""Raum „Bahnhofswartesaal“ als Blender-Modelle.

    import sys; sys.path.insert(0, r"<Repo>/art/blender")
    import station; station.build_all(); station.export_all()

Design, Maße und Positionen stammen 1:1 aus scenes/match/rooms/station_room.gd; besser wird
nur die Machart. Koordinaten sind Godot-Koordinaten (siehe room_kit.gl).

    station.glb   Tisch, Fenster, Heizkörper, Bänke, Koffer, Heißwasserkessel, Fahrplantafel,
                  Neonleuchten („Roehre_0…2“ leuchten einzeln), Kachel- und Sockelleisten,
                  Zuckerstücke, Bahnsteiglampen
    train.glb     der Zug („Zug“, fährt im Spiel als Ganzes vorbei)

Im Code bleiben: Boden, Decke, Kachelwände, Bahnsteig und Gleis, Zeitung, Fahrkarte, alle
Schriften, die LED-Anzeige der Leben, Lichter und Geräusche.
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

ROOM_TEX = os.path.join(REPO, "assets", "rooms", "station")
OUT_DIR = ROOM_TEX

# Maße wie in station_room.gd
ROOM_W = 5.0
BACK_Z = -2.4
CEIL = 3.3
TOP = (1.84, 1.3)
WIN_X = 1.65
WIN_W = 0.9
WIN_Y = (1.0, 2.65)
TRACK_Z = BACK_Z - 2.2
TRAIN_CARS = 7
CAR_LEN = 6.2
FRONT_Z = 3.6  # Seitenwände reichen von BACK_Z bis hierher

FILES = {"station.glb": ["Bahnhof"], "train.glb": ["Zug"]}
PLACES = {"Zug": ((14.0, 0.0, TRACK_Z), 0.0, 1.0)}  # nur für die Ansicht: Zug steht vor den Fenstern


def M():
    wood_c = os.path.join(MODEL_TEX, "table_wood_color.png")
    wood_n = os.path.join(MODEL_TEX, "table_wood_normal.png")
    tiles = os.path.join(ROOM_TEX, "tiles.png")
    d = {}
    d["Tischplatte"] = mat("Tischplatte", (0.42, 0.26, 0.16), 0.4, tex=wood_c, normal=wood_n, scale=0.9)
    d["Tischgestell"] = mat("Tischgestell", (0.3, 0.18, 0.1), 0.4, tex=wood_c, normal=wood_n, scale=0.9)
    d["Fensterrahmen"] = mat("Fensterrahmen", (0.2, 0.28, 0.24), 0.55)
    d["Fensterglas"] = mat("Fensterglas", (0.55, 0.7, 0.75), 0.08, alpha=0.12)
    d["Fensterbank"] = mat("Fensterbank", (0.5, 0.5, 0.46), 0.7)
    d["Gusseisen"] = mat("Gusseisen", (0.32, 0.34, 0.32), 0.5)
    d["Banklatten"] = mat("Banklatten", (0.55, 0.36, 0.2), 0.55, tex=wood_c, normal=wood_n, scale=1.0)
    d["Bankeisen"] = mat("Bankeisen", (0.08, 0.09, 0.08), 0.5)
    d["Kofferleder"] = mat("Kofferleder", (0.36, 0.22, 0.12), 0.6)
    d["Koffergriff"] = mat("Koffergriff", (0.15, 0.1, 0.06), 0.5)
    d["Messing"] = mat("Messing", (0.7, 0.55, 0.3), 0.3, 1.0)
    d["Kesselsockel"] = mat("Kesselsockel", (0.2, 0.3, 0.24), 0.6)
    d["Kesselblech"] = mat("Kesselblech", (0.55, 0.57, 0.52), 0.4, 0.7)
    d["Tafelrahmen"] = mat("Tafelrahmen", (0.3, 0.3, 0.28), 0.5)
    d["Tafel"] = mat("Tafel", (0.03, 0.035, 0.04), 0.8)
    d["Klappfeld"] = mat("Klappfeld", (0.08, 0.085, 0.09), 0.6)
    d["Blech"] = mat("Blech", (0.82, 0.84, 0.8), 0.5, 0.4)
    d["Draht"] = mat("Draht", (0.1, 0.1, 0.1), 0.6)
    d["Roehre"] = mat("Roehre", (0.92, 1.0, 0.97), 0.3, emission=(0.86, 1.0, 0.95), energy=3.0)
    d["Kachel_Dunkel"] = mat("Kachel_Dunkel", (0.14, 0.3, 0.2), 0.18, tex=tiles, scale=1.6)
    d["Sockelleiste"] = mat("Sockelleiste", (0.12, 0.16, 0.13), 0.6)
    d["Deckenkehle"] = mat("Deckenkehle", (0.6, 0.6, 0.55), 0.9)
    d["Zucker"] = mat("Zucker", (0.97, 0.96, 0.93), 0.9)
    d["Lampenmast"] = mat("Lampenmast", (0.12, 0.12, 0.12), 0.5)
    d["Lampenkugel"] = mat("Lampenkugel", (1.0, 0.85, 0.55), 0.3, emission=(1.0, 0.85, 0.55), energy=3.0)
    # Zug
    d["Waggon"] = mat("Waggon", (0.12, 0.26, 0.18), 0.55)
    d["Waggondach"] = mat("Waggondach", (0.2, 0.2, 0.2), 0.6)
    d["Zierstreifen"] = mat("Zierstreifen", (0.75, 0.68, 0.4), 0.5)
    d["Fahrgestell"] = mat("Fahrgestell", (0.05, 0.05, 0.05), 0.8)
    d["Zugfenster_Hell"] = mat("Zugfenster_Hell", (1.0, 0.86, 0.5), 0.3, emission=(1.0, 0.86, 0.5), energy=2.0)
    d["Zugfenster_Dunkel"] = mat("Zugfenster_Dunkel", (0.05, 0.05, 0.05), 0.8)
    return d


def rounded_rect(hx, hz, r, seg=6):
    """Abgerundetes Rechteck in der Blender-XY-Ebene (halbe Maße), gegen den Uhrzeigersinn."""
    pts = []
    for cx, cy, a0 in ((hx - r, -hz + r, -90), (hx - r, hz - r, 0), (-hx + r, hz - r, 90), (-hx + r, -hz + r, 180)):
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append(Vector((cx + r * math.cos(a), cy + r * math.sin(a), 0.0)))
    return pts


# =====================================================================================
#  Tisch
# =====================================================================================

def build_table(col, m, root):
    y = TABLE_Y
    hx, hz = TOP[0] * 0.5, TOP[1] * 0.5
    # Platte: Oberseite genau auf TABLE_Y (Karten liegen darauf), Kante gerundet und unterschnitten
    path = [p + Z * y for p in rounded_rect(hx - 0.012, hz - 0.012, 0.012)]
    top = ngon(path)
    edge = [(0.0, -0.045), (0.004, -0.045), (0.009, -0.040), (0.012, -0.030), (0.012, -0.010), (0.009, -0.003), (0.004, 0.0), (0.0, 0.0)]
    under = ngon([p + Z * (y - 0.045) for p in rounded_rect(hx - 0.012, hz - 0.012, 0.012)], flip=True)
    ob("Tischplatte", join(top, sweep(path, edge), under), m["Tischplatte"], col, root, sharp=50)
    # Zarge mit Zierstab an der Unterkante, vier konische Beine mit gefasten Kanten
    ax, az = hx - 0.05, hz - 0.05
    apath = [Vector((-ax, -az, y)), Vector((ax, -az, y)), Vector((ax, az, y)), Vector((-ax, az, y))]
    apron = [(-0.02, -0.135), (-0.004, -0.135), (0.002, -0.131), (0.003, -0.125), (0.0, -0.120), (0.0, -0.045)]
    ob("Tischgestell", sweep(apath, apron), m["Tischgestell"], col, root, sharp=35)
    legs = []
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            cx, cz = sx * (hx - 0.1), sz * (hz - 0.1)
            rings = []
            for hh, w in ((0.0, 0.024), (0.02, 0.027), (0.045, 0.022), (y - 0.20, 0.035), (y - 0.05, 0.035)):
                c = gl(cx, hh, cz)
                rings.append([c + Vector((-w, -w, 0)), c + Vector((w, -w, 0)), c + Vector((w, w, 0)), c + Vector((-w, w, 0))])
            leg = loft(rings)
            geo.box_uv(leg, 1.0, True)
            legs.append(leg)
    ob("Tischbeine", join(*legs), m["Tischgestell"], col, root, sharp=35, bevel=0.004, seg=2)


# =====================================================================================
#  Fenster und Heizkörper
# =====================================================================================

def build_windows(col, m, root):
    frames, panes, sills, ribs, pipes = [], [], [], [], []
    wall = -BACK_Z
    h = WIN_Y[1] - WIN_Y[0]
    for s in (-1.0, 1.0):
        cx = s * WIN_X
        x0, x1 = cx - WIN_W * 0.5, cx + WIN_W * 0.5
        prof = [(0.0, 0.0), (0.004, 0.006), (0.012, 0.008), (0.03, 0.008), (0.045, 0.002), (0.055, -0.01), (0.06, -0.04)]
        frames.append(panel_moulding(x0, x1, WIN_Y[0], WIN_Y[1], wall, prof))
        frames.append(box((0.045, h - 0.1, 0.05), (cx, (WIN_Y[0] + WIN_Y[1]) * 0.5, BACK_Z - 0.021)))
        frames.append(box((WIN_W - 0.1, 0.04, 0.05), (cx, WIN_Y[0] + h * 0.68, BACK_Z - 0.021)))
        frames.append(box((WIN_W - 0.1, 0.03, 0.045), (cx, WIN_Y[0] + h * 0.34, BACK_Z - 0.022)))
        panes.append(quad(gl(x0 + 0.05, WIN_Y[0] + 0.05, BACK_Z - 0.04), gl(x1 - 0.05, WIN_Y[0] + 0.05, BACK_Z - 0.04),
                          gl(x1 - 0.05, WIN_Y[1] - 0.05, BACK_Z - 0.04), gl(x0 + 0.05, WIN_Y[1] - 0.05, BACK_Z - 0.04),
                          [(0, 0), (1, 0), (1, 1), (0, 1)]))
        sills.append(box((WIN_W + 0.12, 0.04, 0.2), (cx, WIN_Y[0] - 0.01, BACK_Z + 0.06)))
        # Gussheizkörper: neun Glieder mit runden Kanten, oben und unten durchgehende Rohre, Füße, Ventil
        for k in range(9):
            ribs.append(box((0.058, 0.5, 0.085), (cx - 0.32 + k * 0.08, 0.45, BACK_Z + 0.09)))
        for yy in (0.66, 0.24):
            pipes.append(pipe([gl(cx - 0.37, yy, BACK_Z + 0.09), gl(cx + 0.37, yy, BACK_Z + 0.09)], 0.02, 10))
        for dx in (-0.28, 0.28):
            pipes.append(box((0.03, 0.2, 0.06), (cx + dx, 0.1, BACK_Z + 0.09)))
        vx = cx + 0.4
        pipes.append(pipe([gl(vx - 0.03, 0.24, BACK_Z + 0.09), gl(vx, 0.24, BACK_Z + 0.09), gl(vx + 0.012, 0.22, BACK_Z + 0.09),
                           gl(vx + 0.012, 0.0, BACK_Z + 0.09)], 0.012, 8))
        knob = lathe([(0.0, 0.0), (0.016, 0.0), (0.02, 0.006), (0.02, 0.02), (0.014, 0.026), (0.0, 0.027)], 12, 0.1)
        pipes.append(move(rot(knob, PI * 0.5, "Y"), gl(vx - 0.035, 0.66, BACK_Z + 0.09)))
    ob("Fensterrahmen", join(*frames), m["Fensterrahmen"], col, root, sharp=35, bevel=0.002, seg=2)
    ob("Fensterglas", join(*panes), m["Fensterglas"], col, root, smooth=False, shadow=False)
    ob("Fensterbaenke", join(*sills), m["Fensterbank"], col, root, bevel=0.012, seg=3)
    ob("Heizkoerper", join(*ribs), m["Gusseisen"], col, root, bevel=0.024, seg=3)
    ob("Heizkoerper_Rohre", join(*pipes), m["Gusseisen"], col, root, sharp=40)


# =====================================================================================
#  Bänke, Koffer
# =====================================================================================

def _bench(length):
    """Eine Bank, lokal: X entlang, Sitzkante bei +Z (Godot), Lehne bei -Z."""
    slats, iron = [], []
    for k in range(4):
        slats.append(box((length, 0.03, 0.08), (0, 0.45, -0.15 + k * 0.1)))
    for k in range(3):
        b = rot(box((length, 0.08, 0.025), (0, 0, 0)), -0.18, "X")
        slats.append(move(b, gl(0, 0.6 + k * 0.12, -0.24 - k * 0.02)))
    n = 3 if length > 1.6 else 2
    for k in range(n):
        x = (-length * 0.5 + 0.04) + k * (length - 0.08) / (n - 1)

        def P(z, yy):
            return gl(x, yy, z)

        # Gussteil: hinterer Pfosten (läuft in die Lehne aus), vorderes Bein, Sitzträger, Strebe
        iron.append(bar([P(-0.20, 0.0), P(-0.215, 0.25), P(-0.228, 0.45), P(-0.250, 0.66), P(-0.280, 0.84), P(-0.296, 0.93)], 0.034, 0.04, X))
        iron.append(bar([P(0.155, 0.0), P(0.128, 0.2), P(0.122, 0.34), P(0.132, 0.432)], 0.034, 0.04, X))
        iron.append(bar([P(-0.232, 0.418), P(0.134, 0.418)], 0.03, 0.04, X))
        iron.append(bar([P(-0.21, 0.16), P(0.133, 0.16)], 0.022, 0.03, X))
        if k in (0, n - 1):  # Armlehne mit Schwung nach unten
            iron.append(bar([P(-0.262, 0.664), P(0.06, 0.664), P(0.135, 0.648), P(0.168, 0.60), P(0.158, 0.52), P(0.136, 0.44)], 0.024, 0.05, X))
    return join(*slats), join(*iron)


def build_benches(col, m, root):
    slats, iron = [], []
    spots = []
    for s in (-1.0, 1.0):
        spots.append(((s * (ROOM_W * 0.5 - 0.32), 0, -0.9), -s * PI * 0.5, 2.0))
        spots.append(((s * (ROOM_W * 0.5 - 0.32), 0, 1.4), -s * PI * 0.5, 2.0))
        spots.append(((s * WIN_X, 0, BACK_Z + 0.5), 0.0, 1.5))
    for pos, ang, length in spots:
        a, b = _bench(length)
        for part, bucket in ((a, slats), (b, iron)):
            geo.transform(part, Matrix.Translation(gl(*pos)) @ Matrix.Rotation(ang, 4, "Z"))
            bucket.append(part)
    ob("Baenke_Latten", join(*slats), m["Banklatten"], col, root, bevel=0.006, seg=2)
    ob("Baenke_Eisen", join(*iron), m["Bankeisen"], col, root, sharp=50, bevel=0.003, seg=1)

    # Koffer neben der linken hinteren Bank: Kanten gerundet, Riemen, Eckbeschläge, Griff
    pos, ang = gl(-WIN_X + 0.95, 0.0, BACK_Z + 0.45), 0.25
    T = Matrix.Translation(pos) @ Matrix.Rotation(ang, 4, "Z")
    body = geo.transform(box((0.55, 0.38, 0.18), (0, 0.19, 0)), T)
    ob("Koffer", body, m["Kofferleder"], col, root, bevel=0.018, seg=3)
    dark = [box((0.036, 0.386, 0.186), (sx * 0.15, 0.19, 0)) for sx in (-1.0, 1.0)]
    dark.append(box((0.556, 0.012, 0.186), (0, 0.27, 0)))  # Deckelfuge
    handle = [gl(-0.06, 0.38, 0), gl(-0.055, 0.405, 0), gl(-0.03, 0.418, 0), gl(0.03, 0.418, 0), gl(0.055, 0.405, 0), gl(0.06, 0.38, 0)]
    dark.append(pipe(handle, 0.009, 8))
    ob("Koffer_Riemen", geo.transform(join(*dark), T), m["Koffergriff"], col, root, bevel=0.004, seg=2)
    brass = []
    for sx in (-1.0, 1.0):
        brass.append(box((0.03, 0.012, 0.03), (sx * 0.06, 0.384, 0)))
        brass.append(box((0.03, 0.04, 0.008), (sx * 0.15, 0.275, 0.094)))
        for sy in (0.012, 0.368):
            for sz in (-1.0, 1.0):
                brass.append(geo.ellipsoid(Vector((0.022, 0.022, 0.022)), gl(sx * 0.262, sy, sz * 0.078), 10, 8))
    ob("Koffer_Beschlaege", geo.transform(join(*brass), T), m["Messing"], col, root)


# =====================================================================================
#  Heißwasserkessel, Fahrplantafel, Neonleuchten
# =====================================================================================

def build_kettle(col, m, root):
    x, z = ROOM_W * 0.5 - 0.3, 0.25
    # lokal gebaut mit Vorderseite nach +Z (Godot), dann zur Raummitte gedreht (-X)
    T = Matrix.Translation(gl(x, 0, z)) @ Matrix.Rotation(-PI * 0.5, 4, "Z")
    cab = [box((0.5, 0.8, 0.4), (0, 0.4, 0)), box((0.53, 0.07, 0.43), (0, 0.035, 0)), box((0.54, 0.025, 0.44), (0, 0.79, 0))]
    ob("Kessel_Sockel", geo.transform(join(*cab), T), m["Kesselsockel"], col, root, bevel=0.006, seg=2)
    ogee = [(0.0, 0.0), (0.002, 0.006), (0.006, 0.009), (0.012, 0.009), (0.016, 0.005), (0.02, 0.0)]
    door = panel_moulding(-0.19, 0.19, 0.13, 0.72, -0.2, ogee)
    ob("Kessel_Tuer", geo.transform(door, T), m["Kesselsockel"], col, root, sharp=30)
    tank = [(0.0, 0.8), (0.19, 0.8), (0.2, 0.808), (0.206, 0.82), (0.206, 0.842), (0.2, 0.852), (0.2, 1.34), (0.206, 1.35),
            (0.206, 1.378), (0.2, 1.388), (0.2, 1.40), (0.212, 1.402), (0.214, 1.41), (0.212, 1.438), (0.17, 1.468),
            (0.08, 1.494), (0.03, 1.50), (0.03, 1.51), (0.045, 1.52), (0.045, 1.535), (0.02, 1.55), (0.0, 1.552)]
    ob("Kessel", geo.transform(lathe(tank, 40, 1.0), T), m["Kesselblech"], col, root, sharp=40)
    tap = [pipe([gl(0, 0.92, 0.19), gl(0, 0.92, 0.27), gl(0, 0.905, 0.285), gl(0, 0.87, 0.285)], 0.014, 10),
           pipe([gl(0, 0.935, 0.255), gl(0, 0.965, 0.255)], 0.006, 8),
           box((0.07, 0.01, 0.016), (0.02, 0.968, 0.255))]
    flange = lathe([(0.0, 0.0), (0.028, 0.0), (0.028, 0.006), (0.02, 0.012), (0.0, 0.012)], 14, 0.1)
    tap.append(move(rot(flange, PI * 0.5, "X"), gl(0, 0.92, 0.198)))
    ob("Kessel_Hahn", geo.transform(join(*tap), T), m["Messing"], col, root, sharp=40)


def build_board(col, m, root):
    y, w, h = 2.12, 1.9, 0.95
    wall = -BACK_Z
    prof = [(0.0, 0.0), (0.0, 0.06), (0.006, 0.074), (0.014, 0.08), (0.026, 0.08), (0.034, 0.074), (0.04, 0.07), (0.044, 0.07)]
    frame = panel_moulding(-w * 0.5 - 0.04, w * 0.5 + 0.04, y - h * 0.5 - 0.04, y + h * 0.5 + 0.04, wall, prof)
    ob("Tafelrahmen", frame, m["Tafelrahmen"], col, root, sharp=35)
    ob("Tafel", box((w + 0.002, h + 0.002, 0.07), (0, y, BACK_Z + 0.035)), m["Tafel"], col, root, smooth=False)
    slots = []
    cols = ((-0.86, 0.18), (-0.62, 0.9), (0.38, 0.24), (0.7, 0.12))
    for r in range(6):
        ry = y + h * 0.5 - 0.25 - r * 0.112
        for cx, cw in cols:
            slots.append(box((cw, 0.085, 0.006), (cx + cw * 0.5 - 0.02, ry, BACK_Z + 0.072)))
    ob("Klappfelder", join(*slots), m["Klappfeld"], col, root, bevel=0.0015, seg=1)


TUBES = (((0, 2.55, -0.15), 1.6), ((-1.2, 2.85, -1.7), 1.2), ((1.3, 2.85, 1.2), 1.2))


def build_tubes(col, m, root):
    housing, wires = [], []
    shell = [(0.06, 0.012), (0.06, 0.02), (0.035, 0.05), (-0.035, 0.05), (-0.06, 0.02), (-0.06, 0.012),
             (-0.054, 0.012), (-0.03, 0.042), (0.03, 0.042), (0.054, 0.012), (0.06, 0.012)]
    for i, (pos, length) in enumerate(TUBES):
        c = gl(*pos)
        hl = length * 0.5
        housing.append(sweep([c + Vector((-hl - 0.03, 0, 0)), c + Vector((hl + 0.03, 0, 0))], shell, closed=False, caps=True))
        tube = pipe([c + Vector((-hl + 0.02, 0, 0)), c + Vector((hl - 0.02, 0, 0))], 0.016, 12)
        ob("Roehre_%d" % i, tube, m["Roehre"], col, root, shadow=False)
        for s in (-1.0, 1.0):
            housing.append(box((0.03, 0.05, 0.05), (pos[0] + s * hl, pos[1] + 0.003, pos[2])))
            housing.append(pipe([c + Vector((s * (hl - 0.03), 0, 0)), c + Vector((s * (hl - 0.014), 0, 0))], 0.0185, 12))
            wx = pos[0] + s * length * 0.35
            wires.append(pipe([gl(wx, pos[1] + 0.05, pos[2]), gl(wx, CEIL, pos[2])], 0.003, 6, caps=False))
            wires.append(move(lathe([(0.0, -0.012), (0.012, -0.012), (0.018, -0.004), (0.018, 0.0), (0.0, 0.0)], 10, 0.1), gl(wx, CEIL, pos[2])))
    ob("Neon_Gehaeuse", join(*housing), m["Blech"], col, root, sharp=40, bevel=0.002, seg=1)
    ob("Neon_Draehte", join(*wires), m["Draht"], col, root, shadow=False)


# =====================================================================================
#  Leisten an den Wänden, Kleinteile, Bahnsteiglampen
# =====================================================================================

def build_trims(col, m, root):
    hw = ROOM_W * 0.5
    left = [gl(-hw, 0, FRONT_Z), gl(-hw, 0, BACK_Z)]
    right = [gl(hw, 0, BACK_Z), gl(hw, 0, FRONT_Z)]
    w0, w1 = WIN_X - WIN_W * 0.5, WIN_X + WIN_W * 0.5
    # Kachelleisten: an den Fenstern unterbrochen
    pieces = [left + [gl(-w1, 0, BACK_Z)], [gl(-w0, 0, BACK_Z), gl(w0, 0, BACK_Z)], [gl(w1, 0, BACK_Z)] + right]
    tiles = []
    for y0, y1, d in ((1.10, 1.17, 0.015), (1.85, 1.90, 0.012)):
        mid = (y0 + y1) * 0.5
        prof = [(0.0, y0), (d * 0.55, y0), (d * 0.9, y0 + 0.008), (d, mid), (d * 0.9, y1 - 0.008), (d * 0.55, y1), (0.0, y1)]
        for p in pieces:
            tiles.append(sweep(p, prof, closed=False, caps=True))
    ob("Kachelleisten", join(*tiles), m["Kachel_Dunkel"], col, root, sharp=40)
    base = [(0.0, 0.0), (0.03, 0.0), (0.03, 0.07), (0.026, 0.085), (0.018, 0.095), (0.012, 0.1), (0.0, 0.1)]
    ob("Sockelleiste", sweep(left + right, base, closed=False), m["Sockelleiste"], col, root, sharp=40)
    cove = [(0.0, CEIL - 0.12), (0.012, CEIL - 0.12), (0.016, CEIL - 0.11)] + \
           [(0.016 + 0.094 * (1 - math.cos(t)), CEIL - 0.11 + 0.094 * math.sin(t)) for t in [PI * 0.5 * i / 8 for i in range(1, 9)]] + \
           [(0.12, CEIL - 0.008), (0.12, CEIL), (0.0, CEIL)]
    ob("Deckenkehle", sweep([gl(-hw, 0, BACK_Z), gl(hw, 0, BACK_Z)], cove, closed=False), m["Deckenkehle"], col, root, sharp=40)


def build_small(col, m, root):
    y = TABLE_Y
    cubes = []
    for k in range(3):
        c = rot(box((0.014, 0.012, 0.014), (0, 0, 0)), k * 0.7, "Z")
        cubes.append(move(c, gl(0.74 + k * 0.018, y + 0.006, -0.06 + (k % 2) * 0.012)))
    ob("Zucker", join(*cubes), m["Zucker"], col, root, bevel=0.0012, seg=2)
    # Bahnsteiglampen: Mast mit Fuß und Kragen, Kugel obenauf
    poles, globes = [], []
    for x in (-WIN_X - 0.6, WIN_X + 0.4):
        prof = [(0.0, 0.9), (0.07, 0.9), (0.075, 0.93), (0.05, 1.0), (0.04, 1.1), (0.034, 1.6), (0.03, 3.4), (0.045, 3.43),
                (0.06, 3.47), (0.06, 3.5), (0.03, 3.52), (0.0, 3.52)]
        poles.append(move(lathe(prof, 16, 1.0), gl(x, 0, BACK_Z - 1.2)))
        poles.append(move(lathe([(0.0, 3.68), (0.03, 3.68), (0.022, 3.70), (0.008, 3.72), (0.0, 3.74)], 12, 0.2), gl(x, 0, BACK_Z - 1.2)))
        globes.append(geo.ellipsoid(Vector((0.09, 0.09, 0.09)), gl(x, 3.6, BACK_Z - 1.2), 20, 12))
    ob("Bahnsteiglampen", join(*poles), m["Lampenmast"], col, root)
    ob("Bahnsteiglampen_Kugeln", join(*globes), m["Lampenkugel"], col, root, shadow=False)


# =====================================================================================
#  Zug
# =====================================================================================

def build_train(col, m):
    root = empty("Zug", col, size=0.5)
    body, roof, stripe, dark, lit, unlit = [], [], [], [], [], []
    hw = 1.45
    arc = [(1.47 * math.cos(PI * i / 16), 2.97 + 0.4 * math.sin(PI * i / 16)) for i in range(17)]
    for c in range(TRAIN_CARS):
        x0 = -c * CAR_LEN - CAR_LEN * 0.5
        hl = (CAR_LEN - 0.35) * 0.5
        a, b = Vector((x0 - hl, 0, 0)), Vector((x0 + hl, 0, 0))
        body.append(sweep([a, b], [(-hw, 2.95), (-hw, 0.5), (hw, 0.5), (hw, 2.95)], closed=False))
        outline = [(hw, 0.5), (hw, 2.95)] + arc[1:-1] + [(-hw, 2.95), (-hw, 0.5)]
        body.append(ngon([Vector((a.x, -o, hh)) for o, hh in outline]))
        body.append(ngon([Vector((b.x, -o, hh)) for o, hh in outline], flip=True))
        roof.append(sweep([a - Vector((0.03, 0, 0)), b + Vector((0.03, 0, 0))], [(1.5, 2.93), (1.5, 2.97)] + arc[1:-1] + [(-1.5, 2.97), (-1.5, 2.93)], closed=False))
        for k in range(3):
            roof.append(box((0.5, 0.08, 0.3), (x0 - 1.8 + k * 1.8, 3.40, 0)))
        for sz in (-1.0, 1.0):
            stripe.append(box((CAR_LEN - 0.35, 0.06, 0.012), (x0, 1.45, sz * (hw + 0.004))))
        dark.append(box((CAR_LEN - 0.6, 0.4, 2.4), (x0, 0.35, 0)))
        dark.append(box((0.36, 2.0, 1.2), (x0 - CAR_LEN * 0.5, 1.7, 0)))  # Übergang zum nächsten Wagen
        for k in range(8):
            x = x0 - CAR_LEN * 0.5 + 0.55 + k * 0.72
            dark.append(box((0.58, 0.63, 0.012), (x, 2.25, hw + 0.002)))
            pane = quad(gl(x - 0.25, 1.975, hw + 0.01), gl(x + 0.25, 1.975, hw + 0.01), gl(x + 0.25, 2.525, hw + 0.01), gl(x - 0.25, 2.525, hw + 0.01),
                        [(0, 0), (1, 0), (1, 1), (0, 1)])
            (lit if (c * 8 + k) % 5 != 3 else unlit).append(pane)
    ob("Zug_Wagen", join(*body), m["Waggon"], col, root, sharp=30)
    ob("Zug_Dach", join(*roof), m["Waggondach"], col, root, sharp=40)
    ob("Zug_Streifen", join(*stripe), m["Zierstreifen"], col, root, smooth=False)
    ob("Zug_Fahrgestell", join(*dark), m["Fahrgestell"], col, root, smooth=False)
    ob("Zug_Fenster_Hell", join(*lit), m["Zugfenster_Hell"], col, root, smooth=False, shadow=False)
    ob("Zug_Fenster_Dunkel", join(*unlit), m["Zugfenster_Dunkel"], col, root, smooth=False, shadow=False)
    return root


# =====================================================================================
#  Kulisse (nur Blender) und Aufbau
# =====================================================================================

def _preview(col, m):
    tiles = os.path.join(ROOM_TEX, "tiles.png")
    green = mat("Preview_Kachel_Gruen", (0.36, 0.6, 0.46), 0.18, tex=tiles, scale=1.6)
    white = mat("Preview_Kachel_Weiss", (1, 1, 1), 0.18, tex=tiles, scale=1.6)
    plaster = mat("Preview_Putz", (0.8, 0.8, 0.76), 0.92, tex=os.path.join(ROOM_TEX, "plaster.png"), scale=0.5)
    floor = mat("Preview_Boden", (1, 1, 1), 0.7, tex=os.path.join(ROOM_TEX, "floor.png"), scale=0.9)
    hw = ROOM_W * 0.5
    fl = ngon([gl(-hw, 0, FRONT_Z), gl(hw, 0, FRONT_Z), gl(hw, 0, BACK_Z), gl(-hw, 0, BACK_Z)])
    ob("Preview_Boden", fl, floor, col, smooth=False)
    ob("Preview_Decke", ngon([gl(-hw, CEIL, FRONT_Z), gl(hw, CEIL, FRONT_Z), gl(hw, CEIL, BACK_Z), gl(-hw, CEIL, BACK_Z)], flip=True), plaster, col, smooth=False)
    bands = ((0.0, 1.1, green), (1.1, 1.17, m["Kachel_Dunkel"]), (1.17, 1.85, white), (1.85, 1.9, m["Kachel_Dunkel"]), (1.9, CEIL, plaster))
    xs = [-hw, -WIN_X - WIN_W * 0.5, -WIN_X + WIN_W * 0.5, WIN_X - WIN_W * 0.5, WIN_X + WIN_W * 0.5, hw]
    buckets = {}
    for y0, y1, material in bands:
        qs = buckets.setdefault(material.name, [material, []])[1]
        qs.append(quad(gl(-hw, y0, FRONT_Z), gl(-hw, y0, BACK_Z), gl(-hw, y1, BACK_Z), gl(-hw, y1, FRONT_Z), [(FRONT_Z, y0), (BACK_Z, y0), (BACK_Z, y1), (FRONT_Z, y1)]))
        qs.append(quad(gl(hw, y0, BACK_Z), gl(hw, y0, FRONT_Z), gl(hw, y1, FRONT_Z), gl(hw, y1, BACK_Z), [(BACK_Z, y0), (FRONT_Z, y0), (FRONT_Z, y1), (BACK_Z, y1)]))
        for k in range(5):
            spans = [(y0, y1)] if k not in (1, 3) else [(y0, min(y1, WIN_Y[0])), (max(y0, WIN_Y[1]), y1)]
            for a, b in spans:
                if b - a > 0.001:
                    qs.append(quad(gl(xs[k], a, BACK_Z), gl(xs[k + 1], a, BACK_Z), gl(xs[k + 1], b, BACK_Z), gl(xs[k], b, BACK_Z),
                                   [(xs[k], a), (xs[k + 1], a), (xs[k + 1], b), (xs[k], b)]))
    for name, (material, qs) in buckets.items():
        ob("Preview_Wand_" + name.replace("Preview_", ""), join(*qs), material, col, smooth=False)
    for i, (pos, length) in enumerate(TUBES):
        preview_light(col, "Preview_Licht_Neon_%d" % i, "POINT", (pos[0], pos[1] - 0.15, pos[2]), (0.85, 0.96, 0.93), 70.0 if i == 0 else 35.0, shadow_soft_size=0.4)
    preview_light(col, "Preview_Licht_Gegenlicht", "POINT", (0, 1.9, -1.5), (0.37, 0.62, 0.55), 30.0)
    world_color((0.008, 0.012, 0.014))


def build_all(preview=True):
    """Ganze Szene neu aufbauen (löscht alles in der aktuellen Datei)."""
    clear_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    m = M()
    col = geo.collection("Bahnhof")
    root = empty("Bahnhof", col)
    build_table(col, m, root)
    build_windows(col, m, root)
    build_benches(col, m, root)
    build_kettle(col, m, root)
    build_board(col, m, root)
    build_tubes(col, m, root)
    build_trims(col, m, root)
    build_small(col, m, root)
    build_train(geo.collection("Zug"), m)
    place(PLACES, True)
    if preview:
        _preview(geo.collection("Kulisse"), m)
    return "ok"


def export_all(out_dir=None):
    return export_files(FILES, out_dir or OUT_DIR, PLACES)
