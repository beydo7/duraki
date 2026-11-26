"""Kleinteile auf dem Spieltisch als Blender-Modelle: Kerzen der Leben und Goldmünzen.

    import sys; sys.path.insert(0, r"<Repo>/art/blender")
    import table_small; table_small.build_all(); table_small.export_all()

Maße wie in scenes/match/table_props.gd (dort stellt und bewegt der Code die Teile).

    table_small.glb  Vorlagen: „Kerze_0…2“ (7, 8, 9 cm hoch; Wachs und Docht), „Flamme“,
                     „Kerzenteller“, „Muenze“
"""
from __future__ import annotations

import math
import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import geo  # noqa: E402
from room_kit import *  # noqa: E402,F401,F403
from room_kit import MODEL_TEX  # noqa: E402

OUT_DIR = MODEL_TEX
FILES = {"table_small.glb": ["Tischkleinteile"]}
CANDLE_HEIGHTS = (0.07, 0.08, 0.09)


def M():
    d = {}
    d["Wachs"] = mat("Wachs", (0.86, 0.8, 0.66), 0.65)
    d["Docht"] = mat("Docht", (0.05, 0.04, 0.03), 0.9)
    d["Flamme"] = mat("Flamme", (1.0, 0.72, 0.3), 0.3, emission=(1.0, 0.6, 0.2), energy=3.0)
    d["Tellermessing"] = mat("Tellermessing", (0.28, 0.2, 0.1), 0.55, 0.7)
    d["Muenzgold"] = mat("Muenzgold", (0.95, 0.72, 0.28), 0.32, 1.0)
    return d


def build_all(preview=True):
    """Ganze Szene neu aufbauen (löscht alles in der aktuellen Datei)."""
    clear_scene()
    bpy.context.scene.unit_settings.system = "METRIC"
    m = M()
    col = geo.collection("Tischkleinteile")
    root = empty("Tischkleinteile", col, size=0.05)
    # Kerzen: Wachs mit Schmelzmulde, herablaufende Tropfen, gebogener Docht (Ursprung = Standfläche)
    for k, h in enumerate(CANDLE_HEIGHTS):
        body = lathe([(0.0, 0.0), (0.0125, 0.0), (0.0126, 0.004), (0.0118, h - 0.005), (0.012, h - 0.0012), (0.0113, h + 0.0004),
                      (0.0098, h - 0.0006), (0.0045, h - 0.002), (0.0, h - 0.0022)], 20, 0.05)
        wax = [body]
        for j in range(3):
            a = k * 2.2 + j * 2.1
            length = 0.014 + j * 0.008 + k * 0.003
            d = Vector((math.cos(a), math.sin(a), 0.0))
            pts = [d * 0.0108 + Z * (h - 0.0005), d * 0.0122 + Z * (h - 0.004), d * 0.0126 + Z * (h - length * 0.6), d * 0.0128 + Z * (h - length)]
            wax.append(pipe(pts, [0.0022, 0.0024, 0.0026, 0.0032], 7))
            wax.append(geo.ellipsoid(Vector((0.0032, 0.0032, 0.0038)), d * 0.0128 + Z * (h - length), 8, 6))
        wick = pipe([Vector((0, 0, h - 0.003)), Vector((0.0003, 0, h + 0.003)), Vector((0.0014, 0, h + 0.0065))], 0.0009, 5)
        o = ob_multi("Kerze_%d" % k, [(join(*wax), m["Wachs"]), (wick, m["Docht"])], col, root, sharp=50)
        o.location = (-0.04 + k * 0.04, 0.0, 0.0)
    flame = lathe([(0.0, -0.011), (0.0035, -0.009), (0.0055, -0.004), (0.0052, 0.001), (0.0034, 0.007), (0.0012, 0.0115), (0.0, 0.013)], 12, 0.02)
    o = ob("Flamme", flame, m["Flamme"], col, root, shadow=False)
    o.location = (0.0, 0.0, 0.11)
    dish = lathe([(0.0, 0.0), (0.058, 0.0), (0.066, 0.003), (0.068, 0.009), (0.0672, 0.0112), (0.065, 0.0112), (0.0635, 0.0082),
                  (0.06, 0.0078), (0.0, 0.0078)], 40, 0.1)
    o = ob("Kerzenteller", dish, m["Tellermessing"], col, root, sharp=40)
    o.location = (0.0, 0.12, 0.0)
    # Goldmünze: erhabener Rand, Mittelfeld mit Wulst (Ursprung in der Mitte, 3,2 mm hoch)
    coin = lathe([(0.0, -0.0012), (0.006, -0.0012), (0.0066, -0.0015), (0.0124, -0.0012), (0.0132, -0.0016), (0.0155, -0.0016), (0.016, -0.0011),
                  (0.016, 0.0011), (0.0155, 0.0016), (0.0132, 0.0016), (0.0124, 0.0012), (0.0066, 0.0015), (0.006, 0.0012), (0.0, 0.0012)], 28, 0.02)
    o = ob("Muenze", coin, m["Muenzgold"], col, root, sharp=35)
    o.location = (0.0, -0.08, 0.0016)
    return "ok"


def export_all(out_dir=None):
    return export_files(FILES, out_dir or OUT_DIR)
