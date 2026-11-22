"""Der Sumpfmann in HD (nach dem Konzeptbild „Am Spieltisch“, Feld 2):
massiger Klumpen aus nassem Schlamm und Rinde, der Kopf ein Dom ohne Hals, tiefe runde Augenhöhlen
mit glühenden gelben Augen, zackiges Maul mit Schlammzähnen, überall herabrinnender Schlamm,
Moospolster auf Kopf, Schultern und Handgelenken, Zweige aus dem Schädel, Pilze auf Schultern
und Kopf, riesige Schlammhände.

    import hd_swamp_man; hd_swamp_man.build()
    hd_swamp_man.build(steps=("head",))    # nur Teile
"""
from __future__ import annotations

import math
import random

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

import characters as ch
import hd
from geo import G

C = Vector((0, 0, 0.1))  # Schädelmitte (Head-Koordinaten)
HEAD_Y = 1.13
HEAD_SCALE = 1.3
RX, RY, RZ = 0.165, 0.158, 0.19
EYES = [(-0.068, 0.035), (0.068, 0.035)]
MOUTH_Z, MOUTH_W, MOUTH_H = -0.092, 0.07, 0.023


# =====================================================================================
#  Texturen und Materialien
# =====================================================================================

def _aniso(size, beta, seed, stretch):
    """Kachelbares Rauschen, senkrecht gestreckt (Rinnsale, Rindenfasern)."""
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((size, size))
    fy = np.fft.fftfreq(size)[:, None] * stretch
    fx = np.fft.fftfreq(size)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    spec = np.fft.fft2(white) / f ** (beta / 2.0)
    spec[0, 0] = 0
    out = np.real(np.fft.ifft2(spec))
    out -= out.min()
    return out / max(out.max(), 1e-9)


def tex_mud(name, base, dark, moss=(0.2, 0.24, 0.07), size=1024, seed=91, mossy=0.5, streak=7.0):
    """Nasser Schlamm mit herablaufenden Rinnsalen, Rissen und grünlichen Moosflecken."""
    big = hd.fractal(size, 2.6, seed)
    streaks = _aniso(size, 1.8, seed + 1, streak)
    fine = hd.fractal(size, 1.0, seed + 2)
    cr = hd.ridged(hd.fractal(size, 2.2, seed + 3))
    cracks = np.clip((cr - 0.88) * 7, 0, 1)
    rills = np.clip((hd.ridged(streaks) - 0.8) * 4, 0, 1)
    moss_m = np.clip((hd.fractal(size, 3.0, seed + 4) - (0.78 - 0.25 * mossy)) * 4, 0, 1) * mossy
    base_l, dark_l, moss_l = hd.srgb_to_linear(base), hd.srgb_to_linear(dark), hd.srgb_to_linear(moss)
    t = np.clip(0.45 * big + 0.4 * streaks + 0.15 * fine, 0, 1)
    col = dark_l + (base_l - dark_l) * (0.2 + 0.8 * t)[..., None]
    col *= (1 - 0.45 * cracks)[..., None]
    col *= (1 - 0.25 * rills)[..., None]
    col = col * (1 - 0.75 * moss_m[..., None]) + moss_l * 0.75 * moss_m[..., None]
    height = big * 0.5 + streaks * 1.0 + fine * 0.2 - cracks * 1.2 + rills * 0.5 + moss_m * 0.3
    return (hd.to_image(name + "_color", col ** (1 / 2.2)),
            hd.to_image(name + "_normal", hd.height_to_normal(height, 4.0), non_color=True))


def materials():
    m = {}
    c, n = tex_mud("mud", (0.37, 0.26, 0.13), (0.065, 0.045, 0.024), seed=91, mossy=0.45)
    m["mud"] = hd.material("Sumpf_Schlamm", c, n, rough=0.5, normal_strength=1.8, spec=0.45)
    c, n = tex_mud("head", (0.36, 0.25, 0.12), (0.06, 0.04, 0.02), seed=93, mossy=0.7)
    m["head"] = hd.material("Sumpf_Kopf", c, n, rough=0.5, normal_strength=1.6, spec=0.45)
    c, n = tex_mud("wet", (0.32, 0.22, 0.11), (0.12, 0.08, 0.04), seed=95, mossy=0.0, streak=12.0)
    m["wet"] = hd.material("Sumpf_Nass", c, n, rough=0.3, normal_strength=0.6, spec=0.55)
    c, n = tex_mud("bark", (0.26, 0.19, 0.12), (0.07, 0.05, 0.03), seed=97, mossy=0.15, streak=14.0)
    m["bark"] = hd.material("Sumpf_Rinde", c, n, rough=0.85, normal_strength=1.5, spec=0.2)
    c, n = hd.tex_hair("moss", (0.06, 0.08, 0.02), (0.38, 0.47, 0.11), seed=98, strands=50)
    m["moss"] = hd.material("Sumpf_Moos", c, n, rough=0.95, normal_strength=0.5, double_sided=True, spec=0.1,
                            alpha_clip=True)
    c, n = hd.tex_hair("mossdrip", (0.06, 0.08, 0.025), (0.24, 0.3, 0.08), w=64, h=256, seed=99, strands=24)
    m["mossdrip"] = hd.material("Sumpf_Moosfaeden", c, n, rough=0.9, normal_strength=0.4, double_sided=True,
                                spec=0.1, alpha_clip=True)
    c, n = hd.tex_skin("cap", (0.42, 0.28, 0.16), size=256, seed=101, pores=0.4, blotch=1.6)
    m["cap"] = hd.material("Sumpf_Pilzhut", c, n, rough=0.6, normal_strength=0.6, spec=0.3)
    m["stem"] = hd.material("Sumpf_Pilzstiel", color=(0.3, 0.24, 0.16, 1), rough=0.8, spec=0.2)
    m["gills"] = hd.material("Sumpf_Lamellen", color=(0.2, 0.14, 0.09, 1), rough=0.9, spec=0.1)
    m["nail"] = hd.material("Sumpf_Nagel", color=(0.1, 0.07, 0.045, 1), rough=0.5, spec=0.3)
    m["eye"] = hd.material("Sumpf_Auge", color=(1.0, 0.5, 0.08, 1), rough=0.3,
                           emission=(1.0, 0.42, 0.05, 1), emission_strength=1.3)
    m["eyecore"] = hd.material("Sumpf_Augenkern", color=(1.0, 0.85, 0.4, 1), rough=0.3,
                               emission=(1.0, 0.75, 0.25, 1), emission_strength=2.0)
    m["tooth"] = hd.material("Sumpf_Zahn", color=(0.2, 0.145, 0.075, 1), rough=0.55, spec=0.35)
    return m


# =====================================================================================
#  Hilfen
# =====================================================================================

def _g(a, s):
    return math.exp(-(a * a) / (2 * s * s))


def tufts(name, pts, mat, parent, rnd, length, width, flow=0.6, up=0.8, down=0.0, lift=(0.2, 0.45),
          curl=(0.05, 0.2), along=4):
    """Alpha-Büschel (Moos, Fasern) auf Punkten; Vorderseite jedes Büschels nach außen.
    Name muss auf „_Fur“ enden (Godot: keine Schatten, kein Glanz)."""
    mb = hd.MeshBuilder()
    spans = []
    for p, nrm in pts:
        first = len(mb.bm.faces)
        L = rnd.uniform(*length)
        fl = Vector((noise.noise(p * 30), noise.noise(p * 30 + Vector((5, 0, 0))), noise.noise(p * 30 + Vector((0, 9, 0)))))
        direction = nrm * up + fl * flow + Vector((rnd.uniform(-0.2, 0.2), rnd.uniform(-0.2, 0.2), -down))
        hd.add_feather(mb, p - nrm * 0.003, nrm, direction, L, L * rnd.uniform(*width),
                       lift=rnd.uniform(*lift), curl=rnd.uniform(*curl), cup=0.15,
                       twist=rnd.uniform(-0.6, 0.6), along=along, across=3, shape=0.6)
        spans.append((first, len(mb.bm.faces), nrm.copy()))
    mb.bm.faces.ensure_lookup_table()
    flip = []
    for a, b, nrm in spans:
        if b > a:
            mb.bm.faces[a].normal_update()
            if mb.bm.faces[a].normal.dot(nrm) < 0:
                flip.extend(mb.bm.faces[i] for i in range(a, b))
    bmesh.ops.reverse_faces(mb.bm, faces=flip)
    return mb.finish(name, mat, parent=parent)


def _moss_mask(p, scale=6.0, bias=0.1):
    return noise.noise(p * scale) + 0.45 * noise.noise(p * scale * 2.6 + Vector((3, 1, 2))) > bias


def mushroom(base: Vector, up: Vector, s: float, rnd, caps, stems, gills):
    """Kleiner Pilz: leicht gebogener Stiel, gewölbter Hut, dunkle Lamellen darunter."""
    h = rnd.uniform(0.045, 0.075) * s
    rot = Vector((0, 0, 1)).rotation_difference(up.normalized()).to_matrix().to_4x4()
    bend = Matrix.Rotation(rnd.uniform(-0.35, 0.35), 4, "X") @ Matrix.Rotation(rnd.uniform(-0.35, 0.35), 4, "Y")
    M = Matrix.Translation(base) @ rot @ bend
    rs = 0.0075 * s
    stems.append(ch.geo.transform(ch.geo.lathe([(0.0, -0.01), (rs * 1.4, -0.01), (rs * 1.1, h * 0.3), (rs, h * 0.8),
                                                (rs * 0.9, h), (0.0, h)], 12, 0.05), M))
    R = rnd.uniform(0.032, 0.048) * s
    dome = rnd.uniform(0.45, 0.8)
    prof = [(R * 0.18, h - 0.001), (R * 0.98, h - 0.002 * s)]
    for k in range(1, 8):
        a = k / 7 * math.pi / 2
        prof.append((R * math.cos(a) * (1.0 if k > 1 else 1.02), h + R * dome * math.sin(a) + 0.002 * s))
    prof[-1] = (0.0, prof[-1][1])
    caps.append(ch.geo.transform(ch.geo.lathe(prof, 20, 0.08), M))
    gills.append(ch.geo.transform(ch.geo.lathe([(rs * 1.1, h - 0.0005), (R * 0.95, h + 0.0015 * s)], 20, 0.05), M))


def branch(pts_out, radii_out, p, d, length, r, depth, rnd):
    """Knorriger Zweig als Röhre, mit Seitenzweigen."""
    n = 6
    pts, radii = [p.copy()], [r]
    q, dd = p.copy(), d.normalized()
    for k in range(1, n + 1):
        dd = (dd + Vector((rnd.uniform(-0.35, 0.35), rnd.uniform(-0.35, 0.35), rnd.uniform(-0.1, 0.3)))).normalized()
        q = q + dd * (length / n)
        pts.append(q.copy())
        radii.append(r * (1 - k / n) * 0.9 + 0.0008)
    pts_out.append(pts)
    radii_out.append(radii)
    if depth < 2:
        for _ in range(rnd.randint(1, 2)):
            k = rnd.randint(2, 4)
            side = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(0.2, 0.8)))
            branch(pts_out, radii_out, pts[k], (dd + side).normalized(), length * 0.5, radii[k] * 0.75, depth + 1, rnd)


def drip(surf, x, z0, length, r, rnd, lift=-0.0005):
    """Herablaufender Schlamm-Tropfen entlang der Oberfläche (Strahl von vorne), unten ein Tropfen."""
    n = 8
    pts, radii = [], []
    wob = rnd.uniform(0, 6)
    for k in range(n + 1):
        t = k / n
        z = z0 - length * t
        xx = x + 0.003 * math.sin(t * 5 + wob)
        p, nrm = surf(xx, z, lift + r * (0.25 + 0.6 * t))
        pts.append(p)
        radii.append(r * (1.0 - 0.35 * t) * (1 + 0.1 * math.sin(t * 7 + wob)) * (1.3 if k == 0 else 1.0))
    end = pts[-1] + Vector((0, 0, -r * 1.3))
    drop = ch.geo.ellipsoid(Vector((r * 1.05, r * 1.05, r * 1.5)), end, 12, 8)
    return ch.geo.merge(ch.geo.tube(pts, radii, seg=8), drop)


# =====================================================================================
#  Kopf (Head-Koordinaten, vorne = -Y)
# =====================================================================================

def head_shape(c: Vector, d: Vector) -> Vector:
    x, z = c.x, c.z
    front = max(0.0, -d.y)
    off = Vector()
    # Dom: unten breit (geht in die Schultern über), oben schmaler
    off.x += c.x * (0.09 * max(0.0, -z) / RZ - 0.02 * max(0.0, z) / RZ)
    off.z -= 0.015 * (max(0.0, z) / RZ) ** 2  # etwas flacherer Dom
    off.y += c.y * 0.06 * max(0.0, -z) / RZ
    # schwere Stirn über den Augen
    off.y -= 0.024 * front ** 2 * _g(z - 0.072, 0.02) * _g(abs(x) - 0.068, 0.05)
    # tiefe runde Augenhöhlen mit aufgeworfenem Rand
    for ex, ez in EYES:
        dist = math.hypot(x - ex, z - ez)
        off.y += 0.036 * front * _g(dist, 0.027)
        off.y -= 0.012 * front * _g(dist - 0.044, 0.009)
    # Maul: Mulde
    off.y += 0.018 * front * _g(x, 0.055) * _g(z - MOUTH_Z, 0.026)
    # Nasenwulst (nur angedeutet) zwischen den Augen
    off.y -= 0.01 * front * _g(x, 0.015) * _g(z - 0.0, 0.025)
    # senkrechte Schlammrinnen und Klumpen
    n1 = noise.noise(Vector((x * 26, c.y * 26, z * 3.5)))
    ridge = 1 - abs(n1)
    lump = noise.noise(c * 11)
    off += d * (0.016 * ridge ** 2 + 0.009 * lump + 0.004 * noise.noise(c * 40))
    return c + off


def build_head(rig, m, rnd):
    head = ch.Head((RX, RY, RZ), u=110, v=72)
    head.deform(head_shape)
    face = rig.headpart("Face", head.bm.copy(), m["head"], smooth=True, sharp_angle=None)
    hd.organic(face, voxel=0.0016, smooth=1, faces=32000, uv_tile=0.16)
    fb = bmesh.new()
    fb.from_mesh(face.data)
    tree = BVHTree.FromBMesh(fb)
    sample = fb.copy()
    fb.free()

    def surf(x, z, lift=0.0):
        hit = tree.ray_cast(C + Vector((x, -0.6, z)), Vector((0, 1, 0)))
        if hit[0] is None:
            return C + Vector((x, -RY, z)), Vector((0, -1, 0))
        return hit[0] + hit[1] * lift, hit[1]

    eyes(rig, m, surf)
    mouth(rig, m, surf, rnd)
    face_drips(rig, m, surf, rnd)
    twigs_and_shrooms(rig, m, tree, rnd)
    # Moos oben auf dem Dom
    pts = [(p, n) for p, n in hd.sample_surface(sample, 30000, rnd)
           if n.z > 0.15 and (p - C).z > 0.05 and ((p - C).z > 0.13 or _moss_mask(p, 7.0, -0.25))]
    sample.free()
    tufts("HeadMoss_Fur", pts[:10000], m["moss"], rig.head, rnd, (0.012, 0.024), (0.35, 0.55), up=1.0)
    return face


def eyes(rig, m, surf):
    """Glühende Augen in den Höhlen (selbstleuchtend). Die Godot-Marker sitzen im Augapfel,
    damit nur das Licht dazukommt, nicht die kleine Glutkugel."""
    outer, core, rims = [], [], []
    for i, (ex, ez) in enumerate(EYES):
        p, _n = surf(ex, ez)
        c = p + Vector((0, 0.006, 0))
        outer.append(ch.geo.ellipsoid(Vector((0.034, 0.022, 0.034)), c, 28, 18))
        core.append(ch.geo.ellipsoid(Vector((0.02, 0.008, 0.02)), c + Vector((0, -0.0165, 0.001)), 20, 12))
        rig.marker("EyeL" if i == 0 else "EyeR", rig.head, c)
        ring = []
        for k in range(33):
            a = k / 32 * math.tau
            rr = 0.041 + 0.003 * math.sin(a * 5 + i)
            q, nq = surf(ex + rr * math.cos(a), ez + rr * math.sin(a))
            ring.append(q + nq * 0.002)
        rims.append(ch.geo.tube(ring, [0.009 + 0.003 * math.sin(k * 1.3 + i) for k in range(33)], seg=10,
                                cap_start=False))
    rig.headpart("Socket_Rims", ch.geo.merge(*rims), m["head"], smooth=True, sharp_angle=None)
    rig.headpart("Glow_Eyes", ch.geo.merge(*outer), m["eye"], smooth=True, sharp_angle=None)
    rig.headpart("Glow_EyeCores", ch.geo.merge(*core), m["eyecore"], smooth=True, sharp_angle=None)


def mouth(rig, m, surf, rnd):
    """Zackiges Maul: schwarze Öffnung, wulstiger Rand, Schlammzähne oben und unten."""
    cols = 26
    void = bmesh.new()
    top_e, bot_e = [], []
    rows = []
    for k in range(cols + 1):
        u = k / cols * 2 - 1
        x = u * MOUTH_W
        env = max(0.0, 1 - u * u) ** 0.6
        jag = 0.004 * math.sin(k * 2.3) * env
        zt = MOUTH_Z + MOUTH_H * env * 0.75 + jag
        zb = MOUTH_Z - MOUTH_H * env * 0.55 - 0.002 * math.sin(k * 1.7)
        col = []
        for t in (0.0, 0.5, 1.0):
            z = zt + (zb - zt) * t
            p, n = surf(x, z, 0.0008)
            col.append(void.verts.new(p))
        rows.append(col)
        top_e.append(surf(x, zt, 0.002)[0])
        bot_e.append(surf(x, zb, 0.002)[0])
    for k in range(cols):
        for t in range(2):
            void.faces.new((rows[k][t], rows[k + 1][t], rows[k + 1][t + 1], rows[k][t + 1]))
    rig.headpart("Void_Mouth", void, ch.void(), smooth=True, sharp_angle=None)
    # Lippenwulst rundherum
    ring = top_e + list(reversed(bot_e))[1:-1] + [top_e[0]]
    lip_r = [0.0045 + 0.002 * math.sin(i * 0.9) for i in range(len(ring))]
    rig.headpart("Mouth_Lip", ch.geo.tube(ring, lip_r, seg=8, cap_start=False), m["head"], smooth=True,
                 sharp_angle=None)
    # Zähne: oben hängende Schlammzapfen, unten kurze Stummel
    teeth = []
    for k in range(2, cols - 1, 2):
        u = k / cols * 2 - 1
        x = u * MOUTH_W + rnd.uniform(-0.002, 0.002)
        env = max(0.0, 1 - u * u) ** 0.6
        a = top_e[k] + Vector((0, 0.001, 0))
        L = rnd.uniform(0.009, 0.019) * (0.5 + 0.5 * env)
        teeth.append(ch.geo.tube([a, a + Vector((rnd.uniform(-0.002, 0.002), 0.0, -L * 0.6)),
                                  a + Vector((rnd.uniform(-0.003, 0.003), 0.001, -L))],
                                 [0.0042, 0.003, 0.0006], seg=8))
    for k in range(3, cols - 2, 3):
        b = bot_e[k] + Vector((0, 0.001, 0))
        L = rnd.uniform(0.006, 0.011)
        teeth.append(ch.geo.tube([b, b + Vector((0, 0.0, L * 0.6)), b + Vector((rnd.uniform(-0.002, 0.002), 0.001, L))],
                                 [0.0038, 0.0026, 0.0006], seg=8))
    rig.headpart("Mouth_Teeth", ch.geo.merge(*teeth), m["tooth"], smooth=True, sharp_angle=None)


def face_drips(rig, m, surf, rnd):
    """Schlamm rinnt von der Stirn über die Augen, von den Wangen und aus dem Maul."""
    parts = []
    starts = []
    for ex, ez in EYES:  # vom Stirnwulst neben den Augen (nicht über die Glut)
        for k in range(6):
            side = rnd.choice((-1, 1))
            starts.append((ex + side * rnd.uniform(0.038, 0.055), ez + rnd.uniform(0.02, 0.05), rnd.uniform(0.04, 0.09)))
        starts.append((ex + rnd.uniform(-0.012, 0.012), ez + 0.058, rnd.uniform(0.012, 0.02)))  # kurz über dem Rand
    for k in range(7):  # Wangen
        sx = rnd.choice((-1, 1))
        starts.append((sx * rnd.uniform(0.07, 0.12), rnd.uniform(-0.03, 0.01), rnd.uniform(0.04, 0.08)))
    for k in range(11):  # aus dem Maul („Bart“ aus Schlamm)
        starts.append((rnd.uniform(-0.06, 0.06), MOUTH_Z - 0.016, rnd.uniform(0.025, 0.07)))
    for x, z, L in starts:
        parts.append(drip(surf, x, z, L, rnd.uniform(0.0035, 0.006), rnd))
    rig.headpart("Face_Drips", ch.geo.merge(*parts), m["head"], smooth=True, sharp_angle=None)


def twigs_and_shrooms(rig, m, tree, rnd):
    """Zweige wachsen oben/seitlich aus dem Schädel, zwei Pilze an der linken Kopfseite."""
    pts_all, radii_all = [], []
    spots = [(-0.11, 0.02, 0.15), (-0.06, 0.06, 0.19), (0.0, 0.08, 0.2), (0.07, 0.05, 0.18), (0.12, 0.0, 0.13),
             (-0.15, 0.03, 0.06), (0.15, 0.04, 0.08), (0.03, 0.1, 0.17), (-0.13, 0.07, 0.11), (0.13, 0.08, 0.12)]
    for sx, sy, sz in spots:
        target = C + Vector((sx, sy, sz))
        dirv = (target - C).normalized()
        hit = tree.ray_cast(C + dirv * 0.5, -dirv)
        p = hit[0] if hit[0] is not None else target
        n = hit[1] if hit[0] is not None else dirv
        d = (n + Vector((0, 0, 0.6))).normalized()
        branch(pts_all, radii_all, p - n * 0.012, d, rnd.uniform(0.1, 0.17), rnd.uniform(0.009, 0.013), 0, rnd)
    rig.headpart("Twigs", ch.geo.merge(*[ch.geo.tube(p, r, seg=6) for p, r in zip(pts_all, radii_all)]),
                 m["bark"], smooth=True, sharp_angle=None)
    caps, stems, gills = [], [], []
    for (x, z, s) in ((-0.15, 0.0, 0.8), (-0.14, -0.05, 0.6), (0.155, 0.06, 0.5)):
        dirv = Vector((x, -0.02, z)).normalized()
        hit = tree.ray_cast(C + dirv * 0.5, -dirv)
        if hit[0] is None:
            continue
        mushroom(hit[0] - hit[1] * 0.004, hit[1] * 0.35 + Vector((0, 0, 1.0)), s, rnd, caps, stems, gills)
    rig.headpart("Shroom_Caps", ch.geo.merge(*caps), m["cap"], smooth=True, sharp_angle=None)
    rig.headpart("Shroom_Stems", ch.geo.merge(*stems), m["stem"], smooth=True, sharp_angle=None)
    rig.headpart("Shroom_Gills", ch.geo.merge(*gills), m["gills"], smooth=True, sharp_angle=None)


# =====================================================================================
#  Körper (Torso-Koordinaten)
# =====================================================================================

PROFILE = [(0.3, -0.15), (0.31, 0.1), (0.315, 0.45), (0.325, 0.72), (0.33, 0.84), (0.325, 0.92),
           (0.3, 0.99), (0.25, 1.06), (0.19, 1.13), (0.135, 1.2), (0.1, 1.26), (0.07, 1.3)]
SX, SY = 1.55, 0.86


def _radius(z):
    prof = PROFILE
    if z <= prof[0][1]:
        return prof[0][0]
    for (r0, z0), (r1, z1) in zip(prof, prof[1:]):
        if z0 <= z <= z1:
            t = (z - z0) / (z1 - z0)
            t = t * t * (3 - 2 * t)
            return r0 + (r1 - r0) * t
    return prof[-1][0]


def body_point(th, z):
    r = _radius(z)
    n1 = noise.noise(Vector((math.cos(th) * 7.0, math.sin(th) * 7.0, z * 0.8)))
    ridge = 1 - abs(n1)
    lump = noise.noise(Vector((math.cos(th) * 3, math.sin(th) * 3, z * 3)))
    rr = r + 0.034 * ridge ** 3 + 0.014 * lump
    x = rr * SX * math.cos(th)
    y = rr * SY * math.sin(th)
    # Buckel nach vorn, Nackenwulst vorne flacher (Maul bleibt frei)
    if z > 0.75:
        t = min(1.0, (z - 0.75) / 0.4)
        y -= 0.07 * t * max(0.0, 1 - abs(x) / 0.5)
    if z > 0.93 and math.sin(th) < 0:
        y *= 1 - 0.72 * min(1.0, (z - 0.93) / 0.16) * (-math.sin(th)) ** 0.7
    # massige Schultern, Brustmuskeln
    sh = _g(abs(x) - 0.36, 0.09) * _g(z - 0.95, 0.075)
    pec = _g(abs(x) - 0.13, 0.08) * _g(z - 0.78, 0.07) * max(0.0, -math.sin(th))
    return Vector((x, y - 0.02 * pec, z + 0.05 * sh))


def build_body(rig, m, rnd):
    tb = rig.torso
    mb = hd.MeshBuilder()
    zs = [-0.15 + i * 0.0102 for i in range(130)]
    seg = 128
    rows, uvs = [], []
    for z in zs:
        rows.append([body_point(j / seg * math.tau, z) for j in range(seg)])
        uvs.append([(j / seg * 5.0, z * 2.5) for j in range(seg)])
    mb.grid(rows, uvs, close=True)
    sample = mb.bm.copy()
    body = mb.finish("Body", m["mud"], parent=tb)

    for side in (-1, 1):
        rig.marker("Shoulder_L" if side < 0 else "Shoulder_R", tb, Vector((side * 0.4, 0.02, 0.95)))

    pts = hd.sample_surface(sample, 80000, rnd)
    sample.free()
    # Moospolster oben auf Schultern und Rücken
    top = [(p, n) for p, n in pts if n.z > 0.25 and p.z > 0.84 and _moss_mask(p, 5.0, -0.2)]
    tufts("BodyMoss_Fur", top[:12000], m["moss"], tb, rnd, (0.014, 0.028), (0.35, 0.55), up=1.0)
    # herabhängende Moosfäden an den Schulterkanten
    hang = [(p, n) for p, n in pts if -0.2 < n.z < 0.45 and 0.78 < p.z < 1.02 and abs(p.x) > 0.2
            and _moss_mask(p, 5.0, 0.05)]
    tufts("BodyMossHang_Fur", hang[:900], m["mossdrip"], tb, rnd, (0.04, 0.09), (0.25, 0.4), flow=0.2, up=0.15,
          down=1.0, lift=(0.05, 0.15), curl=(0.0, 0.05), along=5)

    # Schlammtropfen an Brust und Schultern
    btree = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())

    def bsurf(x, z, lift=0.0):
        hit = btree.ray_cast(Vector((x, -0.8, z)), Vector((0, 1, 0)))
        if hit[0] is None:
            return Vector((x, -0.3, z)), Vector((0, -1, 0))
        return hit[0] + hit[1] * lift, hit[1]

    drips = []
    for k in range(16):
        x = rnd.choice((-1, 1)) * rnd.uniform(0.08, 0.42)
        drips.append(drip(bsurf, x, rnd.uniform(0.86, 1.0), rnd.uniform(0.06, 0.16), rnd.uniform(0.004, 0.007), rnd))
    rig.body("Body_Drips", ch.geo.merge(*drips), m["mud"], smooth=True, sharp_angle=None)

    # Pilzgruppen auf den Schultern (rechts mehr, wie im Konzept)
    caps, stems, gills = [], [], []
    for (x, y, n_sh, s) in ((0.4, -0.02, 5, 1.1), (-0.42, 0.0, 3, 0.85)):
        for k in range(n_sh):
            xx = x + rnd.uniform(-0.07, 0.07)
            yy = y + rnd.uniform(-0.06, 0.05)
            hit = btree.ray_cast(Vector((xx, yy, 1.4)), Vector((0, 0, -1)))
            if hit[0] is None:
                continue
            mushroom(hit[0] - Vector((0, 0, 0.004)), hit[1] * 0.3 + Vector((math.copysign(0.15, x), 0, 1.0)),
                     s * rnd.uniform(0.6, 1.15), rnd, caps, stems, gills)
    rig.body("Body_ShroomCaps", ch.geo.merge(*caps), m["cap"], smooth=True, sharp_angle=None)
    rig.body("Body_ShroomStems", ch.geo.merge(*stems), m["stem"], smooth=True, sharp_angle=None)
    rig.body("Body_ShroomGills", ch.geo.merge(*gills), m["gills"], smooth=True, sharp_angle=None)


# =====================================================================================
#  Hände und Arme
# =====================================================================================

def mud_limb(name, mat, r0, r1, seed=0, bulge=0.12):
    """Nackter Schlammarm (Länge 1 entlang Z, -0.5 körpernah), senkrechte Rinnen, Muskelwulst."""
    mb = hd.MeshBuilder()
    rows, uvs = [], []
    n_r, n_z = 40, 40
    for i in range(n_z + 1):
        t = i / n_z
        z = -0.5 + t
        r = (r0 + (r1 - r0) * t) * (1 + bulge * math.sin(math.pi * t) ** 2)
        row, uvr = [], []
        for j in range(n_r):
            a = j / n_r * math.tau
            n1 = noise.noise(Vector((math.cos(a) * 2.5, math.sin(a) * 2.5, z * 1.2 + seed * 3.1)))
            lump = noise.noise(Vector((math.cos(a) * 1.5, math.sin(a) * 1.5, z * 4 + seed)))
            rr = r * (1 + 0.07 * (1 - abs(n1)) + 0.05 * lump)
            row.append(Vector((rr * math.cos(a), rr * math.sin(a), z)))
            uvr.append((j / n_r * 1.2, t * 0.55))
        rows.append(row)
        uvs.append(uvr)
    vs = mb.grid(rows, uvs, close=True)
    mb.bm.faces.new(list(reversed(vs[0])))
    mb.bm.faces.new(vs[-1])
    return mb.finish(name, mat)


def hands_and_arms(rig, m, rnd):
    hands = [hd.grip_hand(side, m["mud"], m["nail"], size=1.32, thick=1.35, knobby=0.4, pitch=-0.45,
                          finger_len=1.05, wrist_back=0.07, wrist_up=0.0) for side in (-1, 1)]
    for side, h in zip((-1, 1), hands):
        h.location = G(side * 0.1, 0.9, 0.22)
        # Moos am Handgelenk (Kind der Hand → bewegt sich mit)
        bm = bmesh.new()
        bm.from_mesh(h.data)
        pts = [(p, n) for p, n in hd.sample_surface(bm, 6000, rnd)
               if p.y > -0.035 and n.z > -0.3 and _moss_mask(p, 9.0, -0.25)]
        bm.free()
        tufts(h.name + "_Fur", pts[:700], m["moss"], h, rnd, (0.01, 0.022), (0.6, 0.9), up=1.0)
    upper = mud_limb("SleeveUpper", m["mud"], 0.098, 0.085, seed=1, bulge=0.14)
    fore = mud_limb("SleeveFore", m["mud"], 0.088, 0.07, seed=2, bulge=0.1)
    hd.preview_arms(upper, fore, hands[0], hands[1])


# =====================================================================================

def scale_head(rig, s):
    """Kopf als Ganzes vergrößern (um die Schädelmitte), Marker mit."""
    for ob in rig.head.children:
        ob.location = C + (Vector(ob.location) - C) * s
        if ob.type == "MESH":
            ob.data.transform(Matrix.Scale(s, 4))


def build(steps=("head", "body", "hands"), seed=21):
    rnd = random.Random(seed)
    if set(steps) >= {"head", "body", "hands"}:
        hd.clear_scene()
    rig = ch.Rig(HEAD_Y)
    m = materials()
    if "head" in steps:
        build_head(rig, m, rnd)
        scale_head(rig, HEAD_SCALE)
    if "body" in steps:
        build_body(rig, m, rnd)
    if "hands" in steps:
        hands_and_arms(rig, m, rnd)
    return rig
