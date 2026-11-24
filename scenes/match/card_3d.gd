class_name Card3D
extends Node3D
## Eine Spielkarte als 3D-Objekt. Liegt flach in der XZ-Ebene,
## die Vorderseite zeigt nach +Y. Umdrehen = 180° um die Z-Achse.
##
## Die Wurzel wird vom Tisch (TableWorld) bewegt. Alle Teile, die man sieht,
## hängen an `_body` – darauf liegen die kleinen Eigenbewegungen:
## Kippen zur Maus (Hover), leichtes Wiegen in der Hand, Federn beim Landen
## und Schubsen. Die Vorderseite nutzt card_face.gdshader (Folienglanz, Lichtreflex).

signal clicked(card: Card)
## Maustaste auf einer spielbaren Karte gedrückt (TableWorld entscheidet: Klick oder Ziehen)
signal grabbed(node: Card3D)
signal hover_changed(card3d: Card3D, hovered: bool)

const WIDTH := 0.10
const HEIGHT := 0.14
const THICKNESS := 0.0025

const COLOR_EDGE := Color("2a2440")
const COLOR_TRUMP := Color("d9b06a")
const COLOR_BACK := Color("1b1834")
const COLOR_BACK_BORDER := Color("2a2440")
const COLOR_PLAYABLE := Color("f0d79a")
const INDEX_FONT := preload("res://assets/fonts/DejaVuSans-Bold.ttf")
const FACE_SHADER := preload("res://scenes/match/card_face.gdshader")
const GLASS_SHADER := preload("res://scenes/match/card_face_glass.gdshader")
## Rahmen-/Etikettfarbe je Card.Enhancement
const ENH_TAG := [Color.WHITE, Color("ffd36a"), Color("9fd8ff"), Color("8ff0a0")]
## Folienglanz je Card.Enhancement: [Stärke, Farbe, Regenbogen]
const ENH_FOIL := [
	[0.0, Color.WHITE, 0.0],
	[0.55, Color(1.0, 0.86, 0.55), 0.0],
	[0.75, Color(0.8, 0.95, 1.0), 1.0],
	[0.85, Color(0.45, 1.0, 0.55), 0.0],
]
## Maximales Kippen zur Maus (Bogenmaß)
const TILT := 0.42

var card: Card
var is_trump := false
var playable := false
## Hinweise an: spielbare Karten leuchten. Aus: alle Handkarten sehen gleich aus und sind anklickbar.
static var hints := true
var hovered := false
## Liegt in der eigenen Hand (Wiegen, Kippen, Anheben)
var in_hand := false

var _body: Node3D
var _face_mat: ShaderMaterial
var _border_mat: StandardMaterial3D
var _border: Node3D
var _special := false
var _phase := 0.0
var _skew := 0.0
var _t := 0.0
var _hover_uv := Vector2(0.5, 0.5)
var _tilt := Vector2.ZERO        # aktuelles Kippen (x um X-Achse, y um Z-Achse)
var _shine := 0.0
var _glow := 0.0
var _lift := 0.0
# Federn: Höhe (lokal +Y), Wackeln (um X) und Versatz (lokal XZ)
var _hop := 0.0
var _hop_v := 0.0
var _wob := 0.0
var _wob_v := 0.0
var _off := Vector3.ZERO
var _off_v := Vector3.ZERO
## eigener Zufall, damit Optik nicht den Spiel-Zufall verschiebt
var _rng := RandomNumberGenerator.new()


const SUIT_FILES := ["h", "d", "c", "s"]
static var _textures := {}


## Unterordner der Kartenbilder je Verbesserung (NONE, GOLD, GLASS, LUCKY)
const ENH_FOLDERS := ["", "gold/", "glass/", "lucky/"]


## Kartenbild aus assets/cards (erzeugt mit tools/generate_cards.py), passend zur
## Verbesserung der Karte: Blattgold, Glas oder Kleeblatt-Ecken.
static func face_texture(c: Card) -> Texture2D:
	return _texture("%s%s_%d" % [ENH_FOLDERS[c.enhancement], SUIT_FILES[c.suit], c.rank])


static func back_texture() -> Texture2D:
	var deck_back: Texture2D = Run.deck_back() if Run != null else null
	return deck_back if deck_back != null else _texture("back")


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
	_rng.randomize()
	_phase = _rng.randf() * TAU
	_skew = _rng.randf_range(-0.018, 0.018)
	_build()


func set_state(p_playable: bool) -> void:
	playable = p_playable
	_update_look()


## Feuerzeug-Ziel: leuchtend orangefarbener, pulsierender Rahmen um die Karte.
var _target_frame: Node3D
var _target_mat: StandardMaterial3D


func set_target(on: bool) -> void:
	if on and _target_frame == null:
		_target_mat = StandardMaterial3D.new()
		_target_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_target_mat.albedo_color = Color(1.0, 0.5, 0.12)
		_target_frame = _add_frame(0.007, THICKNESS * 0.5 + 0.0012, _target_mat)
	if _target_frame != null:
		_target_frame.visible = on


## Feuerzeug: Karte verbrennt von unten nach oben und löst sich auf, dann verschwindet sie.
func burn_away(time := 1.1) -> Tween:
	playable = false
	# nur die Vorderseite brennt sichtbar; Rahmen, Kante und Rückseite gleich weg
	for c in _body.get_children():
		if c is GeometryInstance3D and (c as MeshInstance3D).material_override != _face_mat:
			(c as Node3D).visible = false
		elif not (c is GeometryInstance3D):
			(c as Node3D).visible = false
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _face_mat.set_shader_parameter("burn", v), 0.0, 1.0, time)
	tw.parallel().tween_property(self, "position:y", position.y + 0.01, time)
	tw.tween_callback(queue_free)
	return tw


## Karte ist gelandet: kurz federn und wackeln (`strength` 0..1).
func land(strength := 0.5) -> void:
	_hop_v += 0.12 * strength
	_wob_v += (7.0 if _rng.randf() < 0.5 else -7.0) * strength


## Kurz in Richtung `dir` (Weltkoordinaten) geschubst werden.
func nudge(dir: Vector3, strength := 1.0) -> void:
	var local := global_transform.basis.inverse() * dir
	local.y = 0.0
	_off_v += local.normalized() * 0.2 * strength
	_wob_v += 4.0 * strength


func _process(delta: float) -> void:
	_t += delta
	var dt := minf(delta, 1.0 / 30.0)
	# Kippen zur Maus nur für die eigene Hand
	var tilt_target := Vector2.ZERO
	if hovered and in_hand:
		tilt_target = Vector2((0.5 - _hover_uv.y) * TILT, (_hover_uv.x - 0.5) * TILT)
	_tilt = _tilt.lerp(tilt_target, 1.0 - exp(-dt * 14.0))
	_shine = lerpf(_shine, 1.0 if hovered and in_hand else 0.0, 1.0 - exp(-dt * 10.0))
	var shown := playable and hints
	_glow = lerpf(_glow, (1.0 if hovered else 0.45) if shown else 0.0, 1.0 - exp(-dt * 10.0))
	_lift = lerpf(_lift, 0.006 if shown and in_hand else 0.0, 1.0 - exp(-dt * 8.0))
	# Federn (gedämpfte Schwingungen)
	_hop_v += (-260.0 * _hop - 16.0 * _hop_v) * dt
	_hop += _hop_v * dt
	_wob_v += (-300.0 * _wob - 14.0 * _wob_v) * dt
	_wob += _wob_v * dt
	_off_v += (-220.0 * _off - 15.0 * _off_v) * dt
	_off += _off_v * dt
	# Wiegen in der Hand
	var sway := Vector2.ZERO
	if in_hand:
		sway = Vector2(sin(_t * 0.9 + _phase) * 0.012, sin(_t * 1.3 + _phase * 1.7) * 0.014)
	if _body != null:
		_body.rotation = Vector3(_tilt.x + sway.x + _wob * 0.12, _skew if in_hand else 0.0, _tilt.y + sway.y)
		# beim Wackeln etwas anheben, damit keine Kante in den Tisch taucht
		_body.position = Vector3(_off.x, _hop + absf(sin(_wob * 0.12)) * HEIGHT * 0.5, _off.z - _lift)
	if _target_frame != null and _target_frame.visible:
		var p := 0.6 + 0.4 * sin(_t * 7.0)
		_target_mat.albedo_color = Color(1.0, 0.35 + 0.3 * p, 0.08) * (0.8 + 0.5 * p)
	if _face_mat != null:
		_face_mat.set_shader_parameter("shine", _shine)
		_face_mat.set_shader_parameter("shine_uv", _hover_uv)
		_face_mat.set_shader_parameter("glow", _glow)


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(WIDTH, THICKNESS, HEIGHT)
	body.mesh = box
	var enh := card.enhancement if card != null else Card.Enhancement.NONE
	var glass := enh == Card.Enhancement.GLASS
	if glass:
		var gm := _mat(Color(0.45, 0.62, 0.85, 0.35), 0.05) # Glaskörper durchscheinend bläulich
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.metallic_specular = 0.8
		body.material_override = gm
	else:
		body.material_override = _mat(COLOR_EDGE, 0.6)
	_body.add_child(body)

	# Rahmen: Farbe der Verbesserung, sonst Gold für Trumpf/spielbar
	var border_color := COLOR_PLAYABLE
	if enh != Card.Enhancement.NONE:
		border_color = ENH_TAG[enh]
	elif is_trump:
		border_color = COLOR_TRUMP
	_special = enh != Card.Enhancement.NONE or is_trump
	_border_mat = _mat(border_color, 0.6)
	_border = _add_frame(0.0035, THICKNESS * 0.5 + 0.0001, _border_mat)

	# Vorderseite mit Folien-Shader
	_face_mat = ShaderMaterial.new()
	_face_mat.shader = GLASS_SHADER if glass else FACE_SHADER
	if card != null:
		_face_mat.set_shader_parameter("tex", face_texture(card))
	var foil: Array = ENH_FOIL[enh]
	var foil_amount: float = foil[0]
	if enh == Card.Enhancement.NONE and is_trump:
		foil_amount = 0.5
	_face_mat.set_shader_parameter("foil", foil_amount)
	_face_mat.set_shader_parameter("foil_color", foil[1])
	_face_mat.set_shader_parameter("rainbow", foil[2])
	_face_mat.set_shader_parameter("rough", 0.55)
	_add_quad(Vector2(WIDTH, HEIGHT), THICKNESS * 0.5 + 0.0004, _face_mat, false)

	# Rückseite
	var back_mat := _mat(Color.WHITE, 0.6)
	back_mat.albedo_texture = back_texture()
	_add_quad(Vector2(WIDTH, HEIGHT), THICKNESS * 0.5 + 0.0002, back_mat, true)

	if card != null and enh != Card.Enhancement.NONE and not glass: # Glas ohne Schriftzug
		var tag := _label(Card.ENHANCEMENT_TAGS[enh], 80, ENH_TAG[enh], false, 0.0002)
		tag.font = INDEX_FONT
		tag.shaded = false
		tag.outline_size = 16
		tag.outline_modulate = Color("120f24")
		tag.position = Vector3(0, THICKNESS * 0.5 + 0.0008, HEIGHT * 0.5 - 0.011)
		_body.add_child(tag)

	# Klickfläche (an der Wurzel, damit Kippen das Hovern nicht stört)
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


func _on_input_event(_cam: Node, event: InputEvent, pos: Vector3, _normal: Vector3, _idx: int) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		var local := to_local(pos)
		_hover_uv = Vector2(clampf(local.x / WIDTH + 0.5, 0.0, 1.0), clampf(local.z / HEIGHT + 0.5, 0.0, 1.0))
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if card != null and (playable or (not hints and in_hand)):
			grabbed.emit(self)


func _set_hovered(value: bool) -> void:
	hovered = value
	_update_look()
	hover_changed.emit(self, value)


func _update_look() -> void:
	if _border_mat == null:
		return
	var shown := playable and hints
	var lit := shown and hovered
	_border.visible = shown or _special
	_border_mat.emission_enabled = shown or _special
	_border_mat.emission = _border_mat.albedo_color
	if not _special:
		_border_mat.albedo_color = COLOR_PLAYABLE
		_border_mat.emission = COLOR_PLAYABLE
	_border_mat.emission_energy_multiplier = 1.0 if lit else (0.45 if shown else 0.25)


## Schmaler Rahmen rund um die Karte (für Leuchten/Trumpf/Verbesserung).
func _add_frame(width: float, y: float, material: Material) -> Node3D:
	var frame := Node3D.new()
	_body.add_child(frame)
	var w := WIDTH + width * 2
	var h := HEIGHT + width * 2
	for side in [-1.0, 1.0]:
		var top := _add_quad(Vector2(w, width), y, material, false)
		top.position.z = side * (HEIGHT + width) * 0.5
		top.reparent(frame, true)
		var edge := _add_quad(Vector2(width, h), y, material, false)
		edge.position.x = side * (WIDTH + width) * 0.5
		edge.reparent(frame, true)
	return frame


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
	_body.add_child(mi)
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
	m.metallic_specular = 0.2
	return m
