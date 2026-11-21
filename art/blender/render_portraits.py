"""Rendert runde Porträts der Gegner (Cycles) nach assets/portraits/<id>.png.

    python3 art/blender/render_portraits.py            # alle
    python3 art/blender/render_portraits.py crow wolf  # nur bestimmte
"""
from __future__ import annotations

import os
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "assets", "portraits")

# Kamera-Abstand/Brennweite je Charakter (Hüte und Hörner brauchen mehr Platz)
# Augenfarben wie in data/opponents/*.tres
EYE_COLORS = {"bandit": (0.95, 0.92, 0.8), "swamp_man": (0.75, 1.0, 0.25), "crow": (1.0, 0.62, 0.15),
              "wolf": (1.0, 0.7, 0.15), "jester": (0.85, 0.35, 1.0), "bone_man": (0.55, 0.85, 1.0),
              "witch": (0.7, 0.35, 1.0), "giant": (1.0, 0.35, 0.1)}

FRAMING = {"witch": (1.0, 50, 0.04), "jester": (1.0, 50, 0.08), "giant": (0.95, 60, 0.0)}


def render(name: str) -> None:
    bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, "opponents", name + ".blend"))
    sc = bpy.context.scene
    head = bpy.data.objects["Head"]
    bpy.context.view_layer.update()
    center = head.matrix_world.translation + Vector((0, 0, 0.1))
    dist, lens, up = FRAMING.get(name, (0.85, 62, 0.0))
    target = center + Vector((0, 0, up - 0.02))
    cam = bpy.data.objects.new("PortraitCam", bpy.data.cameras.new("PortraitCam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.location = target + Vector((0.2, -dist, 0.06))
    cam.data.lens = lens
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    lights = [((0.7, -1.0, 0.6), 60, (1.0, 0.85, 0.7)), ((-0.8, -0.4, 0.2), 25, (0.55, 0.5, 1.0)),
              ((0.0, 0.9, 0.5), 80, (0.75, 0.45, 1.0))]
    for i, (off, energy, color) in enumerate(lights):
        light = bpy.data.objects.new(f"PL{i}", bpy.data.lights.new(f"PL{i}", "POINT"))
        light.data.energy = energy
        light.data.color = color
        light.location = center + Vector(off)
        sc.collection.objects.link(light)
    # glühende Pupillen an den Augen-Markierungen (in Godot macht das opponent_figure.gd)
    col = EYE_COLORS.get(name, (1, 0.3, 0.1))
    eye_mat = bpy.data.materials.new("PortraitEye")
    eye_mat.use_nodes = True
    bsdf = eye_mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*col, 1)
    bsdf.inputs["Emission Color"].default_value = (*col, 1)
    bsdf.inputs["Emission Strength"].default_value = 9.0
    for ob in list(bpy.data.objects):
        if ob.name.startswith("Eye") and ob.type == "EMPTY":
            r = 0.006 if ob.name.startswith("EyeX") else 0.011
            bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=ob.matrix_world.translation)
            bpy.context.active_object.data.materials.append(eye_mat)
            glow = bpy.data.objects.new("EyeGlow", bpy.data.lights.new("EyeGlow", "POINT"))
            glow.data.energy = 0.6
            glow.data.color = col
            glow.data.shadow_soft_size = 0.01
            glow.location = ob.matrix_world.translation + Vector((0, -0.03, 0))
            sc.collection.objects.link(glow)
    world = bpy.data.worlds.new("PW")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.03, 0.09, 1)
    sc.world = world
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = False
    sc.render.resolution_x = 384
    sc.render.resolution_y = 384
    tmp = os.path.join("/tmp", f"portrait_{name}.png")
    sc.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    _round(tmp, os.path.join(OUT, name + ".png"))


def _round(src: str, dst: str) -> None:
    """Runder Ausschnitt mit weichem Rand (transparent außen)."""
    import numpy as np
    from PIL import Image, ImageFilter
    img = Image.open(src).convert("RGB").resize((256, 256), Image.LANCZOS)
    size = img.size[0]
    y, x = np.mgrid[0:size, 0:size]
    r = np.hypot(x - size / 2 + 0.5, y - size / 2 + 0.5)
    alpha = np.clip((size / 2 - 1 - r) / 1.5, 0, 1)
    rgba = np.dstack([np.asarray(img), (alpha * 255).astype(np.uint8)])
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    Image.fromarray(rgba, "RGBA").filter(ImageFilter.SMOOTH).save(dst, optimize=True)
    print("Porträt:", os.path.relpath(dst, REPO))


if __name__ == "__main__":
    sys.path.insert(0, HERE)
    import characters
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    for n in (args or list(characters.CHARACTERS)):
        render(n)
