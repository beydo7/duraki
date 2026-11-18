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
const COLOR_TRUMP := Color("9b7ff0")
const COLOR_BACK := Color("3b2a6e")
const COLOR_BACK_BORDER := Color("e9dcc0")
const COLOR_RED := Color("a3221c")
const COLOR_BLACK := Color("171512")
const INDEX_FONT := preload("res://assets/fonts/DejaVuSans-Bold.ttf")
## Färbung der Vorderseite + Etikettfarbe je Card.Enhancement
const ENH_FACE := [Color("e9e1cc"), Color("f3dc9a"), Color("cfe6f3"), Color("d3eccb")]
const ENH_TAG := [Color.WHITE, Color("9a6a08"), Color("2c6e9e"), Color("2f7a3c")]

var card: Card
var is_trump := false
var playable := false
var hovered := false

var _face_mat: StandardMaterial3D
var _border_mat: StandardMaterial3D
var _labels: Array[Label3D] = []
var _border: MeshInstance3D
var _special := false


const SUIT_FILES := ["h", "d", "c", "s"]
static var _textures := {}


## Kartenbild aus assets/cards (erzeugt mit tools/generate_cards.py).
static func face_texture(c: Card) -> Texture2D:
	return _texture("%s_%d" % [SUIT_FILES[c.suit], c.rank])


static func back_texture() -> Texture2D:
	return _texture("back")


static func _texture(name: String) -> Texture2D:
	if not _textures.has(name):
		_textures[name] = load("res://assets/cards/%s.png" % name)
	return _textures[name]


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
	# Kartenkörper (Kante)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(WIDTH, THICKNESS, HEIGHT)
	body.mesh = box
	body.material_override = _mat(COLOR_EDGE, 0.9)
	add_child(body)

	var enh := card.enhancement if card != null else Card.Enhancement.NONE
	# Rahmen hinter dem Bild: Farbe der Verbesserung, sonst Trumpf-Lila, sonst unsichtbar
	var border_color := COLOR_FACE
	if enh != Card.Enhancement.NONE:
		border_color = ENH_TAG[enh].lightened(0.25)
	elif is_trump:
		border_color = COLOR_TRUMP
	_special = enh != Card.Enhancement.NONE or is_trump
	_border_mat = _mat(border_color, 0.8)
	# etwas größer als die Karte → sichtbarer Rand (nur bei spielbar/Trumpf/Verbesserung)
	_border = _add_quad(Vector2(WIDTH + 0.008, HEIGHT + 0.008), THICKNESS * 0.5 + 0.0001, _border_mat, false)

	# Vorderseite: das Kartenbild (bei Verbesserung leicht getönt)
	var inset := 0.0
	_face_mat = _mat(ENH_FACE[enh].lightened(0.35) if enh != Card.Enhancement.NONE else Color.WHITE, 0.85)
	if card != null:
		_face_mat.albedo_texture = face_texture(card)
	_add_quad(Vector2(WIDTH - inset, HEIGHT - inset), THICKNESS * 0.5 + 0.0004, _face_mat, false)

	# Rückseite
	var back_mat := _mat(Color.WHITE, 0.75)
	back_mat.albedo_texture = back_texture()
	_add_quad(Vector2(WIDTH, HEIGHT), THICKNESS * 0.5 + 0.0002, back_mat, true)

	if card != null and enh != Card.Enhancement.NONE:
		var tag := _label(Card.ENHANCEMENT_TAGS[enh], 80, ENH_TAG[enh], false, 0.0002)
		tag.font = INDEX_FONT
		tag.shaded = false
		tag.outline_size = 14
		tag.outline_modulate = Color("f6f0e2")
		tag.position = Vector3(0, THICKNESS * 0.5 + 0.0008, HEIGHT * 0.5 - 0.011)
		add_child(tag)

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
	_border.visible = playable or _special
	_border_mat.emission_enabled = playable
	_border_mat.emission = _border_mat.albedo_color if _special else Color("f3e3a0")
	if not _special:
		_border_mat.albedo_color = Color("f3e3a0")
	_border_mat.emission_energy_multiplier = 0.9 if lit else (0.35 if playable else 0.0)


func _add_quad(size: Vector2, y: float, material: Material, bottom: bool) -> MeshInstance3D:
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
	return mi


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
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
