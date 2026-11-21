class_name OpponentFigure
extends Node3D
## Die Gestalt gegenüber am Tisch: ein Monster im Mantel mit Wirbelsäulen-Hals,
## Porzellanschädel mit tiefen, glühenden Augen, Krallenhänden und – je nach
## Gegner – Hörnern, Reißzahn-Grinsen oder Zusatzaugen. Die Einzelteile kommen aus
## assets/models/figure.glb (Quelle: art/blender/figure.blend) und werden hier
## zusammengesetzt, eingefärbt und per Code animiert.
## Ursprung = Mitte der Tischkante auf Gegnerseite, Boden (y = 0), Blick nach +Z.

var mask_color := Color("d8cfb8")
var body_color := Color("1b1716")
var eye_color := Color("c4271b")
var size_scale := 1.0
var hat := false
var horns := 0
var mouth := 1
var extra_eyes := false

const FIGURE_MODEL := preload("res://assets/models/figure.glb")
## Diese Teile sind „Löcher“ (Augenhöhlen, Maul, Nase, Naht): immer pechschwarz,
## sonst spiegeln sie das farbige Augenlicht.
const VOID_PARTS := ["Sockets", "ExtraSockets", "Grin", "Nostrils", "Stitches"]
static var _void_mat: StandardMaterial3D

var _t := 0.0
var _torso: Node3D
var _head: Node3D
var _eyes: Array[MeshInstance3D] = []
var _eye_mat: StandardMaterial3D
var _hands: Array[Node3D] = []
var _hand_rest: Array[Vector3] = []
var _arms: Array[MeshInstance3D] = []
var _gesture := 0.0
var _recoil := 0.0
var _slump := 0.0
var _laugh := 0.0
var _think := 0.0
var _think_target := 0.0
var _think_style := ThinkStyle.CHIN
var _eye_lights: Array[OmniLight3D] = []
var _under_light: SpotLight3D
var _jaw: Node3D
var _jaw_open := 0.0
var _twitch := Vector3.ZERO
var _next_twitch := 3.0

## Verschiedene Arten zu überlegen.
enum ThinkStyle {
	CHIN,  ## Hand ans Kinn, Finger tippen
	STARE, ## beugt sich vor und starrt auf den Tisch, Augen glühen auf
	CARDS, ## mustert die eigenen Karten, Kopf wiegt hin und her
	DRUM,  ## trommelt mit beiden Händen auf den Tisch
}


func setup(data: OpponentData) -> OpponentFigure:
	if data != null:
		mask_color = data.mask_color
		body_color = data.body_color
		eye_color = data.eye_color
		size_scale = data.figure_scale
		hat = data.wears_hat
		horns = data.horns
		mouth = data.mouth
		extra_eyes = data.extra_eyes
	return self


func _ready() -> void:
	_build()


# --- Reaktionen ---------------------------------------------------------------

## Legt eine Karte (kurzes Vorbeugen + Handbewegung).
func gesture() -> void:
	_gesture = 1.0


## Muss aufnehmen (zuckt zurück).
func recoil() -> void:
	_recoil = 1.0


## Überlegt in einem bestimmten Stil (siehe ThinkStyle).
func think(style: int = ThinkStyle.CHIN) -> void:
	_think_style = style
	_think_target = 1.0


func stop_thinking() -> void:
	_think_target = 0.0


## Hat verloren.
func slump() -> void:
	_slump = 1.0


## Hat gewonnen (bebt vor Lachen).
func laugh() -> void:
	_laugh = 1.0


func _process(delta: float) -> void:
	_t += delta
	_gesture = move_toward(_gesture, 0.0, delta * 2.2)
	_recoil = move_toward(_recoil, 0.0, delta * 1.5)
	_laugh = move_toward(_laugh, 0.0, delta * 0.35)
	_think = move_toward(_think, _think_target, delta * 2.0)
	if _slump > 0.0:
		_slump = minf(_slump + delta, 2.0)

	var breath := sin(_t * 1.6) * 0.012
	var lean := sin(_gesture * PI) * 0.12 - _recoil * 0.10 + minf(_slump, 1.0) * 0.18 + _think * _style_lean()
	_torso.rotation.x = lean
	_torso.scale = Vector3(1.0, 1.0 + breath, 1.0)

	# unheimliches Zucken: ab und zu ruckt der Kopf kurz zur Seite
	_next_twitch -= delta
	if _next_twitch <= 0.0 and _slump <= 0.0:
		_next_twitch = randf_range(2.5, 7.0)
		_twitch = Vector3(randf_range(-0.12, 0.12), randf_range(-0.25, 0.25), randf_range(-0.3, 0.3))
	_twitch = _twitch.lerp(Vector3.ZERO, minf(1.0, delta * 3.0))

	var shake := sin(_t * 38.0) * 0.03 * _laugh
	_head.rotation = Vector3(
		sin(_t * 0.7) * 0.05 + minf(_slump, 1.0) * 0.35 - _recoil * 0.2 + _think * _head_pitch(),
		sin(_t * 0.45) * 0.12 * (1.0 - _think) + _think * _head_yaw() + shake,
		sin(_t * 0.9) * 0.04 + _recoil * 0.15 + _think * _head_roll()) + _twitch

	# Kiefer: klappert beim Lachen, öffnet sich beim Legen und Zucken
	var jaw_target := maxf(sin(_gesture * PI) * 0.6, _twitch.length() * 2.0)
	jaw_target = maxf(jaw_target, _laugh * (0.5 + 0.5 * sin(_t * 30.0)))
	_jaw_open = lerpf(_jaw_open, jaw_target, minf(1.0, delta * 14.0))
	if _jaw != null:
		_jaw.position = _jaw.get_meta("rest") + Vector3(0, -0.016, 0.004) * _jaw_open * size_scale
		_jaw.rotation.x = _jaw_open * 0.12

	for i in _hands.size():
		var side := -1.0 if i == 0 else 1.0
		var off := Vector3(0, sin(_t * 1.6 + i) * 0.006, 0)
		if i == 1:
			off += Vector3(-0.08, 0.05, 0.18) * sin(_gesture * PI)
		off += Vector3(side * 0.04, 0.06, -0.08) * _recoil
		off += _hand_think_offset(i) * _think
		_hands[i].position = _hand_rest[i] + off

	_update_arms()

	var glow := 1.2 + sin(_t * 2.3) * 0.4 + _laugh * 3.0
	if _think_style == ThinkStyle.STARE:
		glow += _think * 2.5
	var dim := 0.3 if _slump > 0.0 else 1.0
	_eye_mat.emission_energy_multiplier = glow * 1.7 * dim
	for l in _eye_lights:
		l.light_energy = (0.1 + glow * 0.08) * dim
	if _under_light != null:
		_under_light.light_energy = (0.45 + sin(_t * 1.1) * 0.06 + _laugh * 0.4) * dim


# --- Aufbau -------------------------------------------------------------------

func _build() -> void:
	var s := size_scale
	var model := FIGURE_MODEL.instantiate()
	var coat_tint := body_color.lightened(0.08)

	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = eye_color
	_eye_mat.roughness = 0.4
	_eye_mat.emission_enabled = true
	_eye_mat.emission = eye_color

	# Oberkörper (dreht sich um die Hüfte)
	_torso = Node3D.new()
	# größere Gestalten sitzen tiefer, damit der Kopf im Bild bleibt
	_torso.position = Vector3(0, 0.02 - (s - 1.0) * 1.7, -0.34 - (s - 1.0) * 0.3)
	add_child(_torso)
	for part in ["Coat", "Collar"]:
		_torso.add_child(_part(model, part, coat_tint, s))
	_torso.add_child(_part(model, "Buttons", Color.WHITE, s))
	_torso.add_child(_part(model, "Neck", mask_color.darkened(0.35), s))

	# Kopf
	_head = Node3D.new()
	_head.position = Vector3(0, 1.42, 0.05) * s
	_torso.add_child(_head)
	_head.add_child(_part(model, "Mask", mask_color, s))
	for part in ["Sockets", "Nostrils"]:
		_head.add_child(_part(model, part, Color.WHITE, s))
	if mouth == 0:
		_head.add_child(_part(model, "Stitches", Color.WHITE, s))
	else:
		for part in ["Grin", "Teeth"]:
			_head.add_child(_part(model, part, Color.WHITE, s))
		var jaw_mesh := _part(model, "Jaw", Color.WHITE, s)
		_jaw = Node3D.new()
		var pivot := model.find_child("JawPivot", true, false) as Node3D
		_jaw.position = pivot.position * s if pivot != null else Vector3.ZERO
		_jaw.set_meta("rest", _jaw.position)
		_jaw.add_child(jaw_mesh)
		_head.add_child(_jaw)
	match horns:
		1: _head.add_child(_part(model, "Horns_Devil", Color.WHITE, s))
		2: _head.add_child(_part(model, "Horns_Ram", Color.WHITE, s))
	if hat:
		_head.add_child(_part(model, "Hat", coat_tint, s))
		_head.add_child(_part(model, "HatBand", Color.WHITE, s))

	# glühende Pupillen an den Markierungen aus dem Modell (+ Zusatzaugen)
	var eye_names := ["EyeL", "EyeR"]
	if extra_eyes:
		_head.add_child(_part(model, "ExtraSockets", Color.WHITE, s))
		eye_names += ["EyeX1", "EyeX2", "EyeX3"]
	for eye_name in eye_names:
		var marker := model.find_child(eye_name, true, false) as Node3D
		var small: bool = eye_name.begins_with("EyeX")
		var eye := MeshInstance3D.new()
		eye.mesh = _sphere((0.009 if small else 0.015) * s)
		eye.material_override = _eye_mat
		eye.position = marker.position * s if marker != null else Vector3.ZERO
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_head.add_child(eye)
		_eyes.append(eye)
		if not small:
			# farbiges Glimmen auf dem Schädel rund um die Augen
			var glow := OmniLight3D.new()
			glow.light_color = eye_color
			glow.omni_range = 0.3 * s
			glow.omni_attenuation = 2.2
			glow.position = eye.position + Vector3(0, -0.02 * s, 0.09 * s)
			_head.add_child(glow)
			_eye_lights.append(glow)

	# kaltes Licht von oben vorne holt den Schädel aus der Dunkelheit …
	var face_light := SpotLight3D.new()
	face_light.position = Vector3(0, 0.3 * s, 0.8)
	face_light.rotation_degrees = Vector3(-15, 0, 0)
	face_light.light_color = Color("d9c8ff")
	face_light.light_energy = 0.9
	face_light.spot_range = 1.6
	face_light.spot_angle = 24.0
	_head.add_child(face_light)
	# … und Grusel-Licht von unten in Augenfarbe (wie eine Taschenlampe unterm Kinn)
	_under_light = SpotLight3D.new()
	_under_light.light_color = eye_color.lerp(Color("ffb070"), 0.35)
	_under_light.spot_range = 1.6
	_under_light.spot_angle = 30.0
	_under_light.spot_attenuation = 0.8
	add_child(_under_light)
	_under_light.position = Vector3(0, 0.86, 0.1)
	_under_light.look_at(_torso.position + Vector3(0, 1.45 * s, 0.1))

	# Arme + Hände (Hände liegen am Tisch / halten die Karten)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hand := Node3D.new()
		var rest := Vector3(side * 0.15, 0.86, 0.2)
		hand.position = rest
		add_child(hand)
		_hands.append(hand)
		_hand_rest.append(rest)
		hand.add_child(_part(model, "Hand_L" if i == 0 else "Hand_R", mask_color, 1.0))
		hand.add_child(_part(model, "Claws_L" if i == 0 else "Claws_R", Color.WHITE, 1.0))

		var arm := _part(model, "Sleeve", coat_tint, 1.0)
		add_child(arm)
		_arms.append(arm)
	model.free()
	_update_arms()


## Holt ein Einzelteil aus figure.glb (art/blender/figure.blend) und färbt es ein.
## Weiß = Originalfarbe aus Blender.
func _part(model: Node, part_name: String, tint: Color, scale_factor: float) -> MeshInstance3D:
	var src := model.find_child(part_name, true, false) as MeshInstance3D
	var mi := MeshInstance3D.new()
	mi.name = part_name
	if src == null:
		push_warning("figure.glb: Teil '%s' fehlt" % part_name)
		return mi
	mi.mesh = src.mesh
	mi.scale = Vector3.ONE * scale_factor
	if part_name in VOID_PARTS:
		if _void_mat == null:
			_void_mat = StandardMaterial3D.new()
			_void_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_void_mat.albedo_color = Color(0.008, 0.004, 0.008)
		mi.material_override = _void_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	elif tint != Color.WHITE:
		var mat := src.mesh.surface_get_material(0)
		if mat is BaseMaterial3D:
			var tinted := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
			tinted.albedo_color = tint
			mi.material_override = tinted
	return mi


# --- Denk-Stile -----------------------------------------------------------------

func _style_lean() -> float:
	match _think_style:
		ThinkStyle.STARE: return 0.13
		ThinkStyle.CARDS: return 0.05
		ThinkStyle.DRUM: return 0.04
	return 0.08


func _head_pitch() -> float:
	match _think_style:
		ThinkStyle.STARE: return 0.42
		ThinkStyle.CARDS: return 0.5
		ThinkStyle.DRUM: return 0.15
	return 0.32


func _head_yaw() -> float:
	match _think_style:
		ThinkStyle.STARE: return sin(_t * 0.3) * 0.05
		ThinkStyle.CARDS: return sin(_t * 1.4) * 0.22
		ThinkStyle.DRUM: return sin(_t * 0.5) * 0.35
	return sin(_t * 0.6) * 0.25


func _head_roll() -> float:
	match _think_style:
		ThinkStyle.CARDS: return sin(_t * 1.4 + 1.0) * 0.12
		ThinkStyle.DRUM: return 0.0
		ThinkStyle.STARE: return 0.0
	return 0.12


func _hand_think_offset(i: int) -> Vector3:
	match _think_style:
		ThinkStyle.CHIN:
			if i == 1:
				return Vector3(-0.1, 0.42 + sin(_t * 9.0) * 0.008, -0.2)
		ThinkStyle.STARE:
			# Hände flach auf den Tisch, leicht nach vorne
			return Vector3(0, -0.02, 0.06)
		ThinkStyle.CARDS:
			# Karten näher ans Gesicht ziehen
			return Vector3(0, 0.08, -0.06)
		ThinkStyle.DRUM:
			var phase := _t * 11.0 + i * PI
			return Vector3(0, maxf(0.0, sin(phase)) * 0.035, 0.03)
	return Vector3.ZERO


## Arme als Kapsel zwischen Schulter (bewegt sich mit dem Oberkörper) und Hand.
func _update_arms() -> void:
	for i in _arms.size():
		var side := -1.0 if i == 0 else 1.0
		var shoulder := _torso.transform * Vector3(side * 0.40 * size_scale, 1.02 * size_scale, 0.0)
		var hand := _hands[i].position + Vector3(0, 0.0, -0.05)
		var dir := hand - shoulder
		var length := dir.length()
		var y := dir / length
		var x := y.cross(Vector3.FORWARD).normalized()
		if x.length_squared() < 0.01:
			x = Vector3.RIGHT
		var z := x.cross(y).normalized()
		_arms[i].transform = Transform3D(Basis(x * size_scale, y * length, z * size_scale), (shoulder + hand) * 0.5)


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 10
	return m
