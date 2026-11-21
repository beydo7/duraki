"""Hilfsfunktionen für die Blender-Modelle: Materialien, Grundkörper, UVs, Export.

Koordinaten: Alle Positionen werden in GODOT-Koordinaten angegeben
(Y nach oben, +Z zum Spieler) und mit G()/GS() nach Blender umgerechnet
(Z nach oben, -Y nach vorne). Der glTF-Export rechnet beim Speichern zurück.
"""
from __future__ import annotations

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
TEX_DIR = os.path.join(HERE, "textures")


def G(x: float, y: float, z: float) -> Vector:
    """Godot-Position → Blender-Position."""
    return Vector((x, -z, y))


def GS(x: float, y: float, z: float) -> Vector:
    """Godot-Größe (Breite, Höhe, Tiefe) → Blender-Größe."""
    return Vector((x, z, y))


# --- Szene ---------------------------------------------------------------------------

def new_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"


def collection(name: str) -> bpy.types.Collection:
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return col


# --- Materialien ---------------------------------------------------------------------

def _image(name: str, non_color: bool = False) -> bpy.types.Image:
    path = os.path.join(TEX_DIR, name + ".png")
    img = bpy.data.images.load(path, check_existing=True)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    return img


def material(name: str, tex: str | None = None, color=(1, 1, 1, 1), rough: float = 0.8,
             metal: float = 0.0, normal: bool = True, normal_strength: float = 1.0,
             emission=None, emission_strength: float = 1.0, alpha: float | None = None) -> bpy.types.Material:
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if tex is not None:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = _image(tex + "_color")
        t.location = (-500, 250)
        nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
        if normal and os.path.exists(os.path.join(TEX_DIR, tex + "_normal.png")):
            n = nt.nodes.new("ShaderNodeTexImage")
            n.image = _image(tex + "_normal", non_color=True)
            n.location = (-500, -150)
            nm = nt.nodes.new("ShaderNodeNormalMap")
            nm.inputs["Strength"].default_value = normal_strength
            nm.location = (-200, -150)
            nt.links.new(n.outputs["Color"], nm.inputs["Color"])
            nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    if alpha is not None:
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            mat.surface_render_method = "BLENDED"
        except AttributeError:
            mat.blend_method = "BLEND"
    return mat


# --- Objekte -------------------------------------------------------------------------

def to_object(name: str, bm: bmesh.types.BMesh, mat: bpy.types.Material, col=None,
              smooth: bool = False, sharp_angle: float | None = 35.0, location=(0, 0, 0),
              bevel: float = 0.0, bevel_segments: int = 2, subsurf: int = 0) -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    (col or bpy.context.scene.collection).objects.link(ob)
    ob.location = location
    me.materials.append(mat)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
        if sharp_angle is not None:
            try:
                me.set_sharp_from_angle(angle=math.radians(sharp_angle))
            except (AttributeError, TypeError):
                pass
    if bevel > 0.0:
        mod = ob.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = bevel_segments
        mod.limit_method = "ANGLE"
        mod.harden_normals = False
    if subsurf > 0:
        mod = ob.modifiers.new("Subdivision", "SUBSURF")
        mod.levels = subsurf
        mod.render_levels = subsurf
    return ob


def merge(*bms: bmesh.types.BMesh) -> bmesh.types.BMesh:
    """Mehrere BMeshes zu einem zusammenführen (die Einzelnen werden freigegeben)."""
    out = bmesh.new()
    for b in bms:
        me = bpy.data.meshes.new("_tmp")
        b.to_mesh(me)
        b.free()
        out.from_mesh(me)
        bpy.data.meshes.remove(me)
    return out


def transform(bm: bmesh.types.BMesh, matrix: Matrix) -> bmesh.types.BMesh:
    bmesh.ops.transform(bm, matrix=matrix, verts=bm.verts)
    return bm


def translate(bm: bmesh.types.BMesh, v: Vector) -> bmesh.types.BMesh:
    bmesh.ops.translate(bm, vec=v, verts=bm.verts)
    return bm


# --- Grundkörper ---------------------------------------------------------------------

def box(size: Vector, center: Vector, tile: float = 1.0, uv_rot: bool = False) -> bmesh.types.BMesh:
    """Quader (Blender-Größe/-Mitte) mit Box-UVs in Weltgröße."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    bmesh.ops.translate(bm, vec=center, verts=bm.verts)
    box_uv(bm, tile, uv_rot)
    return bm


def gbox(size_g, center_g, tile: float = 1.0, uv_rot: bool = False) -> bmesh.types.BMesh:
    """Quader in Godot-Koordinaten."""
    return box(GS(*size_g), G(*center_g), tile, uv_rot)


def box_uv(bm: bmesh.types.BMesh, tile: float, rotate: bool = False) -> None:
    """Würfel-Projektion in Weltgröße: Texturen kacheln überall gleich groß."""
    bm.normal_update()
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in f.loops:
            c = loop.vert.co
            if ax == 0:
                u, v = c.y, c.z
            elif ax == 1:
                u, v = c.x, c.z
            else:
                u, v = (c.y, c.x) if rotate else (c.x, c.y)
            loop[uv].uv = (u / tile, v / tile)


def lathe(profile, segments: int = 32, tile: float = 0.25, cap_bottom: bool = False,
          cap_top: bool = False, angle: float = math.tau) -> bmesh.types.BMesh:
    """Drehkörper um die Blender-Z-Achse. profile = [(radius, höhe), ...] von unten nach oben."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    full = abs(angle - math.tau) < 1e-6
    steps = segments if full else segments + 1
    rings = []
    for s in range(steps):
        a = angle * s / segments
        ca, sa = math.cos(a), math.sin(a)
        rings.append([bm.verts.new((r * ca, r * sa, h)) for r, h in profile])
    # Profillänge für V
    lengths = [0.0]
    for i in range(1, len(profile)):
        (r0, h0), (r1, h1) = profile[i - 1], profile[i]
        lengths.append(lengths[-1] + math.hypot(r1 - r0, h1 - h0))
    rmax = max(r for r, _ in profile)
    for s in range(segments):
        a_ring = rings[s]
        b_ring = rings[(s + 1) % steps] if full else rings[s + 1]
        for i in range(len(profile) - 1):
            vs = (a_ring[i], b_ring[i], b_ring[i + 1], a_ring[i + 1])
            if len({v.index for v in vs}) < 4 and profile[i][0] == 0 and profile[i + 1][0] == 0:
                continue
            try:
                f = bm.faces.new(vs)
            except ValueError:
                continue
            for k, loop in enumerate(f.loops):
                si = s + (1 if k in (1, 2) else 0)
                pi = i + (1 if k in (2, 3) else 0)
                loop[uv].uv = (si / segments * angle * rmax / tile, lengths[pi] / tile)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    if cap_bottom or cap_top:
        bm.edges.ensure_lookup_table()
        boundary = [e for e in bm.edges if e.is_boundary]
        if boundary:
            bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
    bm.normal_update()
    # Normalen nach außen
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


def sweep(path, profile, closed: bool = True, tile: float = 0.25) -> bmesh.types.BMesh:
    """Zieht ein 2D-Profil [(außen, oben), ...] entlang eines Pfads in der XY-Ebene (Blender).
    UV: U entlang des Pfads (Holzmaserung folgt dem Rand), V entlang des Profils."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    n = len(path)
    frames = []
    for i in range(n):
        p_prev = path[(i - 1) % n] if closed or i > 0 else path[i]
        p_next = path[(i + 1) % n] if closed or i < n - 1 else path[i]
        t = (Vector(p_next) - Vector(p_prev)).normalized()
        out = t.cross(Vector((0, 0, 1))).normalized()
        frames.append((Vector(path[i]), out))
    rings = []
    for p, out in frames:
        rings.append([bm.verts.new(p + out * o + Vector((0, 0, h))) for o, h in profile])
    dist = [0.0]
    for i in range(1, n + (1 if closed else 0)):
        dist.append(dist[-1] + (Vector(path[i % n]) - Vector(path[i - 1])).length)
    plen = [0.0]
    for i in range(1, len(profile)):
        plen.append(plen[-1] + math.hypot(profile[i][0] - profile[i - 1][0], profile[i][1] - profile[i - 1][1]))
    count = n if closed else n - 1
    for s in range(count):
        a, b = rings[s], rings[(s + 1) % n]
        for i in range(len(profile) - 1):
            f = bm.faces.new((a[i], b[i], b[i + 1], a[i + 1]))
            for k, loop in enumerate(f.loops):
                si = s + (1 if k in (1, 2) else 0)
                pi = i + (1 if k in (2, 3) else 0)
                loop[uv].uv = (dist[si] / tile, plen[pi] / tile)
    bm.normal_update()
    return bm


def rounded_rect(w: float, d: float, r: float, seg: int = 6):
    """Pfad eines abgerundeten Rechtecks (Blender XY), gegen den Uhrzeigersinn."""
    pts = []
    corners = [(w / 2 - r, -d / 2 + r, -90), (w / 2 - r, d / 2 - r, 0), (-w / 2 + r, d / 2 - r, 90), (-w / 2 + r, -d / 2 + r, 180)]
    for cx, cy, start in corners:
        for k in range(seg + 1):
            a = math.radians(start + 90 * k / seg)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a), 0.0))
    return pts


def ellipsoid(radii: Vector, center: Vector, u: int = 24, v: int = 16) -> bmesh.types.BMesh:
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=1.0)
    bmesh.ops.scale(bm, vec=radii, verts=bm.verts)
    bmesh.ops.translate(bm, vec=center, verts=bm.verts)
    sphere_uv(bm, center)
    return bm


def sphere_uv(bm: bmesh.types.BMesh, center: Vector, tile: float = 1.0) -> None:
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        us = []
        for loop in f.loops:
            d = (loop.vert.co - center)
            d = d.normalized() if d.length > 1e-9 else Vector((0, 0, 1))
            u = math.atan2(d.x, -d.y) / math.tau + 0.5
            vv = math.acos(max(-1, min(1, d.z))) / math.pi
            us.append([u, 1 - vv])
        # Naht glätten
        if max(x[0] for x in us) - min(x[0] for x in us) > 0.5:
            for x in us:
                if x[0] < 0.5:
                    x[0] += 1.0
        for loop, (u, vv) in zip(f.loops, us):
            loop[uv].uv = (u * tile * 2, vv * tile)


def cylinder_between(a: Vector, b: Vector, r1: float, r2: float | None = None, seg: int = 12,
                     tile: float = 0.25) -> bmesh.types.BMesh:
    """Zylinder/Kegel zwischen zwei Punkten (Blender-Koordinaten)."""
    r2 = r1 if r2 is None else r2
    d = b - a
    bm = lathe([(r1, 0.0), (r2, d.length)], seg, tile, cap_bottom=True, cap_top=True)
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    transform(bm, Matrix.Translation(a) @ rot)
    return bm


def aim_matrix(origin: Vector, target: Vector) -> Matrix:
    """Matrix, die die lokale +Z-Achse von origin auf target ausrichtet."""
    d = (target - origin).normalized()
    rot = Vector((0, 0, 1)).rotation_difference(d).to_matrix().to_4x4()
    return Matrix.Translation(origin) @ rot


# --- Speichern / Export --------------------------------------------------------------

def save_blend(path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        bpy.ops.file.pack_all()
    except RuntimeError:
        pass
    bpy.ops.wm.save_as_mainfile(filepath=path, compress=True)


def export_glb(path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    kwargs = dict(filepath=path, export_format="GLB", export_apply=True, export_yup=True,
                  export_cameras=False, export_lights=False, export_texcoords=True, export_normals=True)
    try:
        bpy.ops.export_scene.gltf(export_image_format="AUTO", **kwargs)
    except TypeError:
        bpy.ops.export_scene.gltf(**kwargs)


def tube(points, radii, seg: int = 12, tile: float = 0.2, cap_start: bool = True) -> bmesh.types.BMesh:
    """Röhre entlang einer 3D-Kurve mit wechselndem Radius (Hörner, Krallen, Finger).
    Rahmen per Parallel-Transport, damit sich die Röhre nicht verdreht."""
    pts = [Vector(p) for p in points]
    n = len(pts)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.verify()
    tangents = []
    for i in range(n):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, n - 1)]
        tangents.append((b - a).normalized())
    ref = Vector((0, 0, 1)) if abs(tangents[0].z) < 0.9 else Vector((1, 0, 0))
    normal = (ref - tangents[0] * ref.dot(tangents[0])).normalized()
    rings = []
    length = [0.0]
    for i in range(n):
        t = tangents[i]
        normal = (normal - t * normal.dot(t)).normalized()
        binormal = t.cross(normal)
        ring = []
        for k in range(seg):
            ang = math.tau * k / seg
            ring.append(bm.verts.new(pts[i] + (normal * math.cos(ang) + binormal * math.sin(ang)) * radii[i]))
        rings.append(ring)
        if i > 0:
            length.append(length[-1] + (pts[i] - pts[i - 1]).length)
    circ = math.tau * max(radii)
    for i in range(n - 1):
        for k in range(seg):
            vs = (rings[i][k], rings[i][(k + 1) % seg], rings[i + 1][(k + 1) % seg], rings[i + 1][k])
            f = bm.faces.new(vs)
            for j, loop in enumerate(f.loops):
                kk = k + (1 if j in (1, 2) else 0)
                ii = i + (1 if j in (2, 3) else 0)
                loop[uv].uv = (kk / seg * circ / tile, length[ii] / tile)
    if cap_start:
        bm.faces.new(list(reversed(rings[0])))
    tip = bm.verts.new(pts[-1] + tangents[-1] * radii[-1])
    for k in range(seg):
        bm.faces.new((rings[-1][k], rings[-1][(k + 1) % seg], tip))
    bm.normal_update()
    return bm
