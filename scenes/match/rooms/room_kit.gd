class_name RoomKit
## Kleine Bausteine für Räume aus Grundformen (Kisten, Zylinder, Flächen, Schrift, Geräusche).
## Von U-Boot und Zirkuswagen benutzt; Casino und Bahnhof haben eigene Kopien davon.
## Dazu `model()`: Blender-Modell (.glb) einsetzen und die Materialien über ihre Namen zuordnen.


## Blender-Modell unter `parent` hängen. `mats` = { Materialname in Blender: Godot-Material }.
## So bleiben Farben, Lauflichter und Tisch-Looks im Code; Blender liefert die Form.
## Materialien, die nicht in `mats` stehen, bleiben so, wie sie aus Blender kommen.
static func model(parent: Node, scene: PackedScene, mats := {}) -> Node3D:
	var root := scene.instantiate() as Node3D
	parent.add_child(root)
	apply_materials(root, mats)
	return root


static func apply_materials(root: Node, mats: Dictionary) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var count := mi.mesh.get_surface_count()
		for i in count:
			var src := mi.mesh.surface_get_material(i)
			if src == null or not mats.has(src.resource_name):
				continue
			if count == 1: # ein Material → material_override (TableSkin tauscht darüber)
				mi.material_override = mats[src.resource_name]
			else:
				mi.set_surface_override_material(i, mats[src.resource_name])


static func mat(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func glow(c: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


static func tex(path: String, rough := 0.7, world_scale := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if world_scale > 0.0: # Textur läuft in Weltmaßen über alle Teile (keine Nähte)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * world_scale
	return m


static func box(parent: Node, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func cyl(parent: Node, top: float, bottom: float, h: float, pos: Vector3, m: Material, segs := 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func sphere(parent: Node, r: float, pos: Vector3, m: Material, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	mi.mesh = s
	mi.material_override = m
	mi.position = pos
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func torus(parent: Node, r: float, thick: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = r - thick
	t.outer_radius = r + thick
	t.rings = 40
	t.ring_segments = 10
	mi.mesh = t
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Fläche, die nach +z schaut (für Wände, Bilder, Zifferblätter).
static func quad(parent: Node, size: Vector2, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Boden- oder Deckenfläche (nach +y).
static func plane(parent: Node, size: Vector2, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = size
	mi.mesh = p
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func label(parent: Node, text: String, size: int, color: Color, pos: Vector3, pixel := 0.0012) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = preload("res://assets/fonts/RussoOne-Regular.ttf")
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	parent.add_child(l)
	return l


## Quadratische Platte mit rundem Loch in der Mitte (für Bullaugen), Blick nach +z.
static func plate_with_hole(half: float, r: float, m: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 48
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var in0 := Vector3(cos(a0), sin(a0), 0) * r
		var in1 := Vector3(cos(a1), sin(a1), 0) * r
		var out0 := Vector3(cos(a0), sin(a0), 0) * (half / maxf(absf(cos(a0)), absf(sin(a0))))
		var out1 := Vector3(cos(a1), sin(a1), 0) * (half / maxf(absf(cos(a1)), absf(sin(a1))))
		for v in [in0, out1, out0, in0, in1, out1]: # im Uhrzeigersinn = Vorderseite in Godot
			st.set_normal(Vector3.BACK)
			st.set_uv(Vector2(v.x / (half * 2) + 0.5, 0.5 - v.y / (half * 2)))
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	return mi


## Klickfläche (Kiste) für Easter Eggs.
static func click_area(parent: Node, size: Vector3, pos: Vector3, on_click: Callable) -> Area3D:
	var area := Area3D.new()
	area.input_ray_pickable = false
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	shape.shape = b
	shape.position = pos
	area.add_child(shape)
	area.input_event.connect(func(_c: Node, e: InputEvent, _p: Vector3, _n: Vector3, _i: int) -> void:
		if area.input_ray_pickable and e is InputEventMouseButton and e.pressed \
				and e.button_index == MOUSE_BUTTON_LEFT:
			area.get_viewport().set_input_as_handled()
			on_click.call())
	parent.add_child(area)
	return area


## Geräusch einmal abspielen (auf dem SFX-Bus, ohne Fenster nichts).
static func play(owner_node: Node, stream: AudioStream, db := -12.0, pitch := 1.0) -> void:
	if DisplayServer.get_name() == "headless" or owner_node == null or not owner_node.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX"
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	owner_node.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## Endlos laufendes Hintergrundgeräusch (WAV wird zur Schleife).
static func loop(owner_node: Node, stream: AudioStreamWAV, db: float) -> AudioStreamPlayer:
	if DisplayServer.get_name() == "headless":
		return null
	var st := stream.duplicate() as AudioStreamWAV
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = int(st.get_length() * st.mix_rate)
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX"
	p.stream = st
	p.volume_db = db
	owner_node.add_child(p)
	p.play()
	return p
