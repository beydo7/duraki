class_name MenuCard3D
extends Node3D
## Großer Menüpunkt als Spielkarte auf dem Tisch (Hauptmenü).
## Schwebt leicht, hebt sich beim Hover und neigt sich zur Kamera.

signal chosen
signal hovered_changed(card: MenuCard3D, hovered: bool)

const W := 0.17
const H := 0.238
const T := 0.003
const BRUSH := preload("res://assets/fonts/PermanentMarker-Regular.ttf")
const SYM := preload("res://assets/fonts/DejaVuSans-Bold.ttf")
const MONO := preload("res://assets/fonts/CourierPrime-Bold.ttf")
const INK := Color("1b1426")

var title := "SPIELEN"
var subtitle := ""
var symbol := "♠"
var symbol_color := INK
var hovered := false
var focused := false
var base_xf: Transform3D

var _lift := 0.0
var _t := 0.0
var _glow_mat: StandardMaterial3D
var _body: Node3D


func setup(p_title: String, p_sub: String, p_symbol: String, p_color: Color) -> MenuCard3D:
	title = p_title
	subtitle = p_sub
	symbol = p_symbol
	symbol_color = p_color
	return self


func _ready() -> void:
	base_xf = transform
	_t = randf() * 10.0
	_body = Node3D.new()
	add_child(_body)

	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color("ece3cf")
	paper.roughness = 0.8
	paper.metallic_specular = 0.15
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(W, T, H)
	box.mesh = bm
	box.material_override = paper
	_body.add_child(box)

	# Goldrahmen (leuchtet bei Hover/Fokus)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.albedo_color = Color(1, 0.8, 0.4)
	_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var frame := MeshInstance3D.new()
	var fm := QuadMesh.new()
	fm.size = Vector2(W + 0.016, H + 0.016)
	frame.mesh = fm
	frame.material_override = _glow_mat
	frame.rotation_degrees.x = -90
	frame.position.y = -T * 0.5 - 0.0004
	_body.add_child(frame)

	# Innenrahmen + Beschriftung
	var inner := MeshInstance3D.new()
	var im := QuadMesh.new()
	im.size = Vector2(W - 0.018, H - 0.018)
	inner.mesh = im
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color("d9cdb3")
	line_mat.roughness = 0.9
	inner.material_override = line_mat
	inner.rotation_degrees.x = -90
	inner.position.y = T * 0.5 + 0.0003
	_body.add_child(inner)
	var inner2 := MeshInstance3D.new()
	var im2 := QuadMesh.new()
	im2.size = Vector2(W - 0.024, H - 0.024)
	inner2.mesh = im2
	inner2.material_override = paper
	inner2.rotation_degrees.x = -90
	inner2.position.y = T * 0.5 + 0.0005
	_body.add_child(inner2)

	_text(symbol, SYM, 260, symbol_color, Vector3(0, 0, -0.03), 0.00028)
	_text(title, BRUSH, 120, INK, Vector3(0, 0, 0.055), 0.00026)
	if not subtitle.is_empty():
		_text(subtitle, MONO, 52, Color(INK, 0.7), Vector3(0, 0, 0.088), 0.00022)
	_text(symbol, SYM, 70, symbol_color, Vector3(-W * 0.5 + 0.016, 0, -H * 0.5 + 0.02), 0.00024)
	var corner := _text(symbol, SYM, 70, symbol_color, Vector3(W * 0.5 - 0.016, 0, H * 0.5 - 0.02), 0.00024)
	corner.rotation_degrees.y = 180

	var area := Area3D.new()
	area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(W, 0.02, H)
	shape.shape = bs
	area.add_child(shape)
	area.input_event.connect(_on_input)
	area.mouse_entered.connect(func() -> void: _set_hover(true))
	area.mouse_exited.connect(func() -> void: _set_hover(false))
	_body.add_child(area)


func _process(delta: float) -> void:
	_t += delta
	var active := hovered or focused
	_lift = move_toward(_lift, 1.0 if active else 0.0, delta * 4.0)
	var e := _lift * _lift * (3.0 - 2.0 * _lift)
	var bob := sin(_t * 1.3) * 0.003
	# heben, zur Kamera kippen, leicht wiegen
	var tilt := Basis.from_euler(Vector3(deg_to_rad(28.0 * e), 0, sin(_t * 0.9) * 0.02 * (1.0 - e)))
	_body.transform = Transform3D(tilt, Vector3(0, 0.004 + bob + 0.05 * e, 0.02 * e))
	_glow_mat.albedo_color.a = 0.1 + 0.8 * e + 0.1 * sin(_t * 4.0) * e


func _on_input(_cam: Node, event: InputEvent, _p: Vector3, _n: Vector3, _i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		chosen.emit()


func _set_hover(v: bool) -> void:
	hovered = v
	hovered_changed.emit(self, v)


func _text(text: String, font: Font, size: int, color: Color, pos: Vector3, px: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = px
	l.modulate = color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	l.rotation_degrees.x = -90
	l.position = pos + Vector3(0, T * 0.5 + 0.0008, 0)
	_body.add_child(l)
	return l
