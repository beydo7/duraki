"""Duraki – Werkzeugkasten für die Charakter-Überarbeitung (Nov. 2026).

Grundlage ist MPFB/MakeHuman (Blender-Erweiterung, Ergebnis CC0): Kopf, Augen, Zähne, Hände und
Oberkörper kommen aus einem anatomisch sauberen Grundmodell mit ordentlicher Topologie und UVs.
Die Figur wird über Formregler (Targets) gestaltet, in Greifhaltung gebracht, in die Teile zerlegt,
die `scenes/match/opponent_figure.gd` erwartet (Torso → Head, Hand_L/Hand_R, Ärmel), und in den
Spielmaßstab gebracht. Kleidung, Fell und Requisiten bauen die Figuren-Skripte (`dk_<id>.py`) darauf.

Voraussetzung: MPFB + „MakeHuman system assets“ (siehe docs/CHARAKTER_OVERHAUL.md).
"""
from __future__ import annotations

import glob
import math
import os
from contextlib import contextmanager

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

from bl_ext.blender_org.mpfb.services.assetservice import AssetService
from bl_ext.blender_org.mpfb.services.humanservice import HumanService
from bl_ext.blender_org.mpfb.services.locationservice import LocationService
from bl_ext.blender_org.mpfb.services.targetservice import TargetService

import characters as ch
import geo
import hd
from geo import G

S = 1.68                                 # Maßstab Mensch → Spielfigur (Kopf ~0,40 m hoch)
ANCHOR = Vector((0.0, -0.017, 1.383))    # MPFB: Höhe der Schultergelenke, Körpermitte
SHOULDER = Vector((0.0, 0.02, 0.97))     # dieselbe Stelle in Torso-Koordinaten
ARM_GROUPS = ("upperarm02", "lowerarm01", "lowerarm02", "wrist", "finger", "metacarpal")
HAND_GROUPS = ("lowerarm02", "wrist", "finger", "metacarpal")


@contextmanager
def ui():
    """MPFB greift auf bpy.context.object zu – das gibt es nur mit einem 3D-Fenster im Kontext."""
    win = bpy.context.window_manager.windows[0]
    area = next(a for a in win.screen.areas if a.type == "VIEW_3D")
    region = next(r for r in area.regions if r.type == "WINDOW")
    with bpy.context.temp_override(window=win, area=area, region=region):
        yield


def both(name: str, value: float) -> dict:
    return {"l-" + name: value, "r-" + name: value}


def _asset(sub: str, name: str) -> str:
    for p in AssetService.list_mhclo_assets(sub):
        if os.path.basename(os.path.dirname(str(p))) == name:
            return str(p)
    raise KeyError(f"MPFB-Asset fehlt: {sub}/{name}")


def data_file(pattern: str) -> str:
    """Datei aus den MPFB-Daten (System-Assets) suchen, z. B. 'skins/old_caucasian_female/*diffuse*.png'."""
    for root in (LocationService.get_user_data(), LocationService.get_mpfb_data("")):
        hits = sorted(glob.glob(os.path.join(str(root), pattern), recursive=True))
        if hits:
            return hits[0]
    raise FileNotFoundError(pattern)


def make_human(macro: dict, targets: dict, brows="eyebrow006", lashes="eyelashes02", teeth="teeth_base",
               eyes="high-poly"):
    """Grundmodell mit Formreglern, Augen/Zähnen/Brauen/Wimpern und Skelett. → (body, rig, parts)"""
    d = TargetService.get_default_macro_info_dict()
    d.update({k: v for k, v in macro.items() if k != "race"})
    if "race" in macro:
        d["race"] = dict(macro["race"])
    parts = {}
    with ui():
        body = HumanService.create_human(scale=0.1, macro_detail_dict=d)
        body.name = "Mensch"
        for k, v in targets.items():
            TargetService.load_target(body, TargetService.target_full_path(k), weight=min(v, 1.0), name=k)
        if body.data.shape_keys:  # Übertreibung über 1.0 hinaus (Stilisierung)
            for kb in body.data.shape_keys.key_blocks:
                for k, v in targets.items():
                    if v > 1.0 and (kb.name == k or kb.name.endswith(k)):
                        kb.slider_max = v
                        kb.value = v
        for key, sub, name, typ in (("eyes", "eyes", eyes, "Eyes"), ("teeth", "teeth", teeth, "Teeth"),
                                    ("brows", "eyebrows", brows, "Eyebrows"), ("lashes", "eyelashes", lashes, "Eyelashes")):
            if not name:
                continue
            before = set(bpy.data.objects)
            HumanService.add_mhclo_asset(_asset(sub, name), body, asset_type=typ, subdiv_levels=0,
                                         set_up_rigging=False, import_subrig=False, import_weights=False)
            parts[key] = (set(bpy.data.objects) - before).pop()
        rig = HumanService.add_builtin_rig(body, "default_no_toes", import_weights=True)
    bpy.context.view_layer.update()
    return body, rig, parts


# --- Pose ---------------------------------------------------------------------------------

def rot_world(rig, name: str, axis: Vector, angle: float) -> None:
    pb = rig.pose.bones[name]
    M = pb.matrix.copy()
    pos = M.to_translation()
    pb.matrix = Matrix.Translation(pos) @ Matrix.Rotation(angle, 4, axis) @ Matrix.Translation(-pos) @ M
    bpy.context.view_layer.update()


def aim_arm(rig, sfx: str, direction) -> None:
    """Ganzen Arm um das Schultergelenk drehen, bis der Oberarm in `direction` zeigt."""
    pb = rig.pose.bones
    cur = (pb["lowerarm01" + sfx].head - pb["upperarm01" + sfx].head).normalized()
    axis, ang = cur.rotation_difference(Vector(direction).normalized()).to_axis_angle()
    rot_world(rig, "upperarm01" + sfx, axis, ang)


def hand_frame(rig, sfx: str):
    """Handgelenk, Fingerrichtung, Handrücken-Normale (Armature-Raum)."""
    pb = rig.pose.bones
    o = pb["wrist" + sfx].head.copy()
    f = (pb["finger3-1" + sfx].head - o).normalized()
    back = (pb["finger2-1" + sfx].head - o).cross(pb["finger5-1" + sfx].head - o) * (1 if sfx == ".L" else -1)
    back = (back - f * back.dot(f)).normalized()
    return o, f, back


def grip_pose(rig, sfx: str, curl=(38, 62, 42), thumb=(22, 12, 28), fan=6.0) -> None:
    """Finger um die Kartenkante krümmen (Grad je Gelenk), Daumen legt sich oben an."""
    _o, _f, back = hand_frame(rig, sfx)
    palm = -back
    pb = rig.pose.bones
    for fi, k in ((2, 0.8), (3, 1.0), (4, 1.08), (5, 1.15)):
        d = (pb[f"finger{fi}-1{sfx}"].tail - pb[f"finger{fi}-1{sfx}"].head).normalized()
        hinge = d.cross(palm).normalized()
        rot_world(rig, f"finger{fi}-1{sfx}", palm, math.radians((fi - 3.5) * fan * (1 if sfx == ".L" else -1)))
        for j, a in enumerate(curl, 1):
            rot_world(rig, f"finger{fi}-{j}{sfx}", hinge, math.radians(a * k))
    d = (pb["finger1-1" + sfx].tail - pb["finger1-1" + sfx].head).normalized()
    hinge = d.cross(palm).normalized()
    for j, a in enumerate(thumb, 1):
        rot_world(rig, f"finger1-{j}{sfx}", hinge, math.radians(a))


# --- Zerlegen -----------------------------------------------------------------------------

def evaluated(ob, subdiv: int = 0) -> bmesh.types.BMesh:
    """Fertig verformtes Mesh (Formregler, Skelett, ohne Hilfsgeometrie) als bmesh."""
    mod = None
    if subdiv:
        mod = ob.modifiers.new("Glatt", "SUBSURF")
        mod.levels = subdiv
    dg = bpy.context.evaluated_depsgraph_get()
    dg.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    bm = bmesh.new()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    if mod:
        ob.modifiers.remove(mod)
    return bm


def group_weight(ob, bm, prefixes, sfx: str):
    """Je Vertex die Summe der Gewichte aller Gruppen, die mit einem der Präfixe beginnen."""
    idx = {g.index for g in ob.vertex_groups if g.name.endswith(sfx) and g.name.startswith(prefixes)}
    dl = bm.verts.layers.deform.verify()
    return {v: sum(w for i, w in v[dl].items() if i in idx) for v in bm.verts}


def bisect(bm, co, no) -> None:
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], dist=1e-6, plane_co=co, plane_no=no)


def keep_faces(bm, keep) -> None:
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not keep(f)], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")


def close_holes(bm) -> None:
    edges = [e for e in bm.edges if e.is_boundary]
    if edges:
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)


def to_torso(p: Vector) -> Vector:
    return (p - ANCHOR) * S + SHOULDER


def transform(bm, fn) -> None:
    for v in bm.verts:
        v.co = fn(v.co)


def to_object(name, bm, mat, parent=None, location=(0, 0, 0)):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
        p.material_index = 0
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    if mat is not None:
        me.materials.append(mat)
    ob.parent = parent
    ob.location = location
    return ob


class Figure:
    """Zerlegt einen gestellten MPFB-Menschen in die Spielteile."""

    def __init__(self, body, rig, parts, head_scale=1.12, neck_cut=1.47, torso_top=1.515, waist=1.03):
        self.body, self.mrig, self.parts = body, rig, parts
        self.head_scale = head_scale
        pb = rig.pose.bones
        self.pivot_src = (pb["neck02"].head + pb["neck02"].tail) * 0.5
        self.rig = ch.Rig(1.25)
        self.rig.head.location = to_torso(self.pivot_src)
        self.neck_cut, self.torso_top, self.waist = neck_cut, torso_top, waist
        bpy.context.view_layer.update()

    # Kopf-Koordinaten: relativ zum Head-Empty, um den Drehpunkt vergrößert
    def to_head(self, p: Vector) -> Vector:
        return (to_torso(p) - Vector(self.rig.head.location)) * self.head_scale

    def head(self, mat, subdiv=1):
        bm = evaluated(self.body, subdiv)
        bisect(bm, Vector((0, 0, self.neck_cut)), Vector((0, 0, 1)))
        keep_faces(bm, lambda f: f.calc_center_median().z > self.neck_cut)
        transform(bm, self.to_head)
        return to_object("Face", bm, mat, self.rig.head)

    def head_part(self, key, name, mat):
        ob = self.parts.get(key)
        if ob is None:
            return None
        bm = evaluated(ob)
        transform(bm, lambda p: self.to_head(ob.matrix_world @ p))
        return to_object(name, bm, mat, self.rig.head)

    def eye_markers(self):
        pb = self.mrig.pose.bones
        for name, bone in (("EyeL", "eye.R"), ("EyeR", "eye.L")):  # Spiel: L = vom Spieler aus links
            p = pb[bone].head.lerp(pb[bone].tail, 0.5)
            self.rig.marker(name, self.rig.head, self.to_head(p))

    def torso(self, mat, subdiv=1, arm_stub=0.1):
        ob = self.body
        bm = evaluated(ob, subdiv)
        pb = self.mrig.pose.bones
        planes = {}
        for sfx in (".L", ".R"):
            sh, el = pb["upperarm01" + sfx].head, pb["lowerarm01" + sfx].head
            d = (el - sh).normalized()
            planes[sfx] = (sh + d * arm_stub, d)
            bisect(bm, *planes[sfx])
        bisect(bm, Vector((0, 0, self.torso_top)), Vector((0, 0, 1)))
        bisect(bm, Vector((0, 0, self.waist)), Vector((0, 0, 1)))
        w = {sfx: group_weight(ob, bm, ARM_GROUPS + ("upperarm01",), sfx) for sfx in planes}

        def keep(f):
            c = f.calc_center_median()
            if c.z > self.torso_top or c.z < self.waist:
                return False
            for sfx, (co, no) in planes.items():
                if (c - co).dot(no) > 0 and sum(w[sfx][v] for v in f.verts) / len(f.verts) > 0.35:
                    return False
            return True
        keep_faces(bm, keep)
        transform(bm, to_torso)
        tb = self.rig.torso
        for sfx, name in ((".R", "Shoulder_L"), (".L", "Shoulder_R")):
            self.rig.marker(name, tb, to_torso(pb["upperarm01" + sfx].head))
        return to_object("Body_Skin", bm, mat, tb)

    def hands(self, skin, scale=1.3, stub=0.05, roll=72.0, pitch=-0.45, subdiv=1, pos=(0.1, 0.9, 0.22),
              grip=(0.045, -0.03, 0.05)):
        """Hand_L/Hand_R, gedreht wie hd.grip_hand. Die Hand wird so verschoben, dass die Lücke
        zwischen Daumen und Zeigefinger an der unteren Ecke des Kartenfächers liegt
        (grip = nach innen, nach vorn (Blender −Y), nach oben; relativ zum Hand-Ursprung)."""
        ob = self.body
        out = []
        for sfx, side, name in ((".R", -1, "Hand_L"), (".L", 1, "Hand_R")):
            bm = evaluated(ob, subdiv)
            o, f, back = hand_frame(self.mrig, sfx)
            pb = self.mrig.pose.bones
            fore = (pb["wrist" + sfx].head - pb["lowerarm01" + sfx].head).normalized()
            co = o - fore * stub
            bisect(bm, co, fore)
            w = group_weight(ob, bm, HAND_GROUPS, sfx)
            keep_faces(bm, lambda fc: (fc.calc_center_median() - co).dot(fore) > 0
                       and sum(w[v] for v in fc.verts) / len(fc.verts) > 0.5)
            close_holes(bm)
            R = Matrix((back.cross(f), -f, back))  # Zeilen = Zielachsen X, Y, Z
            orient = Matrix.Rotation(math.radians(side * roll), 3, "Y") @ Matrix.Rotation(pitch, 3, "X")
            place = lambda p: orient @ ((R @ (p - o)) * scale)
            g = place((pb["finger1-3" + sfx].tail + pb["finger2-2" + sfx].head) * 0.5)
            shift = Vector((-side * grip[0], grip[1], grip[2])) - g
            transform(bm, lambda p: place(p) + shift)
            h = to_object(name, bm, skin, None, G(side * pos[0], pos[1], pos[2]))
            out.append(h)
        return out


# --- Texturen aus Bildern -----------------------------------------------------------------

def part_image(ob):
    """Farbtextur eines MPFB-Teils (erstes Bild im Material, auch in Knotengruppen)."""
    def walk(tree):
        for n in tree.nodes:
            if n.type == "TEX_IMAGE" and n.image is not None:
                return n.image
            if n.type == "GROUP" and n.node_tree:
                img = walk(n.node_tree)
                if img:
                    return img
        return None
    for slot in ob.material_slots:
        if slot.material and slot.material.node_tree:
            img = walk(slot.material.node_tree)
            if img:
                return img
    return None


def image_array(path_or_img) -> np.ndarray:
    img = path_or_img if isinstance(path_or_img, bpy.types.Image) else bpy.data.images.load(path_or_img, check_existing=True)
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(h, w, 4)


def studio(scale=1.0, strength=1.0):
    """Neutrales Dreipunkt-Licht für Kontroll-Renderings (ersetzt vorhandene Lampen)."""
    sc = bpy.context.scene
    for ob in list(sc.objects):
        if ob.type == "LIGHT":
            bpy.data.objects.remove(ob, do_unlink=True)
    world = bpy.data.worlds.new("Studio")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.16, 0.16, 0.18, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.4
    sc.world = world
    c = Vector((0, 0.3, 1.35))
    for name, off, energy, color, sz in (("Key", (-1.1, -1.6, 0.9), 55, (1.0, 0.95, 0.88), 0.8),
                                         ("Fill", (1.5, -1.2, 0.1), 14, (0.8, 0.86, 1.0), 1.6),
                                         ("Rim", (0.7, 1.5, 1.0), 70, (1.0, 0.98, 0.95), 0.6)):
        l = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
        l.data.energy = energy * strength * scale * scale
        l.data.color = color
        l.data.size = sz * scale
        l.location = c + Vector(off) * scale
        l.rotation_euler = (c - l.location).to_track_quat("-Z", "Y").to_euler()
        sc.collection.objects.link(l)
    sc.view_settings.view_transform = "Standard"


def camera(name, target, angle=0.0, dist=1.6, lens=60, height=0.05):
    sc = bpy.context.scene
    cam = bpy.data.objects.get(name) or bpy.data.objects.new(name, bpy.data.cameras.new(name))
    if cam.name not in sc.collection.objects:
        sc.collection.objects.link(cam)
    a = math.radians(angle)
    t = Vector(target)
    cam.data.lens = lens
    cam.location = t + Vector((math.sin(a) * dist, -math.cos(a) * dist, height))
    cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    return cam


# --- Messen und Formen am Kopf ---------------------------------------------------------------

def head_metrics(face_ob, eye_z: float) -> dict:
    """Maße des Kopfes in Head-Koordinaten (für Mützen, Tücher, Kapuzen)."""
    co = np.empty(len(face_ob.data.vertices) * 3, dtype=np.float32)
    face_ob.data.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    up = co[co[:, 2] > eye_z + 0.02]
    front = co[(np.abs(co[:, 0]) < 0.05) & (co[:, 1] < up[:, 1].mean())]
    return {"top": float(co[:, 2].max()), "eye": eye_z, "x": float(np.abs(up[:, 0]).max()),
            "yf": float(up[:, 1].min()), "yb": float(up[:, 1].max()), "yc": float((up[:, 1].min() + up[:, 1].max()) * 0.5),
            "chin": float(front[:, 2].min()), "nose_y": float(front[:, 1].min())}


def bvh(ob):
    from mathutils.bvhtree import BVHTree
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    return tree


def box_uv(bm, tile: float = 0.25) -> None:
    """Würfel-Projektion (für kachelnde Stoffe/Leder), Maßstab: 1 UV-Einheit = `tile` Meter."""
    uv = bm.loops.layers.uv.verify()
    bm.normal_update()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in f.loops:
            c = loop.vert.co
            a, b = ((c.y, c.z), (c.x, c.z), (c.x, c.y))[ax]
            loop[uv].uv = (a / tile, b / tile)


def inflate(bm, dist: float, smooth: int = 2) -> None:
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * dist
    for _ in range(smooth):
        bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)


# --- Schalen-Fell ---------------------------------------------------------------------------

def tex_fur_shells(name, root, tip, shells=16, size=256, clumps=900, radius=5.5, seed=1):
    """Kachelnde Büschel-Höhenkarte, je Schale ein Bild mit Alpha (Büschel werden nach außen dünner)."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    height = np.zeros((size, size), np.float32)
    tone = np.ones((size, size), np.float32)
    for _ in range(clumps):
        px, py = rng.random(2) * size
        r = rng.uniform(0.7, 1.3) * radius
        dx = np.abs(xx - px)
        dy = np.abs(yy - py)
        dx = np.minimum(dx, size - dx)
        dy = np.minimum(dy, size - dy)
        h = rng.uniform(0.6, 1.0) * np.clip(1 - (dx * dx + dy * dy) / (r * r), 0, 1)
        m = h > height
        tone = np.where(m, rng.uniform(0.84, 1.12), tone)
        height = np.maximum(height, h)
    root_l, tip_l = hd.srgb_to_linear(root), hd.srgb_to_linear(tip)
    imgs = []
    for i in range(shells):
        t = i / (shells - 1)
        alpha = (height > t * 0.85).astype(np.float32) if i else np.ones_like(height)
        k = t ** 0.7
        col = (root_l * (1 - k) + tip_l * k)[None, None, :] * (tone * (0.65 + 0.35 * t))[..., None]
        imgs.append(hd.to_image(f"{name}_{i:02d}", np.clip(col, 0, 1) ** (1 / 2.2), alpha=alpha))
    return imgs


def shell_fur(base_ob, name, mat_name, imgs, length=0.045, lean=(0.0, 0.0, -0.35), parent=None, uneven=0.3):
    """Fell aus Schalen: Kopien der Grundform, nach außen versetzt, jede mit dünneren Büscheln.
    Das Objekt heißt `*_Fur` (Godot: kein Schattenwurf, wenig Glanz)."""
    from mathutils import noise
    src = bmesh.new()
    src.from_mesh(base_ob.data)
    src.normal_update()
    lean = Vector(lean)
    n = len(imgs)
    out = bmesh.new()
    out.loops.layers.uv.verify()
    tmp_me = bpy.data.meshes.new("tmp")
    for i in range(n):
        t = i / (n - 1)
        b = src.copy()
        for v in b.verts:
            L = length * (1 - uneven * 0.5 + uneven * (0.5 + 0.5 * noise.noise(v.co * 14)))
            v.co += v.normal * (L * t) + lean * (L * t * t)
        for f in b.faces:
            f.material_index = i
        b.to_mesh(tmp_me)
        b.free()
        out.from_mesh(tmp_me)
    src.free()
    bpy.data.meshes.remove(tmp_me)
    me = bpy.data.meshes.new(name)
    out.to_mesh(me)
    out.free()
    for i, img in enumerate(imgs):
        me.materials.append(hd.material(f"{mat_name}_{i:02d}", img, rough=0.92, spec=0.1, alpha_clip=i > 0))
    for p in me.polygons:
        p.use_smooth = True
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = parent if parent is not None else base_ob.parent
    ob.matrix_basis = base_ob.matrix_basis.copy()
    return ob


def tex_knit(name, base, dark, size=512, cols=22, rows=30, seed=3):
    """Grobstrick: Maschen als V-Reihen (kachelnd)."""
    v, u = np.mgrid[0:size, 0:size] / size
    cu = u * cols
    fu = cu - np.floor(cu)
    f = v * rows + np.abs(fu - 0.5) * 1.1
    ff = f - np.floor(f)
    strand = np.sin(np.pi * ff) ** 0.8
    groove = np.clip(1 - np.abs(fu - 0.5) * 2, 0, 1) ** 0.5 * 0.35 + np.clip(np.minimum(fu, 1 - fu) * 6, 0, 1) * 0.65
    height = strand * groove
    n = hd.fractal(size, 1.6, seed)
    base_l, dark_l = hd.srgb_to_linear(base), hd.srgb_to_linear(dark)
    k = np.clip(height * 1.1, 0, 1)
    col = (dark_l[None, None, :] * (1 - k[..., None]) + base_l[None, None, :] * k[..., None]) * (0.85 + 0.3 * n)[..., None]
    return (hd.to_image(name + "_color", np.clip(col, 0, 1) ** (1 / 2.2)),
            hd.to_image(name + "_normal", hd.height_to_normal(height, 5.0), non_color=True))


def skin_textures(name, diffuse_path, tint=(1.0, 1.0, 1.0), gain=1.0, contrast=1.0, saturation=1.0, bump_path=None,
                  bump=2.0, pores=0.5, seed=5):
    """Hauttextur aus dem CC0-Scan: Farbe abstimmen, Normal-Map aus Bump-Karte + feinen Poren."""
    a = image_array(diffuse_path)[..., :3] ** 2.2
    grey = a.mean(axis=2, keepdims=True)
    a = grey + (a - grey) * saturation
    a = (a - 0.18) * contrast + 0.18
    a = np.clip(a * np.array(tint, dtype=np.float32)[None, None, :] * gain, 0, 1)
    size = a.shape[0]
    height = hd.fractal(size, 0.9, seed) * pores * 0.25
    if bump_path:
        height = height + image_array(bump_path)[..., 0]
    return (hd.to_image(name + "_color", a ** (1 / 2.2)),
            hd.to_image(name + "_normal", hd.height_to_normal(height, bump), non_color=True))
