"""Gemeinsame Bausteine für die Raum-Modelle (Casino, Bahnhof, U-Boot, Zirkuswagen).

Koordinaten in den Raum-Skripten sind Godot-Koordinaten (Y nach oben, +Z zum Spieler);
`gl()` rechnet nach Blender um. UVs sind in Metern, die Kachelung stellt das Material ein.

Grundsatz der Raum-Modelle: Blender liefert die Form, Godot ordnet die Materialien über
ihren NAMEN zu (RoomKit.model). Die .glb enthalten deshalb keine Bilder.
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
MODEL_TEX = os.path.join(REPO, "assets", "models")

PI = math.pi
TAU = math.tau
X = Vector((1, 0, 0))
Z = Vector((0, 0, 1))
FRONT = Vector((0, -1, 0))  # Godot +Z (zum Spieler) in Blender
TABLE_Y = 0.80


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


# =====================================================================================
#  Bausteine
# =====================================================================================

def uv_layer(bm):
    return bm.loops.layers.uv.verify()


def sweep(path, profile, closed=True, tile=1.0, up=Z, flip=False, caps=False):
    """Zieht ein Profil [(außen, hoch), ...] an einem Pfad entlang; Ecken werden auf Gehrung
    geschnitten. „außen“ zeigt nach rechts der Laufrichtung (t × up), „hoch“ entlang `up`.
    Profil gegen den Uhrzeigersinn (unten nach außen, außen hoch, oben nach innen) →
    Flächen zeigen nach außen; `flip` dreht sie um. UV: U am Pfad entlang, V ums Profil (Meter)."""
    pts = [Vector(p) for p in path]
    n = len(pts)
    up = Vector(up).normalized()
    bm = bmesh.new()
    uv = uv_layer(bm)
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
    if caps and not closed:  # offene Enden mit dem Profil verschließen
        for ring, rev in ((rings[0], flip), (rings[-1], not flip)):
            vs = list(ring)
            if (vs[0].co - vs[-1].co).length < 1e-9:
                vs.pop()
            if rev:
                vs.reverse()
            try:
                f = bm.faces.new(vs)
            except ValueError:
                continue
            for loop in f.loops:
                c = loop.vert.co
                loop[uv].uv = ((c.x + c.y) / tile, c.z / tile)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-9)
    bm.normal_update()
    return bm


def bar(path, width, thick, up=Z, tile=1.0):
    """Flachstab entlang einer Linie: `width` in der Ebene der Linie, `thick` entlang `up`."""
    w, t = width * 0.5, thick * 0.5
    return sweep(path, [(-w, -t), (w, -t), (w, t), (-w, t), (-w, -t)], closed=False, tile=tile, up=up, caps=True)


def lathe(profile, seg=32, tile=1.0, flip=False, angle=TAU, start=0.0):
    """Drehkörper um die Blender-Z-Achse. profile = [(radius, höhe), ...] gegen den Uhrzeigersinn
    (unten nach außen, außen hoch, oben nach innen) → Flächen zeigen nach außen."""
    bm = bmesh.new()
    uv = uv_layer(bm)
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
    uv = uv_layer(bm)
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
    uv = uv_layer(bm)
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
    uv = uv_layer(bm)
    f = bm.faces.new([bm.verts.new(Vector(p)) for p in (p0, p1, p2, p3)])
    if uvs:
        for loop, t in zip(f.loops, uvs):
            loop[uv].uv = t
    return bm


def loft(loops, closed=True, tile=1.0):
    """Verbindet aufeinanderfolgende Punktringe (gleiche Punktzahl) mit Vierecken.
    Ausrichtung: Ringe gegen den Uhrzeigersinn um die Laufrichtung → Flächen nach außen."""
    bm = bmesh.new()
    uv = uv_layer(bm)
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
    uv = uv_layer(bm)
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


def smooth01(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def bulb(r, neck=0.55, seg=14):
    """Kleine Glühbirne: Kugel mit kurzem Hals, Achse = Blender +Z, Mitte der Kugel im Ursprung."""
    prof = [(0.0, -r * 1.55), (r * neck, -r * 1.55), (r * neck, -r * 0.9)]
    for i in range(1, 9):
        a = -PI * 0.33 + (PI * 0.83) * i / 8
        prof.append((math.cos(a) * r, math.sin(a) * r))
    prof.append((0.0, r))
    return lathe(prof, seg, 0.05)


# =====================================================================================
#  Szene, Kulisse, Export
# =====================================================================================

def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for c in list(bpy.data.collections):
        bpy.data.collections.remove(c)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.lights, bpy.data.cameras):
        for b in list(block):
            if b.users == 0:
                block.remove(b)


def tree(o):
    out = [o]
    for c in o.children:
        out += tree(c)
    return out


def place(places, placed=True):
    """Geräte an ihren Platz im Raum stellen (placed=False: in den Ursprung, für den Export).
    places = { Wurzelknoten: (Ort in Godot-Koordinaten, Drehung um die Hochachse, Größe) }"""
    for name, (pos, yaw, sc) in places.items():
        o = bpy.data.objects.get(name)
        if o is None:
            continue
        o.location = G(*pos) if placed else (0, 0, 0)
        o.rotation_euler = (0, 0, yaw if placed else 0.0)
        o.scale = (sc, sc, sc) if placed else (1, 1, 1)


def export_files(files, out_dir, places=None):
    """Schreibt die .glb (files = { Dateiname: [Wurzelknoten, ...] }) ohne Bilder.
    Geräte aus `places` werden dafür kurz in den Ursprung gestellt."""
    os.makedirs(out_dir, exist_ok=True)
    places = places or {}
    place(places, False)
    bpy.context.view_layer.update()
    written = []
    try:
        for filename, roots in files.items():
            for o in bpy.context.scene.objects:
                o.select_set(False)
            for name in roots:
                for o in tree(bpy.data.objects[name]):
                    if not o.name.startswith("Preview_"):
                        o.select_set(True)
            path = os.path.join(out_dir, filename)
            bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                                      export_yup=True, export_cameras=False, export_lights=False,
                                      export_texcoords=True, export_normals=True, export_image_format="NONE")
            written.append(path)
    finally:
        place(places, True)
    return written


def preview_light(col, name, kind, pos, color, power, **kw):
    """Licht nur für die Ansicht in Blender (ungefähr wie im Spiel)."""
    data = bpy.data.lights.new(name, kind)
    data.color = lin(color)
    data.energy = power
    for k, v in kw.items():
        setattr(data, k, v)
    o = bpy.data.objects.new(name, data)
    col.objects.link(o)
    o.location = gl(*pos)
    return o


def world_color(color):
    world = bpy.context.scene.world or bpy.data.worlds.new("Welt")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg is not None:
        bg.inputs["Color"].default_value = (*color, 1.0)


def copy_tree(src, col, prefix="Preview_", swap=None):
    """Kopie eines Knotens samt Kindern (gleiche Meshes), z. B. für ein zweites Exemplar als
    Kulisse. swap = { Materialname: anderes Material } tauscht dabei Materialien."""
    copies = {}
    for o in tree(src):
        c = o.copy()
        c.name = prefix + o.name
        col.objects.link(c)
        copies[o] = c
        if swap and o.type == "MESH" and o.data.materials and o.data.materials[0] and o.data.materials[0].name in swap:
            c.data = o.data.copy()
            c.data.materials[0] = swap[o.data.materials[0].name]
    for o, c in copies.items():
        if o.parent in copies:
            c.parent = copies[o.parent]
    return copies[src]
