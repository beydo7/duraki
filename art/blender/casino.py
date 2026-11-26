"""Raum „Altes Casino“ als Blender-Modelle (Raum, Pokertisch, Deko, Automat, Roulette, Lampe).

In Blender ausführen (Skript-Editor, Konsole oder MCP):

    import sys; sys.path.insert(0, r"<Repo>/art/blender")
    import casino; casino.build_all()        # baut die ganze Szene neu
    casino.export_all()                      # schreibt die .glb nach assets/rooms/casino/

Grundsatz: Das Design bleibt, nur die Machart wird besser. Alle Maße, Positionen und Farben
stammen 1:1 aus den früheren Code-Bauten (scenes/match/rooms/casino_room.gd, slot_machine.gd,
mini_roulette.gd, banker_lamp.gd). Koordinaten in diesem Skript sind Godot-Koordinaten
(Y nach oben, +Z zum Spieler), siehe geo.G.

Aufteilung der Dateien:
    casino.glb        Raum (Vertäfelung, Leisten, Vorhänge, Schild, Leuchter), Pokertisch, Würfel, Glas
    slot_machine.glb  Spielautomat (Hebel „Hebel“, Birnen „Birne_00…12“ als eigene Teile)
    roulette.glb      Tisch-Roulette (drehender Teil „Kessel“)
    banker_lamp.glb   Bankerlampe (Schirm „Schirm“, Zugkette „Kette“)
    chip.glb          ein Pokerchip (das Spiel stapelt ihn und färbt ihn je Stapel)

Materialien: In Godot ordnet der Code die Materialien über den NAMEN zu (RoomKit.model).
Farben und Texturen hier in Blender sind dieselben Werte, damit die Vorschau stimmt; das
Spiel nimmt für alles, was im Code steht, die Godot-Materialien (Lauflichter, Tisch-Looks,
Automatenfarbe …). Materialien, die der Code nicht kennt, kommen so ins Spiel, wie sie hier sind.
Objekte mit „Preview_“ am Anfang sind nur Kulisse in Blender und werden nicht exportiert.
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
from geo import G  # noqa: E402

REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
ROOM_TEX = os.path.join(REPO, "assets", "rooms", "casino")
MODEL_TEX = os.path.join(REPO, "assets", "models")
## Zielordner für die .glb (zum Ausprobieren auf einen Arbeitsordner umstellbar)
OUT_DIR = ROOM_TEX

PI = math.pi
TAU = math.tau
Z = Vector((0, 0, 1))
FRONT = Vector((0, -1, 0))  # Godot +Z (zum Spieler) in Blender

# Maße wie in casino_room.gd
TABLE_Y = 0.80
ROOM_W = 4.4
BACK_Z = -2.3
CEIL = 3.0
FELT = (2.1, 1.2)
RAIL = 0.1


# =====================================================================================
#  Materialien
# =====================================================================================

def lin(c):
    """Farbe wie in Godot (sRGB) → linear für Blender."""
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c)


def mat(name, color=(1, 1, 1), rough=0.6, metal=0.0, tex=None, normal=None, scale=1.0,
        emission=None, energy=1.0, alpha=None, strength=1.0):
    """Material mit denselben Werten wie das Godot-Material gleichen Namens.
    tex/normal: Bilddateien (voller Pfad), scale: Kacheln pro Meter (UVs sind in Metern)."""
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.use_backface_culling = True  # wie im Spiel: Rückseiten unsichtbar → Fehler fallen auf
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    col = (*lin(color), 1.0)
    bsdf.inputs["Base Color"].default_value = col
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    mapping = None
    if tex or normal:
        tc = nt.nodes.new("ShaderNodeTexCoord")
        tc.location = (-1100, 100)
        mapping = nt.nodes.new("ShaderNodeMapping")
        mapping.location = (-900, 100)
        mapping.inputs["Scale"].default_value = (scale, scale, scale)
        nt.links.new(tc.outputs["UV"], mapping.inputs["Vector"])
    if tex and os.path.exists(tex):
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = bpy.data.images.load(tex, check_existing=True)
        t.location = (-650, 300)
        nt.links.new(mapping.outputs["Vector"], t.inputs["Vector"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.location = (-300, 300)
        mix.inputs[0].default_value = 1.0
        nt.links.new(t.outputs["Color"], mix.inputs[6])
        mix.inputs[7].default_value = col
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    if normal and os.path.exists(normal):
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(normal, check_existing=True)
        n.image.colorspace_settings.name = "Non-Color"
        n.location = (-650, -100)
        nt.links.new(mapping.outputs["Vector"], n.inputs["Vector"])
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = strength
        nm.location = (-300, -100)
        nt.links.new(n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*lin(emission), 1.0)
        bsdf.inputs["Emission Strength"].default_value = energy
    if alpha is not None:
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            m.surface_render_method = "BLENDED"
        except AttributeError:
            m.blend_method = "BLEND"
    m.diffuse_color = (*lin(color), 1.0 if alpha is None else alpha)
    return m


def M():
    """Alle Materialien des Casinos (Namen = Zuordnung in Godot)."""
    wood_c = os.path.join(MODEL_TEX, "table_wood_color.png")
    wood_n = os.path.join(MODEL_TEX, "table_wood_normal.png")
    d = {}
    d["Filz"] = mat("Filz", (0.62, 1.0, 0.72), 0.95, tex=os.path.join(MODEL_TEX, "table_felt_color.png"),
                    normal=os.path.join(MODEL_TEX, "table_felt_normal.png"), scale=1.2)
    d["Leder"] = mat("Leder", (0.26, 0.09, 0.06), 0.38, normal=os.path.join(ROOM_TEX, "leather_normal.png"), scale=9.0,
                     strength=0.3)
    d["Tischholz"] = mat("Tischholz", (0.55, 0.3, 0.18), 0.5, tex=wood_c, normal=wood_n, scale=1.5)
    d["Holz"] = mat("Holz", (0.55, 0.3, 0.18), 0.5, tex=wood_c, normal=wood_n, scale=1.5)
    d["Gold"] = mat("Gold", (0.9, 0.68, 0.3), 0.3, 1.0)
    d["Samt"] = mat("Samt", (0.42, 0.03, 0.06), 0.75, normal=os.path.join(ROOM_TEX, "velvet_normal.png"), scale=6.0,
                    strength=0.5)
    d["Schild"] = mat("Schild", (0.05, 0.02, 0.03), 0.6)
    d["Schildbirne"] = mat("Schildbirne", (1, 0.9, 0.6), 0.3, emission=(1, 0.78, 0.4), energy=2.6)
    d["Kerzenlicht"] = mat("Kerzenlicht", (1, 0.9, 0.7), 0.3, emission=(1, 0.8, 0.5), energy=4.0)
    d["Kristall"] = mat("Kristall", (0.95, 0.97, 1.0), 0.02, emission=(1, 0.85, 0.6), energy=0.3, alpha=0.55)
    d["Lampenschirm"] = mat("Lampenschirm", (0.95, 0.7, 0.45), 0.7, emission=(1, 0.6, 0.3), energy=1.2)
    d["Wuerfel"] = mat("Wuerfel", (0.95, 0.93, 0.88), 0.25)
    d["Wuerfelauge"] = mat("Wuerfelauge", (0.08, 0.06, 0.06), 0.5)
    d["Glas"] = mat("Glas", (0.85, 0.92, 1.0), 0.05, alpha=0.25)
    d["Drink"] = mat("Drink", (0.95, 0.9, 0.6), 0.1, alpha=0.6)
    d["Olive"] = mat("Olive", (0.35, 0.45, 0.12), 0.4)
    d["Paprika"] = mat("Paprika", (0.75, 0.12, 0.08), 0.4)
    # Spielautomat
    d["Sockelholz"] = mat("Sockelholz", (0.2, 0.1, 0.05), 0.55, tex=wood_c, normal=wood_n, scale=2.0)
    d["Chrom"] = mat("Chrom", (0.86, 0.86, 0.9), 0.18, 1.0)
    d["Messing"] = mat("Messing", (0.92, 0.7, 0.3), 0.3, 1.0)
    d["Lack"] = mat("Lack", (0.62, 0.06, 0.08), 0.35)
    d["Dunkel"] = mat("Dunkel", (0.03, 0.03, 0.04), 0.6)
    d["Birne"] = mat("Birne", (1, 0.85, 0.5), 0.3, emission=(1, 0.72, 0.3), energy=3.2)
    d["Fensterglas"] = mat("Fensterglas", (0.8, 0.9, 1.0), 0.05, alpha=0.12)
    d["Gewinnlinie"] = mat("Gewinnlinie", (0.9, 0.1, 0.1), 0.5)
    d["Knauf"] = mat("Knauf", (0.8, 0.04, 0.05), 0.2)
    d["Knopf_Rot"] = mat("Knopf_Rot", (0.9, 0.2, 0.1), 0.3)
    d["Knopf_Gelb"] = mat("Knopf_Gelb", (0.95, 0.75, 0.2), 0.3)
    d["Knopf_Gruen"] = mat("Knopf_Gruen", (0.2, 0.6, 0.3), 0.3)
    # Roulette
    d["Kesselholz"] = mat("Kesselholz", (0.55, 0.32, 0.18), 0.45, tex=wood_c, normal=wood_n, scale=8.0)
    d["Kesselgold"] = mat("Kesselgold", (0.92, 0.7, 0.3), 0.28, 1.0)
    d["Steggold"] = mat("Steggold", (0.92, 0.7, 0.3), 0.35, 1.0)
    d["Scheibe"] = mat("Scheibe", (0.85, 0.85, 0.85), 0.85, tex=os.path.join(ROOM_TEX, "roulette.png"))
    # Pokerchip (Farbe je Stapel setzt das Spiel)
    d["Chipfarbe"] = mat("Chipfarbe", (0.72, 0.06, 0.08), 0.45)
    d["Chipweiss"] = mat("Chipweiss", (0.94, 0.92, 0.86), 0.5)
    # Bankerlampe
    d["Lampenmessing"] = mat("Lampenmessing", (0.86, 0.64, 0.3), 0.22, 1.0)
    d["Glas_Gruen"] = mat("Glas_Gruen", (0.01, 0.2, 0.07), 0.06, emission=(0.03, 0.3, 0.1), energy=0.55)
    d["Schirm_Innen"] = mat("Schirm_Innen", (0.98, 0.94, 0.82), 0.5, emission=(1.0, 0.86, 0.6), energy=1.6)
    d["Gluehbirne"] = mat("Gluehbirne", (1.0, 0.9, 0.7), 0.3, emission=(1.0, 0.82, 0.55), energy=4.0)
    d["Juwel"] = mat("Juwel", (0.9, 0.08, 0.06), 0.15, emission=(1.0, 0.12, 0.08), energy=2.2)
    return d


# =====================================================================================
#  Bausteine
# =====================================================================================

def _uv(bm):
    return bm.loops.layers.uv.verify()


def sweep(path, profile, closed=True, tile=1.0, up=Z, flip=False):
    """Zieht ein Profil [(außen, hoch), ...] an einem Pfad entlang; Ecken werden auf Gehrung
    geschnitten. „außen“ zeigt nach rechts der Laufrichtung (t × up), „hoch“ entlang `up`.
    Profil gegen den Uhrzeigersinn (unten nach außen, außen hoch, oben nach innen) →
    Flächen zeigen nach außen; `flip` dreht sie um. UV: U am Pfad entlang, V ums Profil (Meter)."""
    pts = [Vector(p) for p in path]
    n = len(pts)
    up = Vector(up).normalized()
    bm = bmesh.new()
    uv = _uv(bm)
    rings = []
    for i in range(n):
        a = pts[i - 1] if (closed or i > 0) else pts[i]
        b = pts[(i + 1) % n] if (closed or i < n - 1) else pts[i]
        t_in = pts[i] - a
        t_out = b - pts[i]
        if t_in.length < 1e-9:
            t_in = t_out
        if t_out.length < 1e-9:
            t_out = t_in
        n_in = t_in.normalized().cross(up).normalized()
        n_out = t_out.normalized().cross(up).normalized()
        m = n_in + n_out
        if m.length < 1e-6:
            m = n_in.copy()
        m.normalize()
        k = 1.0 / max(m.dot(n_in), 0.35)
        rings.append([bm.verts.new(pts[i] + m * (o * k) + up * h) for o, h in profile])
    dist = [0.0]
    for i in range(1, n + (1 if closed else 0)):
        dist.append(dist[-1] + (pts[i % n] - pts[i - 1]).length)
    plen = [0.0]
    for i in range(1, len(profile)):
        plen.append(plen[-1] + math.hypot(profile[i][0] - profile[i - 1][0], profile[i][1] - profile[i - 1][1]))
    for s in range(n if closed else n - 1):
        a, b = rings[s], rings[(s + 1) % n]
        for i in range(len(profile) - 1):
            quad = [(a[i], s, i), (b[i], s + 1, i), (b[i + 1], s + 1, i + 1), (a[i + 1], s, i + 1)]
            if flip:
                quad.reverse()
            try:
                f = bm.faces.new([q[0] for q in quad])
            except ValueError:
                continue
            for loop, q in zip(f.loops, quad):
                loop[uv].uv = (dist[q[1]] / tile, plen[q[2]] / tile)
    bm.normal_update()
    return bm


def lathe(profile, seg=32, tile=1.0, flip=False, angle=TAU, start=0.0):
    """Drehkörper um die Blender-Z-Achse. profile = [(radius, höhe), ...] gegen den Uhrzeigersinn
    (unten nach außen, außen hoch, oben nach innen) → Flächen zeigen nach außen."""
    bm = bmesh.new()
    uv = _uv(bm)
    full = abs(angle - TAU) < 1e-6
    steps = seg if full else seg + 1
    rings = []
    for s in range(steps):
        a = start + angle * s / seg
        rings.append([bm.verts.new((r * math.cos(a), r * math.sin(a), h)) for r, h in profile])
    plen = [0.0]
    for i in range(1, len(profile)):
        plen.append(plen[-1] + math.hypot(profile[i][0] - profile[i - 1][0], profile[i][1] - profile[i - 1][1]))
    rmax = max(r for r, _ in profile)
    for s in range(seg):
        a, b = rings[s], rings[(s + 1) % steps]
        for i in range(len(profile) - 1):
            r0, r1 = profile[i][0], profile[i + 1][0]
            if r0 < 1e-9 and r1 < 1e-9:
                continue
            if r0 < 1e-9:
                quad = [(a[i], s, i), (b[i + 1], s + 1, i + 1), (a[i + 1], s, i + 1)]
            elif r1 < 1e-9:
                quad = [(a[i], s, i), (b[i], s + 1, i), (a[i + 1], s, i + 1)]
            else:
                quad = [(a[i], s, i), (b[i], s + 1, i), (b[i + 1], s + 1, i + 1), (a[i + 1], s, i + 1)]
            if flip:
                quad.reverse()
            f = bm.faces.new([q[0] for q in quad])
            for loop, q in zip(f.loops, quad):
                loop[uv].uv = (q[1] / seg * angle * rmax / tile, plen[q[2]] / tile)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
    bm.normal_update()
    return bm


def pipe(points, r, seg=10, closed=False, tile=1.0, caps=True):
    """Rundes Rohr entlang einer 3D-Linie (gleichbleibender Radius oder Liste je Punkt)."""
    pts = [Vector(p) for p in points]
    n = len(pts)
    radii = r if isinstance(r, (list, tuple)) else [r] * n
    bm = bmesh.new()
    uv = _uv(bm)
    tangents = []
    for i in range(n):
        a = pts[i - 1] if (closed or i > 0) else pts[i]
        b = pts[(i + 1) % n] if (closed or i < n - 1) else pts[i]
        tangents.append((b - a).normalized())
    ref = Z if abs(tangents[0].z) < 0.9 else Vector((1, 0, 0))
    normal = (ref - tangents[0] * ref.dot(tangents[0])).normalized()
    rings = []
    length = [0.0]
    for i in range(n):
        t = tangents[i]
        normal = (normal - t * normal.dot(t)).normalized()
        binormal = t.cross(normal)
        rings.append([bm.verts.new(pts[i] + (normal * math.cos(TAU * k / seg) + binormal * math.sin(TAU * k / seg)) * radii[i])
                      for k in range(seg)])
        if i > 0:
            length.append(length[-1] + (pts[i] - pts[i - 1]).length)
    if closed:
        length.append(length[-1] + (pts[0] - pts[-1]).length)
    circ = TAU * max(radii)
    for i in range(n if closed else n - 1):
        j = (i + 1) % n
        for k in range(seg):
            k1 = (k + 1) % seg
            f = bm.faces.new((rings[i][k], rings[i][k1], rings[j][k1], rings[j][k]))
            uvs = [(k, i), (k + 1, i), (k + 1, i + 1), (k, i + 1)]
            for loop, (kk, ii) in zip(f.loops, uvs):
                loop[uv].uv = (length[ii] / tile, kk / seg * circ / tile)
    if caps and not closed:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bm.normal_update()
    return bm


def ngon(points, flip=False, tile=1.0, uv_axes=(0, 1)):
    """Ebene Fläche aus einem Umriss (gegen den Uhrzeigersinn von der Sichtseite aus)."""
    bm = bmesh.new()
    uv = _uv(bm)
    vs = [bm.verts.new(Vector(p)) for p in points]
    if flip:
        vs.reverse()
    f = bm.faces.new(vs)
    for loop in f.loops:
        c = loop.vert.co
        loop[uv].uv = (c[uv_axes[0]] / tile, c[uv_axes[1]] / tile)
    bm.normal_update()
    return bm


def quad(p0, p1, p2, p3, uvs=None):
    """Einzelnes Viereck (Reihenfolge gegen den Uhrzeigersinn von der Sichtseite)."""
    bm = bmesh.new()
    uv = _uv(bm)
    f = bm.faces.new([bm.verts.new(Vector(p)) for p in (p0, p1, p2, p3)])
    if uvs:
        for loop, t in zip(f.loops, uvs):
            loop[uv].uv = t
    return bm


def loft(loops, closed=True, tile=1.0):
    """Verbindet aufeinanderfolgende Punktringe (gleiche Punktzahl) mit Vierecken.
    Ausrichtung: Ringe gegen den Uhrzeigersinn um die Laufrichtung → Flächen nach außen."""
    bm = bmesh.new()
    uv = _uv(bm)
    rings = [[bm.verts.new(Vector(p)) for p in loop] for loop in loops]
    n = len(loops[0])
    for a, b in zip(rings, rings[1:]):
        for k in range(n if closed else n - 1):
            k1 = (k + 1) % n
            f = bm.faces.new((a[k], a[k1], b[k1], b[k]))
            for loop in f.loops:
                c = loop.vert.co
                loop[uv].uv = ((c.x + c.y) / tile, c.z / tile)
    bm.normal_update()
    return bm


def box(size_g, center_g, tile=1.0, uv_rot=False):
    """Quader in Godot-Koordinaten (Breite, Höhe, Tiefe)."""
    return geo.gbox(size_g, center_g, tile, uv_rot)


def join(*bms):
    return geo.merge(*bms)


def move(bm, v):
    return geo.translate(bm, Vector(v))


def rot(bm, angle, axis="Z", center=(0, 0, 0)):
    c = Vector(center)
    return geo.transform(bm, Matrix.Translation(c) @ Matrix.Rotation(angle, 4, axis) @ Matrix.Translation(-c))


def scale(bm, v):
    bmesh.ops.scale(bm, vec=Vector(v), verts=bm.verts)
    return bm


def planar_uv(bm, tile=1.0, axes=(0, 1)):
    uv = _uv(bm)
    for f in bm.faces:
        for loop in f.loops:
            c = loop.vert.co
            loop[uv].uv = (c[axes[0]] / tile, c[axes[1]] / tile)
    return bm


def face_room(bm, direction):
    """Dreht alle Flächen um, falls sie im Mittel von `direction` wegzeigen (offene Flächen)."""
    bm.normal_update()
    d = Vector(direction)
    if sum(f.normal.dot(d) * f.calc_area() for f in bm.faces) < 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    return bm


def outward(bm):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def empty(name, col, loc_g=(0, 0, 0), rot_y=0.0, rot_x=0.0, parent=None, size=0.05, scale_=1.0):
    """Leerer Knoten (in Godot ein Node3D): Drehpunkt für bewegliche Teile oder Gruppe.
    Ort und Drehung in Godot-Koordinaten (rot_y um die Hochachse, rot_x um die Querachse)."""
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = size
    col.objects.link(e)
    e.location = G(*loc_g)
    e.rotation_euler = (rot_x, 0.0, rot_y)
    e.scale = (scale_, scale_, scale_)
    if parent is not None:
        e.parent = parent
    return e


def ob(name, bm, material, col, parent=None, smooth=True, sharp=40.0, bevel=0.0, seg=2, shadow=True):
    """BMesh → Objekt. Koordinaten des BMesh sind lokal zum Elternknoten."""
    o = geo.to_object(name, bm, material, col, smooth=smooth, sharp_angle=sharp, bevel=bevel, bevel_segments=seg)
    if bevel > 0.0:
        wn = o.modifiers.new("Normalen", "WEIGHTED_NORMAL")
        wn.keep_sharp = True
    if parent is not None:
        o.parent = parent
    if not shadow:
        o.visible_shadow = False
    return o


def ob_multi(name, parts, col, parent=None, sharp=40.0):
    """Ein Objekt mit mehreren Materialien: parts = [(BMesh, Material), ...]."""
    out = bmesh.new()
    mats = []
    for bm, material in parts:
        me = bpy.data.meshes.new("_tmp")
        bm.to_mesh(me)
        bm.free()
        before = len(out.faces)
        out.from_mesh(me)
        bpy.data.meshes.remove(me)
        out.faces.ensure_lookup_table()
        for f in out.faces[before:]:
            f.material_index = len(mats)
        mats.append(material)
    o = ob(name, out, mats[0], col, parent, sharp=sharp)
    for material in mats[1:]:
        o.data.materials.append(material)
    return o


def gl(x, y, z):
    """Godot-Punkt → Blender (wie geo.G, kurz)."""
    return Vector((x, -z, y))


def circle(cx, cz, r, a0, a1, n):
    """Kreisbogen in der Blender-XZ-Ebene (Frontansicht), Winkel in Bogenmaß."""
    return [(cx + math.cos(a0 + (a1 - a0) * i / n) * r, cz + math.sin(a0 + (a1 - a0) * i / n) * r) for i in range(n + 1)]


def superellipse(a, b, n, steps, a0=0.0, a1=PI):
    """Punkte einer Superellipse (weiche Kissenform)."""
    out = []
    e = 2.0 / n
    for i in range(steps + 1):
        t = a0 + (a1 - a0) * i / steps
        c, s = math.cos(t), math.sin(t)
        out.append((math.copysign(abs(c) ** e, c) * a, math.copysign(abs(s) ** e, s) * b))
    return out


def stadium(straight, r, seg=40):
    """Stadion-Umriss in der Blender-XY-Ebene, gegen den Uhrzeigersinn (von oben)."""
    cx = straight * 0.5
    pts = []
    for i in range(seg + 1):
        a = -PI * 0.5 + PI * i / seg
        pts.append(Vector((cx + math.cos(a) * r, math.sin(a) * r, 0.0)))
    for i in range(seg + 1):
        a = PI * 0.5 + PI * i / seg
        pts.append(Vector((-cx + math.cos(a) * r, math.sin(a) * r, 0.0)))
    return pts


def rect_path(x0, x1, z0, z1, y, clockwise=False):
    """Rechteck in einer senkrechten Ebene (Blender XZ bei festem y)."""
    pts = [Vector((x0, y, z0)), Vector((x1, y, z0)), Vector((x1, y, z1)), Vector((x0, y, z1))]
    if clockwise:
        pts.reverse()
    return pts


def panel_moulding(x0, x1, z0, z1, y, profile, tile=1.0):
    """Profil rund um ein Rechteck auf einer Fläche, die zum Spieler (-Y) zeigt.
    profile = [(nach innen, Vorsprung), ...]."""
    # im Uhrzeigersinn (vom Raum aus gesehen) → „außen“ des Sweeps zeigt zur Rechteckmitte
    path = [Vector((x1, y, z0)), Vector((x0, y, z0)), Vector((x0, y, z1)), Vector((x1, y, z1))]
    return sweep(path, profile, closed=True, tile=tile, up=FRONT, flip=True)


# =====================================================================================
#  Pokertisch
# =====================================================================================

def build_table(col, m):
    y = TABLE_Y
    root = empty("Tisch", col)
    straight = FELT[0] - FELT[1]
    r = FELT[1] * 0.5  # Filzkante

    # Filz: eine ebene Fläche knapp unter TABLE_Y (Karten liegen auf TABLE_Y)
    felt = ngon([p + Z * (y - 0.0006) for p in stadium(straight, r + 0.008, 48)])
    ob("Filz", felt, m["Filz"], col, root, smooth=False)

    # gepolsterter Lederrand: Kissenprofil statt Röhre, außen unten eingeschlagen
    base = [p + Z * y for p in stadium(straight, r, 48)]
    cushion = [(0.05 + px, -0.004 + pz) for px, pz in superellipse(0.05, 0.062, 2.6, 22)]
    rail = [(0.091, -0.036), (0.0975, -0.031), (0.1005, -0.020)] + cushion
    ob("Lederrand", sweep(base, rail, tile=1.0), m["Leder"], col, root)
    # Keder (Lederwulst) in der Fuge zwischen Polster und Holz
    welt = pipe([p + Z * (y - 0.0335) for p in stadium(straight, r + 0.1005, 48)], 0.0036, 8, closed=True)
    ob("Keder", welt, m["Leder"], col, root)

    # Holzzarge mit Profil (Wulst oben, Hohlkehle, Stab unten); Maserung läuft um den Tisch
    apron = [(0.099, -0.135), (0.105, -0.1335), (0.1092, -0.128), (0.110, -0.121), (0.1078, -0.1145),
             (0.1042, -0.111), (0.103, -0.107), (0.103, -0.059), (0.1042, -0.053), (0.1075, -0.047),
             (0.1104, -0.042), (0.1104, -0.038), (0.108, -0.0348), (0.090, -0.0348)]
    zarge = sweep(base, apron, tile=1.0)
    under = ngon([p + Z * (y - 0.135) for p in stadium(straight, r + 0.099, 48)], flip=True)
    ob("Zarge", join(zarge, under), m["Tischholz"], col, root, sharp=50)

    # goldene Ziernaht auf dem Filz (flach gewölbt, Oberkante wie bisher 0,4 mm über dem Filz)
    seam_path = [p + Z * y for p in stadium(straight, r - 0.04, 48)]
    seam = [(0.003, -0.0006), (0.0026, 0.0001), (0.0012, 0.0004), (-0.0012, 0.0004), (-0.0026, 0.0001), (-0.003, -0.0006)]
    ob("Ziernaht", sweep(seam_path, seam), m["Gold"], col, root)

    # zwei gedrechselte Säulenfüße auf gestuften Sockelplatten
    leg = [(0.0, 0.05), (0.128, 0.05), (0.132, 0.062), (0.124, 0.078), (0.104, 0.088), (0.098, 0.10),
           (0.108, 0.14), (0.116, 0.20), (0.108, 0.27), (0.092, 0.34), (0.082, 0.40), (0.080, 0.43),
           (0.090, 0.445), (0.090, 0.46), (0.080, 0.47), (0.084, 0.56), (0.092, 0.62), (0.104, 0.655),
           (0.108, 0.68), (0.0, 0.68)]
    parts = []
    for s in (-1.0, 1.0):
        parts.append(move(lathe(leg, 32, 1.0), gl(s * 0.55, 0, 0)))
    ob("Tischfuesse", join(*parts), m["Tischholz"], col, root, sharp=35)
    plates = []
    for s in (-1.0, 1.0):
        plates.append(box((0.5, 0.03, 0.6), (s * 0.55, 0.015, 0)))
        plates.append(box((0.44, 0.022, 0.54), (s * 0.55, 0.039, 0)))
    ob("Fussplatten", join(*plates), m["Tischholz"], col, root, smooth=True, bevel=0.006, seg=3)
    return root


# =====================================================================================
#  Wände: Vertäfelung und Leisten
# =====================================================================================

def _wainscot(length, n):
    """Rahmen und Füllungen einer Wand (lokal: X entlang der Wand, Z hoch, Raum bei -Y)."""
    y0 = -0.04  # Vorderseite des Rahmens
    z_lo, z_hi = 0.14, 0.975
    hz0, hz1 = 0.22, 0.82
    parts = []
    for k in range(n):
        xb0 = -length * 0.5 + k * length / n
        xb1 = xb0 + length / n
        xc = (xb0 + xb1) * 0.5
        hw = (length / n - 0.12) * 0.5
        hx0, hx1 = xc - hw, xc + hw
        # Rahmen: links/rechts senkrechte Friese (Maserung hoch), oben/unten Querfriese
        for xa, xb in ((xb0, hx0), (hx1, xb1)):
            parts.append(quad((xa, y0, z_lo), (xb, y0, z_lo), (xb, y0, z_hi), (xa, y0, z_hi),
                              [(z_lo, xa), (z_lo, xb), (z_hi, xb), (z_hi, xa)]))
        for za, zb in ((z_lo, hz0), (hz1, z_hi)):
            parts.append(quad((hx0, y0, za), (hx1, y0, za), (hx1, y0, zb), (hx0, y0, zb),
                              [(hx0, za), (hx1, za), (hx1, zb), (hx0, zb)]))
        # Füllung: Nut, kleiner Stab, lange Fase, erhabenes Feld
        prof = [(0.0, 0.040), (0.002, 0.0385), (0.004, 0.031), (0.011, 0.031), (0.014, 0.036),
                (0.019, 0.039), (0.024, 0.039), (0.052, 0.051), (0.056, 0.052)]
        parts.append(panel_moulding(hx0, hx1, hz0, hz1, 0.0, prof))
        i = 0.056
        parts.append(quad((hx0 + i, -0.052, hz0 + i), (hx1 - i, -0.052, hz0 + i), (hx1 - i, -0.052, hz1 - i), (hx0 + i, -0.052, hz1 - i),
                          [(hz0 + i, hx0 + i), (hz0 + i, hx1 - i), (hz1 - i, hx1 - i), (hz1 - i, hx0 + i)]))
    return join(*parts)


def build_walls(col, m, root):
    # Lauf der Leisten: linke Wand → Rückwand → rechte Wand (innen entlang, Ecken auf Gehrung)
    hw = ROOM_W * 0.5
    per = [gl(-hw, 0, 3.7), gl(-hw, 0, BACK_Z), gl(hw, 0, BACK_Z), gl(hw, 0, 3.7)]
    base = [(0.0, 0.0), (0.06, 0.0), (0.06, 0.085), (0.057, 0.094), (0.050, 0.100), (0.047, 0.104),
            (0.046, 0.118), (0.043, 0.130), (0.040, 0.138), (0.040, 0.14)]
    cove = [(0.022 + 0.048 * (1 - math.cos(t)), 2.848 + 0.107 * math.sin(t)) for t in [PI * 0.5 * i / 8 for i in range(9)]]
    crown = [(0.0, 2.826), (0.014, 2.826), (0.018, 2.832), (0.018, 2.842)] + cove + \
            [(0.074, 2.958), (0.078, 2.964), (0.080, 2.972), (0.080, 3.0), (0.0, 3.0)]
    wood = [sweep(per, base, closed=False), sweep(per, crown, closed=False)]
    walls = [((0, 0, BACK_Z), ROOM_W, 0.0), ((-hw, 0, 0.7), 6.0, PI * 0.5), ((hw, 0, 0.7), 6.0, -PI * 0.5)]
    for pos, length, ang in walls:
        w = _wainscot(length, int(length / 0.7))
        geo.transform(w, Matrix.Translation(gl(*pos)) @ Matrix.Rotation(ang, 4, "Z"))
        wood.append(w)
    ob("Vertaefelung", join(*wood), m["Holz"], col, root, sharp=30)

    chair = [(0.040, 0.972), (0.046, 0.974), (0.050, 0.980), (0.056, 0.984), (0.062, 0.992), (0.064, 1.000),
             (0.062, 1.008), (0.056, 1.016), (0.050, 1.019), (0.046, 1.024), (0.0, 1.026)]
    bead = [(0.0, 2.796), (0.016, 2.796), (0.024, 2.800), (0.028, 2.810), (0.024, 2.820), (0.016, 2.824), (0.014, 2.826)]
    ob("Zierleisten", join(sweep(per, chair, closed=False), sweep(per, bead, closed=False)), m["Gold"], col, root, sharp=50)


# =====================================================================================
#  Vorhänge und Querbehang
# =====================================================================================

def _smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def _curtain(side):
    """Schwerer Samtvorhang mit echten Falten, am Raffhalter (y = 1,05) gerafft."""
    width, height = 0.50, CEIL - 0.25
    nu, nv, folds = 132, 48, 6
    x_wall = side * 1.985
    z0 = BACK_Z + 0.135
    bm = bmesh.new()
    uv = _uv(bm)
    grid = []
    for j in range(nv + 1):
        yy = 0.012 + (height - 0.012) * j / nv
        if yy >= 1.05:
            w = 0.52 + 0.48 * _smooth((yy - 1.05) / 1.15)
        else:
            w = 0.52 + 0.30 * _smooth((1.05 - yy) / 0.85)
        bunch = math.exp(-((yy - 1.05) / 0.16) ** 2)
        row = []
        for i in range(nu + 1):
            u = i / nu
            phase = TAU * folds * u + 0.7 * math.sin(3.1 * u + 1.3 * side) + 0.25 * math.sin(yy * 2.3 + u * 5.0)
            amp = min(0.030 * (0.8 + 0.2 * math.sin(7.0 * u + 2.0)) / (w ** 0.7), 0.052)
            amp *= 1.0 - 0.35 * bunch  # im Raffhalter liegt der Stoff enger
            edge = _smooth(u / 0.04) * _smooth((1.0 - u) / 0.04)  # Säume laufen flach aus
            x = x_wall - side * (0.015 + u * width * w)
            z = z0 + amp * math.sin(phase) * (0.35 + 0.65 * edge) + 0.012 * bunch
            row.append(bm.verts.new(gl(x, yy, z)))
        grid.append(row)
    for j in range(nv):
        for i in range(nu):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            for loop, (ii, jj) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                loop[uv].uv = (ii / nu * width * 1.6, 0.012 + (height - 0.012) * jj / nv)
    return face_room(bm, FRONT)


def _tieback(side):
    """Raffhalter: doppelte Goldkordel um den gerafften Vorhang."""
    w_tie = 0.50 * 0.52
    cx = side * 1.985 - side * (0.015 + w_tie * 0.5)
    cz = BACK_Z + 0.142
    a, b = w_tie * 0.5 + 0.018, 0.062
    cords = []
    for dy in (-0.013, 0.013):
        pts = [gl(cx + math.cos(TAU * i / 48) * a, 1.05 + dy + 0.006 * math.sin(TAU * i / 48), cz + math.sin(TAU * i / 48) * b)
               for i in range(48)]
        cords.append(pipe(pts, 0.0115, 10, closed=True))
    return join(*cords)


def _pleat(x, period):
    s = math.sin(TAU * x / period)
    return math.tanh(1.7 * s) / math.tanh(1.7)


def build_curtains(col, m, root):
    velvet = [_curtain(-1.0), _curtain(1.0)]
    # Querbehang: Samtblende mit 30 Falten wie bisher (4,3 m breit, 0,34 m hoch)
    half = (ROOM_W - 0.1) * 0.5
    period = 0.145
    nx, ny = 30 * 14, 5
    top, bottom = CEIL - 0.20, CEIL - 0.54
    zc = BACK_Z + 0.2
    bm = bmesh.new()
    uv = _uv(bm)
    grid = []
    for j in range(ny + 1):
        v = j / ny
        yy = bottom + (top - bottom) * v
        row = []
        for i in range(nx + 1):
            x = -half + 2 * half * i / nx
            amp = 0.028 * (1.0 - 0.45 * v)
            row.append(bm.verts.new(gl(x, yy, zc + amp * _pleat(x + 0.03, period))))
        grid.append(row)
    for j in range(ny):
        for i in range(nx):
            f = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            for loop, (ii, jj) in zip(f.loops, ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))):
                loop[uv].uv = (ii / nx * 2 * half * 1.5, bottom + (top - bottom) * jj / ny)
    velvet.append(face_room(bm, FRONT))
    # Unterseite schließen (von unten sieht man sonst hinter den Stoff)
    under = bmesh.new()
    uvu = _uv(under)
    prev = None
    for i in range(nx + 1):
        x = -half + 2 * half * i / nx
        a = under.verts.new(gl(x, bottom, zc + 0.028 * _pleat(x + 0.03, period)))
        b = under.verts.new(gl(x, bottom, BACK_Z + 0.1))
        if prev is not None:
            f = under.faces.new((prev[0], prev[1], b, a))
            for loop in f.loops:
                loop[uvu].uv = (loop.vert.co.x * 1.5, loop.vert.co.y)
        prev = (a, b)
    velvet.append(face_room(under, Vector((0, 0, -1))))
    ob("Vorhaenge", join(*velvet), m["Samt"], col, root, sharp=None)

    # goldene Borte mit Fransen an der Unterkante: gerade vor den Falten wie die bisherige Leiste
    # (folgt sie den Falten, glänzt sie aus der Entfernung nur punktweise)
    zf = zc + 0.031
    path = [gl(-half, 0, zf), gl(half, 0, zf)]
    band = [(0.0, bottom - 0.006), (0.006, bottom - 0.006), (0.008, bottom), (0.008, bottom + 0.014),
            (0.006, bottom + 0.022), (0.0, bottom + 0.022)]
    fringe = [(0.0045, bottom - 0.04), (0.0065, bottom - 0.006)]
    gold = [sweep(path, band, closed=False), sweep(path, fringe, closed=False), _tieback(-1.0), _tieback(1.0)]
    ob("Borten", join(*gold), m["Gold"], col, root, sharp=60)


# =====================================================================================
#  Neonschild, Kronleuchter, Wandleuchter
# =====================================================================================

def sign_bulb_positions():
    """Glühbirnen ums Schild, genau wie bisher im Code (24 Stück, Lauf im Uhrzeigersinn)."""
    out = []
    per = 2.0 * (1.3 + 0.38)
    for i in range(24):
        d = i / 24.0 * per
        if d < 1.3:
            p = (-0.65 + d, 0.19)
        elif d < 1.68:
            p = (0.65, 0.19 - (d - 1.3))
        elif d < 2.98:
            p = (0.65 - (d - 1.68), -0.19)
        else:
            p = (-0.65, -0.19 + (d - 2.98))
        out.append(p)
    return out


def _bulb(r, neck=0.55, seg=14):
    """Kleine Glühbirne: Kugel mit kurzem Hals, Achse = Blender +Z, Mitte der Kugel im Ursprung."""
    prof = [(0.0, -r * 1.55), (r * neck, -r * 1.55), (r * neck, -r * 0.9)]
    for i in range(1, 9):
        a = -PI * 0.33 + (PI * 0.83) * i / 8
        prof.append((math.cos(a) * r, math.sin(a) * r))
    prof.append((0.0, r))
    return lathe(prof, seg, 0.05)


def build_sign(col, m, root):
    yc = 2.35
    wall = -BACK_Z  # Blender-y der Rückwand
    # Tafel (wie bisher 1,3 × 0,38 m) mit erhabenem Rahmen, in dessen Rinne die Birnen sitzen
    board = box((1.3, 0.38, 0.05), (0, yc, BACK_Z + 0.025))
    prof = [(-0.036, 0.0), (-0.036, 0.060), (-0.032, 0.068), (-0.026, 0.068), (-0.021, 0.058), (-0.018, 0.052),
            (0.018, 0.052), (0.021, 0.058), (0.026, 0.068), (0.032, 0.068), (0.036, 0.060), (0.036, 0.046)]
    frame = panel_moulding(-0.65, 0.65, yc - 0.19, yc + 0.19, wall, prof)
    ob("Neonschild", join(board, frame), m["Schild"], col, root, sharp=35)
    sockets = []
    for i, (px, py) in enumerate(sign_bulb_positions()):
        c = gl(px, yc + py, BACK_Z + 0.07)
        b = rot(_bulb(0.014), PI * 0.5, "X")  # Achse zum Spieler
        o = ob("Schildbirne_%02d" % i, b, m["Schildbirne"], col, root, shadow=False)
        o.location = c
        s = lathe([(0.0, 0.0), (0.0105, 0.0), (0.0105, 0.006), (0.0085, 0.008), (0.0, 0.008)], 12, 0.05)
        sockets.append(move(rot(s, PI * 0.5, "X"), c + Vector((0, 0.019, 0))))
    ob("Schild_Fassungen", join(*sockets), m["Gold"], col, root, shadow=False)


def _crystal(h=0.04, r=0.011, n=6):
    """Geschliffener Kristalltropfen (oben spitz, unten spitz, Gürtel etwas über der Mitte)."""
    bm = bmesh.new()
    top = bm.verts.new((0, 0, 0.0))
    upper = [bm.verts.new((math.cos(TAU * k / n) * r * 0.55, math.sin(TAU * k / n) * r * 0.55, -h * 0.18)) for k in range(n)]
    mid = [bm.verts.new((math.cos(TAU * (k + 0.5) / n) * r, math.sin(TAU * (k + 0.5) / n) * r, -h * 0.55)) for k in range(n)]
    bot = bm.verts.new((0, 0, -h))
    for k in range(n):
        k1 = (k + 1) % n
        bm.faces.new((top, upper[k], upper[k1]))
        bm.faces.new((upper[k], mid[k], upper[k1]))
        bm.faces.new((upper[k1], mid[k], mid[k1]))
        bm.faces.new((mid[k], bot, mid[k1]))
    outward(bm)
    geo.box_uv(bm, 0.05)
    return bm


def build_chandelier(col, m, root):
    c = (0, 2.4, -0.35)
    e = empty("Kronleuchter", col, c, parent=root, size=0.1)
    gold = []
    # Deckenrosette und Kette aus einzelnen Gliedern bis zur Decke
    top_h = CEIL - c[1]
    gold.append(lathe([(0.0, top_h - 0.036), (0.012, top_h - 0.036), (0.018, top_h - 0.028), (0.045, top_h - 0.014),
                       (0.06, top_h - 0.008), (0.062, top_h - 0.002), (0.062, top_h), (0.0, top_h)], 24, 0.2))
    link_len = 0.036
    zz = top_h - 0.034
    k = 0
    while zz - link_len > 0.215:
        pts = []
        for i in range(16):
            a = TAU * i / 16
            px = math.cos(a) * 0.0085
            pz = math.sin(a) * (link_len * 0.5 + 0.004)
            pts.append(Vector((px, 0, zz - link_len * 0.5 + pz)) if k % 2 == 0 else Vector((0, px, zz - link_len * 0.5 + pz)))
        gold.append(pipe(pts, 0.0028, 6, closed=True))
        zz -= link_len - 0.006
        k += 1
    # Mittelstück: gedrechselter Schaft mit Kugel unten
    body = [(0.0, -0.135), (0.012, -0.132), (0.02, -0.12), (0.02, -0.108), (0.011, -0.098), (0.016, -0.09),
            (0.034, -0.07), (0.05, -0.04), (0.052, -0.015), (0.04, 0.01), (0.024, 0.03), (0.018, 0.05),
            (0.03, 0.062), (0.03, 0.07), (0.016, 0.082), (0.012, 0.13), (0.02, 0.15), (0.02, 0.16),
            (0.008, 0.175), (0.006, 0.22), (0.0, 0.222)]
    gold.append(lathe(body, 24, 0.2))
    # Reif (Profilband) mit acht Armen zur Mitte
    ring = [(0.300, -0.012), (0.318, -0.012), (0.322, -0.006), (0.319, 0.0), (0.322, 0.006), (0.318, 0.012), (0.300, 0.012),
            (0.297, 0.006), (0.299, 0.0), (0.297, -0.006), (0.300, -0.012)]
    gold.append(lathe(ring, 64, 0.2))
    cup = [(0.0, 0.0), (0.008, 0.0), (0.011, 0.01), (0.022, 0.016), (0.024, 0.02), (0.016, 0.022), (0.013, 0.026),
           (0.013, 0.05), (0.0, 0.05)]
    flame = [(0.0, 0.05), (0.011, 0.05), (0.014, 0.058), (0.0125, 0.07), (0.007, 0.084), (0.002, 0.094), (0.0, 0.096)]
    flames = []
    crystals = []
    for kk in range(8):
        a = TAU * kk / 8.0
        px, pz = math.cos(a) * 0.31, math.sin(a) * 0.31
        gold.append(move(lathe(cup, 16, 0.1), gl(px, 0.008, pz)))
        flames.append(move(lathe(flame, 12, 0.1), gl(px, 0.008, pz)))
        # Arm von der Mitte zum Reif (leicht geschwungen), zwischen den Kerzen
        a2 = a + 0.2
        arm = []
        for i in range(13):
            t = i / 12
            rr = 0.03 + (0.305 - 0.03) * t
            arm.append(gl(math.cos(a2) * rr, 0.0 + 0.03 * math.sin(PI * t) * (1 - t) * 2.0 - 0.012 * math.sin(PI * t), math.sin(a2) * rr))
        gold.append(pipe(arm, 0.0045, 6, caps=False))
        for j in range(2):
            rr = 0.3 - j * 0.1
            top = -0.07 - j * 0.06 + 0.02
            p = gl(math.cos(a2) * rr, top, math.sin(a2) * rr)
            crystals.append(move(_crystal(), p))
            gold.append(pipe([p, gl(math.cos(a2) * rr, 0.012 * j, math.sin(a2) * rr)], 0.0009, 4, caps=False))
    ob("Kronleuchter_Gold", join(*gold), m["Gold"], col, e, shadow=False, sharp=40)
    ob("Kronleuchter_Kerzen", join(*flames), m["Kerzenlicht"], col, e, shadow=False)
    ob("Kronleuchter_Kristalle", join(*crystals), m["Kristall"], col, e, smooth=False, shadow=False)


def build_sconces(col, m, root):
    gold = []
    shades = []
    for s in (-1.0, 1.0):
        for zpos in (-1.4, 0.2):
            base = Vector(gl(s * (ROOM_W * 0.5 - 0.02), 1.75, zpos))
            g = []
            # Wandplatte: ovaler Schild mit Wulstrand, Achse zeigt in den Raum
            plate = [(0.0, 0.0), (0.05, 0.0), (0.052, 0.004), (0.048, 0.010), (0.04, 0.012), (0.03, 0.016), (0.012, 0.022), (0.0, 0.023)]
            p = scale(lathe(plate, 24, 0.1), (1.9, 1.0, 1.0))  # hochoval (nach dem Drehen)
            g.append(move(rot(p, PI * 0.5, "Y"), (-0.02, 0, 0)))  # Achse +Z → +X (in den Raum), Rückseite an der Wand
            # geschwungener Arm zum Schirm
            arm = [Vector((0.1 * t, 0.0, -0.04 + 0.07 * t * t - 0.02 * math.sin(PI * t))) for t in [i / 12 for i in range(13)]]
            g.append(pipe(arm, 0.006, 8))
            # Tülle und Messingränder des Schirms
            g.append(move(lathe([(0.0, 0.03), (0.018, 0.03), (0.026, 0.036), (0.012, 0.04), (0.0, 0.04)], 16, 0.1), (0.1, 0, 0)))
            g.append(move(lathe([(0.079, 0.04), (0.082, 0.04), (0.082, 0.045), (0.079, 0.045), (0.079, 0.04)], 24, 0.1), (0.1, 0, 0)))
            g.append(move(lathe([(0.049, 0.155), (0.052, 0.155), (0.052, 0.16), (0.049, 0.16), (0.049, 0.155)], 24, 0.1), (0.1, 0, 0)))
            # Stoffschirm (wie bisher oben 5 cm, unten 8 cm Radius, 12 cm hoch), innen und außen
            sh = join(lathe([(0.08, 0.042), (0.05, 0.158)], 24, 0.1), lathe([(0.048, 0.158), (0.078, 0.042)], 24, 0.1))
            sh = move(sh, (0.1, 0, 0))
            for part, bucket in ((join(*g), gold), (sh, shades)):
                if s > 0:
                    rot(part, PI, "Z")  # rechte Wand: nach links in den Raum
                bucket.append(move(part, base))
    ob("Wandleuchter", join(*gold), m["Gold"], col, root, sharp=40)
    ob("Wandleuchter_Schirme", join(*shades), m["Lampenschirm"], col, root, shadow=False)


# =====================================================================================
#  Deko auf dem Tisch: Würfel, Cocktailglas
# =====================================================================================

PIPS = {1: [(0, 0)], 2: [(-1, -1), (1, 1)], 3: [(-1, -1), (0, 0), (1, 1)], 4: [(-1, -1), (1, -1), (-1, 1), (1, 1)],
        5: [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)], 6: [(-1, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (1, 1)]}


def _die(size=0.017):
    """Würfel mit abgerundeten Kanten; Augen auf allen sechs Seiten (gegenüber = 7)."""
    h = size * 0.5
    cube = bmesh.new()
    bmesh.ops.create_cube(cube, size=size)
    geo.box_uv(cube, 0.05)
    pips = []
    # (Achse der Seite, Vorzeichen, Augenzahl): oben 5, unten 2, +X 3, -X 4, +Y 6, -Y 1
    for axis, sign, count in ((2, 1, 5), (2, -1, 2), (0, 1, 3), (0, -1, 4), (1, 1, 6), (1, -1, 1)):
        for u, v in PIPS[count]:
            disc = lathe([(0.0, 0.0), (0.0017, 0.0), (0.0013, 0.00025), (0.0, 0.0003)], 10, 0.01)
            move(disc, (u * 0.0045, v * 0.0045, h))
            if axis == 2 and sign < 0:
                rot(disc, PI, "X")
            elif axis == 0:
                rot(disc, sign * PI * 0.5, "Y")
            elif axis == 1:
                rot(disc, -sign * PI * 0.5, "X")
            pips.append(disc)
    return cube, join(*pips)


def build_table_deco(col, m, root):
    y = TABLE_Y
    cubes, dots = [], []
    for k in range(2):
        cube, pips = _die()
        for part, bucket in ((cube, cubes), (pips, dots)):
            if k == 1:
                rot(part, -PI * 0.5, "Y")  # die 3 nach oben
            rot(part, 0.5 + k * 0.9, "Z")
            bucket.append(move(part, gl(0.9 + k * 0.05, y + 0.0085, 0.08 + k * 0.03)))
    ob("Wuerfel", join(*cubes), m["Wuerfel"], col, root, bevel=0.0018, seg=3)
    ob("Wuerfelaugen", join(*dots), m["Wuerfelauge"], col, root, shadow=False)

    # Cocktailglas (Martini) mit Wandstärke, Drink und Olive
    g = gl(0.86, y, -0.28)
    glass = [(0.0, 0.0), (0.0246, 0.0), (0.0252, 0.0012), (0.024, 0.0026), (0.009, 0.004), (0.0035, 0.008),
             (0.0026, 0.02), (0.0026, 0.066), (0.004, 0.0722), (0.045, 0.1172), (0.0447, 0.1182), (0.0438, 0.1176),
             (0.0024, 0.0758), (0.0, 0.0755)]
    ob("Cocktailglas", move(lathe(glass, 32, 0.1), g), m["Glas"], col, root, shadow=False)
    drink = [(0.0, 0.0762), (0.0022, 0.0762), (0.0326, 0.1068), (0.0, 0.1068)]
    ob("Cocktail", move(lathe(drink, 32, 0.1), g), m["Drink"], col, root, shadow=False)
    olive = geo.ellipsoid(Vector((0.0085, 0.007, 0.007)), Vector((0, 0, 0)), 16, 10)
    ob("Olive", move(olive, g + Vector((0.004, 0, 0.094))), m["Olive"], col, root, shadow=False)
    pim = geo.ellipsoid(Vector((0.0022, 0.0034, 0.0034)), Vector((0.0072, 0, 0)), 8, 6)
    ob("Olive_Paprika", move(pim, g + Vector((0.004, 0, 0.094))), m["Paprika"], col, root, shadow=False)


# =====================================================================================
#  Raum zusammensetzen
# =====================================================================================

def build_room(col, m):
    build_table(col, m)
    root = empty("Raum", col)
    build_walls(col, m, root)
    build_curtains(col, m, root)
    build_sign(col, m, root)
    build_chandelier(col, m, root)
    build_sconces(col, m, root)
    deko = empty("Tischdeko", col)
    build_table_deco(col, m, deko)


# =====================================================================================
#  Spielautomat (Maße wie slot_machine.gd)
# =====================================================================================

SLOT_W = 0.46
SLOT_D = 0.36
SLOT_BASE_H = 0.55
SLOT_BODY_H = 0.78
SLOT_REEL_Y = SLOT_BASE_H + 0.5


def slot_bulb_positions():
    top = SLOT_BASE_H + SLOT_BODY_H
    out = []
    for i in range(13):
        a = PI * (0.06 + 0.88 * i / 12.0)
        out.append((math.cos(a) * (SLOT_W * 0.5 - 0.03), top + math.sin(a) * (SLOT_W * 0.5 - 0.03), SLOT_D * 0.5 + 0.012))
    return out


def build_slot_machine(col, m):
    W, D, BASE_H, BODY_H, REEL_Y = SLOT_W, SLOT_D, SLOT_BASE_H, SLOT_BODY_H, SLOT_REEL_Y
    top = BASE_H + BODY_H
    fz = D * 0.5
    root = empty("Automat", col, size=0.2)

    # Holzsockel: Plinthe, Korpus, Deckplatte – mit aufgesetzten Zierrahmen vorn und an den Seiten
    wood = [box((W + 0.085, 0.07, D + 0.085), (0, 0.035, 0)),
            box((W + 0.06, BASE_H - 0.09, D + 0.06), (0, 0.07 + (BASE_H - 0.09) * 0.5, 0)),
            box((W + 0.08, 0.02, D + 0.08), (0, BASE_H - 0.01, 0))]
    ob("Sockel", join(*wood), m["Sockelholz"], col, root, bevel=0.005, seg=2)
    ogee = [(0.0, 0.0), (0.002, 0.006), (0.006, 0.009), (0.011, 0.009), (0.014, 0.006), (0.018, 0.0045), (0.022, 0.004), (0.024, 0.0)]
    frames = [panel_moulding(-0.19, 0.19, 0.13, 0.47, -(D + 0.06) * 0.5, ogee)]
    for sgn in (-1.0, 1.0):
        frames.append(rot(panel_moulding(-0.14, 0.14, 0.13, 0.47, -(W + 0.06) * 0.5, ogee), sgn * PI * 0.5, "Z"))
    ob("Sockel_Zierrahmen", join(*frames), m["Sockelholz"], col, root, sharp=30)
    # Messingleiste zwischen Sockel und Gehäuse
    a, b = (W + 0.05) * 0.5, (D + 0.05) * 0.5
    path = [Vector((-a, -b, BASE_H)), Vector((a, -b, BASE_H)), Vector((a, b, BASE_H)), Vector((-a, b, BASE_H))]
    strip = [(0.0, -0.01), (0.008, -0.01), (0.012, -0.006), (0.013, 0.0), (0.012, 0.006), (0.008, 0.01), (-0.04, 0.01)]
    ob("Sockelleiste", sweep(path, strip), m["Messing"], col, root, sharp=50)

    # Gehäuse: Grabstein-Umriss (Kasten mit rundem Kopf) aus einem Stück, Kanten gerundet
    outline = [(-W * 0.5, BASE_H), (W * 0.5, BASE_H)] + circle(0.0, top, W * 0.5, 0.0, PI, 32)
    body = bmesh.new()
    front = [body.verts.new((x, -fz, z)) for x, z in outline]
    back = [body.verts.new((x, fz, z)) for x, z in outline]
    body.faces.new(front)
    body.faces.new(list(reversed(back)))
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        body.faces.new((front[i], back[i], back[j], front[j]))
    geo.box_uv(body, 1.0)
    ob("Gehaeuse", body, m["Lack"], col, root, bevel=0.008, seg=3)
    # Chromleiste folgt vorn dem Umriss (Seiten und Bogen)
    trim = [Vector((-W * 0.5, -fz - 0.001, BASE_H + 0.012))] + \
           [Vector((x, -fz - 0.001, z)) for x, z in reversed(circle(0.0, top, W * 0.5, 0.0, PI, 32))] + \
           [Vector((W * 0.5, -fz - 0.001, BASE_H + 0.012))]
    chrome = [pipe(trim, 0.0115, 10)]

    # Schild im Kopf (Schrift bleibt ein Label3D im Spiel) mit Chromrahmen
    plate = box((0.335, 0.1, 0.01), (0, top + 0.06, fz + 0.002))
    ob("Schild", plate, m["Dunkel"], col, root, bevel=0.0015, seg=2)
    px, pz0, pz1, py = 0.1675, top + 0.01, top + 0.11, -(fz + 0.0065)
    chrome.append(pipe([Vector((-px, py, pz0)), Vector((px, py, pz0)), Vector((px, py, pz1)), Vector((-px, py, pz1))], 0.0032, 6, closed=True))

    # Lauflicht: 13 Birnen als eigene Teile (jede bekommt im Spiel ihr eigenes Leuchtmaterial)
    for i, (bx, by, bz) in enumerate(slot_bulb_positions()):
        o = ob("Birne_%02d" % i, rot(_bulb(0.011, seg=12), PI * 0.5, "X"), m["Birne"], col, root, shadow=False)
        o.location = gl(bx, by, bz)
        sock = lathe([(0.0, 0.0), (0.0145, 0.0), (0.0145, 0.004), (0.0115, 0.0075), (0.0, 0.0075)], 12, 0.05)
        chrome.append(move(rot(sock, PI * 0.5, "X"), gl(bx, by, fz)))

    # Walzenfenster: vorspringende dunkle Haube mit gefasten Kanten und schräger Laibung
    win_w, win_h, depth = W * 0.8, 0.17, 0.065
    ox, oz0, oz1 = win_w * 0.5 + 0.03, REEL_Y - win_h * 0.5 - 0.09, REEL_Y + win_h * 0.5 + 0.09
    hx, hz0, hz1 = win_w * 0.5, REEL_Y - win_h * 0.5, REEL_Y + win_h * 0.5
    yf = -(fz + depth)

    def ring(x, z0, z1, yy):
        return [(-x, yy, z0), (x, yy, z0), (x, yy, z1), (-x, yy, z1)]

    hood = loft([ring(ox, oz0, oz1, -fz + 0.004), ring(ox, oz0, oz1, yf + 0.012), ring(ox - 0.012, oz0 + 0.012, oz1 - 0.012, yf),
                 ring(hx, hz0, hz1, yf), ring(hx - 0.003, hz0 + 0.003, hz1 - 0.003, yf + 0.0045)])
    geo.box_uv(hood, 0.5)
    dividers = [box((0.006, win_h, 0.011), (sgn * win_w / 6.0, REEL_Y, fz + depth - 0.0105)) for sgn in (-1.0, 1.0)]
    ob("Fensterhaube", join(hood, *dividers), m["Dunkel"], col, root, sharp=30, bevel=0.0012, seg=2)
    bar = [(-0.016, 0.0), (-0.0145, 0.004), (-0.011, 0.0065), (-0.008, 0.0072), (-0.005, 0.0065), (-0.0015, 0.004), (0.0, 0.0)]
    chrome.append(panel_moulding(-hx, hx, hz0, hz1, yf, bar))
    glass = quad((-hx + 0.002, yf + 0.0035, hz0 + 0.002), (hx - 0.002, yf + 0.0035, hz0 + 0.002),
                 (hx - 0.002, yf + 0.0035, hz1 - 0.002), (-hx + 0.002, yf + 0.0035, hz1 - 0.002), [(0, 0), (1, 0), (1, 1), (0, 1)])
    ob("Fensterglas", glass, m["Fensterglas"], col, root, smooth=False, shadow=False)
    ob("Gewinnlinie", box((win_w - 0.004, 0.003, 0.001), (0, REEL_Y, fz + depth - 0.0025)), m["Gewinnlinie"], col, root, smooth=False, shadow=False)

    # Münzschale: Chromwanne mit runder Lippe, innen dunkel
    t0, t1 = Vector((-W * 0.35, -fz, 0.0)), Vector((W * 0.35, -fz, 0.0))
    shell = [(0.0, 0.585), (0.06, 0.585), (0.072, 0.592), (0.078, 0.605), (0.078, 0.635), (0.074, 0.643), (0.068, 0.643), (0.066, 0.636)]
    inner = [(0.066, 0.636), (0.064, 0.612), (0.05, 0.602), (0.0, 0.602)]
    chrome.append(sweep([t0, t1], shell, closed=False))
    full = shell + inner[1:]
    chrome.append(ngon([Vector((t0.x, -fz - o, h)) for o, h in full]))
    chrome.append(ngon([Vector((t1.x, -fz - o, h)) for o, h in full], flip=True))
    dark = [sweep([t0, t1], inner, closed=False)]

    # Münzschlitz und drei Knöpfe zwischen Fenster und Schale
    by = 0.80
    chrome.append(box((0.07, 0.034, 0.005), (W * 0.28, by, fz + 0.0025)))
    dark.append(box((0.046, 0.006, 0.002), (W * 0.28, by, fz + 0.0052)))
    bezel = [(0.0, 0.0), (0.0215, 0.0), (0.0215, 0.004), (0.0185, 0.0065), (0.0165, 0.0065), (0.0165, 0.0)]
    cap = [(0.0, 0.0), (0.0155, 0.0), (0.0155, 0.008), (0.0135, 0.0115), (0.008, 0.0135), (0.0, 0.014)]
    for k, name in enumerate(("Knopf_Rot", "Knopf_Gelb", "Knopf_Gruen")):
        pos = gl(-W * 0.25 + k * 0.05, by, fz)
        chrome.append(move(rot(lathe(bezel, 20, 0.05), PI * 0.5, "X"), pos))
        ob(name, move(rot(lathe(cap, 20, 0.05), PI * 0.5, "X"), pos), m[name], col, root, shadow=False)
    ob("Schale_Innen", join(*dark), m["Dunkel"], col, root, sharp=40)

    # Hebel: feste Lagerschale am Gehäuse, drehbar sind Nabe, Stange und Knauf (Knoten „Hebel“)
    pivot = (W * 0.5 + 0.035, REEL_Y - 0.08, 0.02)
    flange = lathe([(0.0, 0.0), (0.046, 0.0), (0.046, 0.004), (0.04, 0.01), (0.036, 0.013), (0.0, 0.013)], 24, 0.1)
    chrome.append(move(rot(flange, PI * 0.5, "Y"), gl(W * 0.5, pivot[1], pivot[2])))
    ob("Chromteile", join(*chrome), m["Chrom"], col, root, sharp=40)
    lever = empty("Hebel", col, pivot, parent=root, size=0.08)
    hub = lathe([(0.0, 0.0), (0.03, 0.0), (0.034, 0.004), (0.034, 0.04), (0.03, 0.046), (0.022, 0.05), (0.012, 0.053),
                 (0.012, 0.057), (0.008, 0.06), (0.0, 0.06)], 24, 0.1)
    hub = move(rot(hub, PI * 0.5, "Y"), (-0.022, 0, 0))
    rod = lathe([(0.0, 0.0), (0.019, 0.0), (0.019, 0.035), (0.015, 0.045), (0.0138, 0.06), (0.011, 0.39),
                 (0.016, 0.395), (0.016, 0.405), (0.012, 0.41), (0.0, 0.41)], 16, 0.1)
    ob("Hebel_Chrom", join(hub, move(rod, (0.012, 0, 0))), m["Chrom"], col, lever, sharp=40)
    ball = geo.ellipsoid(Vector((0.04, 0.04, 0.04)), Vector((0.012, 0, 0.44)), 24, 16)
    ob("Hebel_Knauf", ball, m["Knauf"], col, lever)
    return root


# =====================================================================================
#  Tisch-Roulette (Maße wie mini_roulette.gd)
# =====================================================================================

ROULETTE_R = 0.08
POCKETS = 37


def build_roulette(col, m):
    R = ROULETTE_R
    root = empty("Roulette", col, size=0.1)
    # gedrechselte Holzschale mit Messingrand
    bowl = [(0.0, 0.0), (0.060, 0.0), (0.064, 0.0015), (0.066, 0.006), (0.0665, 0.010), (0.069, 0.013), (0.076, 0.022),
            (0.0795, 0.029), (0.080, 0.033), (0.0796, 0.0345), (0.0748, 0.0345), (0.0748, 0.0330), (0.0, 0.0330)]
    ob("Schale", lathe(bowl, 64, 1.0), m["Kesselholz"], col, root, sharp=50)
    rim = [(0.0796, 0.0340), (0.0802, 0.0355), (0.0796, 0.0372), (0.0780, 0.0380), (0.0762, 0.0376), (0.0750, 0.0365), (0.0748, 0.0345)]
    ob("Schale_Rand", lathe(rim, 64, 0.2), m["Kesselgold"], col, root)

    # drehender Kessel: Scheibe mit dem Zahlenbild, Fächer leicht vertieft, Stege, Ringe, Drehkreuz
    wheel = empty("Kessel", col, (0, 0.0335, 0), parent=root, size=0.05)
    disc = lathe([(0.93 * R, 0.002), (0.82 * R, 0.0), (0.672 * R, 0.0), (0.668 * R, -0.0008), (0.41 * R, -0.0008), (0.40 * R, 0.0004)], 148, 1.0)
    size = R * 1.86
    uv = _uv(disc)
    for f in disc.faces:
        for loop in f.loops:
            loop[uv].uv = (loop.vert.co.x / size + 0.5, loop.vert.co.y / size + 0.5)
    ob("Scheibe", disc, m["Scheibe"], col, wheel, sharp=None, shadow=False)
    cone = [(0.0325, -0.0008), (0.0325, 0.0012), (0.030, 0.0022), (0.02, 0.0052), (0.012, 0.0072), (0.0095, 0.0078), (0.0, 0.0078)]
    ob("Kessel_Mitte", lathe(cone, 48, 1.0), m["Kesselholz"], col, wheel, shadow=False)
    gold = [lathe([(0.0320, 0.0008), (0.0336, 0.0008), (0.0340, 0.0018), (0.0334, 0.0028), (0.0322, 0.0028), (0.0316, 0.0018), (0.0320, 0.0008)], 64, 0.1),
            lathe([(0.0528, -0.0002), (0.0544, -0.0002), (0.0548, 0.0012), (0.0542, 0.0024), (0.0530, 0.0024), (0.0524, 0.0012), (0.0528, -0.0002)], 96, 0.1)]
    step = TAU / POCKETS
    for p in range(POCKETS):
        a = PI * 0.5 - TAU * p / POCKETS + step * 0.5
        fret = geo.box(Vector((R * 0.26, 0.0011, 0.0038)), Vector((R * 0.54, 0.0, 0.0011)), 0.05)
        gold.append(rot(fret, a, "Z"))
    ob("Kessel_Stege", join(*gold), m["Steggold"], col, wheel, sharp=40, shadow=False)
    post = [(0.0, 0.0078), (0.0105, 0.0078), (0.0105, 0.0092), (0.008, 0.0105), (0.0065, 0.014), (0.006, 0.020),
            (0.0075, 0.0215), (0.0075, 0.0235), (0.005, 0.0255), (0.003, 0.0285), (0.0042, 0.0300), (0.0042, 0.0318), (0.0, 0.033)]
    cross = [lathe(post, 20, 0.05)]
    for k in range(2):
        d = Vector((1, 0, 0)) if k == 0 else Vector((0, 1, 0))
        cross.append(pipe([-d * 0.02 + Z * 0.0225, d * 0.02 + Z * 0.0225], 0.0022, 8))
        for sgn in (-1.0, 1.0):
            cross.append(geo.ellipsoid(Vector((0.0036, 0.0036, 0.0036)), d * 0.021 * sgn + Z * 0.0225, 10, 8))
    ob("Kessel_Drehkreuz", join(*cross), m["Kesselgold"], col, wheel, shadow=False)
    return root


# =====================================================================================
#  Bankerlampe (Maße wie banker_lamp.gd, unverkleinert – das Spiel skaliert auf 0,75)
# =====================================================================================

LAMP_SHADE_LEN = 0.26
LAMP_SHADE_R = 0.072
LAMP_SHADE_Y = 0.33


def _shade_surface(r, half, dome, inside=False, seg_phi=28, seg_dome=7):
    """Halber Zylinder (obere Hälfte) entlang X mit gewölbten Enden; lokal: X Länge, Z hoch, -Y vorn."""
    stations = []
    for i in range(seg_dome, 0, -1):
        psi = PI * 0.5 * i / seg_dome
        stations.append((-(half - dome) - dome * math.sin(psi), math.cos(psi)))
    stations += [(-(half - dome), 1.0), (half - dome, 1.0)]
    for i in range(1, seg_dome + 1):
        psi = PI * 0.5 * i / seg_dome
        stations.append((half - dome + dome * math.sin(psi), math.cos(psi)))
    bm = bmesh.new()
    uv = _uv(bm)
    rows = []
    for x, k in stations:
        rows.append([bm.verts.new((x, -math.cos(PI * j / seg_phi) * r * k, math.sin(PI * j / seg_phi) * r * k)) for j in range(seg_phi + 1)])
    for a, b in zip(rows, rows[1:]):
        for j in range(seg_phi):
            vs = [a[j], b[j], b[j + 1], a[j + 1]]
            if inside:
                vs.reverse()
            try:
                f = bm.faces.new(vs)
            except ValueError:
                continue
            for loop in f.loops:
                loop[uv].uv = (loop.vert.co.x * 4.0, loop.vert.co.z * 4.0)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bm.normal_update()
    return bm


def build_banker_lamp(col, m):
    root = empty("Lampe", col, size=0.1)
    brass = []
    # ovaler Fuß in zwei Stufen (auf der oberen sitzen im Spiel die roten Lämpchen)
    base = [(0.0, 0.0), (0.110, 0.0), (0.1155, 0.002), (0.117, 0.006), (0.1155, 0.012), (0.111, 0.0165), (0.104, 0.0195),
            (0.097, 0.0205), (0.094, 0.022), (0.094, 0.027), (0.091, 0.0325), (0.086, 0.0355), (0.08, 0.036), (0.0, 0.036)]
    brass.append(scale(lathe(base, 56, 0.2), (1.0, 0.62, 1.0)))
    # Säule mit Zierknauf und Ring, hinten auf dem Fuß (z = -0,02)
    column = [(0.03, 0.0355), (0.029, 0.04), (0.024, 0.05), (0.019, 0.06), (0.016, 0.066), (0.016, 0.0695), (0.0105, 0.073),
              (0.009, 0.078), (0.009, 0.086), (0.0125, 0.0875), (0.0185, 0.093), (0.0205, 0.10), (0.0185, 0.107),
              (0.0125, 0.1125), (0.009, 0.114), (0.0088, 0.214), (0.015, 0.2155), (0.0165, 0.22), (0.015, 0.2245),
              (0.0088, 0.226), (0.0088, 0.296), (0.0115, 0.298), (0.0115, 0.304), (0.0065, 0.311), (0.0, 0.313)]
    brass.append(move(lathe(column, 24, 0.2), gl(0, 0, -0.02)))
    # kurzer Bogen nach vorn in den Schirm
    brass.append(pipe([gl(0, 0.300, -0.02), gl(0, 0.314, -0.014), gl(0, 0.322, -0.002), gl(0, 0.3235, 0.016)], 0.0065, 8))
    ob("Lampenfuss", join(*brass), m["Lampenmessing"], col, root, sharp=35)

    # Schirm: grünes Glas außen, helle Innenseite, Messingrand um die Öffnung; leicht zum Spieler gekippt
    shade = empty("Schirm", col, (0, LAMP_SHADE_Y, 0.02), rot_x=0.28, parent=root, size=0.05)
    half, r, dome = LAMP_SHADE_LEN * 0.5, LAMP_SHADE_R, 0.022
    ob("Schirm_Glas", _shade_surface(r, half, dome), m["Glas_Gruen"], col, shade, sharp=None)
    ob("Schirm_Innen", _shade_surface(r * 0.955, half - 0.002, dome - 0.001, inside=True), m["Schirm_Innen"], col, shade, sharp=None, shadow=False)
    edge = []
    n = 16
    for i in range(n + 1):  # rechtes Ende, von vorn nach hinten
        psi = -PI * 0.5 + PI * i / n
        edge.append(Vector((half - dome + dome * math.cos(psi), math.sin(psi) * r, 0.0)))
    for i in range(n + 1):  # linkes Ende, von hinten nach vorn
        psi = PI * 0.5 + PI * i / n
        edge.append(Vector((-(half - dome) + dome * math.cos(psi), math.sin(psi) * r, 0.0)))
    trim = [pipe(edge, 0.0032, 8, closed=True)]
    # Fassung quer im Schirm, links und rechts je eine Röhrenbirne
    trim.append(pipe([Vector((-0.024, 0, -0.006)), Vector((0.024, 0, -0.006))], 0.0105, 12))
    ob("Schirm_Messing", join(*trim), m["Lampenmessing"], col, shade, sharp=40)
    bulbs = []
    for sgn in (-1.0, 1.0):
        prof = [(0.0, 0.0), (0.0085, 0.0), (0.0125, 0.004), (0.0135, 0.012), (0.0135, 0.048), (0.011, 0.056), (0.005, 0.0605), (0.0, 0.061)]
        bulbs.append(move(rot(lathe(prof, 14, 0.05), sgn * PI * 0.5, "Y"), (sgn * 0.024, 0, -0.006)))
    ob("Schirm_Birnen", join(*bulbs), m["Gluehbirne"], col, shade, shadow=False)

    # Zugkette: Kügelchen an einer feinen Schnur mit Messinggriff (Knoten „Kette“ bewegt sich im Spiel)
    chain = empty("Kette", col, parent=shade, size=0.03)
    cx, cz = LAMP_SHADE_LEN * 0.36, LAMP_SHADE_R * 0.55
    beads = [geo.ellipsoid(Vector((0.0035, 0.0035, 0.0035)), gl(cx, -0.012 - k * 0.0085, cz), 10, 6) for k in range(12)]
    beads.append(pipe([gl(cx, 0.03, cz), gl(cx, -0.112, cz)], 0.0009, 5, caps=False))
    grip = lathe([(0.0, -0.011), (0.008, -0.011), (0.0085, -0.008), (0.006, -0.002), (0.0045, 0.006), (0.004, 0.011), (0.0, 0.011)], 14, 0.05)
    beads.append(move(grip, gl(cx, -0.12, cz)))
    ob("Kette_Messing", join(*beads), m["Lampenmessing"], col, chain)

    # Vorlage für die Lämpchen (das Spiel setzt je Leben eines auf den Fuß)
    jewel = lathe([(0.0085, 0.0), (0.0075, 0.003), (0.0045, 0.0055), (0.0, 0.006)], 8, 0.02)
    ob("Juwel", jewel, m["Juwel"], col, root, smooth=False, shadow=False)
    bez = lathe([(0.0085, -0.0003), (0.0108, -0.0003), (0.0108, 0.0012), (0.0094, 0.0022), (0.0085, 0.0016)], 16, 0.02)
    ob("Juwel_Fassung", bez, m["Lampenmessing"], col, root, shadow=False)
    return root


# =====================================================================================
#  Szene, Kulisse, Export
# =====================================================================================

# =====================================================================================
#  Pokerchip (ersetzt im Casino die Goldmünzen; Maße wie TableProps._make_chip)
# =====================================================================================

def build_chip(col, m):
    root = empty("Pokerchip", col, size=0.03)
    body = lathe([(0.0, -0.0019), (0.0118, -0.0019), (0.0122, -0.0021), (0.0182, -0.0021), (0.019, -0.0015),
                  (0.019, 0.0015), (0.0182, 0.0021), (0.0122, 0.0021), (0.0118, 0.0019), (0.0, 0.0019)], 36, 0.02)
    white = [lathe([(0.0148, 0.00214), (0.0125, 0.00214)], 36, 0.02), lathe([(0.0125, -0.00214), (0.0148, -0.00214)], 36, 0.02)]
    insert = [(0.0155, -0.00215), (0.0182, -0.00215), (0.01905, -0.0015), (0.01905, 0.0015), (0.0182, 0.00215), (0.0155, 0.00215)]
    for k in range(6):  # sechs weiße Randeinlagen
        white.append(lathe(insert, 4, 0.02, angle=0.34, start=TAU * k / 6.0 - 0.17))
    ob_multi("Chip", [(body, m["Chipfarbe"]), (join(*white), m["Chipweiss"])], col, root, sharp=35)
    return root


def _clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.lights, bpy.data.cameras):
        for b in list(block):
            if b.users == 0:
                block.remove(b)


## Wo die Geräte im Raum stehen (nur für die Ansicht in Blender; im Spiel setzt sie der Code).
PLACES = {
    "Automat": ((-1.4, 0.0, -1.95), 0.3, 1.0),
    "Roulette": ((-0.58, TABLE_Y, 0.19), 0.0, 1.45),
    "Lampe": ((-0.78, TABLE_Y, -0.07), 0.5, 0.75),
    "Pokerchip": ((0.6, TABLE_Y + 0.0022, 0.24), 0.0, 1.0),
}
## Welche Wurzelknoten in welche Datei kommen
FILES = {
    "casino.glb": ["Tisch", "Raum", "Tischdeko"],
    "slot_machine.glb": ["Automat"],
    "roulette.glb": ["Roulette"],
    "banker_lamp.glb": ["Lampe"],
    "chip.glb": ["Pokerchip"],
}


def _place(placed=True):
    for name, (pos, yaw, sc) in PLACES.items():
        o = bpy.data.objects.get(name)
        if o is None:
            continue
        o.location = G(*pos) if placed else (0, 0, 0)
        o.rotation_euler = (0, 0, yaw if placed else 0.0)
        o.scale = (sc, sc, sc) if placed else (1, 1, 1)


def _tree(o):
    out = [o]
    for c in o.children:
        out += _tree(c)
    return out


def _preview(col, m):
    """Kulisse nur für Blender: Boden, Wände, Decke und der zweite (blaue) Automat."""
    carpet = mat("Preview_Teppich", (1, 1, 1), 0.95, tex=os.path.join(ROOM_TEX, "carpet.png"), scale=1.0)
    paper = mat("Preview_Tapete", (1, 1, 1), 0.85, tex=os.path.join(ROOM_TEX, "wallpaper.png"), scale=2.4)
    dark = mat("Preview_Decke", (0.09, 0.05, 0.04), 0.8)
    hw = ROOM_W * 0.5
    floor = ngon([gl(-hw, 0, 3.7), gl(hw, 0, 3.7), gl(hw, 0, BACK_Z), gl(-hw, 0, BACK_Z)])
    uv = _uv(floor)
    for f in floor.faces:
        for loop in f.loops:
            c = loop.vert.co
            loop[uv].uv = ((c.x / ROOM_W + 0.5) * 5.0, ((c.y + 0.7) / 6.0 + 0.5) * 5.0)
    ob("Preview_Boden", floor, carpet, col, smooth=False)
    ob("Preview_Decke", ngon([gl(-hw, CEIL, 3.7), gl(hw, CEIL, 3.7), gl(hw, CEIL, BACK_Z), gl(-hw, CEIL, BACK_Z)], flip=True), dark, col, smooth=False)
    walls = [quad(gl(-hw, 0, BACK_Z), gl(hw, 0, BACK_Z), gl(hw, CEIL, BACK_Z), gl(-hw, CEIL, BACK_Z), [(-hw, 0), (hw, 0), (hw, CEIL), (-hw, CEIL)]),
             quad(gl(-hw, 0, 3.7), gl(-hw, 0, BACK_Z), gl(-hw, CEIL, BACK_Z), gl(-hw, CEIL, 3.7), [(3.7, 0), (BACK_Z, 0), (BACK_Z, CEIL), (3.7, CEIL)]),
             quad(gl(hw, 0, BACK_Z), gl(hw, 0, 3.7), gl(hw, CEIL, 3.7), gl(hw, CEIL, BACK_Z), [(BACK_Z, 0), (3.7, 0), (3.7, CEIL), (BACK_Z, CEIL)])]
    ob("Preview_Waende", join(*walls), paper, col, smooth=False)
    # Licht ungefähr wie im Spiel, damit die Ansicht „Gerendert“ einen Eindruck gibt
    def lamp(name, kind, pos, color, power, **kw):
        data = bpy.data.lights.new(name, kind)
        data.color = lin(color)
        data.energy = power
        for k, v in kw.items():
            setattr(data, k, v)
        o = bpy.data.objects.new(name, data)
        col.objects.link(o)
        o.location = gl(*pos)
        return o
    lamp("Preview_Licht_Kronleuchter", "POINT", (0, 2.25, -0.2), (1.0, 0.81, 0.54), 60.0, shadow_soft_size=0.3)
    lamp("Preview_Licht_Gegenlicht", "POINT", (0, 1.9, -1.5), (0.82, 0.31, 0.24), 40.0, shadow_soft_size=0.2)
    lamp("Preview_Licht_Tisch", "SPOT", (0, 2.3, 0.3), (1.0, 0.9, 0.75), 120.0, spot_size=1.6, spot_blend=0.6)
    lamp("Preview_Licht_Schild", "POINT", (0, 2.35, BACK_Z + 0.35), (1.0, 0.29, 0.42), 12.0)
    for sgn in (-1.0, 1.0):
        for zpos in (-1.4, 0.2):
            lamp("Preview_Licht_Wand", "POINT", (sgn * 2.03, 1.85, zpos), (1.0, 0.66, 0.38), 8.0, shadow_soft_size=0.08)
    world = bpy.context.scene.world or bpy.data.worlds.new("Welt")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg is not None:
        bg.inputs["Color"].default_value = (0.012, 0.007, 0.008, 1.0)
    # Walzen (im Spiel baut sie der Code, weil sie sich drehen und das Walzenband tragen)
    automat = bpy.data.objects.get("Automat")
    if automat is not None:
        reel_mat = mat("Preview_Walzenband", (1, 1, 1), 0.45, tex=os.path.join(ROOM_TEX, "reels.png"))
        win_w = SLOT_W * 0.8
        reels = []
        for i in range(3):
            r = lathe([(0.1, -(win_w / 6.0 - 0.006)), (0.1, win_w / 6.0 - 0.006)], 40, 1.0)
            uvr = _uv(r)
            for f in r.faces:
                for loop in f.loops:
                    c = loop.vert.co
                    loop[uvr].uv = (c.z / (win_w / 3.0 - 0.012) + 0.5, (math.atan2(c.y, c.x) / TAU) % 1.0)
            for f in r.faces:  # Naht: Winkel 0/1 nicht quer über die Fläche ziehen
                vs = [loop[uvr].uv.y for loop in f.loops]
                if max(vs) - min(vs) > 0.5:
                    for loop in f.loops:
                        if loop[uvr].uv.y < 0.5:
                            loop[uvr].uv.y += 1.0
            rot(r, PI * 0.5, "Y")
            reels.append(move(r, gl((i - 1) * win_w / 3.0, SLOT_REEL_Y, SLOT_D * 0.5 + 0.065 - 0.012 - 0.1)))
        ob("Preview_Walzen", join(*reels), reel_mat, col, automat, sharp=None)
    # zweiter Automat rechts (im Spiel dasselbe Modell mit blauem Lack)
    src = bpy.data.objects.get("Automat")
    if src is not None:
        blue = mat("Preview_Lack_Blau", (0.1, 0.22, 0.42), 0.35)
        copies = {}
        for o in _tree(src):
            c = o.copy()
            c.name = "Preview_" + o.name
            col.objects.link(c)
            copies[o] = c
            if o.type == "MESH" and o.data.materials and o.data.materials[0] and o.data.materials[0].name == "Lack":
                c.data = o.data.copy()
                c.data.materials[0] = blue
        for o, c in copies.items():
            if o.parent in copies:
                c.parent = copies[o.parent]
        root = copies[src]
        root.location = G(1.4, 0.0, -1.95)
        root.rotation_euler = (0, 0, -0.3)


def build_all(preview=True):
    """Ganze Szene neu aufbauen (löscht alles in der aktuellen Datei)."""
    _clear()
    bpy.context.scene.unit_settings.system = "METRIC"
    m = M()
    build_room(geo.collection("Casino"), m)
    build_slot_machine(geo.collection("Automat"), m)
    build_roulette(geo.collection("Roulette"), m)
    build_banker_lamp(geo.collection("Bankerlampe"), m)
    build_chip(geo.collection("Pokerchip"), m)
    _place(True)
    if preview:
        _preview(geo.collection("Kulisse"), m)
    return "ok"


def export_all(out_dir=None):
    """Schreibt die vier .glb. Die Geräte werden dafür kurz in den Ursprung gestellt."""
    out_dir = out_dir or OUT_DIR
    os.makedirs(out_dir, exist_ok=True)
    _place(False)
    bpy.context.view_layer.update()
    written = []
    try:
        for filename, roots in FILES.items():
            for o in bpy.context.scene.objects:
                o.select_set(False)
            for name in roots:
                for o in _tree(bpy.data.objects[name]):
                    if not o.name.startswith("Preview_"):
                        o.select_set(True)
            path = os.path.join(out_dir, filename)
            bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                      export_yup=True, export_cameras=False, export_lights=False,
                                      export_texcoords=True, export_normals=True, export_image_format="NONE")
            written.append(path)
    finally:
        _place(True)
    return written
