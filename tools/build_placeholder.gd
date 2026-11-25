extends SceneTree
## Baut die Figur für die Platzhalter-Gegner (Kapuzengestalt aus Grundformen, kein Blender).
##   godot --headless --path . -s res://tools/build_placeholder.gd
## Schreibt res://assets/models/placeholder/shadow_figure.tscn mit denselben Knotennamen wie
## die echten Gegner-Modelle (Torso, Head, Eye*, Hand_L/R, Sleeve, Shoulder_L/R), damit
## OpponentFigure sie ganz normal bewegen kann. Die Augenfarbe kommt aus den Gegnerdaten.

const OUT := "res://assets/models/placeholder/shadow_figure.tscn"


func _init() -> void:
	var root := Node3D.new()
	root.name = "ShadowFigure"
	var cloth := _mat(Color(0.12, 0.11, 0.13), 0.85)
	var cloth_dark := _mat(Color(0.06, 0.055, 0.07), 0.9)
	var glove := _mat(Color(0.28, 0.26, 0.25), 0.7)
	var trim := _mat(Color(0.45, 0.36, 0.2), 0.45)
	trim.metallic = 0.6

	var torso := Node3D.new()
	torso.name = "Torso"
	root.add_child(torso)
	# Umhang: unten breit, zu den Schultern schmal
	_add(torso, "Cloak", _cyl(0.24, 0.42, 0.75), Vector3(0, 0.72, 0), cloth)
	_add(torso, "Shoulders", _sphere(0.3, 0.36), Vector3(0, 1.06, 0), cloth, Vector3(1.25, 0.55, 0.85))
	_add(torso, "Clasp", _sphere(0.035, 0.05), Vector3(0, 1.08, 0.24), trim)
	for side in [-1.0, 1.0]:
		var sh := Marker3D.new()
		sh.name = "Shoulder_L" if side < 0 else "Shoulder_R"
		sh.position = Vector3(side * 0.34, 1.04, 0.02)
		torso.add_child(sh)
	# Kopf: Kapuze mit schwarzem Gesichtsloch, darin glühen die Augen
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.33, 0.03)
	torso.add_child(head)
	_add(head, "Hood", _sphere(0.17, 0.4), Vector3(0, 0.02, -0.07), cloth, Vector3(1.0, 1.1, 1.0))
	_add(head, "HoodTip", _cyl(0.0, 0.1, 0.16), Vector3(0, 0.2, -0.1), cloth, Vector3.ONE, Vector3(-0.5, 0, 0))
	_add(head, "Void_Face", _sphere(0.115, 0.26), Vector3(0, -0.01, 0.075), cloth_dark, Vector3(1.0, 1.15, 0.6))
	for side in [-1.0, 1.0]:
		var eye := Marker3D.new()
		eye.name = "Eye_L" if side < 0 else "Eye_R"
		eye.position = Vector3(side * 0.045, 0.005, 0.15)
		head.add_child(eye)
	# Hände (halten die Karten) und Ärmel
	for side in [-1.0, 1.0]:
		var hand := Node3D.new()
		hand.name = "Hand_L" if side < 0 else "Hand_R"
		hand.position = Vector3(side * 0.15, 0.86, 0.2)
		root.add_child(hand)
		_add(hand, "Glove", _sphere(0.045, 0.08), Vector3.ZERO, glove, Vector3(1.0, 0.7, 1.2))
		_add(hand, "Thumb", _sphere(0.018, 0.04), Vector3(-side * 0.035, 0.01, 0.02), glove)
	var sleeve := MeshInstance3D.new()
	sleeve.name = "Sleeve"
	var sm := _cyl(0.05, 0.065, 1.0)
	sm.material = cloth
	sleeve.mesh = sm
	root.add_child(sleeve)

	_own(root, root)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
		err = ResourceSaver.save(packed, OUT)
	print("Platzhalter-Figur: ", OUT, " → ", error_string(err))
	root.free()
	quit()


func _own(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		_own(c, owner_node)


func _add(parent: Node, n: String, mesh: PrimitiveMesh, pos: Vector3, m: Material,
		scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mesh.material = m
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 32
	return c


func _sphere(r: float, h: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h
	return s


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
