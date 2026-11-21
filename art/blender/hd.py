"""HD-Bausteine für die Gegner: prozedurale Texturen (numpy, ohne PIL), Federn,
Stofffalten, Lumpen, gelofteter Schnabel.

Läuft in jedem Blender (auch direkt im Blender auf dem Entwicklungs-PC über BlenderMCP):
    import sys; sys.path.insert(0, r"<repo>/art/blender"); import hd

Koordinaten wie in characters.py: Blender, Z oben, vorne = -Y. Rumpf-Teile in
Torso-Koordinaten, Kopf-Teile in Head-Koordinaten (Schädelmitte bei (0, 0, 0.1)).
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

# =====================================================================================
#  Szene
# =====================================================================================


def clear_scene() -> None:
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.lights, bpy.data.cameras):
        for block in list(coll):
            if block.users == 0:
                coll.remove(block)


# =====================================================================================
#  Texturen (numpy → bpy.Image, gepackt; der glTF-Export schreibt sie als PNG)
# =====================================================================================

def fractal(size: int, beta: float = 2.0, seed: int = 0, aspect: int = 1) -> np.ndarray:
    """Kachelbares Fraktalrauschen 0..1 (FFT-gefiltert, nahtlos)."""
    rng = np.random.default_rng(seed)
    h, w = size * aspect, size
    white = rng.standard_normal((h, w))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    spec = np.fft.fft2(white) / f ** (beta / 2.0)
    spec[0, 0] = 0
    out = np.real(np.fft.ifft2(spec))
    out -= out.min()
    return out / max(out.max(), 1e-9)


def ridged(n: np.ndarray) -> np.ndarray:
    return 1.0 - np.abs(n * 2.0 - 1.0)


def height_to_normal(height: np.ndarray, strength: float) -> np.ndarray:
    dy, dx = np.gradient(height)
    nx, ny = -dx * strength, dy * strength
    nz = np.ones_like(height)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.dstack(((nx / ln) * 0.5 + 0.5, (ny / ln) * 0.5 + 0.5, (nz / ln) * 0.5 + 0.5))


def to_image(name: str, rgb: np.ndarray, non_color: bool = False) -> bpy.types.Image:
    h, w = rgb.shape[:2]
    old = bpy.data.images.get(name)
    if old is not None:
        bpy.data.images.remove(old)
    img = bpy.data.images.new(name, w, h, alpha=False)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[..., :3] = np.clip(rgb, 0, 1)
    img.pixels.foreach_set(rgba.ravel())
    img.file_format = "PNG"
    img.pack()
    return img


def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def tex_cloth(name: str, base, dark, size=1024, seed=1, weave=96, rag=0.5):
    """Grober, verdreckter Stoff (Leinen/Wolle): Webmuster, Flecken, Abrieb."""
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:size, 0:size] / size
    jitter = (fractal(size, 3.0, seed + 7) - 0.5) * 0.02
    wx = 0.5 + 0.5 * np.sin((x + jitter) * math.tau * weave)
    wy = 0.5 + 0.5 * np.sin((y - jitter) * math.tau * weave)
    checker = np.sin(x * math.pi * weave) * np.sin(y * math.pi * weave) > 0
    weave_h = np.where(checker, wx, wy) ** 0.7
    big = fractal(size, 2.6, seed)
    mid = fractal(size, 2.0, seed + 1)
    fine = fractal(size, 1.0, seed + 2)
    stains = np.clip((fractal(size, 3.2, seed + 3) - 0.55) * 4, 0, 1)
    wear = np.clip((ridged(fractal(size, 2.2, seed + 4)) - 0.8) * 5, 0, 1) * rag
    t = np.clip(0.55 * big + 0.3 * mid + 0.15 * fine, 0, 1)
    base_l, dark_l = srgb_to_linear(base), srgb_to_linear(dark)
    col = dark_l + (base_l - dark_l) * (0.35 + 0.65 * t)[..., None]
    col *= (0.72 + 0.28 * weave_h)[..., None]
    col *= (1.0 - 0.45 * stains)[..., None]
    col += wear[..., None] * base_l * 0.6
    col *= (0.92 + 0.16 * rng.random((size, size)))[..., None]
    height = weave_h * 0.5 + big * 1.5 + mid * 0.6 - wear * 0.6
    return (to_image(name + "_color", col ** (1 / 2.2)),
            to_image(name + "_normal", height_to_normal(height, 5.0), non_color=True))


def tex_feather(name: str, base=(0.035, 0.035, 0.045), sheen=(0.12, 0.1, 0.2), w=128, h=256, seed=3):
    """Einzelfeder (nicht kachelnd): U quer, V entlang (0 = Kiel, 1 = Spitze)."""
    rng = np.random.default_rng(seed)
    v, u = np.mgrid[0:h, 0:w]
    u = u / (w - 1)
    v = v / (h - 1)
    du = np.abs(u - 0.5) * 2
    rachis = np.exp(-(du / 0.05) ** 2)
    barb_phase = v * 70 - du * 28 + rng.random() * 3
    barbs = 0.5 + 0.5 * np.sin(barb_phase * math.tau)
    split = (fractal(64, 2.0, seed)[(v * 63).astype(int) % 64, (u * 63).astype(int) % 64] > 0.78) * (du > 0.3)
    base_l = srgb_to_linear(base)
    sheen_l = srgb_to_linear(sheen)
    shade = 0.55 + 0.45 * barbs ** 1.5
    shade *= 1.0 - 0.45 * du ** 3
    shade *= 0.75 + 0.25 * v
    col = base_l[None, None, :] * shade[..., None]
    col += sheen_l[None, None, :] * (0.4 * (1 - du) * v)[..., None]
    col += rachis[..., None] * base_l[None, None, :] * 0.6
    col *= (1 - 0.6 * split)[..., None]
    height = barbs * 0.4 + rachis * 1.2 - du * 0.5
    return (to_image(name + "_color", col ** (1 / 2.2)),
            to_image(name + "_normal", height_to_normal(height, 4.0), non_color=True))


def tex_keratin(name: str, base, size=512, seed=5, streak=1.0):
    """Horn/Schnabel/Krallen: Längsriefen + Abnutzung."""
    v, u = np.mgrid[0:size, 0:size] / size
    n1 = fractal(size, 2.4, seed)
    streaks = fractal(size, 1.6, seed + 1)
    streaks = np.repeat(streaks[:1, :], size, axis=0) * 0.6 + streaks * 0.4
    pits = np.clip((fractal(size, 1.2, seed + 2) - 0.7) * 5, 0, 1)
    base_l = srgb_to_linear(base)
    shade = 0.7 + 0.5 * n1 + 0.25 * (streaks - 0.5) * streak
    col = base_l[None, None, :] * shade[..., None] * (1 - 0.35 * pits)[..., None]
    height = streaks * streak + n1 * 0.6 - pits * 0.5
    return (to_image(name + "_color", col ** (1 / 2.2)),
            to_image(name + "_normal", height_to_normal(height, 3.0), non_color=True))


def tex_scales(name: str, base, size=512, seed=9, cells=28):
    """Schuppige Vogelhaut (Krähenhände): Zellmuster mit dunklen Fugen."""
    rng = np.random.default_rng(seed)
    pts = rng.random((cells * cells, 2))
    y, x = np.mgrid[0:size, 0:size] / size
    d1 = np.full((size, size), 9.0)
    d2 = np.full((size, size), 9.0)
    for px, py in pts:
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                dx = x - (px + ox)
                dy = y - (py + oy)
                # Schuppen in V-Richtung gestreckt
                d = np.sqrt(dx * dx * 1.0 + dy * dy * 2.2)
                closer = d < d1
                d2 = np.where(closer, d1, np.minimum(d2, d))
                d1 = np.where(closer, d, d1)
    edge = np.clip((d2 - d1) * cells * 1.6, 0, 1)
    n = fractal(size, 2.2, seed + 1)
    base_l = srgb_to_linear(base)
    col = base_l[None, None, :] * (0.6 + 0.5 * edge ** 0.6 + 0.3 * (n - 0.5))[..., None]
    height = edge ** 0.5 + n * 0.3
    return (to_image(name + "_color", col ** (1 / 2.2)),
            to_image(name + "_normal", height_to_normal(height, 3.0), non_color=True))


def material(name, color_img=None, normal_img=None, color=(1, 1, 1, 1), rough=0.8, metal=0.0,
             normal_strength=1.0, double_sided=False, spec=0.5, emission=None, emission_strength=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (-300, 0)
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    try:
        bsdf.inputs["Specular IOR Level"].default_value = spec
    except KeyError:
        pass
    if color_img is not None:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = color_img
        t.location = (-800, 200)
        nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    if normal_img is not None:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = normal_img
        t.location = (-800, -200)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = normal_strength
        nm.location = (-500, -200)
        nt.links.new(t.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = emission
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    mat.use_backface_culling = not double_sided
    return mat


# =====================================================================================
#  Mesh-Werkzeuge
# =====================================================================================

class MeshBuilder:
    """Sammelt viele kleine Teile in einem bmesh (schneller als hunderte Objekte)."""

    def __init__(self) -> None:
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.verify()

    def grid(self, rows, uvs=None, close=False):
        """rows: Liste von Zeilen (Listen von Vector). uvs: gleiche Form mit (u, v)."""
        bm = self.bm
        vs = [[bm.verts.new(p) for p in row] for row in rows]
        n = len(rows[0])
        cols = n if close else n - 1
        for i in range(len(rows) - 1):
            for j in range(cols):
                j2 = (j + 1) % n
                f = bm.faces.new((vs[i][j], vs[i][j2], vs[i + 1][j2], vs[i + 1][j]))
                if uvs is not None:
                    for loop, (a, b) in zip(f.loops, ((i, j), (i, j2), (i + 1, j2), (i + 1, j))):
                        uu, vv = uvs[a][b]
                        if close and b == 0 and j2 == 0:
                            uu = uvs[a][n - 1][0] + (uvs[a][n - 1][0] - uvs[a][n - 2][0])
                        loop[self.uv].uv = (uu, vv)
        return vs

    def finish(self, name, mat, parent=None, smooth=True, location=(0, 0, 0)):
        bm = self.bm
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
        bm.normal_update()
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        me.materials.append(mat)
        if smooth:
            for p in me.polygons:
                p.use_smooth = True
        ob.parent = parent
        ob.location = location
        return ob


def frame(normal: Vector, direction: Vector):
    """Orthonormale Basis: d entlang der Oberfläche, s seitlich, n normal."""
    n = normal.normalized()
    d = direction - n * direction.dot(n)
    if d.length < 1e-6:
        d = n.orthogonal()
    d.normalize()
    s = d.cross(n).normalized()
    return d, s, n


def add_feather(mb: MeshBuilder, base: Vector, normal: Vector, direction: Vector, length: float, width: float,
                lift: float = 0.15, curl: float = 0.1, cup: float = 0.25, twist: float = 0.0, sink: float = 0.003,
                shape: float = 1.0, along: int = 5, across: int = 3):
    """Eine Feder als leicht gewölbtes, spitzes Blatt, die Spitze steht etwas ab.
    lift: Anstellwinkel (Anteil der Länge), curl: Spitze biegt sich zurück zur Haut."""
    d, s, n = frame(normal, direction)
    if twist:
        rot = Matrix.Rotation(twist, 3, d)
        s = rot @ s
        n = rot @ n
    rows, uvs = [], []
    for i in range(along):
        t = i / (along - 1)
        # Breite: rund am Kiel, breit in der Mitte, spitz am Ende
        wp = width * (math.sin(math.pi * min(1.0, 0.12 + t * 0.95)) ** (0.55 * shape)) * (1 - t) ** 0.25
        wp = max(wp, width * 0.02)
        h = length * (lift * t - curl * t * t) - sink * (1 - t)
        row, uvr = [], []
        for j in range(across):
            a = j / (across - 1) * 2 - 1
            p = base + d * (length * t) + s * (a * wp) + n * (h - cup * wp * a * a)
            row.append(p)
            uvr.append((0.5 + a * 0.5, t))
        rows.append(row)
        uvs.append(uvr)
    mb.grid(rows, uvs)


def sample_surface(bm: bmesh.types.BMesh, count: int, rnd: random.Random, keep=None):
    """Zufällige Punkte (flächengewichtet) mit Normalen auf einem bmesh."""
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    bm.faces.ensure_lookup_table()
    tris = []
    for f in bm.faces:
        vs = [v.co for v in f.verts]
        for k in range(1, len(vs) - 1):
            tris.append((vs[0], vs[k], vs[k + 1], f.normal.copy()))
    areas = [((b - a).cross(c - a)).length * 0.5 for a, b, c, _ in tris]
    total = sum(areas)
    cum = []
    acc = 0.0
    for ar in areas:
        acc += ar
        cum.append(acc)
    out = []
    tries = 0
    import bisect
    while len(out) < count and tries < count * 30:
        tries += 1
        r = rnd.random() * total
        a, b, c, nrm = tris[min(bisect.bisect_left(cum, r), len(tris) - 1)]
        u, v = rnd.random(), rnd.random()
        if u + v > 1:
            u, v = 1 - u, 1 - v
        p = a + (b - a) * u + (c - a) * v
        if keep is None or keep(p, nrm):
            out.append((p, nrm))
    return out


def lathe_rows(radius_fn, z_values, segments):
    """Zeilen eines Drehkörpers; radius_fn(theta, z) -> Vector (Punkt)."""
    rows, uvs = [], []
    for i, z in enumerate(z_values):
        row, uvr = [], []
        for j in range(segments):
            th = j / segments * math.tau
            row.append(radius_fn(th, z))
            uvr.append((j / segments * 4.0, z * 2.0))
        rows.append(row)
        uvs.append(uvr)
    return rows, uvs


def loft(mb: MeshBuilder, sections, close_tip=True, uv_scale=(1.0, 1.0)):
    """Verbindet Querschnitte (Listen von Vector, gleiche Länge) zu einer geschlossenen Röhre."""
    n = len(sections[0])
    uvs = [[(j / n * uv_scale[0], i / (len(sections) - 1) * uv_scale[1]) for j in range(n)] for i in range(len(sections))]
    vs = mb.grid(sections, uvs, close=True)
    bm = mb.bm
    # Kappe hinten
    try:
        bm.faces.new(list(reversed(vs[0])))
    except ValueError:
        pass
    if close_tip:
        c = sum(sections[-1], Vector()) / n
        tip = bm.verts.new(c)
        for j in range(n):
            try:
                bm.faces.new((vs[-1][j], vs[-1][(j + 1) % n], tip))
            except ValueError:
                pass
    return vs


def noise3(p: Vector, scale: float = 1.0) -> float:
    from mathutils import noise
    return noise.noise(p * scale)


# =====================================================================================
#  Vorschau: Kamera und Licht ungefähr wie im Spiel (Kerze/Tischlicht + kühles Kopflicht)
# =====================================================================================

def preview_setup(head_height: float = 1.45, focal: float = 42.0) -> None:
    sc = bpy.context.scene
    for ob in list(bpy.data.objects):
        if ob.name.startswith("Preview_"):
            bpy.data.objects.remove(ob, do_unlink=True)
    cam_d = bpy.data.cameras.new("Preview_Cam")
    cam_d.lens = focal
    cam = bpy.data.objects.new("Preview_Cam", cam_d)
    sc.collection.objects.link(cam)
    cam.location = (0, -1.55, head_height + 0.05)
    target = Vector((0, 0.3, head_height - 0.28))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam

    def light(name, kind, loc, energy, color, size=0.3, target=None):
        ld = bpy.data.lights.new("Preview_" + name, kind)
        ld.energy = energy
        ld.color = color
        if kind == "AREA":
            ld.size = size
        if kind == "SPOT":
            ld.spot_size = math.radians(50)
            ld.shadow_soft_size = size
        ob = bpy.data.objects.new("Preview_" + name, ld)
        sc.collection.objects.link(ob)
        ob.location = loc
        if target is not None:
            ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        return ob

    light("Key", "AREA", (0.5, -1.1, head_height + 0.45), 55, (1.0, 0.86, 0.7), 0.6, (0, 0, head_height - 0.15))
    light("Fill", "AREA", (-0.9, -0.8, head_height), 12, (0.65, 0.6, 1.0), 0.8, (0, 0, head_height - 0.2))
    light("Rim", "AREA", (0.0, 0.9, head_height + 0.5), 60, (0.75, 0.7, 1.0), 0.8, (0, 0, head_height - 0.1))
    light("Table", "AREA", (0.0, -0.7, 0.8), 18, (1.0, 0.62, 0.3), 0.5, (0, 0, 1.1))
    w = bpy.data.worlds.get("Preview_World") or bpy.data.worlds.new("Preview_World")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.008, 0.007, 0.01, 1)
    sc.world = w
    sc.render.engine = "CYCLES"
    try:
        sc.cycles.device = "GPU"
    except Exception:
        pass
    sc.cycles.samples = 64
    sc.cycles.use_denoising = True
    sc.render.resolution_x = 900
    sc.render.resolution_y = 1100
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"


def shade_like(target: bpy.types.Object, source: bpy.types.Object, mix: float = 0.8) -> None:
    """Federn/Fell schattieren wie die glatte Haut darunter: Normalen der nächsten Stelle
    auf `source` übernehmen (custom normals). Beide Objekte müssen denselben Parent haben."""
    from mathutils.bvhtree import BVHTree
    sb = bmesh.new()
    sb.from_mesh(source.data)
    sb.transform(source.matrix_basis)
    sb.normal_update()
    sb.faces.ensure_lookup_table()
    tree = BVHTree.FromBMesh(sb)
    me = target.data
    M = target.matrix_basis
    out = []
    for v in me.vertices:
        p = M @ v.co
        hit = tree.find_nearest(p)
        if hit[0] is None:
            out.append(v.normal.copy())
            continue
        loc, _, idx, _ = hit
        n = Vector()
        for fv in sb.faces[idx].verts:
            n += fv.normal / ((fv.co - loc).length + 1e-4)
        n.normalize()
        out.append(v.normal.lerp(n, mix).normalized())
    sb.free()
    me.normals_split_custom_set_from_vertices(out)


def game_camera(add_table: bool = True) -> None:
    """Kamera exakt wie im Spiel (table_world.gd: Position (0, 1.36, 0.86), Blick auf (0, 1.0, -0.3),
    vertikales FOV 64°) plus ein schlichter Tisch auf Handhöhe."""
    from geo import G
    sc = bpy.context.scene
    cam = sc.camera
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle = math.radians(64)
    cam.location = G(0, 1.36, 0.86)
    cam.rotation_euler = (G(0, 1.0, -0.3) - G(0, 1.36, 0.86)).to_track_quat("-Z", "Y").to_euler()
    sc.render.resolution_x = 1280
    sc.render.resolution_y = 720
    if add_table and "Preview_Table_Top" not in bpy.data.objects:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        bmesh.ops.scale(bm, vec=Vector((1.6, 0.85, 0.05)), verts=bm.verts)
        me = bpy.data.meshes.new("Preview_Table_Top")
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new("Preview_Table_Top", me)
        sc.collection.objects.link(ob)
        ob.location = G(0, 0.775, 0.28)  # Oberkante 0.80 = TABLE_Y
        me.materials.append(material("Preview_Holz", color=(0.05, 0.028, 0.016, 1), rough=0.6))


def preview_eyes(color=(1.0, 0.62, 0.15), radius=0.012, strength=6.0) -> None:
    """Simuliert die glühenden Pupillen, die Godot an EyeL/EyeR/EyeX* setzt."""
    mat = material("Preview_Augenglut", color=(*color, 1), emission=(*color, 1), emission_strength=strength)
    for ob in list(bpy.data.objects):
        if ob.name.startswith("Preview_Eye"):
            bpy.data.objects.remove(ob, do_unlink=True)
    for mk in [o for o in bpy.data.objects if o.type == "EMPTY" and o.name.startswith("Eye")]:
        r = radius * (0.6 if mk.name.startswith("EyeX") else 1.0)
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=r)
        me = bpy.data.meshes.new("Preview_" + mk.name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(mat)
        ob = bpy.data.objects.new("Preview_" + mk.name, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.parent = mk.parent
        ob.location = mk.location


def export_character(path: str) -> None:
    """Exportiert alles außer den Vorschau-Objekten als .glb."""
    import os
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for ob in bpy.context.scene.objects:
        ob.select_set(not ob.name.startswith("Preview_"))
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_cameras=False, export_lights=False, export_texcoords=True,
                              export_normals=True, export_image_format="AUTO")
