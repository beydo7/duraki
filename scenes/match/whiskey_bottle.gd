class_name WhiskeyBottle
extends Node3D
## Whiskeyflasche auf dem Tisch (ersetzt die grüne Flasche aus props.glb): eckiger,
## bernsteinfarbener Glaskörper mit Whiskey drin, Hals, schwarzer Verschluss mit Goldring
## und ein Etikett der erfundenen Marke „Hinterzimmer“.
## Ursprung = Mitte des Flaschenbodens. Signal `clicked`, wenn man sie anklickt.

signal clicked

const POS := Vector3(0.68, 0.8, 0.0)
const BODY := Vector2(0.066, 0.165) # Breite, Höhe
const NECK_TOP := 0.268 # Höhe der Öffnung (für das Einschenken)

var fill := 0.78: # 0..1 Füllstand
	set(v):
		fill = clampf(v, 0.05, 1.0)
		_update_fill()

var _liquid: MeshInstance3D


func _ready() -> void:
	position = POS
	rotation.y = 0.35 # Etikett leicht zur Kamera gedreht
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.42, 0.3, 0.28)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	glass.clearcoat_enabled = true
	glass.rim_enabled = true
	glass.rim = 0.4
	var whiskey := StandardMaterial3D.new()
	whiskey.albedo_color = Color(0.34, 0.15, 0.04)
	whiskey.roughness = 0.1
	whiskey.emission_enabled = true
	whiskey.emission = Color(0.3, 0.1, 0.02)
	whiskey.emission_energy_multiplier = 0.12
	var cap := _mat(Color(0.06, 0.05, 0.05), 0.4)
	var gold := _mat(Color(0.85, 0.65, 0.3), 0.3, 0.9)
	var paper := _mat(Color(0.86, 0.8, 0.66), 0.85)
	var ink := _mat(Color(0.12, 0.09, 0.08), 0.8)

	# Whiskey (innen, wird beim Einschenken weniger)
	_liquid = _square(BODY.x - 0.008, 1.0, whiskey, 0.004)
	_update_fill()
	# Glaskörper, Schulter, Hals
	_square(BODY.x, BODY.y, glass, 0.0)
	var shoulder := CylinderMesh.new()
	shoulder.radial_segments = 4
	shoulder.bottom_radius = BODY.x * 0.5 * sqrt(2.0)
	shoulder.top_radius = 0.016
	shoulder.height = 0.04
	_add(shoulder, glass, Vector3(0, BODY.y + 0.02, 0), PI / 4.0)
	var neck := CylinderMesh.new()
	neck.top_radius = 0.0125
	neck.bottom_radius = 0.014
	neck.height = 0.04
	_add(neck, glass, Vector3(0, BODY.y + 0.06, 0))
	var c := CylinderMesh.new()
	c.top_radius = 0.0155
	c.bottom_radius = 0.0155
	c.height = 0.026
	_add(c, cap, Vector3(0, NECK_TOP - 0.013, 0))
	var ring := CylinderMesh.new()
	ring.top_radius = 0.0158
	ring.bottom_radius = 0.0158
	ring.height = 0.004
	_add(ring, gold, Vector3(0, NECK_TOP - 0.024, 0))

	# Etikett vorne (+Z) mit erfundener Marke
	var frame := BoxMesh.new()
	frame.size = Vector3(BODY.x * 0.9, 0.091, 0.0008)
	_add(frame, ink, Vector3(0, 0.075, BODY.x * 0.5 + 0.0005))
	var label := BoxMesh.new()
	label.size = Vector3(BODY.x * 0.84, 0.085, 0.0008)
	_add(label, paper, Vector3(0, 0.075, BODY.x * 0.5 + 0.001))
	var band := BoxMesh.new()
	band.size = Vector3(BODY.x * 0.86, 0.012, 0.0012)
	_add(band, ink, Vector3(0, 0.106, BODY.x * 0.5 + 0.0016))
	_text("HINTERZIMMER", 9, Color(0.93, 0.88, 0.76), Vector3(0, 0.106, BODY.x * 0.5 + 0.0026))
	_text("WHISKEY", 14, Color(0.55, 0.1, 0.08), Vector3(0, 0.083, BODY.x * 0.5 + 0.0022))
	_text("SEIT 1926", 7, Color(0.15, 0.1, 0.08), Vector3(0, 0.064, BODY.x * 0.5 + 0.0022))
	var seal := CylinderMesh.new()
	seal.top_radius = 0.009
	seal.bottom_radius = 0.009
	seal.height = 0.0015
	var s := _add(seal, gold, Vector3(0, 0.046, BODY.x * 0.5 + 0.0018))
	s.rotation.x = PI / 2.0

	var area := Area3D.new()
	area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BODY.x + 0.01, NECK_TOP, BODY.x + 0.01)
	shape.shape = box
	shape.position = Vector3(0, NECK_TOP * 0.5, 0)
	area.add_child(shape)
	add_child(area)
	area.input_event.connect(func(_c: Node, e: InputEvent, _p: Vector3, _n: Vector3, _i: int) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit())


## Altes Modell ausblenden.
func hide_model_parts(world: Node) -> void:
	for n in ["Flasche", "Flaschenetikett"]:
		var node := world.find_child(n, true, false) as Node3D
		if node != null:
			node.visible = false


## Weltposition der Flaschenöffnung.
func spout() -> Vector3:
	return global_transform * Vector3(0, NECK_TOP, 0)


func _update_fill() -> void:
	if _liquid == null:
		return
	var h := (BODY.y - 0.01) * fill
	_liquid.scale = Vector3(1, h, 1)
	_liquid.position.y = 0.004 + h * 0.5


## Quader mit quadratischem Querschnitt (Breite w, Höhe h), Boden bei y0.
func _square(w: float, h: float, mat: Material, y0: float) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = Vector3(w, h, w)
	return _add(b, mat, Vector3(0, y0 + h * 0.5, 0))


func _add(mesh: Mesh, mat: Material, pos: Vector3, rot_y := 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation.y = rot_y
	add_child(m)
	return m


func _text(t: String, size: int, col: Color, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = t
	l.font = preload("res://assets/fonts/RussoOne-Regular.ttf")
	l.font_size = size * 8
	l.pixel_size = 0.0001
	l.modulate = col
	l.outline_size = 0
	l.shaded = true
	l.position = pos
	add_child(l)


func _mat(color: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m
