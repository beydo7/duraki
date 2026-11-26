"""Deck-Belohnungen, Items und Rauchzeug als Blender-Modelle (Vorlagen, die der Code aufstellt).

    import sys; sys.path.insert(0, r"<Repo>/art/blender")
    import cosmetics; cosmetics.build_all(); cosmetics.export_all()

Design und Maße wie in scenes/match/table_skin.gd, ashtray.gd, cigarette_pack.gd,
table_world.gd (mirror_flight) und opponent_figure.gd (_make_shot). Alle Teile stehen mit
ihrem Ursprung so, wie der Code sie setzt (Standfläche bzw. Drehpunkt).

    assets/cosmetics/cosmetics.glb  Totenkopf, Doppeladler, Kraehe (mit „Kraehe_Kopf“ und
                                    „Kraehe_Schnabel“), Gloeckchen, Seerosenblatt, Seerose,
                                    Hexenkerze, Skinflamme, Faberge, Tischrahmen_Ecke,
                                    Tischrahmen_Leiste
    assets/models/items.glb         Spiegel (Item), Schnapsglas (Runde Schnaps)
    assets/models/smoking.glb       Aschenbecher des Spielers, Zigarettenschachtel mit Deckel,
                                    Zigarette für die Schachtel
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

COSMETICS_DIR = os.path.join(REPO, "assets", "cosmetics")
FILES_COSMETICS = {"cosmetics.glb": ["Belohnungen"]}
FILES_MODELS = {"items.glb": ["Items"], "smoking.glb": ["Rauchzeug"]}
GOLD = (0.95, 0.74, 0.32)
# Schachtel und Zigarette wie in cigarette_pack.gd
PACK_W, PACK_H, PACK_D, LID_H = 0.056, 0.086, 0.023, 0.026
CIG_R, CIG_LEN = 0.0042, 0.084


def M():
    d = {}
    d["Knochen"] = mat("Knochen", (0.9, 0.86, 0.74), 0.6)
    d["Knochen_Dunkel"] = mat("Knochen_Dunkel", (0.05, 0.04, 0.04), 0.9)
    d["Zahn"] = mat("Zahn", (0.95, 0.93, 0.85), 0.5)
    d["Skin_Gold"] = mat("Skin_Gold", GOLD, 0.25, 1.0)
    d["Juwel_Rot"] = mat("Juwel_Rot", (0.9, 0.1, 0.15), 0.2, emission=(0.9, 0.1, 0.15), energy=1.0)
    d["Kraehe_Federn"] = mat("Kraehe_Federn", (0.05, 0.05, 0.07), 0.35, 0.2)
    d["Kraehe_Schnabel"] = mat("Kraehe_Schnabel", (0.2, 0.2, 0.22), 0.4)
    d["Kraehe_Auge"] = mat("Kraehe_Auge", (0.9, 0.75, 0.2), 0.3, emission=(0.9, 0.75, 0.2), energy=0.8)
    d["Glocke_Band"] = mat("Glocke_Band", (0.75, 0.1, 0.1), 0.7)
    d["Glocke_Schlitz"] = mat("Glocke_Schlitz", (0.1, 0.08, 0.05), 0.6)
    d["Seerose_Blatt"] = mat("Seerose_Blatt", (0.25, 0.5, 0.2), 0.7)
    d["Seerose_Bluete"] = mat("Seerose_Bluete", (0.95, 0.65, 0.8), 0.6)
    d["Seerose_Mitte"] = mat("Seerose_Mitte", (0.95, 0.8, 0.25), 0.6)
    d["Kerzenwachs"] = mat("Kerzenwachs", (0.12, 0.3, 0.12), 0.7)
    d["Kerzenhalter"] = mat("Kerzenhalter", (0.25, 0.22, 0.2), 0.4, 0.8)
    d["Docht"] = mat("Docht", (0.05, 0.04, 0.03), 0.9)
    d["Skinflamme"] = mat("Skinflamme", (0.25, 1.0, 0.35), 0.3, emission=(0.25, 1.0, 0.35), energy=4.0)
    d["Faberge_Emaille"] = mat("Faberge_Emaille", (0.55, 0.05, 0.12), 0.15, 0.3)
    for k, c in enumerate(((0.2, 0.5, 1.0), (0.1, 0.9, 0.4), (1, 1, 1))):
        d["Faberge_Juwel_%d" % k] = mat("Faberge_Juwel_%d" % k, c, 0.2, emission=c, energy=1.2)
    d["Faberge_Kerze"] = mat("Faberge_Kerze", (0.95, 0.92, 0.85), 0.6)
    d["Tischrahmen"] = mat("Tischrahmen", (0.43, 0.25, 0.13), 0.45)
    # Items
    d["Spiegel_Rahmen"] = mat("Spiegel_Rahmen", (0.79, 0.6, 0.29), 0.35, 0.8)
    d["Spiegel_Glas"] = mat("Spiegel_Glas", (0.3, 0.36, 0.48), 0.05, 1.0, emission=(0.35, 0.4, 0.55), energy=0.25)
    d["Schnapsglas"] = mat("Schnapsglas", (0.85, 0.92, 1.0), 0.05, alpha=0.35)
    # Rauchzeug
    d["Aschenbecher_Metall"] = mat("Aschenbecher_Metall", (0.3, 0.2, 0.11), 0.38, 0.85)
    d["Aschenbecher_Rand"] = mat("Aschenbecher_Rand", (0.55, 0.4, 0.22), 0.25, 0.9)
    d["Aschenbecher_Mulde"] = mat("Aschenbecher_Mulde", (0.05, 0.045, 0.045), 0.9)
    d["Schachtel_Weiss"] = mat("Schachtel_Weiss", (0.95, 0.94, 0.9), 0.55)
    d["Schachtel_Farbe"] = mat("Schachtel_Farbe", (0.74, 0.08, 0.1), 0.45)
    d["Schachtel_Innen"] = mat("Schachtel_Innen", (0.82, 0.78, 0.68), 0.8)
    d["Schachtel_Folie"] = mat("Schachtel_Folie", (0.75, 0.74, 0.7), 0.3, 0.8)
    d["Zigarettenpapier"] = mat("Zigarettenpapier", (0.93, 0.91, 0.86), 0.75)
    d["Zigarettenfilter"] = mat("Zigarettenfilter", (0.82, 0.55, 0.28), 0.7)
    d["Tabak"] = mat("Tabak", (0.35, 0.22, 0.1), 0.95)
    return d


def aim(bm, direction, at=(0, 0, 0)):
    q = Z.rotation_difference(Vector(direction).normalized())
    return geo.transform(bm, Matrix.Translation(Vector(at)) @ q.to_matrix().to_4x4())


def ell(rx, ry, rz, x, y, z, u=14, v=10):
    """Ellipsoid, Maße und Ort in Godot-Achsen (x rechts, y hoch, z nach vorn)."""
    return geo.ellipsoid(Vector((rx, rz, ry)), gl(x, y, z), u, v)


def spindle(profile, seg=14):
    """Drehkörper um die X-Achse: profile = [(x, radius), ...] von hinten nach vorn."""
    return rot(lathe([(max(r, 0.0), x) for x, r in profile], seg, 0.1), PI * 0.5, "Y")


def blade(length, width, thick=0.0016, bend=0.0):
    """Flache Feder / Blütenblatt entlang +X ab dem Ursprung, in der XZ-Ebene gewölbt."""
    bm = bmesh.new()
    n = 6
    top, bot = [], []
    for i in range(n + 1):
        t = i / n
        w = width * 0.5 * math.sin(PI * min(t * 0.92 + 0.08, 1.0)) ** 0.7
        zz = bend * t * t * length
        top.append([bm.verts.new((t * length, -w, zz + thick)), bm.verts.new((t * length, w, zz + thick))])
        bot.append([bm.verts.new((t * length, -w, zz - thick)), bm.verts.new((t * length, w, zz - thick))])
    for i in range(n):
        bm.faces.new((top[i][0], top[i + 1][0], top[i + 1][1], top[i][1]))
        bm.faces.new((bot[i][0], bot[i][1], bot[i + 1][1], bot[i + 1][0]))
        bm.faces.new((top[i][0], bot[i][0], bot[i + 1][0], top[i + 1][0]))
        bm.faces.new((top[i][1], top[i + 1][1], bot[i + 1][1], bot[i][1]))
    bm.faces.new((top[0][0], top[0][1], bot[0][1], bot[0][0]))
    bm.faces.new((top[n][0], bot[n][0], bot[n][1], top[n][1]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    geo.box_uv(bm, 0.05)
    return bm


def flame_mesh(h, r, y0=0.0):
    return lathe([(0.0, y0), (r * 0.6, y0 + h * 0.06), (r, y0 + h * 0.26), (r * 0.92, y0 + h * 0.42), (r * 0.6, y0 + h * 0.68),
                  (r * 0.2, y0 + h * 0.9), (0.0, y0 + h)], 12, 0.02)


def wedge_cap(profile, a, toward):
    """Schnittfläche eines offenen Drehkörpers (Winkel a); zeigt in Drehrichtung `toward` (+1/-1)."""
    bm = bmesh.new()
    vs = [bm.verts.new((r * math.cos(a), r * math.sin(a), h)) for r, h in profile]
    f = bm.faces.new(vs)
    bm.normal_update()
    if f.normal.dot(Vector((-math.sin(a), math.cos(a), 0.0))) * toward < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    geo.box_uv(bm, 0.05)
    return bm


def notched_lathe(profile, seg, notches, half_w, floor, tile=0.1):
    """Drehkörper wie lathe(), aber an den Winkeln `notches` sattelt der Rand weich auf die
    Höhe `floor` ab (Kerben für die Zigarette). half_w = halbe Kerbenbreite als Winkel."""
    bm = bmesh.new()
    uv = uv_layer(bm)
    rings = []
    for s in range(seg):
        a = TAU * s / seg
        d = min(abs((a - n + PI) % TAU - PI) for n in notches)
        w = 1.0 - smooth01(min(max((d - half_w * 0.7) / (half_w * 1.5), 0.0), 1.0))
        rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), h - w * max(0.0, h - floor))) for r, h in profile])
    plen = [0.0]
    for i in range(1, len(profile)):
        plen.append(plen[-1] + math.hypot(profile[i][0] - profile[i - 1][0], profile[i][1] - profile[i - 1][1]))
    rmax = max(r for r, _ in profile)
    for s in range(seg):
        ra, rb = rings[s], rings[(s + 1) % seg]
        for i in range(len(profile) - 1):
            quad = [(ra[i], s, i), (rb[i], s + 1, i), (rb[i + 1], s + 1, i + 1), (ra[i + 1], s, i + 1)]
            f = bm.faces.new([q[0] for q in quad])
            for loop, q in zip(f.loops, quad):
                loop[uv].uv = (q[1] / seg * TAU * rmax / tile, plen[q[2]] / tile)
    bm.normal_update()
    return bm


# =====================================================================================
#  Tischecken: Totenkopf, Doppeladler
# =====================================================================================

def build_skull(col, m, root):
    bone = [ell(0.031, 0.030, 0.035, 0, 0.038, -0.002, 20, 14),                  # Hirnschädel
            ell(0.0165, 0.0095, 0.0105, 0, 0.0225, 0.0195, 14, 10),              # Oberkiefer
            ell(0.0235, 0.0165, 0.012, 0, 0.03, 0.0165, 16, 10)]                 # Gesichtsschädel (schmaler als die Stirn)
    for s in (-1.0, 1.0):
        bone.append(ell(0.0105, 0.0034, 0.005, s * 0.0125, 0.0448, 0.0238, 10, 6))  # Brauenbogen
        bone.append(ell(0.0045, 0.0042, 0.01, s * 0.0185, 0.0262, 0.0165, 10, 8))   # Jochbein
        bone.append(ell(0.0055, 0.009, 0.007, s * 0.0155, 0.0095, 0.004, 10, 8))  # Kieferast
    jaw_path = [gl(math.sin(a) * 0.0165, 0.0045, 0.012 + math.cos(a) * 0.0165) for a in [-2.0 + 4.0 * i / 16 for i in range(17)]]
    bone.append(pipe(jaw_path, 0.0042, 8))                                       # Unterkiefer als Bogen
    dark = []
    for s in (-1.0, 1.0):
        eye = ell(0.0088, 0.0084, 0.0045, 0, 0, 0, 14, 10)
        rot(eye, s * 0.18, "Y")
        dark.append(move(eye, gl(s * 0.0125, 0.0345, 0.0266)))
        dark.append(ell(0.0026, 0.0044, 0.002, s * 0.0024, 0.0235, 0.0282, 8, 6))  # Nasenöffnung
    dark.append(ell(0.0125, 0.0045, 0.006, 0, 0.012, 0.021, 10, 6))               # Mundhöhle hinter den Zähnen
    teeth = []
    for k in range(6):
        a = (k - 2.5) * 0.3
        px, pz = math.sin(a) * 0.0165, 0.012 + math.cos(a) * 0.0165
        for yy, hh in ((0.0147, 0.005), (0.0097, 0.0043)):
            t = rot(box((0.0046, hh, 0.003), (0, 0, 0)), a, "Z")
            teeth.append(move(t, gl(px, yy, pz)))
    return ob_multi("Totenkopf", [(join(*bone), m["Knochen"]), (join(*dark), m["Knochen_Dunkel"]), (join(*teeth), m["Zahn"])], col, root, sharp=60)


def build_eagle(col, m, root):
    gold = [lathe([(0.0, 0.0), (0.026, 0.0), (0.027, 0.003), (0.024, 0.006), (0.0225, 0.009), (0.023, 0.011), (0.02, 0.013), (0.0, 0.013)], 20, 0.05),
            ell(0.015, 0.025, 0.011, 0, 0.036, 0, 14, 10)]
    for s in (-1.0, 1.0):
        neck = [gl(s * 0.006, 0.052, 0), gl(s * 0.012, 0.064, 0), gl(s * 0.019, 0.073, 0), gl(s * 0.022, 0.078, 0)]
        gold.append(pipe(neck, [0.0075, 0.006, 0.0055, 0.005], 8))
        gold.append(ell(0.0095, 0.0085, 0.008, s * 0.0225, 0.079, 0, 12, 8))
        beak = lathe([(0.0, 0.0), (0.0042, 0.0), (0.0034, 0.005), (0.0016, 0.01), (0.0, 0.0125)], 8, 0.02)
        gold.append(aim(beak, (s, 0.0, -0.25), gl(s * 0.03, 0.0785, 0)))
        crown = lathe([(0.0, 0.0), (0.0048, 0.0), (0.0058, 0.006), (0.0048, 0.0065), (0.0036, 0.004), (0.0, 0.004)], 8, 0.02)
        gold.append(move(crown, gl(s * 0.0225, 0.0865, 0)))
        # Schwinge: sieben Federn im Fächer, nach oben hin länger
        for k in range(7):
            ang = -0.5 + k * 0.24
            f = blade(0.03 + 0.002 * k, 0.0085, 0.0011)
            rot(f, PI * 0.5, "X")                 # Fläche zeigt nach vorn
            rot(f, -ang if s > 0 else PI + ang, "Y")
            gold.append(move(f, gl(s * 0.011, 0.045, -0.003 - 0.0006 * k)))
    big = lathe([(0.0, 0.0), (0.0065, 0.0), (0.0085, 0.008), (0.0072, 0.0092), (0.0055, 0.006), (0.0, 0.0075)], 10, 0.02)
    gold.append(move(big, gl(0, 0.094, 0)))
    for s in (-1.0, 1.0):  # Bänder von den Kopfkronen zur großen Krone (sie schwebte vorher frei)
        gold.append(pipe([gl(s * 0.0225, 0.0915, 0), gl(s * 0.017, 0.0975, 0), gl(s * 0.009, 0.0985, 0), gl(s * 0.004, 0.096, 0)], 0.0013, 6))
    o = ob("Doppeladler", join(*gold), m["Skin_Gold"], col, root, sharp=50)
    ob("Doppeladler_Juwel", ell(0.004, 0.004, 0.004, 0, 0.106, 0, 10, 8), m["Juwel_Rot"], col, o, shadow=False)
    return o


# =====================================================================================
#  Extras: Krähe, Glöckchen, Seerosen, Hexenkerze, Fabergé-Leuchter
# =====================================================================================

def build_crow(col, m, root):
    crow = empty("Kraehe", col, parent=root, size=0.05)
    feathers = [scale(spindle([(-0.085, 0.0), (-0.07, 0.014), (-0.04, 0.032), (0.0, 0.044), (0.035, 0.04), (0.058, 0.026), (0.068, 0.0)], 16), (1.0, 0.86, 1.0))]
    geo.translate(feathers[0], gl(0, 0.07, 0))
    for s in (-1.0, 1.0):  # angelegte Flügel aus drei Federlagen
        for k, (length, width, dx) in enumerate(((0.085, 0.05, 0.03), (0.095, 0.04, 0.012), (0.105, 0.028, -0.004))):
            w = blade(length, width, 0.004, bend=-0.6)
            rot(w, PI, "Z")                       # nach hinten
            rot(w, PI * 0.5 * s, "X")             # Fläche an die Körperseite
            rot(w, -0.25, "Y")
            feathers.append(move(w, gl(dx, 0.082 - k * 0.006, s * (0.034 + k * 0.0015))))
    for k in range(5):  # Schwanz
        t = blade(0.075, 0.016, 0.002)
        rot(t, PI + (k - 2) * 0.12, "Z")
        rot(t, -0.35, "Y")
        feathers.append(move(t, gl(-0.06, 0.062, 0)))
    ob("Kraehe_Koerper", join(*feathers), m["Kraehe_Federn"], col, crow, sharp=60)
    legs = []
    for s in (-1.0, 1.0):
        legs.append(pipe([gl(0.0, 0.04, s * 0.012), gl(0.004, 0.002, s * 0.012)], 0.0026, 6))
        for a in (-0.5, 0.0, 0.5, PI):
            legs.append(pipe([gl(0.004, 0.002, s * 0.012), gl(0.004 + math.cos(a) * 0.016, 0.0012, s * 0.012 + math.sin(a) * 0.016)], 0.0016, 5))
    ob("Kraehe_Beine", join(*legs), m["Kraehe_Schnabel"], col, crow)
    head = empty("Kraehe_Kopf", col, (0.055, 0.115, 0), parent=crow, size=0.02)
    hf = [ell(0.026, 0.025, 0.024, 0, 0, 0, 16, 12), ell(0.024, 0.028, 0.024, -0.016, -0.02, 0, 12, 8)]
    ob("Kraehe_Kopf_Federn", join(*hf), m["Kraehe_Federn"], col, head)
    eyes = [ell(0.005, 0.005, 0.0035, 0.012, 0.007, s * 0.0205, 10, 8) for s in (-1.0, 1.0)]
    ob("Kraehe_Augen", join(*eyes), m["Kraehe_Auge"], col, head, shadow=False)
    upper = spindle([(0.0, 0.0105), (0.012, 0.0095), (0.026, 0.0062), (0.036, 0.0028), (0.042, 0.0)], 10)
    bmesh.ops.delete(upper, geom=[v for v in upper.verts if v.co.z < -0.0008], context="VERTS")
    ob("Kraehe_Oberschnabel", move(upper, gl(0.018, 0.0, 0)), m["Kraehe_Schnabel"], col, head, sharp=60)
    beak = empty("Kraehe_Schnabel", col, (0.02, -0.002, 0), parent=head, size=0.01)
    lower = spindle([(0.0, 0.008), (0.012, 0.0066), (0.024, 0.0038), (0.033, 0.0)], 10)
    bmesh.ops.delete(lower, geom=[v for v in lower.verts if v.co.z > 0.0008], context="VERTS")
    ob("Kraehe_Unterschnabel", lower, m["Kraehe_Schnabel"], col, beak, sharp=60)
    return crow


def build_bell(col, m, root):
    cy, r = 0.038, 0.019
    gold = [ell(r, r, r, 0, cy, 0, 20, 14),
            lathe([(r + 0.0004, cy - 0.0013), (r + 0.0013, cy - 0.0007), (r + 0.0013, cy + 0.0007), (r + 0.0004, cy + 0.0013)], 20, 0.02)]  # Naht am Äquator
    # Schlitz vorn unten (zum Spieler), endet in zwei runden Löchern
    el = -0.36
    pts = [Vector((math.cos(el) * math.sin(az), -math.cos(el) * math.cos(az), math.sin(el))) * (r + 0.0002) + Z * cy
           for az in [-0.8 + 1.6 * i / 12 for i in range(13)]]
    slit = [pipe(pts, 0.0015, 5), geo.ellipsoid(Vector((0.003, 0.003, 0.003)), pts[0], 8, 6), geo.ellipsoid(Vector((0.003, 0.003, 0.003)), pts[-1], 8, 6)]
    # Band: Stummel wie bisher, dazu eine kleine Rosette auf dem Rand
    band = [pleated_disc(0.014, 0.005, 8), lathe([(0.0, 0.003), (0.005, 0.003), (0.0046, 0.021), (0.0, 0.021)], 8, 0.02)]
    return ob_multi("Gloeckchen", [(join(*gold), m["Skin_Gold"]), (join(*slit), m["Glocke_Schlitz"]), (join(*band), m["Glocke_Band"])], col, root, sharp=50)


def pleated_disc(r, h, folds):
    """Kleine Rosette aus Band (liegt auf dem Rand)."""
    bm = bmesh.new()
    n = folds * 4
    centre_top = bm.verts.new((0, 0, h))
    ring = []
    for i in range(n):
        a = TAU * i / n
        rr = r * (1.0 + 0.12 * math.cos(folds * a))
        ring.append((bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, h * (0.45 + 0.3 * math.cos(folds * a)))), bm.verts.new((math.cos(a) * rr, math.sin(a) * rr, 0.0))))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((centre_top, ring[i][0], ring[j][0]))
        bm.faces.new((ring[i][0], ring[i][1], ring[j][1], ring[j][0]))
    geo.box_uv(bm, 0.05)
    bm.normal_update()
    return bm


def build_lily(col, m, root):
    # Blatt: runde Scheibe mit Kerbe, Rand leicht hochgebogen (Ursprung = Auflage)
    prof = [(0.0, 0.0), (0.0295, 0.0), (0.03, 0.004), (0.03, 0.0052), (0.029, 0.0052), (0.024, 0.0036), (0.012, 0.003), (0.0, 0.0028)]
    a0, ang = TAU * 0.035, TAU * 0.93
    pad = join(lathe(prof, 28, 0.05, angle=ang, start=a0), wedge_cap(prof, a0, -1.0), wedge_cap(prof, a0 + ang, 1.0))
    ob("Seerosenblatt", pad, m["Seerose_Blatt"], col, root, sharp=50)
    petals = []
    for ring_i, (count, length, tilt) in enumerate(((8, 0.014, 0.45), (6, 0.011, 0.9), (4, 0.008, 1.25))):
        for k in range(count):
            p = blade(length, length * 0.55, 0.0007, bend=0.5)
            rot(p, -tilt, "Y")
            rot(p, TAU * (k + 0.5 * ring_i) / count, "Z")
            petals.append(move(p, (0, 0, 0.004)))
    centre = geo.ellipsoid(Vector((0.0032, 0.0032, 0.0028)), Vector((0, 0, 0.007)), 10, 6)
    ob_multi("Seerose", [(join(*petals), m["Seerose_Bluete"]), (centre, m["Seerose_Mitte"])], col, root, sharp=60)


def build_witch_candle(col, m, root):
    h = 0.102  # Oberkante bei 0,11 wie bisher
    wax = [lathe([(0.0, 0.008), (0.018, 0.008), (0.0182, 0.014), (0.0165, h + 0.002), (0.0168, h + 0.0065), (0.0158, h + 0.008),
                  (0.0138, h + 0.0068), (0.006, h + 0.005), (0.0, h + 0.0048)], 18, 0.05)]
    for j in range(4):
        a = 0.7 + j * 1.7
        length = 0.022 + j * 0.012
        d = Vector((math.cos(a), math.sin(a), 0.0))
        top = h + 0.007
        pts = [d * 0.0152 + Z * top, d * 0.0172 + Z * (top - 0.006), d * 0.0178 + Z * (top - length * 0.6), d * 0.018 + Z * (top - length)]
        wax.append(pipe(pts, [0.003, 0.0032, 0.0034, 0.0042], 7))
        wax.append(geo.ellipsoid(Vector((0.0042, 0.0042, 0.005)), d * 0.018 + Z * (top - length), 8, 6))
    holder = lathe([(0.0, 0.0), (0.024, 0.0), (0.0275, 0.002), (0.0285, 0.006), (0.028, 0.0082), (0.0262, 0.0082), (0.0252, 0.006),
                    (0.021, 0.0055), (0.02, 0.0085), (0.0, 0.0085)], 20, 0.05)
    wick = pipe([Vector((0, 0, h + 0.004)), Vector((0.0004, 0, h + 0.011)), Vector((0.002, 0, h + 0.016))], 0.0011, 5)
    ob_multi("Hexenkerze", [(join(*wax), m["Kerzenwachs"]), (holder, m["Kerzenhalter"]), (wick, m["Docht"])], col, root, sharp=50)
    # Flamme: Ursprung wie im Code (Knoten wird in der Höhe gestreckt), Form reicht von -0,006 bis +0,026
    ob("Skinflamme", flame_mesh(0.032, 0.008, -0.006), m["Skinflamme"], col, root, shadow=False)


def build_faberge(col, m, root):
    egg_y = 0.075
    gold = [lathe([(0.0, 0.0), (0.028, 0.0), (0.029, 0.003), (0.025, 0.007), (0.02, 0.0095), (0.012, 0.012), (0.007, 0.016), (0.0065, 0.024),
                   (0.0095, 0.027), (0.0095, 0.03), (0.0065, 0.033), (0.007, 0.04), (0.013, 0.045), (0.0, 0.045)], 20, 0.05)]

    def egg_r(dy):
        return 0.03 * math.sqrt(max(0.0, 1.0 - (dy / 0.039) ** 2))

    for k in range(3):  # drei Goldbänder wie bisher, als Wulst mit feinen Kanten
        dy = (k - 1) * 0.022
        r = egg_r(dy) + 0.0002
        gold.append(lathe([(r, egg_y + dy - 0.0032), (r + 0.0012, egg_y + dy - 0.0026), (r + 0.0012, egg_y + dy - 0.0016), (r + 0.0024, egg_y + dy - 0.0008),
                           (r + 0.0024, egg_y + dy + 0.0008), (r + 0.0012, egg_y + dy + 0.0016), (r + 0.0012, egg_y + dy + 0.0026), (r, egg_y + dy + 0.0032)], 28, 0.05))
    gold.append(lathe([(0.0, egg_y + 0.036), (0.01, egg_y + 0.036), (0.013, egg_y + 0.04), (0.013, egg_y + 0.044), (0.0095, egg_y + 0.046),
                       (0.0085, egg_y + 0.044), (0.0, egg_y + 0.044)], 14, 0.05))  # Tülle
    egg = lathe([(0.0, egg_y - 0.039)] + [(math.cos(t) * 0.03, egg_y + math.sin(t) * 0.039) for t in [-1.45 + 2.9 * i / 14 for i in range(15)]] + [(0.0, egg_y + 0.039)], 28, 0.05)
    o = ob("Faberge", join(*gold), m["Skin_Gold"], col, root, sharp=50)
    ob("Faberge_Ei", egg, m["Faberge_Emaille"], col, o, sharp=None)
    for c in range(3):  # Edelsteine am mittleren Band, drei Farben im Wechsel
        gems = []
        for k in range(6):
            if k % 3 == c:
                a = TAU * k / 6
                gems.append(geo.ellipsoid(Vector((0.0042, 0.0042, 0.0042)), gl(math.cos(a) * 0.0312, egg_y, math.sin(a) * 0.0312), 8, 6))
        ob("Faberge_Juwelen_%d" % c, join(*gems), m["Faberge_Juwel_%d" % c], col, o, shadow=False)
    candle = lathe([(0.0, egg_y + 0.043), (0.008, egg_y + 0.043), (0.0082, egg_y + 0.09), (0.0074, egg_y + 0.0935), (0.004, egg_y + 0.0925), (0.0, egg_y + 0.092)], 12, 0.05)
    wick = pipe([Vector((0, 0, egg_y + 0.092)), Vector((0.0008, 0, egg_y + 0.098))], 0.0008, 5)
    ob_multi("Faberge_Kerze", [(candle, m["Faberge_Kerze"]), (wick, m["Docht"])], col, o)
    return o


# =====================================================================================
#  Tischrahmen (Rand für Tische ohne eigenen Rand)
# =====================================================================================

FRAME_ARM = 0.07  # Länge der Schenkel am Eckstück


def build_frame(col, m, root):
    """Rahmen für Tische ohne eigenen Rand: Eckstück (Ecke vorne rechts, Ursprung = Plattenecke
    auf Tischhöhe) und 1 m Leiste (außen = zum Spieler); der Code setzt beides passend zusammen."""
    prof = [(0.0, -0.045), (0.045, -0.045), (0.05, -0.04), (0.05, 0.006), (0.046, 0.0125), (0.038, 0.015), (0.012, 0.015),
            (0.004, 0.0125), (0.0, 0.006), (0.0, -0.045)]
    corner = sweep([Vector((-FRAME_ARM, 0, 0)), Vector((0, 0, 0)), Vector((0, FRAME_ARM, 0))], prof, closed=False)
    ob("Tischrahmen_Ecke", corner, m["Tischrahmen"], col, root, sharp=40)
    straight = sweep([Vector((-0.5, 0, 0)), Vector((0.5, 0, 0))], prof, closed=False)
    ob("Tischrahmen_Leiste", straight, m["Tischrahmen"], col, root, sharp=40)


# =====================================================================================
#  Items: Spiegel, Schnapsglas
# =====================================================================================

def build_items(col, m):
    root = empty("Items", col, size=0.05)
    # ovaler Spiegel (0,26 × 0,35 m wie bisher, beide Seiten Glas): Rahmen mit Profil, Glas leicht gewölbt
    oval = (0.8, 1.1, 1.0)
    frame = lathe([(0.139, -0.012), (0.143, -0.009), (0.148, -0.013), (0.156, -0.011), (0.162, -0.004), (0.162, 0.004), (0.156, 0.011),
                   (0.148, 0.013), (0.143, 0.009), (0.139, 0.012)], 56, 0.1)
    mirror = ob("Spiegel", aim(scale(frame, oval), FRONT), m["Spiegel_Rahmen"], col, root, sharp=40)
    glass = join(lathe([(0.141, 0.0105), (0.08, 0.0118), (0.0, 0.0122)], 56, 0.1), lathe([(0.0, -0.0122), (0.08, -0.0118), (0.141, -0.0105)], 56, 0.1))
    ob("Spiegel_Glas", aim(scale(glass, oval), FRONT), m["Spiegel_Glas"], col, mirror, sharp=None, shadow=False)
    # Schnapsglas: Außenmaße wie bisher (unten 0,02, oben 0,026, 0,06 hoch), mit Wandstärke und rundem Rand
    shot = lathe([(0.0, 0.0), (0.019, 0.0), (0.0202, 0.0012), (0.026, 0.059), (0.0255, 0.06), (0.0246, 0.0592), (0.0192, 0.0035), (0.018, 0.002), (0.0, 0.002)], 24, 0.05)
    ob("Schnapsglas", shot, m["Schnapsglas"], col, root, sharp=50, shadow=False)
    return root


# =====================================================================================
#  Rauchzeug: Aschenbecher des Spielers, Schachtel, Zigarette
# =====================================================================================

def build_smoking(col, m):
    root = empty("Rauchzeug", col, size=0.05)
    # schwerer Messingaschenbecher: Fuß, polierter Wulstrand mit drei Kerben (erste zeigt nach +Z), dunkle Mulde
    body = lathe([(0.0, 0.0), (0.066, 0.0), (0.071, 0.0015), (0.0712, 0.004), (0.069, 0.006), (0.0668, 0.019), (0.0672, 0.021)], 60, 0.1)
    notches = [-PI * 0.5 + TAU * k / 3 for k in range(3)]  # Blender -Y = Godot +Z
    rim = notched_lathe([(0.0672, 0.021), (0.0676, 0.0245), (0.066, 0.0275), (0.0625, 0.0288), (0.057, 0.0288), (0.053, 0.0272), (0.0508, 0.024), (0.05, 0.0222)],
                        240, notches, 0.0055 / 0.059, 0.026)
    well = lathe([(0.05, 0.0222), (0.047, 0.0218), (0.0, 0.0218)], 60, 0.1)
    ob_multi("Aschenbecher", [(body, m["Aschenbecher_Metall"]), (rim, m["Aschenbecher_Rand"]), (well, m["Aschenbecher_Mulde"])], col, root, sharp=40)
    # Zigarettenschachtel: Körper, Farbstreifen und Dreiecke, Innenkragen, Folie; Deckel am Scharnier hinten oben
    W, H, D = PACK_W, PACK_H, PACK_D
    body_h = H - LID_H
    bev = 0.0008
    pack = empty("Schachtel", col, parent=root, size=0.03)
    ob("Schachtel_Koerper", box((W, body_h, D), (0, body_h * 0.5, 0)), m["Schachtel_Weiss"], col, pack, bevel=bev, seg=2)
    ob("Schachtel_Streifen", box((W + 0.0006, 0.007, D + 0.0006), (0, 0.009, 0)), m["Schachtel_Farbe"], col, pack, bevel=bev, seg=2)
    tris = []
    for side in (1.0, -1.0):
        tri = bmesh.new()
        zz = side * (D * 0.5 + 0.0004)
        vs = [tri.verts.new(gl(-W * 0.5 + bev, body_h, zz)), tri.verts.new(gl(W * 0.5 - bev, body_h, zz)), tri.verts.new(gl(0, body_h * 0.54, zz))]
        tri.faces.new(vs)
        geo.box_uv(tri, 0.05)
        tris.append(face_room(tri, FRONT * side))
    ob("Schachtel_Dreiecke", join(*tris), m["Schachtel_Farbe"], col, pack, smooth=False)
    ob("Schachtel_Kragen", box((W - 0.003, 0.012, D - 0.003), (0, body_h + 0.004, 0)), m["Schachtel_Innen"], col, pack, smooth=False)
    ob("Schachtel_Folie", box((W - 0.006, 0.002, D - 0.006), (0, body_h + 0.0095, 0)), m["Schachtel_Folie"], col, pack, smooth=False)
    lid = empty("Schachtel_Deckel", col, (0, body_h, -D * 0.5), parent=pack, size=0.02)
    ob("Schachtel_Deckel_Form", box((W + 0.0008, LID_H, D + 0.0008), (0, LID_H * 0.5, D * 0.5)), m["Schachtel_Farbe"], col, lid, bevel=bev, seg=2)
    # Zigarette für die Schachtel: steht senkrecht, Filter oben (Ursprung in der Mitte wie im Code)
    paper = lathe([(CIG_R * 0.86, -CIG_LEN * 0.5), (CIG_R, -CIG_LEN * 0.5 + 0.0006), (CIG_R, CIG_LEN * 0.22)], 12, 0.02)
    filt = lathe([(CIG_R, CIG_LEN * 0.22), (CIG_R * 1.01, CIG_LEN * 0.5 - 0.0006), (CIG_R * 0.9, CIG_LEN * 0.5), (0.0, CIG_LEN * 0.5)], 12, 0.02)
    tobacco = lathe([(0.0, -CIG_LEN * 0.5 + 0.0003), (CIG_R * 0.86, -CIG_LEN * 0.5)], 12, 0.02)
    ob_multi("Zigarette_Stange", [(paper, m["Zigarettenpapier"]), (filt, m["Zigarettenfilter"]), (tobacco, m["Tabak"])], col, root)
    return root


# =====================================================================================
#  Aufbau und Export
# =====================================================================================

VIEW = {  # Plätze nur für die Ansicht in Blender (Godot-Koordinaten); beim Export steht alles im Ursprung
    "Totenkopf": (-0.36, 0, 0), "Doppeladler": (-0.24, 0, 0), "Kraehe": (-0.06, 0, 0), "Gloeckchen": (0.1, 0, 0),
    "Hexenkerze": (0.2, 0, 0), "Skinflamme": (0.2, 0.122, 0), "Faberge": (0.32, 0, 0),
    "Seerosenblatt": (-0.36, 0, 0.16), "Seerose": (-0.36, 0.004, 0.16), "Tischrahmen_Ecke": (-0.1, 0.045, 0.2), "Tischrahmen_Leiste": (0.6, 0.045, 0.34),
    "Spiegel": (0.0, 0.2, -0.3), "Schnapsglas": (0.3, 0, -0.3),
    "Aschenbecher": (-0.3, 0, 0.42), "Schachtel": (-0.12, 0, 0.42), "Zigarette_Stange": (-0.04, CIG_LEN * 0.5, 0.42),
}


def build_all(preview=True):
    """Ganze Szene neu aufbauen (löscht alles in der aktuellen Datei)."""
    clear_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    m = M()
    col = geo.collection("Belohnungen")
    root = empty("Belohnungen", col, size=0.05)
    build_skull(col, m, root)
    build_eagle(col, m, root)
    build_crow(col, m, root)
    build_bell(col, m, root)
    build_lily(col, m, root)
    build_witch_candle(col, m, root)
    build_faberge(col, m, root)
    build_frame(col, m, root)
    build_items(geo.collection("Items"), m)
    build_smoking(geo.collection("Rauchzeug"), m)
    spread(True)
    if preview:
        pc = geo.collection("Preview")
        ground = ngon([gl(-0.7, 0, -0.6), gl(1.2, 0, -0.6), gl(1.2, 0, 0.7), gl(-0.7, 0, 0.7)])
        ob("Preview_Boden", face_room(ground, Z), mat("Preview_Filz", (0.1, 0.3, 0.18), 0.95), pc, smooth=False)
        preview_light(pc, "Preview_Lampe", "AREA", (0.2, 1.1, 0.5), (1.0, 0.86, 0.66), 60.0, size=0.8)
        world_color((0.03, 0.028, 0.03))
    return "ok"


def spread(placed=True):
    """Vorlagen für die Ansicht nebeneinander stellen (placed=False: alle in den Ursprung, für den Export)."""
    for name, pos in VIEW.items():
        o = bpy.data.objects.get(name)
        if o is not None:
            o.location = gl(*pos) if placed else (0.0, 0.0, 0.0)


def export_all(out_dir=None):
    spread(False)
    bpy.context.view_layer.update()
    try:
        written = export_files(FILES_COSMETICS, out_dir or COSMETICS_DIR)
        written += export_files(FILES_MODELS, out_dir or MODEL_TEX)
    finally:
        spread(True)
    return written
