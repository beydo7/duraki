class_name Card3D
extends Node3D
## Eine Spielkarte als 3D-Objekt. Liegt flach in der XZ-Ebene,
## die Vorderseite zeigt nach +Y. Umdrehen = 180° um die Z-Achse.

signal clicked(card: Card)
signal hover_changed(card3d: Card3D, hovered: bool)

const WIDTH := 0.10
const HEIGHT := 0.14
const THICKNESS := 0.0025

const COLOR_FACE := Color("e9e1cc")
const COLOR_EDGE := Color("b9ad92")
const COLOR_TRUMP := Color("d9a531")
const COLOR_BACK := Color("6e1a1a")
const COLOR_BACK_BORDER := Color("d8ccb0")
const COLOR_RED := Color("a3221c")
const COLOR_BLACK := Color("171512")

var card: Card
var is_trump := false
var playable := false
var hovered := false

var _face_mat: StandardMaterial3D
var _border_mat: StandardMaterial3D
var _labels: Array[Label3D] = []


static func create(p_card: Card, p_is_trump: bool) -> Card3D:
	var c := Card3D.new()
	c.card = p_card
	c.is_trump = p_is_trump
	return c


func _ready() -> void:
	_build()


func set_state(p_playable: bool) -> void:
	playable = p_playable
	_update_look()


func _build() -> void:
	# Kartenkörper (Rückseite / Rand)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(WIDTH, THICKNESS, HEIGHT)
	body.mesh = box
	body.material_override = _mat(COLOR_EDGE, 0.9)
	add_child(body)

	# Vorderseite: Rand (gold bei Trumpf) + Innenfläche
	_border_mat = _mat(COLOR_TRUMP if is_trump else COLOR_FACE.darkened(0.08), 0.8)
	_add_quad(Vector2(WIDTH, HEIGHT), THICKNESS * 0.5 + 0.0002, _border_mat, false)
	_face_mat = _mat(COLOR_FACE, 0.85)
	_add_quad(Vector2(WIDTH - 0.008, HEIGHT - 0.008), THICKNESS * 0.5 + 0.0004, _face_mat, false)

	# Rückseite: heller Rand + dunkelrotes Feld mit Rautenmuster
	_add_quad(Vector2(WIDTH, HEIGHT), THICKNESS * 0.5 + 0.0002, _mat(COLOR_BACK_BORDER, 0.9), true)
	_add_quad(Vector2(WIDTH - 0.012, HEIGHT - 0.012), THICKNESS * 0.5 + 0.0004, _mat(COLOR_BACK, 0.7), true)
	var back_mark := _label("◆", 240, COLOR_BACK_BORDER.darkened(0.25), true, 0.0002)
	back_mark.position = Vector3(0, -(THICKNESS * 0.5 + 0.0006), 0)
	add_child(back_mark)

	if card != null:
		var color := COLOR_RED if card.is_red() else COLOR_BLACK
		var rank := Card.RANK_NAMES[card.rank] as String
		var suit := Card.SUIT_SYMBOLS[card.suit] as String
		var y := THICKNESS * 0.5 + 0.0006
		# großes Farbsymbol in der Mitte
		var center := _label(suit, 280, color, false, 0.0002)
		center.position = Vector3(0, y, 0.008)
		add_child(center)
		# Rang oben links und (gedreht) unten rechts
		# Ecke oben links ist bei überlappenden Karten immer sichtbar → groß
		for corner in [Vector3(-WIDTH * 0.335, y, -HEIGHT * 0.3), Vector3(WIDTH * 0.335, y, HEIGHT * 0.3)]:
			var l := _label("%s\n%s" % [rank, suit], 150, color, false, 0.0002)
			l.position = corner
			if corner.z > 0:
				l.rotate_y(PI)
			l.line_spacing = -40
			add_child(l)
			_labels.append(l)
		_labels.append(center)

	# Klickfläche
	var area := Area3D.new()
	area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = Vector3(WIDTH, 0.01, HEIGHT)
	shape.shape = bshape
	area.add_child(shape)
	area.input_event.connect(_on_input_event)
	area.mouse_entered.connect(func() -> void: _set_hovered(true))
	area.mouse_exited.connect(func() -> void: _set_hovered(false))
	add_child(area)
	_update_look()


func _on_input_event(_cam: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if playable and card != null:
			clicked.emit(card)


func _set_hovered(value: bool) -> void:
	hovered = value
	_update_look()
	hover_changed.emit(self, value)


func _update_look() -> void:
	if _face_mat == null:
		return
	var lit := playable and hovered
	_face_mat.emission_enabled = lit
	_face_mat.emission = Color("fff2c0")
	_face_mat.emission_energy_multiplier = 0.25
	_border_mat.emission_enabled = playable
	_border_mat.emission = COLOR_TRUMP if is_trump else Color("f3e3a0")
	_border_mat.emission_energy_multiplier = 0.9 if lit else (0.35 if playable else 0.0)


func _add_quad(size: Vector2, y: float, material: Material, bottom: bool) -> void:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	mi.mesh = quad
	mi.material_override = material
	# QuadMesh zeigt nach +Z → flach hinlegen
	mi.rotation_degrees = Vector3(90 if bottom else -90, 0, 0)
	mi.position = Vector3(0, -y if bottom else y, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _label(text: String, font_size: int, color: Color, bottom: bool, px := 0.0004) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = px
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	l.modulate = color
	l.outline_size = 0
	l.double_sided = false
	l.shaded = true
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.rotation_degrees = Vector3(90 if bottom else -90, 0, 0)
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l


static func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m
