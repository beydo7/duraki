"""Baut die 3D-Modelle für Duraki in Blender und exportiert sie für Godot.

Aufruf (eine der beiden Varianten):

    blender -b -P art/blender/build_models.py            # mit installiertem Blender
    python3 art/blender/build_models.py                  # mit dem Python-Modul "bpy"

Verhalten:
- Gibt es art/blender/<modell>.blend schon, wird sie NUR geöffnet und als
  assets/models/<modell>.glb exportiert. So gehen eure Änderungen in Blender
  nicht verloren: einfach in Blender bearbeiten, speichern, Skript laufen lassen
  (oder in Blender direkt "Datei > Exportieren > glTF 2.0 (.glb)").
- Mit "--rebuild" wird alles aus diesem Skript neu erzeugt (überschreibt die .blend!).
  Nur ein Modell neu bauen: "--rebuild table" (room, table, props) oder ein Gegner
  ("--rebuild crow", Namen siehe characters.py).

Koordinaten in diesem Skript sind Godot-Koordinaten (siehe geo.G).
"""
from __future__ import annotations

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import geo  # noqa: E402
import textures  # noqa: E402
from geo import G, GS  # noqa: E402

REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
MODEL_DIR = os.path.join(REPO, "assets", "models")

TABLE_Y = 0.80
TABLE_W = 1.6
TABLE_D = 1.2


# =====================================================================================
#  Raum
# =====================================================================================

def build_room() -> None:
    brick = geo.material("Ziegel", "brick", rough=0.92)
    planks = geo.material("Dielen", "floor", rough=0.8)
    ceiling = geo.material("Decke", "floor", color=(0.3, 0.3, 0.3, 1), rough=0.95)
    wood = geo.material("Holz", "wood", rough=0.6)
    metal = geo.material("Messing", "metal", color=(0.55, 0.42, 0.2, 1), rough=0.35, metal=0.9)
    glass_green = geo.material("Glas_Gruen", color=(0.05, 0.16, 0.08, 1), rough=0.08)
    glass_brown = geo.material("Glas_Braun", color=(0.2, 0.08, 0.02, 1), rough=0.1)
    glass_clear = geo.material("Glas_Klar", color=(0.55, 0.6, 0.62, 1), rough=0.05)

    col = geo.collection("Raum")
    geo.to_object("Boden", geo.gbox((6, 0.1, 6), (0, -0.05, 0), tile=1.5), planks, col)
    geo.to_object("Wand_Hinten", geo.gbox((6, 4, 0.2), (0, 2, -2.4), tile=1.0), brick, col)
    geo.to_object("Wand_Links", geo.gbox((0.2, 4, 6), (-2.3, 2, 0), tile=1.0), brick, col)
    geo.to_object("Wand_Rechts", geo.gbox((0.2, 4, 6), (2.3, 2, 0), tile=1.0), brick, col)
    geo.to_object("Decke", geo.gbox((6, 0.2, 6), (0, 3.2, 0), tile=1.5), ceiling, col)
    for i, x in enumerate((-1.2, 0.0, 1.2)):
        geo.to_object(f"Balken_{i}", geo.gbox((0.18, 0.22, 6), (x, 3.0, 0), tile=0.8, uv_rot=True), wood, col, bevel=0.01)

    # Fußleisten
    geo.to_object("Leiste_Hinten", geo.gbox((4.4, 0.12, 0.03), (0, 0.06, -2.285), tile=0.8), wood, col, bevel=0.006)
    geo.to_object("Leiste_Links", geo.gbox((0.03, 0.12, 6), (-2.185, 0.06, 0), tile=0.8, uv_rot=True), wood, col, bevel=0.006)
    geo.to_object("Leiste_Rechts", geo.gbox((0.03, 0.12, 6), (2.185, 0.06, 0), tile=0.8, uv_rot=True), wood, col, bevel=0.006)

    # Tür hinten links
    dx, dz = -1.05, -2.27
    door = geo.merge(
        geo.gbox((0.09, 2.16, 0.07), (dx - 0.5, 1.08, dz), tile=0.8),
        geo.gbox((0.09, 2.16, 0.07), (dx + 0.5, 1.08, dz), tile=0.8),
        geo.gbox((1.09, 0.09, 0.07), (dx, 2.2, dz), tile=0.8),
    )
    geo.to_object("Tuerrahmen", door, wood, col, bevel=0.008)
    panel = geo.gbox((0.91, 2.1, 0.04), (dx, 1.06, dz - 0.01), tile=0.8)
    for px in (-0.21, 0.21):
        for py, ph in ((0.55, 0.8), (1.5, 0.95)):
            panel = geo.merge(panel, geo.gbox((0.33, ph, 0.02), (dx + px, py, dz + 0.015), tile=0.8))
    geo.to_object("Tuer", panel, wood, col, bevel=0.005)
    knob = geo.merge(geo.ellipsoid(Vector((0.025, 0.025, 0.025)), G(dx + 0.36, 1.0, dz + 0.06)),
                     geo.cylinder_between(G(dx + 0.36, 1.0, dz + 0.01), G(dx + 0.36, 1.0, dz + 0.05), 0.008))
    geo.to_object("Tuerknauf", knob, metal, col, smooth=True)

    # Regal hinten rechts mit Flaschen
    sx = 1.05
    shelf = geo.merge(
        geo.gbox((0.95, 0.035, 0.22), (sx, 1.45, -2.19), tile=0.8),
        geo.gbox((0.95, 0.035, 0.22), (sx, 1.9, -2.19), tile=0.8),
        geo.gbox((0.03, 0.5, 0.2), (sx - 0.44, 1.66, -2.2), tile=0.8),
        geo.gbox((0.03, 0.5, 0.2), (sx + 0.44, 1.66, -2.2), tile=0.8),
    )
    geo.to_object("Regal", shelf, wood, col, bevel=0.006)
    bottle_profile = [(0.0, 0.0), (0.034, 0.0), (0.036, 0.006), (0.036, 0.15), (0.03, 0.18),
                      (0.013, 0.21), (0.011, 0.27), (0.013, 0.275), (0.0, 0.275)]
    jar_profile = [(0.0, 0.0), (0.045, 0.0), (0.048, 0.01), (0.048, 0.11), (0.04, 0.125), (0.04, 0.14), (0.0, 0.14)]
    items = [(-0.33, 1.4675, bottle_profile, 1.0, glass_green), (-0.2, 1.4675, bottle_profile, 0.85, glass_brown),
             (-0.07, 1.4675, bottle_profile, 1.1, glass_green), (0.2, 1.4675, jar_profile, 1.0, glass_clear),
             (0.33, 1.4675, bottle_profile, 0.9, glass_brown),
             (-0.28, 1.9175, jar_profile, 0.9, glass_brown), (-0.12, 1.9175, jar_profile, 1.1, glass_clear),
             (0.15, 1.9175, bottle_profile, 0.95, glass_green), (0.3, 1.9175, bottle_profile, 1.05, glass_clear)]
    for i, (ox, oy, prof, sc, mat) in enumerate(items):
        p = [(r * sc, h * sc) for r, h in prof]
        bm = geo.lathe(p, 20, 0.2, cap_bottom=True, cap_top=True)
        geo.translate(bm, G(sx + ox, oy, -2.19))
        geo.to_object(f"Regal_Flasche_{i}", bm, mat, col, smooth=True)


# =====================================================================================
#  Tisch
# =====================================================================================

def build_table() -> None:
    felt = geo.material("Filz", "felt", rough=0.98, normal_strength=0.6)
    wood = geo.material("Tischholz", "wood", rough=0.4)
    col = geo.collection("Tisch")

    # Filz: abgerundetes Rechteck, oben genau auf TABLE_Y
    import bmesh
    bm = bmesh.new()
    pts = geo.rounded_rect(TABLE_W, TABLE_D, 0.05)
    verts = [bm.verts.new(G(p[0], 0, -p[1]) + Vector((0, 0, TABLE_Y))) for p in pts]
    face = bm.faces.new(verts)
    bm.normal_update()
    if face.normal.z < 0:
        face.normal_flip()
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    down = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=Vector((0, 0, -0.05)), verts=down)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    geo.box_uv(bm, 0.5)
    geo.to_object("Filz", bm, felt, col)

    # Holzrand mit Zarge (ein Profil, das rund um den Filz gezogen wird)
    path = [Vector(p) for p in geo.rounded_rect(TABLE_W, TABLE_D, 0.05, seg=8)]
    profile = [(0.0, 0.63), (0.0, TABLE_Y), (0.012, 0.818), (0.03, 0.826), (0.05, 0.824),
               (0.066, 0.812), (0.074, 0.795), (0.07, 0.775), (0.05, 0.765), (0.045, 0.75),
               (0.045, 0.63), (0.0, 0.63)]
    rim = geo.sweep(path, profile, closed=True, tile=0.6)
    bmesh.ops.recalc_face_normals(rim, faces=rim.faces)
    geo.to_object("Tischrand", rim, wood, col, smooth=True, sharp_angle=50)

    # gedrechselte Beine
    leg_profile = [(0.0, 0.0), (0.03, 0.0), (0.024, 0.035), (0.028, 0.06), (0.02, 0.2), (0.03, 0.34),
                   (0.036, 0.37), (0.027, 0.41), (0.033, 0.48), (0.04, 0.53), (0.04, 0.63), (0.0, 0.63)]
    for i, (x, z) in enumerate(((-1, -1), (1, -1), (-1, 1), (1, 1))):
        bm = geo.lathe(leg_profile, 20, 0.3)
        geo.translate(bm, G(x * 0.74, 0, z * 0.54))
        geo.to_object(f"Tischbein_{i}", bm, wood, col, smooth=True, sharp_angle=60)


# =====================================================================================
#  Requisiten: Lampe, Scheinwerfer, Lautsprecher, Kisten, Dinge auf dem Tisch
# =====================================================================================

def build_props() -> None:
    import bmesh
    enamel = geo.material("Emaille", "metal", color=(0.12, 0.2, 0.16, 1), rough=0.35, metal=0.3)
    enamel_in = geo.material("Emaille_Innen", color=(0.95, 0.9, 0.8, 1), rough=0.4,
                             emission=(1.0, 0.85, 0.6, 1), emission_strength=0.6)
    bulb = geo.material("Gluehbirne", color=(1, 0.9, 0.7, 1), rough=0.2, emission=(1.0, 0.82, 0.54, 1), emission_strength=6.0)
    dark_metal = geo.material("Metall_Dunkel", "metal", rough=0.5, metal=0.6)
    cable = geo.material("Kabel", color=(0.02, 0.02, 0.02, 1), rough=0.7)
    cloth = geo.material("Bespannung", "cloth", rough=0.95)
    crate = geo.material("Kistenholz", "crate", rough=0.85)
    lens_l = geo.material("Linse_Lila", color=(0.7, 0.4, 0.65, 1), rough=0.1, emission=(0.69, 0.42, 0.63, 1), emission_strength=0.15)
    lens_r = geo.material("Linse_Blau", color=(0.5, 0.56, 0.82, 1), rough=0.1, emission=(0.5, 0.56, 0.82, 1), emission_strength=0.15)
    bottle_glass = geo.material("Flaschenglas", color=(0.05, 0.14, 0.07, 1), rough=0.06)
    label = geo.material("Etikett", "porcelain", color=(0.9, 0.85, 0.7, 1), rough=0.9, normal=False)
    shot_glass = geo.material("Schnapsglas", color=(0.8, 0.85, 0.9, 1), rough=0.05, alpha=0.35)
    liquor = geo.material("Schnaps", color=(0.75, 0.4, 0.08, 1), rough=0.05, alpha=0.8)
    paper = geo.material("Zigarettenpapier", color=(0.92, 0.9, 0.85, 1), rough=0.8)
    filt = geo.material("Filter", color=(0.8, 0.5, 0.25, 1), rough=0.8)
    ember = geo.material("Glut", color=(1.0, 0.3, 0.05, 1), rough=0.8, emission=(1.0, 0.25, 0.02, 1), emission_strength=5.0)

    # --- Hängelampe ---
    col = geo.collection("Lampe")
    geo.to_object("Lampenkabel", geo.cylinder_between(G(0, 3.1, 0), G(0, 2.25, 0), 0.005, seg=8), cable, col, smooth=True)
    cap = geo.lathe([(0.0, 2.29), (0.018, 2.29), (0.03, 2.25), (0.036, 2.225), (0.0, 2.225)], 24, 0.2, cap_bottom=True)
    geo.to_object("Lampenfassung", geo.transform(cap, Matrix.Identity(4)), dark_metal, col, smooth=True)
    shade_out = [(0.034, 2.23), (0.05, 2.215), (0.12, 2.155), (0.2, 2.095), (0.226, 2.075), (0.229, 2.066)]
    shade_in = [(0.222, 2.066), (0.198, 2.084), (0.116, 2.147), (0.046, 2.205), (0.032, 2.215)]
    geo.to_object("Lampenschirm", geo.lathe(shade_out + shade_in, 40, 0.3), enamel, col, smooth=True, sharp_angle=70)
    geo.to_object("Lampenschirm_Innen", geo.lathe(shade_in, 40, 0.3), enamel_in, col, smooth=True)
    geo.to_object("Gluehbirne", geo.ellipsoid(Vector((0.042, 0.042, 0.05)), G(0, 2.08, 0)), bulb, col, smooth=True)

    # --- Bühnenscheinwerfer ---
    col = geo.collection("Scheinwerfer")
    for side, lens in ((-1, lens_l), (1, lens_r)):
        name = "L" if side < 0 else "R"
        base = G(side * 1.25, 0, -1.6)
        hub = base + Vector((0, 0, 0.42))
        parts = []
        for leg in range(3):
            a = leg * math.tau / 3 + 0.3
            foot = base + Vector((math.cos(a) * 0.3, math.sin(a) * 0.3, 0.01))
            parts.append(geo.cylinder_between(foot, hub, 0.012, 0.014, seg=8))
            parts.append(geo.ellipsoid(Vector((0.02, 0.02, 0.012)), foot, 8, 6))
        parts.append(geo.cylinder_between(hub - Vector((0, 0, 0.04)), base + Vector((0, 0, 1.82)), 0.02, 0.016, seg=10))
        origin = G(side * 1.25, 1.95, -1.6)
        target = G(side * -0.2, TABLE_Y, 0.1)
        aim = geo.aim_matrix(origin, target)
        # Bügel
        yoke = geo.merge(
            geo.box(Vector((0.012, 0.03, 0.18)), Vector((-0.17, 0, -0.06))),
            geo.box(Vector((0.012, 0.03, 0.18)), Vector((0.17, 0, -0.06))),
        )
        yoke_m = Matrix.Translation(origin) @ Matrix.Rotation(aim.to_euler().z, 4, "Z")
        parts.append(geo.transform(yoke, yoke_m))
        geo.to_object(f"Stativ_{name}", geo.merge(*parts), dark_metal, col, smooth=True, sharp_angle=40)
        can_profile = [(0.0, -0.17), (0.06, -0.17), (0.1, -0.15), (0.12, -0.1), (0.13, 0.08), (0.155, 0.13),
                       (0.16, 0.15), (0.145, 0.15), (0.135, 0.12)]
        can = geo.lathe(can_profile, 32, 0.3, cap_bottom=True)
        for k in range(4):  # Kühlrippen
            z = -0.12 + k * 0.035
            can = geo.merge(can, geo.lathe([(0.121, z), (0.128, z + 0.004), (0.128, z + 0.012), (0.121, z + 0.016)], 32, 0.3))
        geo.to_object(f"Scheinwerfer_{name}", geo.transform(can, aim), dark_metal, col, smooth=True, sharp_angle=50)
        lens_bm = geo.lathe([(0.0, 0.135), (0.137, 0.12)], 32, 0.3)
        geo.to_object(f"Linse_{name}", geo.transform(lens_bm, aim), lens, col, smooth=True)

    # --- Lautsprecher links ---
    col = geo.collection("Lautsprecher")
    rot = Matrix.Translation(G(-1.75, 0, -1.2)) @ Matrix.Rotation(math.radians(25), 4, "Z")
    cab = geo.box(Vector((0.5, 0.4, 0.7)), Vector((0, 0, 0.35)), tile=0.5)
    geo.to_object("Lautsprecher", geo.transform(cab, rot), cloth, col, bevel=0.02, bevel_segments=3)
    cones = []
    for r, z in ((0.15, 0.27), (0.06, 0.55)):
        prof = [(0.0, -0.03), (r * 0.2, -0.028), (r * 0.85, -0.006), (r, 0.0), (r * 1.12, 0.0), (r * 1.15, 0.008)]
        c = geo.lathe(prof, 32, 0.3)
        geo.transform(c, Matrix.Translation(Vector((0, -0.205, z))) @ Matrix.Rotation(math.radians(90), 4, "X"))
        cones.append(c)
    geo.to_object("Lautsprecher_Membran", geo.transform(geo.merge(*cones), rot), dark_metal, col, smooth=True)

    # --- Kisten rechts ---
    col = geo.collection("Kisten")
    for i, (size, pos, deg) in enumerate(((0.45, (1.7, 0.225, -1.4), -15), (0.35, (1.75, 0.6, -1.4), 10))):
        m = Matrix.Translation(G(*pos)) @ Matrix.Rotation(math.radians(deg), 4, "Z")
        s = size
        parts = [geo.box(Vector((s * 0.96, s * 0.96, s * 0.96)), Vector((0, 0, 0)), tile=0.4)]
        for side in (-1, 1):  # Latten
            for zz in (-0.3, 0.3):
                parts.append(geo.box(Vector((s, 0.02, s * 0.16)), Vector((0, side * s * 0.49, zz * s)), tile=0.4))
                parts.append(geo.box(Vector((0.02, s, s * 0.16)), Vector((side * s * 0.49, 0, zz * s)), tile=0.4, uv_rot=True))
        geo.to_object(f"Kiste_{i}", geo.transform(geo.merge(*parts), m), crate, col, bevel=0.006)

    # --- Kabel von der Decke ---
    col = geo.collection("Deckenkabel")
    for i in range(4):
        x = -1.6 + i * 1.05
        z = -2.2 + (i % 2) * 0.2
        geo.to_object(f"Deckenkabel_{i}", geo.cylinder_between(G(x, 3.1, z), G(x, 1.9 + (i % 3) * 0.15, z), 0.008, seg=8),
                      cable, col, smooth=True)

    # --- Auf dem Tisch ---
    col = geo.collection("Tischdeko")
    bottle = geo.lathe([(0.0, 0.0), (0.034, 0.0), (0.036, 0.006), (0.036, 0.17), (0.03, 0.2), (0.014, 0.23),
                        (0.012, 0.29), (0.014, 0.296), (0.014, 0.3), (0.0, 0.3)], 28, 0.2, cap_bottom=True, cap_top=True)
    geo.to_object("Flasche", geo.translate(bottle, G(0.68, TABLE_Y, 0.0)), bottle_glass, col, smooth=True)
    lab = geo.lathe([(0.0365, 0.07), (0.0365, 0.13)], 28, 0.1, angle=math.radians(200))
    geo.transform(lab, Matrix.Translation(G(0.68, TABLE_Y, 0.0)) @ Matrix.Rotation(math.radians(180), 4, "Z"))
    geo.to_object("Flaschenetikett", lab, label, col, smooth=True)
    glass = geo.lathe([(0.0, 0.0), (0.022, 0.0), (0.026, 0.055), (0.023, 0.055), (0.019, 0.01), (0.0, 0.01)], 24, 0.1)
    geo.to_object("Schnapsglas", geo.translate(glass, G(0.57, TABLE_Y, 0.14)), shot_glass, col, smooth=True, sharp_angle=60)
    liq = geo.lathe([(0.0, 0.011), (0.0195, 0.011), (0.0215, 0.035), (0.0, 0.035)], 24, 0.1, cap_top=True)
    geo.to_object("Schnaps", geo.translate(liq, G(0.57, TABLE_Y, 0.14)), liquor, col, smooth=True)
    tray = geo.lathe([(0.0, 0.0), (0.06, 0.0), (0.066, 0.016), (0.062, 0.02), (0.052, 0.018), (0.047, 0.007), (0.0, 0.007)], 32, 0.2)
    geo.to_object("Aschenbecher", geo.translate(tray, G(-0.68, TABLE_Y, -0.42)), dark_metal, col, smooth=True, sharp_angle=50)
    a = G(-0.665, TABLE_Y + 0.02, -0.425)
    b = G(-0.60, TABLE_Y + 0.012, -0.40)
    mid = a.lerp(b, 0.25)
    geo.to_object("Zigarette", geo.cylinder_between(mid, b, 0.0045, seg=10), paper, col, smooth=True)
    geo.to_object("Zigarettenfilter", geo.cylinder_between(a.lerp(b, 0.02), mid, 0.0046, seg=10), filt, col, smooth=True)
    geo.to_object("Glut", geo.cylinder_between(b, b + (b - a).normalized() * 0.004, 0.0044, seg=10), ember, col, smooth=True)


BUILDERS = {
    "room": build_room,
    "table": build_table,
    "props": build_props,
}


def _build_one(name: str, builder, blend: str, glb: str, rebuild: bool) -> None:
    if rebuild or not os.path.exists(blend):
        if not os.path.exists(os.path.join(textures.OUT_DIR, "fur_grey_color.png")):
            textures.build_all()
        print(f"Baue {name} …")
        geo.new_scene()
        builder()
        geo.save_blend(blend)
    else:
        print(f"Öffne {os.path.basename(blend)} …")
        bpy.ops.wm.open_mainfile(filepath=blend)
    geo.export_glb(glb)
    print(f"  → {os.path.relpath(glb, REPO)}")


def main(argv: list[str]) -> None:
    import characters
    rebuild = "--rebuild" in argv
    only = [a for a in argv if a in BUILDERS or a in characters.CHARACTERS]
    if rebuild and not only:
        print("Erzeuge Texturen …")
        textures.build_all()
    for name in only or list(BUILDERS):
        if name in BUILDERS:
            _build_one(name, BUILDERS[name], os.path.join(HERE, name + ".blend"),
                       os.path.join(MODEL_DIR, name + ".glb"), rebuild)
    for name in only or list(characters.CHARACTERS):
        if name in characters.CHARACTERS:
            _build_one(name, characters.CHARACTERS[name], os.path.join(HERE, "opponents", name + ".blend"),
                       os.path.join(MODEL_DIR, "opponents", name + ".glb"), rebuild)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    main(args)
