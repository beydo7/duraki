"""Raum „U-Boot“ als Blender-Modelle.

    import sys; sys.path.insert(0, r"<Repo>/art/blender")
    import submarine; submarine.build_all(); submarine.export_all()

Design, Maße und Positionen stammen 1:1 aus scenes/match/rooms/submarine_room.gd und
gauge_lives.gd; besser wird nur die Machart. Koordinaten sind Godot-Koordinaten.

    submarine.glb  Spanten mit Nieten, Rohre mit Flanschen und Ventilrädern, Notlicht („Notlicht“),
                   Bullauge, Sonar-Konsole, Tisch, Blechbecher, Seekarte, Lampen,
                   Periskop (Knoten „Periskop“ dreht sich im Spiel)
    sea.glb        Vorlage „Fisch“ und der Wal (Knoten „Wal“)
    gauge.glb      eine Druckanzeige (Zeiger = Knoten „Zeiger“, Leuchte = „Leuchte“)

Im Code bleiben: Boden, Decke, Wandplatten, das Meer hinter dem Bullauge, Luftblasen,
Sonarstrahl und Echos, Rohre unter den Druckanzeigen, Lichter, Geräusche.
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
from room_kit import REPO  # noqa: E402

ROOM_TEX = os.path.join(REPO, "assets", "rooms", "submarine")
OUT_DIR = ROOM_TEX

# Maße wie in submarine_room.gd
ROOM_W = 4.6
BACK_Z = -2.2
CEIL = 2.75
TOP = (1.84, 1.3)
PORT = (-1.15, 1.3, BACK_Z)
PORT_R = 0.3
PERISCOPE = (1.5, 0.0, -0.95)
FRONT_Z = 3.6
GAUGE_R = 0.095

FILES = {"submarine.glb": ["UBoot"], "sea.glb": ["Meer"], "gauge.glb": ["Druckanzeige"]}
PLACES = {
    "Meer": ((PORT[0], PORT[1], BACK_Z - 1.2), 0.0, 0.5),
    "Druckanzeige": ((1.55, 1.0, BACK_Z), 0.0, 1.0),
}
PIPE_COLORS = ((0.55, 0.12, 0.1), (0.75, 0.6, 0.2), (0.42, 0.45, 0.44), (0.3, 0.4, 0.55))


def M():
    d = {}
    d["Spant"] = mat("Spant", (0.2, 0.27, 0.23), 0.5, 0.5)
    for i, name in enumerate(("Rohr_Rot", "Rohr_Gelb", "Rohr_Grau", "Rohr_Blau")):
        d[name] = mat(name, PIPE_COLORS[i], 0.5, 0.4)
    d["Ventilrad"] = mat("Ventilrad", (0.75, 0.12, 0.1), 0.5)
    d["Notlicht"] = mat("Notlicht", (1.0, 0.1, 0.06), 0.3, emission=(1.0, 0.1, 0.06), energy=2.0)
    d["Gitter"] = mat("Gitter", (0.15, 0.15, 0.15), 0.5, 0.6)
    d["Messing"] = mat("Messing", (0.8, 0.6, 0.3), 0.28, 1.0)
    d["Bullaugenrohr"] = mat("Bullaugenrohr", (0.2, 0.26, 0.24), 0.5, 0.5)
    d["Bullaugenglas"] = mat("Bullaugenglas", (0.6, 0.85, 0.9), 0.05, alpha=0.12)
    d["Konsole"] = mat("Konsole", (0.32, 0.36, 0.34), 0.45, 0.6)
    d["Konsole_Dunkel"] = mat("Konsole_Dunkel", (0.12, 0.12, 0.12), 0.4, 0.5)
    d["Sonarschirm"] = mat("Sonarschirm", (0.02, 0.25, 0.08), 0.3, emission=(0.02, 0.25, 0.08), energy=0.8)
    d["Sonargitter"] = mat("Sonargitter", (0.2, 0.9, 0.35), 0.3, emission=(0.2, 0.9, 0.35), energy=1.2)
    for k, c in enumerate(((1, 0.2, 0.1), (1, 0.8, 0.2), (0.3, 1, 0.4), (0.3, 1, 0.4))):
        d["Sonarknopf_%d" % k] = mat("Sonarknopf_%d" % k, c, 0.3, emission=c, energy=1.5)
    d["Linoleum"] = mat("Linoleum", (0.18, 0.22, 0.2), 0.75)
    d["Tischstahl"] = mat("Tischstahl", (0.45, 0.48, 0.47), 0.35, 0.8)
    d["Blechbecher"] = mat("Blechbecher", (0.62, 0.64, 0.62), 0.35, 0.8)
    d["Seekarte"] = mat("Seekarte", (0.82, 0.8, 0.68), 0.95)
    d["Tinte"] = mat("Tinte", (0.3, 0.4, 0.55), 0.9)
    d["Periskop_Lack"] = mat("Periskop_Lack", (0.36, 0.42, 0.38), 0.45, 0.35)
    d["Periskop_Dunkel"] = mat("Periskop_Dunkel", (0.22, 0.26, 0.23), 0.5, 0.35)
    d["Okular"] = mat("Okular", (0.05, 0.05, 0.05), 0.4)
    d["Lampenglas"] = mat("Lampenglas", (1.0, 0.85, 0.6), 0.3, emission=(1.0, 0.85, 0.6), energy=3.0)
    d["Fisch"] = mat("Fisch", (0.55, 0.72, 0.75), 0.5, emission=(0.55, 0.72, 0.75), energy=0.5)
    d["Wal_Haut"] = mat("Wal_Haut", (0.16, 0.22, 0.3), 0.6, emission=(0.16, 0.22, 0.3), energy=0.6)
    d["Wal_Bauch"] = mat("Wal_Bauch", (0.5, 0.56, 0.6), 0.6, emission=(0.5, 0.56, 0.6), energy=0.5)
    d["Wal_Auge"] = mat("Wal_Auge", (0.02, 0.02, 0.02), 0.2)
    d["Wal_Maul"] = mat("Wal_Maul", (0.05, 0.06, 0.08), 0.6)
    # Druckanzeige
    d["Anzeige_Messing"] = mat("Anzeige_Messing", (0.78, 0.6, 0.3), 0.3, 1.0)
    d["Zifferblatt"] = mat("Zifferblatt", (1, 1, 1), 0.5, tex=os.path.join(ROOM_TEX, "gauge.png"))
    d["Zeiger"] = mat("Zeiger", (0.75, 0.1, 0.08), 0.4)
    d["Leuchte"] = mat("Leuchte", (0.2, 1.0, 0.35), 0.3, emission=(0.2, 1.0, 0.35), energy=2.5)
    return d


def aim(bm, direction, at=(0, 0, 0)):
    """Dreht ein um Blender-Z gebautes Teil so, dass seine Achse nach `direction` zeigt, und setzt es nach `at`."""
    q = Z.rotation_difference(Vector(direction).normalized())
    return geo.transform(bm, Matrix.Translation(Vector(at)) @ q.to_matrix().to_4x4())


def rivet(r=0.012, seg=7):
    return lathe([(r, 0.0), (r * 0.86, r * 0.42), (r * 0.5, r * 0.68), (0.0, r * 0.76)], seg, 0.05)


def bolt(r=0.012, h=0.008):
    """Sechskantkopf."""
    return lathe([(0.0, 0.0), (r, 0.0), (r, h * 0.8), (r * 0.8, h), (0.0, h)], 6, 0.05)


def ring_at(center, axis, major, minor, seg=32, sides=8):
    """Runder Ring (Torus) um `axis` mit Mittelpunkt `center` (Blender-Koordinaten)."""
    pts = [Vector((math.cos(TAU * i / seg) * major, math.sin(TAU * i / seg) * major, 0.0)) for i in range(seg)]
    return aim(pipe(pts, minor, sides, closed=True), axis, center)


# =====================================================================================
#  Spanten, Rohre, Notlicht
# =====================================================================================

IBEAM = [(0.0, -0.08), (0.012, -0.08), (0.012, -0.012), (0.108, -0.012), (0.108, -0.05), (0.12, -0.05), (0.12, 0.05),
         (0.108, 0.05), (0.108, 0.012), (0.012, 0.012), (0.012, 0.08), (0.0, 0.08), (0.0, -0.08)]


def build_ribs(col, m, root):
    hw = ROOM_W * 0.5
    r = 0.1
    beams, rivets = [], []
    for zpos in (-1.6, -0.5, 0.6, 1.7):
        path = [gl(-hw, 0, zpos), gl(-hw, CEIL - r, zpos)]
        for i in range(1, 6):
            a = PI - PI * 0.5 * i / 6
            path.append(gl(-hw + r + math.cos(a) * r, CEIL - r + math.sin(a) * r, zpos))
        path += [gl(-hw + r, CEIL, zpos), gl(hw - r, CEIL, zpos)]
        for i in range(1, 6):
            a = PI * 0.5 - PI * 0.5 * i / 6
            path.append(gl(hw - r + math.cos(a) * r, CEIL - r + math.sin(a) * r, zpos))
        path += [gl(hw, CEIL - r, zpos), gl(hw, 0, zpos)]
        beams.append(sweep(path, IBEAM, closed=False, up=FRONT))
        # Nieten auf dem inneren Gurt
        n = int((CEIL - 0.3) / 0.16)
        for s in (-1.0, 1.0):
            for k in range(n):
                rivets.append(aim(rivet(), (-s, 0, 0), gl(s * (hw - 0.12), 0.12 + k * 0.16, zpos)))
        for k in range(int((ROOM_W - 0.5) / 0.16) + 1):
            rivets.append(aim(rivet(), (0, 0, -1), gl(-hw + 0.25 + k * 0.16, CEIL - 0.12, zpos)))
    tbeam = [(o * 0.83, hh * 0.875) for o, hh in IBEAM]
    for x in (-0.45, 0.45, 2.0, -2.0):
        beams.append(sweep([gl(x, 0, BACK_Z), gl(x, CEIL, BACK_Z)], tbeam, closed=False, up=Vector((-1, 0, 0))))
        for k in range(int((CEIL - 0.3) / 0.16)):
            yy = 0.12 + k * 0.16
            if abs(x) < 1.0 or yy < CEIL - 0.75:  # oben liegen die Rohre davor
                rivets.append(aim(rivet(), FRONT, gl(x, yy, BACK_Z + 0.1)))
    ob("Spanten", join(*beams), m["Spant"], col, root, sharp=40)
    ob("Spanten_Nieten", join(*rivets), m["Spant"], col, root, shadow=False)


def _flange(r, axis, at):
    """Flanschpaar mit Schrauben um ein Rohr."""
    parts = [lathe([(r, -0.012), (r + 0.022, -0.012), (r + 0.022, -0.002), (r, -0.002)], 16, 0.1),
             lathe([(r, 0.002), (r + 0.022, 0.002), (r + 0.022, 0.012), (r, 0.012)], 16, 0.1)]
    for k in range(6):
        a = TAU * k / 6
        parts.append(move(bolt(0.006, 0.005), (math.cos(a) * (r + 0.012), math.sin(a) * (r + 0.012), 0.012)))
    return aim(join(*parts), axis, at)


def build_pipes(col, m, root):
    hw = ROOM_W * 0.5
    names = ("Rohr_Rot", "Rohr_Gelb", "Rohr_Grau", "Rohr_Blau")
    buckets = {n: [] for n in names}
    clamps = []
    for i in range(4):  # quer an der Rückwand oben
        r = 0.035 + 0.01 * (i % 2)
        yy, zz = CEIL - 0.3 - i * 0.1, BACK_Z + 0.18 + i * 0.03
        b = buckets[names[i]]
        b.append(pipe([gl(-hw, yy, zz), gl(hw, yy, zz)], r, 14, caps=False))
        for x in (-1.75 + 0.3 * i, -0.2 + 0.25 * i, 1.2 - 0.2 * i):
            b.append(_flange(r, (1, 0, 0), gl(x, yy, zz)))
        for x in (-2.0, -0.45, 0.45, 2.0):  # Rohrschellen an den Wandspanten
            clamps.append(ring_at(gl(x, yy, zz), (1, 0, 0), r + 0.005, 0.006, 16, 6))
    for s in (-1.0, 1.0):  # längs an den Seiten
        for i in range(2):
            xx, yy = s * (hw - 0.2), CEIL - 0.25 - i * 0.12
            b = buckets[names[i + 2]]
            b.append(pipe([gl(xx, yy, BACK_Z), gl(xx, yy, FRONT_Z)], 0.04, 14, caps=False))
            for zz in (-1.05, 0.05, 1.15):
                b.append(_flange(0.04, (0, 1, 0), gl(xx, yy, zz + 0.2 * i)))
            for zz in (-1.6, -0.5, 0.6, 1.7):
                clamps.append(ring_at(gl(xx, yy, zz), (0, 1, 0), 0.045, 0.006, 16, 6))
    for n in names:
        ob("Rohre_" + n[5:], join(*buckets[n]), m[n], col, root, sharp=40)
    ob("Rohrschellen", join(*clamps), m["Spant"], col, root, shadow=False)
    # Ventilräder mit Speichen, Nabe und Spindel zum Rohr
    wheels = []
    for x in (-0.9, 0.3, 1.9):
        c = gl(x, CEIL - 0.3, BACK_Z + 0.28)
        wheels.append(ring_at(c, FRONT, 0.08, 0.012, 28, 8))
        for k in range(3):
            a = PI * k / 3
            d = Vector((math.cos(a), 0, math.sin(a))) * 0.076
            wheels.append(pipe([c - d, c + d], 0.006, 6))
        wheels.append(aim(lathe([(0.0, -0.012), (0.018, -0.012), (0.02, 0.0), (0.014, 0.014), (0.0, 0.016)], 12, 0.1), FRONT, c))
        wheels.append(pipe([c, gl(x, CEIL - 0.3, BACK_Z + 0.2)], 0.008, 8))
    ob("Ventilraeder", join(*wheels), m["Ventilrad"], col, root, sharp=40)
    # rotes Notlicht im Schutzkorb an der linken Wand (Achse zeigt in den Raum)
    c = gl(-hw, 2.1, -1.2)
    glass = lathe([(0.048, 0.03), (0.058, 0.05), (0.062, 0.085), (0.058, 0.12), (0.042, 0.15), (0.02, 0.165), (0.0, 0.168)], 16, 0.2)
    ob("Notlicht", aim(glass, (1, 0, 0), c), m["Notlicht"], col, root, shadow=False)
    cage = [lathe([(0.0, 0.0), (0.085, 0.0), (0.085, 0.012), (0.07, 0.03), (0.0, 0.03)], 16, 0.2)]
    for hh in (0.06, 0.105, 0.15):
        rr = 0.074 if hh < 0.14 else 0.058
        pts = [Vector((math.cos(TAU * i / 20) * rr, math.sin(TAU * i / 20) * rr, hh)) for i in range(20)]
        cage.append(pipe(pts, 0.004, 5, closed=True))
    for k in range(6):
        a = TAU * k / 6
        d = Vector((math.cos(a), math.sin(a), 0))
        cage.append(pipe([d * 0.074 + Z * 0.03, d * 0.074 + Z * 0.105, d * 0.058 + Z * 0.15, d * 0.02 + Z * 0.185, Z * 0.19], 0.004, 5))
    ob("Notlicht_Korb", aim(join(*cage), (1, 0, 0), c), m["Gitter"], col, root, shadow=False)


# =====================================================================================
#  Bullauge, Sonar, Lampen
# =====================================================================================

def build_porthole(col, m, root):
    c = gl(*PORT)
    R = PORT_R
    frame = []
    frame.append(lathe([(R + 0.075, 0.0), (R + 0.075, 0.03), (R + 0.068, 0.04), (R + 0.03, 0.048), (R + 0.012, 0.065), (R + 0.002, 0.066),
                        (R - 0.008, 0.058), (R - 0.012, 0.03), (R - 0.012, -0.02)], 48, 0.2))
    for k in range(8):
        a = TAU * k / 8.0
        frame.append(move(bolt(0.016, 0.012), (math.cos(a) * (R + 0.05), math.sin(a) * (R + 0.05), 0.044)))
    ob("Bullauge", aim(join(*frame), FRONT, c), m["Messing"], col, root, sharp=40)
    tube = lathe([(R, -0.30), (R, 0.0)], 40, 0.5, flip=True)
    ob("Bullauge_Rohr", aim(tube, FRONT, c), m["Bullaugenrohr"], col, root, shadow=False)
    glass = lathe([(R, -0.02), (0.0, -0.02)], 40, 0.5)
    ob("Bullauge_Glas", aim(glass, FRONT, c), m["Bullaugenglas"], col, root, shadow=False)


def build_sonar(col, m, root):
    pos = (-1.65, 0.62, BACK_Z + 0.25)
    hgt = pos[1] + 0.45
    body = [box((0.55, hgt - 0.06, 0.4), (pos[0], 0.06 + (hgt - 0.06) * 0.5, pos[2])),
            box((0.58, 0.06, 0.43), (pos[0], 0.03, pos[2])),
            box((0.57, 0.02, 0.42), (pos[0], hgt - 0.01, pos[2]))]
    ob("Sonar_Gehaeuse", join(*body), m["Konsole"], col, root, bevel=0.008, seg=2)
    sc = gl(pos[0], pos[1] + 0.22, pos[2] + 0.2)  # Vorderseite des Gehäuses
    steel = [aim(lathe([(0.205, 0.0), (0.225, 0.0), (0.225, 0.012), (0.212, 0.02), (0.205, 0.02)], 40, 0.2), FRONT, sc)]
    for k in range(8):
        a = TAU * (k + 0.5) / 8
        steel.append(aim(bolt(0.008, 0.006), FRONT, sc + Vector((math.cos(a) * 0.215, -0.02, math.sin(a) * 0.215))))
    # Seitengriffe und Typenschild
    for s in (-1.0, 1.0):
        x = pos[0] + s * 0.2
        steel.append(pipe([gl(x, 0.34, pos[2] + 0.2), gl(x, 0.34, pos[2] + 0.235), gl(x, 0.24, pos[2] + 0.235), gl(x, 0.24, pos[2] + 0.2)], 0.007, 6))
    ob("Sonar_Beschlaege", join(*steel), m["Konsole"], col, root, sharp=40)
    dark = [aim(lathe([(0.0, 0.0), (0.2, 0.0), (0.2, 0.03), (0.192, 0.04), (0.176, 0.04), (0.17, 0.034), (0.17, 0.028)], 40, 0.2), FRONT, sc)]
    dark.append(box((0.42, 0.07, 0.006), (pos[0], pos[1] - 0.12, pos[2] + 0.203)))
    ob("Sonar_Blende", join(*dark), m["Konsole_Dunkel"], col, root, sharp=40, shadow=False)
    screen = lathe([(0.17, 0.028), (0.12, 0.033), (0.0, 0.035)], 40, 0.2)
    ob("Sonar_Schirm", aim(screen, FRONT, sc), m["Sonarschirm"], col, root, shadow=False)
    grid = []
    for rr in (0.06, 0.12):
        grid.append(ring_at(sc + FRONT * 0.036, FRONT, rr, 0.002, 40, 4))
    for a in (0.0, PI * 0.5):
        d = Vector((math.cos(a), 0, math.sin(a))) * 0.165
        grid.append(pipe([sc + FRONT * 0.0358 - d, sc + FRONT * 0.0358 + d], 0.0012, 4))
    ob("Sonar_Gitter", join(*grid), m["Sonargitter"], col, root, shadow=False)
    collars = []
    for k in range(4):
        c = gl(pos[0] - 0.15 + k * 0.1, pos[1] - 0.12, pos[2] + 0.206)
        collars.append(aim(lathe([(0.0, 0.0), (0.024, 0.0), (0.024, 0.005), (0.019, 0.008), (0.0, 0.008)], 14, 0.1), FRONT, c))
        knob = lathe([(0.0, 0.008), (0.017, 0.008), (0.017, 0.016), (0.012, 0.021), (0.0, 0.022)], 14, 0.1)
        ob("Sonar_Knopf_%d" % k, aim(knob, FRONT, c), m["Sonarknopf_%d" % k], col, root, shadow=False)
    ob("Sonar_Knopfringe", join(*collars), m["Konsole"], col, root, shadow=False)


def _cage_lamp(c, axis):
    """Schutzkorblampe: Sockel, Glas, Korb. Achse zeigt vom Sockel weg."""
    base = [lathe([(0.0, 0.0), (0.06, 0.0), (0.06, 0.02), (0.05, 0.05), (0.05, 0.065), (0.0, 0.065)], 16, 0.2)]
    for hh in (0.085, 0.125, 0.165):
        rr = 0.08 if hh < 0.16 else 0.06
        pts = [Vector((math.cos(TAU * i / 20) * rr, math.sin(TAU * i / 20) * rr, hh)) for i in range(20)]
        base.append(pipe(pts, 0.004, 5, closed=True))
    for k in range(6):
        a = TAU * k / 6
        d = Vector((math.cos(a), math.sin(a), 0))
        base.append(pipe([d * 0.055 + Z * 0.06, d * 0.08 + Z * 0.085, d * 0.08 + Z * 0.125, d * 0.06 + Z * 0.165, d * 0.02 + Z * 0.2, Z * 0.205], 0.004, 5))
    glass = lathe([(0.045, 0.065), (0.064, 0.09), (0.07, 0.125), (0.064, 0.16), (0.04, 0.185), (0.0, 0.192)], 16, 0.2)
    return aim(join(*base), axis, c), aim(glass, axis, c)


def build_lamps(col, m, root):
    cages, glasses = [], []
    for x in (-1.1, 1.1):  # Glas wie bisher bei CEIL - 0,28
        a, b = _cage_lamp(gl(x, CEIL - 0.155, -0.4), (0, 0, -1))
        cages.append(a)
        glasses.append(b)
        cages.append(pipe([gl(x, CEIL, -0.4), gl(x, CEIL - 0.155, -0.4)], 0.012, 8, caps=False))  # Kabelrohr zur Decke
        cages.append(move(lathe([(0.0, -0.01), (0.035, -0.01), (0.04, 0.0), (0.0, 0.0)], 12, 0.1), gl(x, CEIL, -0.4)))
    # kleine Wandlampe über den Druckanzeigen: Sockel, Schirmblech, längliches Glas
    wp = (1.55, 1.42, BACK_Z + 0.07)
    cages.append(box((0.14, 0.014, 0.1), (wp[0], wp[1] + 0.04, wp[2] - 0.01)))
    cages.append(box((0.12, 0.07, 0.02), (wp[0], wp[1], BACK_Z + 0.01)))
    for s in (-1.0, 1.0):
        cages.append(pipe([gl(wp[0] + s * 0.05, wp[1] - 0.03, BACK_Z + 0.02), gl(wp[0] + s * 0.05, wp[1] - 0.036, wp[2] + 0.04),
                           gl(wp[0] + s * 0.05, wp[1] + 0.03, wp[2] + 0.04)], 0.003, 5))
    glasses.append(geo.ellipsoid(Vector((0.049, 0.028, 0.028)), gl(*wp), 16, 10))
    ob("Lampen_Korb", join(*cages), m["Gitter"], col, root, sharp=40, shadow=False)
    ob("Lampen_Glas", join(*glasses), m["Lampenglas"], col, root, shadow=False)


# =====================================================================================
#  Tisch und Deko
# =====================================================================================

def rounded_rect(hx, hz, r, seg=6):
    pts = []
    for cx, cy, a0 in ((hx - r, -hz + r, -90), (hx - r, hz - r, 0), (-hx + r, hz - r, 90), (-hx + r, -hz + r, 180)):
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append(Vector((cx + r * math.cos(a), cy + r * math.sin(a), 0.0)))
    return pts


def build_table(col, m, root):
    y = TABLE_Y
    hx, hz = TOP[0] * 0.5, TOP[1] * 0.5
    path = [p + Z * y for p in rounded_rect(hx, hz, 0.02)]
    ob("Tischplatte", ngon(path), m["Linoleum"], col, root, smooth=False)
    steel = []
    edge = [(-0.03, -0.05), (0.02, -0.05), (0.025, -0.045), (0.025, -0.005), (0.021, -0.0005), (0.003, 0.0), (0.0, 0.0)]
    steel.append(sweep(path, edge))
    steel.append(ngon([p + Z * (y - 0.05) for p in rounded_rect(hx - 0.03, hz - 0.03, 0.02)], flip=True))
    for sx in (-1.0, 1.0):  # am Boden verschraubte Beine: Rohr, Kragen, Fußflansch mit Schrauben, Kopfplatte
        for sz in (-1.0, 1.0):
            c = gl(sx * (hx - 0.12), 0, sz * (hz - 0.12))
            leg = [(0.0, 0.0), (0.07, 0.0), (0.07, 0.012), (0.042, 0.016), (0.036, 0.03), (0.03, 0.04), (0.03, y - 0.1),
                   (0.036, y - 0.09), (0.036, y - 0.07), (0.055, y - 0.062), (0.055, y - 0.05), (0.0, y - 0.05)]
            steel.append(move(lathe(leg, 20, 0.5), c))
            for k in range(4):
                a = TAU * (k + 0.5) / 4
                steel.append(move(bolt(0.008, 0.006), c + Vector((math.cos(a) * 0.055, math.sin(a) * 0.055, 0.012))))
    ob("Tischgestell", join(*steel), m["Tischstahl"], col, root, sharp=40)
    # Blechbecher mit Wandstärke, Rollrand und Henkel
    c = gl(0.9, y, -0.22)
    mug = [(0.0, 0.0), (0.031, 0.0), (0.033, 0.002), (0.0355, 0.078), (0.037, 0.08), (0.0355, 0.082), (0.0335, 0.08),
           (0.031, 0.004), (0.0, 0.004)]
    parts = [move(lathe(mug, 24, 0.1), c)]
    handle = [c + Vector((0.034, 0, 0.066)), c + Vector((0.05, 0, 0.068)), c + Vector((0.06, 0, 0.055)), c + Vector((0.06, 0, 0.03)),
              c + Vector((0.05, 0, 0.018)), c + Vector((0.033, 0, 0.02))]
    parts.append(pipe(handle, 0.004, 6))
    ob("Blechbecher", join(*parts), m["Blechbecher"], col, root, sharp=40)
    # Seekarte: Blatt mit leicht aufgerollter Ecke, Gradnetz aus dünnen Linien
    T = Matrix.Translation(gl(0.85, y, 0.12)) @ Matrix.Rotation(0.3, 4, "Z")
    sheet = bmesh.new()
    uv = uv_layer(sheet)
    nx, ny = 12, 9
    grid = []
    for j in range(ny + 1):
        row = []
        for i in range(nx + 1):
            px, py = -0.15 + 0.3 * i / nx, -0.11 + 0.22 * j / ny
            curl = max(0.0, (px - 0.07) / 0.08) * max(0.0, (py - 0.03) / 0.08)
            row.append(sheet.verts.new((px - curl * 0.008, py - curl * 0.008, 0.0012 + curl * curl * 0.02)))
        grid.append(row)
    for j in range(ny):
        for i in range(nx):
            f = sheet.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            for loop in f.loops:
                loop[uv].uv = (loop.vert.co.x / 0.3 + 0.5, loop.vert.co.y / 0.22 + 0.5)
    ob("Seekarte", geo.transform(sheet, T), m["Seekarte"], col, root, shadow=False)
    ink = []
    for k in range(4):
        ink.append(box((0.26, 0.0006, 0.002), (0, 0.0018, -0.08 + k * 0.05)))
        ink.append(box((0.002, 0.0006, 0.19), (-0.125 + k * 0.06, 0.0018, 0)))
    ob("Seekarte_Linien", geo.transform(join(*ink), T), m["Tinte"], col, root, smooth=False, shadow=False)


# =====================================================================================
#  Periskop (dreht sich im Spiel um die Hochachse)
# =====================================================================================

def build_periscope(col, m, root):
    low = 1.25
    node = empty("Periskop", col, PERISCOPE, parent=root, size=0.2)
    tube = [(0.0, low - 0.09), (0.05, low - 0.09), (0.06, low - 0.07), (0.06, CEIL)]
    paint = [lathe(tube, 24, 0.5)]
    paint.append(box((0.16, 0.16, 0.2), (0, low, 0.04)))
    for s in (-1.0, 1.0):  # Griffarme mit Gelenk
        paint.append(pipe([gl(s * 0.08, low - 0.02, 0.04), gl(s * 0.2, low - 0.02, 0.04)], 0.018, 10))
        paint.append(aim(lathe([(0.0, 0.0), (0.03, 0.0), (0.03, 0.012), (0.0, 0.012)], 12, 0.1), (s, 0, 0), gl(s * 0.08, low - 0.02, 0.04)))
    ob("Periskop_Rohr", join(*paint), m["Periskop_Lack"], col, node, sharp=40, bevel=0.006, seg=2)
    dark = []
    for k in range(4):  # Ringe ums Rohr
        hh = low + 0.25 + k * 0.32
        dark.append(lathe([(0.06, hh - 0.014), (0.067, hh - 0.014), (0.069, hh - 0.008), (0.069, hh + 0.008), (0.067, hh + 0.014), (0.06, hh + 0.014)], 24, 0.2))
    for k in range(9):  # Nietenreihe vorne
        dark.append(aim(rivet(0.009), FRONT, gl(0, low + 0.15 + k * 0.13, 0.059)))
    for s in (-1.0, 1.0):  # geriffelte Griffe
        grip = [(0.0, 0.0), (0.022, 0.0), (0.025, 0.004)]
        for k in range(5):
            grip += [(0.025, 0.008 + k * 0.012), (0.022, 0.011 + k * 0.012), (0.025, 0.014 + k * 0.012)]
        grip += [(0.025, 0.068), (0.02, 0.072), (0.0, 0.072)]
        dark.append(aim(lathe(grip, 12, 0.1), (s, 0, 0), gl(s * 0.195, low - 0.02, 0.04)))
    ob("Periskop_Ringe", join(*dark), m["Periskop_Dunkel"], col, node, sharp=40)
    # Okular: Gummimuschel vorn am Kasten
    cup = lathe([(0.03, 0.0), (0.05, 0.0), (0.052, 0.012), (0.046, 0.03), (0.04, 0.034), (0.034, 0.028), (0.03, 0.01), (0.03, 0.0)], 20, 0.1)
    cup = scale(cup, (1.25, 0.72, 1.0))
    ob("Periskop_Okular", aim(cup, FRONT, gl(0, low + 0.01, 0.14)), m["Okular"], col, node, shadow=False)
    # feste Manschette an der Decke (dreht sich nicht)
    collar = [lathe([(0.062, CEIL - 0.08), (0.1, CEIL - 0.08), (0.104, CEIL - 0.07), (0.104, CEIL - 0.02), (0.13, CEIL - 0.012), (0.13, CEIL), (0.062, CEIL)], 28, 0.2)]
    for k in range(6):
        a = TAU * k / 6
        collar.append(aim(bolt(0.009, 0.007), (0, 0, -1), Vector((math.cos(a) * 0.117, math.sin(a) * 0.117, CEIL - 0.012))))
    ob("Periskop_Manschette", move(join(*collar), gl(PERISCOPE[0], 0, PERISCOPE[2])), m["Periskop_Dunkel"], col, root, sharp=40)


# =====================================================================================
#  Fisch-Vorlage und Wal (schwimmen im Spiel am Bullauge vorbei)
# =====================================================================================

def _spindle(profile, seg=14):
    """Drehkörper um die X-Achse: profile = [(x, radius), ...] von hinten nach vorn."""
    bm = lathe([(max(rr, 0.0), xx) for xx, rr in profile], seg, 0.2)
    return rot(bm, PI * 0.5, "Y")


def build_sea(col, m):
    root = empty("Meer", col, size=0.3)
    # Fisch, Maße wie bisher (8 cm lang, schmal), schwimmt nach +X
    body = scale(_spindle([(-0.075, 0.0), (-0.07, 0.008), (-0.045, 0.017), (0.0, 0.03), (0.04, 0.028), (0.068, 0.016), (0.08, 0.0)], 12), (1.0, 0.6, 1.0))
    fins = bmesh.new()
    tail = [(-0.068, 0.0), (-0.115, 0.045), (-0.098, 0.0), (-0.115, -0.045)]
    dorsal = [(-0.02, 0.028), (0.0, 0.05), (0.03, 0.026)]
    belly = [(-0.01, -0.028), (0.005, -0.045), (0.025, -0.026)]
    for outline in (tail, dorsal, belly):
        for off, rev in ((0.0008, False), (-0.0008, True)):
            vs = [fins.verts.new((px, off, pz)) for px, pz in outline]
            if rev:
                vs.reverse()
            fins.faces.new(vs)
    geo.box_uv(fins, 0.1)
    fish = empty("Fisch", col, parent=root, size=0.05)
    ob("Fisch_Koerper", join(body, fins), m["Fisch"], col, fish, shadow=False)

    # Wal: Körper aus einem Stück (stumpfer Kopf), Bauch heller, Flossen, Auge, Maul
    whale = empty("Wal", col, (-0.6, 0.0, 0.0), parent=root, size=0.5)
    prof = [(-1.95, 0.0), (-1.9, 0.07), (-1.6, 0.14), (-1.2, 0.26), (-0.7, 0.4), (-0.2, 0.48), (0.4, 0.5), (0.9, 0.48),
            (1.3, 0.44), (1.5, 0.38), (1.6, 0.26), (1.64, 0.0)]
    wb = scale(_spindle(prof, 28), (1.0, 0.92, 1.0))
    wb.normal_update()
    skin, belly_bm = bmesh.new(), bmesh.new()
    me = bpy.data.meshes.new("_tmp")
    wb.to_mesh(me)
    for target, keep_belly in ((skin, False), (belly_bm, True)):
        target.from_mesh(me)
        target.normal_update()
        drop = [f for f in target.faces if (f.normal.z < -0.45) != keep_belly]
        bmesh.ops.delete(target, geom=drop, context="FACES")
    wb.free()
    bpy.data.meshes.remove(me)
    parts = [skin]
    # Schwanzflosse (zwei Flunken, wie bisher von der Seite zu sehen), Brustflossen, Rückenflosse
    for s in (-1.0, 1.0):
        lobe = geo.ellipsoid(Vector((0.17, 0.05, 0.42)), Vector((0, 0, 0)), 14, 10)
        rot(lobe, s * 0.55, "Y")
        parts.append(move(lobe, gl(-2.02, 0.06 + s * 0.24, 0)))
        fin = geo.ellipsoid(Vector((0.48, 0.035, 0.1)), Vector((0, 0, 0)), 14, 8)
        rot(fin, -0.55, "Y")
        rot(fin, s * 0.35, "Z")
        parts.append(move(fin, gl(0.45, -0.34, s * 0.42)))
    dorsal = rot(geo.ellipsoid(Vector((0.22, 0.04, 0.16)), Vector((0, 0, 0)), 12, 8), -0.5, "Y")
    parts.append(move(dorsal, gl(-0.75, 0.44, 0)))
    ob("Wal_Haut", join(*parts), m["Wal_Haut"], col, whale, sharp=None, shadow=False)
    ob("Wal_Bauch", belly_bm, m["Wal_Bauch"], col, whale, sharp=None, shadow=False)
    eyes = [geo.ellipsoid(Vector((0.04, 0.02, 0.04)), gl(1.15, 0.1, s * 0.4), 10, 8) for s in (-1.0, 1.0)]
    ob("Wal_Augen", join(*eyes), m["Wal_Auge"], col, whale, shadow=False)
    mouth = []
    for s in (-1.0, 1.0):
        pts = [gl(1.6, -0.1, s * 0.2), gl(1.45, -0.13, s * 0.36), gl(1.15, -0.15, s * 0.44), gl(0.8, -0.13, s * 0.46)]
        mouth.append(pipe(pts, 0.012, 5))
    ob("Wal_Maul", join(*mouth), m["Wal_Maul"], col, whale, shadow=False)
    return root


# =====================================================================================
#  Druckanzeige (das Spiel stellt je Leben eine an die Wand)
# =====================================================================================

def build_gauge(col, m):
    R = GAUGE_R
    root = empty("Druckanzeige", col, size=0.1)
    # Gehäuse an der Wand (Achse zeigt in den Raum), Lünette mit Schrauben
    brass = [lathe([(0.0, 0.0), (R + 0.024, 0.0), (R + 0.024, 0.006), (R + 0.018, 0.01), (R + 0.018, 0.036), (R + 0.022, 0.04),
                    (R + 0.022, 0.046), (R + 0.016, 0.052), (R + 0.006, 0.052), (R + 0.002, 0.046), (R + 0.002, 0.0405)], 40, 0.2)]
    for k in range(6):
        a = TAU * (k + 0.5) / 6
        brass.append(move(bolt(0.005, 0.004), (math.cos(a) * (R + 0.014), math.sin(a) * (R + 0.014), 0.051)))
    ob("Anzeige_Gehaeuse", aim(join(*brass), FRONT), m["Anzeige_Messing"], col, root, sharp=40)
    face = quad((-R, -0.041, -R), (R, -0.041, -R), (R, -0.041, R), (-R, -0.041, R), [(0, 0), (1, 0), (1, 1), (0, 1)])
    ob("Anzeige_Zifferblatt", face, m["Zifferblatt"], col, root, smooth=False, shadow=False)
    needle = empty("Zeiger", col, (0, 0, 0.046), parent=root, size=0.03)
    arrow = bmesh.new()
    outline = [(-R * 0.16, -0.004), (R * 0.1, -0.0045), (R * 0.66, -0.002), (R * 0.75, 0.0), (R * 0.66, 0.002), (R * 0.1, 0.0045), (-R * 0.16, 0.004)]
    arrow.faces.new([arrow.verts.new((px, -0.0015, pz)) for px, pz in outline])
    geo.box_uv(arrow, 0.1)
    ob("Zeiger_Nadel", arrow, m["Zeiger"], col, needle, smooth=False, shadow=False)
    hub = lathe([(0.0, 0.0), (0.011, 0.0), (0.011, 0.004), (0.007, 0.007), (0.0, 0.0075)], 14, 0.05)
    ob("Zeiger_Nabe", aim(hub, FRONT), m["Anzeige_Messing"], col, needle, shadow=False)
    # Kontrollleuchte unter der Anzeige: Fassung und gewölbtes Glas
    lp = gl(0, -R - 0.12, 0.05)
    bez = lathe([(0.0, -0.01), (0.03, -0.01), (0.032, -0.004), (0.032, 0.008), (0.027, 0.012), (0.023, 0.012), (0.023, 0.006)], 20, 0.1)
    ob("Leuchte_Fassung", aim(bez, FRONT, lp), m["Anzeige_Messing"], col, root, shadow=False)
    lens = lathe([(0.023, 0.006), (0.021, 0.014), (0.014, 0.021), (0.0, 0.0245)], 16, 0.1)
    ob("Leuchte", aim(lens, FRONT, lp), m["Leuchte"], col, root, shadow=False)
    # Flansch am Boden kommt wie das Rohr aus dem Code (Länge hängt von der Wandhöhe ab)
    return root


# =====================================================================================
#  Kulisse (nur Blender) und Aufbau
# =====================================================================================

def _preview(col, m):
    hull = mat("Preview_Rumpf", (1, 1, 1), 0.55, 0.45, tex=os.path.join(ROOM_TEX, "hull.png"), scale=0.9)
    floor = mat("Preview_Boden", (1, 1, 1), 0.45, 0.6, tex=os.path.join(ROOM_TEX, "floor.png"), scale=1.6)
    sea = mat("Preview_Meer", (0.05, 0.24, 0.36), 0.9, emission=(0.05, 0.24, 0.36), energy=1.0)
    hw = ROOM_W * 0.5
    ob("Preview_Boden", ngon([gl(-hw, 0, FRONT_Z), gl(hw, 0, FRONT_Z), gl(hw, 0, BACK_Z), gl(-hw, 0, BACK_Z)]), floor, col, smooth=False)
    walls = [ngon([gl(-hw, CEIL, FRONT_Z), gl(hw, CEIL, FRONT_Z), gl(hw, CEIL, BACK_Z), gl(-hw, CEIL, BACK_Z)], flip=True),
             quad(gl(-hw, 0, FRONT_Z), gl(-hw, 0, BACK_Z), gl(-hw, CEIL, BACK_Z), gl(-hw, CEIL, FRONT_Z), [(FRONT_Z, 0), (BACK_Z, 0), (BACK_Z, CEIL), (FRONT_Z, CEIL)]),
             quad(gl(hw, 0, BACK_Z), gl(hw, 0, FRONT_Z), gl(hw, CEIL, FRONT_Z), gl(hw, CEIL, BACK_Z), [(BACK_Z, 0), (FRONT_Z, 0), (FRONT_Z, CEIL), (BACK_Z, CEIL)])]
    # Rückwand mit rundem Loch fürs Bullauge
    back = bmesh.new()
    uv = uv_layer(back)
    n = 48
    inner = [back.verts.new(gl(PORT[0] + math.cos(TAU * i / n) * PORT_R, PORT[1] + math.sin(TAU * i / n) * PORT_R, BACK_Z)) for i in range(n)]
    def edge_point(a):
        dx, dy = math.cos(a), math.sin(a)
        t = min((hw - PORT[0]) / dx if dx > 1e-9 else ((-hw - PORT[0]) / dx if dx < -1e-9 else 1e9),
                (CEIL - PORT[1]) / dy if dy > 1e-9 else ((0 - PORT[1]) / dy if dy < -1e-9 else 1e9))
        return gl(PORT[0] + dx * t, PORT[1] + dy * t, BACK_Z)
    angles = [TAU * i / n for i in range(n)]
    for cx, cy in ((-hw, 0), (hw, 0), (hw, CEIL), (-hw, CEIL)):  # Strahl zur Wandecke, damit keine Lücke bleibt
        ca = math.atan2(cy - PORT[1], cx - PORT[0]) % TAU
        k = min(range(n), key=lambda i: abs((angles[i] - ca + PI) % TAU - PI))
        angles[k] = ca
    outer = [back.verts.new(edge_point(a)) for a in angles]
    for i in range(n):
        j = (i + 1) % n
        f = back.faces.new((inner[i], outer[i], outer[j], inner[j]))
        for loop in f.loops:
            loop[uv].uv = (loop.vert.co.x, loop.vert.co.z)
    walls.append(face_room(back, FRONT))
    ob("Preview_Waende", join(*walls), hull, col, smooth=False)
    ob("Preview_Meer", quad(gl(PORT[0] - 4, PORT[1] - 2.2, BACK_Z - 2.5), gl(PORT[0] + 4, PORT[1] - 2.2, BACK_Z - 2.5),
                            gl(PORT[0] + 4, PORT[1] + 2.8, BACK_Z - 2.5), gl(PORT[0] - 4, PORT[1] + 2.8, BACK_Z - 2.5)), sea, col, smooth=False)
    for x in (-1.1, 1.1):
        preview_light(col, "Preview_Licht_Decke", "POINT", (x, CEIL - 0.35, -0.4), (1.0, 0.84, 0.6), 45.0, shadow_soft_size=0.1)
    preview_light(col, "Preview_Licht_Gegenlicht", "POINT", (0, 1.9, -1.6), (0.37, 0.64, 0.63), 25.0)
    preview_light(col, "Preview_Licht_Notlicht", "POINT", (-hw + 0.35, 2.1, -1.2), (1.0, 0.15, 0.1), 15.0)
    world_color((0.004, 0.01, 0.012))


def build_all(preview=True):
    """Ganze Szene neu aufbauen (löscht alles in der aktuellen Datei)."""
    clear_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    m = M()
    col = geo.collection("UBoot")
    root = empty("UBoot", col)
    build_ribs(col, m, root)
    build_pipes(col, m, root)
    build_porthole(col, m, root)
    build_sonar(col, m, root)
    build_lamps(col, m, root)
    build_table(col, m, root)
    build_periscope(col, m, root)
    build_sea(geo.collection("Meer"), m)
    build_gauge(geo.collection("Druckanzeige"), m)
    place(PLACES, True)
    if preview:
        _preview(geo.collection("Kulisse"), m)
    return "ok"


def export_all(out_dir=None):
    return export_files(FILES, out_dir or OUT_DIR, PLACES)
