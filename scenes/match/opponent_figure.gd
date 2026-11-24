class_name OpponentFigure
extends Node3D
## Die Gestalt gegenüber am Tisch. Das Modell kommt aus Blender
## (art/blender/opponents/<id>.blend → assets/models/opponents/<id>.glb) und wird
## hier zusammengesetzt und per Code animiert: Atmen, Vorbeugen, Nachdenken,
## Kopfzucken, Kiefer, glühende Augen.
##
## Erwartete Struktur im Modell (siehe art/blender/characters.py):
## Torso → Head → EyeL/EyeR(/EyeX…), optional Jaw; Hand_L, Hand_R, Sleeve;
## optional Props → PropLight. Teile, deren Name mit „Void“ beginnt, werden pechschwarz.
## Ursprung = Mitte der Tischkante auf Gegnerseite, Boden (y = 0), Blick nach +Z.

const DEFAULT_MODEL := preload("res://assets/models/opponents/bandit.glb")

var eye_color := Color("c4271b")
## false: keine Glut-Pupillen (das Modell hat eigene Augen, z. B. der HD-Bandit)
var eye_glow := true
var size_scale := 1.0
var model_scene: PackedScene = DEFAULT_MODEL

static var _void_mat: StandardMaterial3D

var _t := 0.0
var _torso: Node3D
var _head: Node3D
var _eyes: Array[MeshInstance3D] = []
var _eye_mat: StandardMaterial3D
var _hands: Array[Node3D] = []
var _hand_rest: Array[Vector3] = []
var _arms: Array[MeshInstance3D] = []
## Zwei-Segment-Arme (Ober-/Unterarm), wenn das Modell SleeveUpper/SleeveFore hat
var _uppers: Array[MeshInstance3D] = []
var _fores: Array[MeshInstance3D] = []
var _shoulders: Array[Vector3] = []
## Länge Ober-/Unterarm (gleich wie art/blender/hd.py ARM_SEGMENT)
const ARM_SEGMENT := 0.34
## Drehpunkt des Kartenfächers: etwas über/vor der Mitte zwischen den Händen
const CARD_GRIP := Vector3(0.0, 0.035, 0.03)
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
var _twitch_target := Vector3.ZERO
var _next_twitch := 3.0
## Geglättete Ist-Werte: alle Ziele werden weich angefahren, damit nichts ruckt
## (Reaktionen setzen ihre Stärke schlagartig, Denk-Stile wechseln, Zucken …).
const SMOOTH := 9.0
var _lean_now := 0.0
var _head_now := Vector3.ZERO
var _hand_now: Array[Vector3] = []

## Verschiedene Arten zu überlegen.
enum ThinkStyle {
	CHIN,  ## Hand ans Kinn, Finger tippen
	STARE, ## beugt sich vor und starrt auf den Tisch, Augen glühen auf
	CARDS, ## mustert die eigenen Karten, Kopf wiegt hin und her
	DRUM,  ## trommelt mit beiden Händen auf den Tisch
}


func setup(data: OpponentData) -> OpponentFigure:
	if data != null:
		eye_color = data.eye_color
		eye_glow = data.eye_glow
		size_scale = data.figure_scale
		if data.model != null:
			model_scene = data.model
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
	_think_style = style # Wechsel wird über die geglätteten Werte weich übergeblendet
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
	_gesture = move_toward(_gesture, 0.0, delta * 1.8)
	_recoil = move_toward(_recoil, 0.0, delta * 1.3)
	_laugh = move_toward(_laugh, 0.0, delta * 0.35)
	_think = move_toward(_think, _think_target, delta * 2.0)
	if _slump > 0.0:
		_slump = minf(_slump + delta, 2.0)

	var k := 1.0 - exp(-delta * SMOOTH)
	var think := smoothstep(0.0, 1.0, _think)
	var gest := sin(_gesture * PI)
	var rec := smoothstep(0.0, 1.0, _recoil)
	var breath := sin(_t * 1.6) * 0.012
	var lean := gest * 0.12 - rec * 0.10 + smoothstep(0.0, 1.0, minf(_slump, 1.0)) * 0.18 + think * _style_lean()
	_lean_now = lerpf(_lean_now, lean, k)
	_torso.rotation.x = _lean_now
	_torso.scale = Vector3(size_scale, size_scale * (1.0 + breath), size_scale)

	# unheimliches Zucken: ab und zu dreht sich der Kopf kurz zur Seite (weich, kein harter Ruck)
	_next_twitch -= delta
	if _next_twitch <= 0.0 and _slump <= 0.0:
		_next_twitch = randf_range(3.0, 8.0)
		_twitch_target = Vector3(randf_range(-0.08, 0.08), randf_range(-0.18, 0.18), randf_range(-0.2, 0.2))
	_twitch = _twitch.lerp(_twitch_target, minf(1.0, delta * 10.0))
	_twitch_target = _twitch_target.lerp(Vector3.ZERO, minf(1.0, delta * 2.5))

	var shake := sin(_t * 24.0) * 0.025 * _laugh
	var head := Vector3(
		sin(_t * 0.7) * 0.05 + minf(_slump, 1.0) * 0.35 - rec * 0.2 + think * _head_pitch(),
		sin(_t * 0.45) * 0.12 * (1.0 - think) + think * _head_yaw(),
		sin(_t * 0.9) * 0.04 + rec * 0.15 + think * _head_roll()) + _twitch
	_head_now = _head_now.lerp(head, k)
	_head.rotation = _head_now + Vector3(0, shake, 0)

	# Kiefer: klappert beim Lachen, öffnet sich beim Legen und Zucken
	var jaw_target := maxf(gest * 0.6, _twitch.length() * 2.0)
	jaw_target = maxf(jaw_target, _laugh * (0.5 + 0.5 * sin(_t * 22.0)))
	_jaw_open = lerpf(_jaw_open, jaw_target, minf(1.0, delta * 12.0))
	if _jaw != null:
		_jaw.position = _jaw.get_meta("rest") + Vector3(0, -0.014, 0.004) * _jaw_open
		_jaw.rotation.x = _jaw.get_meta("rest_rot", 0.0) + _jaw_open * 0.14

	for i in _hands.size():
		var side := -1.0 if i == 0 else 1.0
		var off := Vector3(0, sin(_t * 1.6 + i) * 0.006, 0)
		if i == 1:
			off += Vector3(-0.08, 0.05, 0.18) * gest
		off += Vector3(side * 0.04, 0.06, -0.08) * rec
		off += _hand_think_offset(i) * think
		if _hand_now.size() <= i:
			_hand_now.append(off)
		_hand_now[i] = _hand_now[i].lerp(off, k)
		_hands[i].position = _hand_rest[i] + _hand_now[i]

	_update_arms()

	var glow := 1.2 + sin(_t * 2.3) * 0.4 + _laugh * 3.0
	if _think_style == ThinkStyle.STARE:
		glow += _think * 2.5
	var dim := 0.3 if _slump > 0.0 else 1.0
	_eye_mat.emission_energy_multiplier = glow * 1.7 * dim
	for l in _eye_lights:
		l.light_energy = (0.02 + glow * 0.02) * dim
	if _under_light != null:
		_under_light.light_energy = (0.12 + sin(_t * 1.1) * 0.03 + _laugh * 0.25) * dim


# --- Aufbau -------------------------------------------------------------------

func _build() -> void:
	var s := size_scale
	var model := model_scene.instantiate()

	_eye_mat = StandardMaterial3D.new()
	_eye_mat.albedo_color = eye_color
	_eye_mat.roughness = 0.4
	_eye_mat.emission_enabled = true
	_eye_mat.emission = eye_color

	# Oberkörper samt Kopf direkt aus dem Modell übernehmen
	_torso = _take(model.find_child("Torso", true, false), self)
	if _torso == null:
		push_warning("Gegnermodell ohne 'Torso'")
		_torso = Node3D.new()
		add_child(_torso)
	# größere Gestalten sitzen tiefer, damit der Kopf im Bild bleibt
	_torso.position = Vector3(0, 0.02 - (s - 1.0) * 1.7, -0.34 - (s - 1.0) * 0.3)
	_torso.scale = Vector3.ONE * s
	_head = _torso.find_child("Head", true, false) as Node3D
	if _head == null:
		_head = Node3D.new()
		_head.position = Vector3(0, 1.33, 0.03)
		_torso.add_child(_head)
	_jaw = _head.find_child("Jaw", true, false) as Node3D
	if _jaw != null:
		_jaw.set_meta("rest", _jaw.position)
		_jaw.set_meta("rest_rot", _jaw.rotation.x)
	_apply_void(_torso)

	# glühende Pupillen an den Augen-Markierungen
	for marker in (_head.find_children("Eye*", "", true, false) if eye_glow else []):
		var small: bool = String(marker.name).begins_with("EyeX")
		var eye := MeshInstance3D.new()
		eye.mesh = _sphere(0.007 if small else 0.012)
		eye.material_override = _eye_mat
		eye.position = (marker as Node3D).position
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.get_parent().add_child(eye)
		_eyes.append(eye)
		if not small:
			var glow := OmniLight3D.new()
			glow.light_color = eye_color
			glow.omni_range = 0.3 * s
			glow.omni_attenuation = 2.2
			glow.position = eye.position + Vector3(0, -0.02, 0.15)
			marker.get_parent().add_child(glow)
			_eye_lights.append(glow)

	# Licht von oben vorne holt das Gesicht aus der Dunkelheit …
	var face_light := SpotLight3D.new()
	face_light.position = Vector3(0, 0.3, 0.8)
	face_light.rotation_degrees = Vector3(-15, 0, 0)
	face_light.light_color = Color("e6d8ff")
	face_light.light_energy = 1.1
	face_light.spot_range = 1.6
	face_light.spot_angle = 26.0
	_head.add_child(face_light)
	# … und Grusel-Licht von unten in Augenfarbe
	_under_light = SpotLight3D.new()
	_under_light.light_color = eye_color.lerp(Color("ffb070"), 0.35)
	_under_light.spot_range = 1.6
	_under_light.spot_angle = 30.0
	_under_light.spot_attenuation = 0.8
	add_child(_under_light)
	_under_light.position = Vector3(0, 0.86, 0.1)
	_under_light.look_at(_torso.position + Vector3(0, 1.4 * s, 0.1))

	# Hände (halten die Karten) und Arme. Ruheposition = Lage der Hand im Modell.
	var sleeve_src := model.find_child("Sleeve", true, false) as MeshInstance3D
	var upper_src := model.find_child("SleeveUpper", true, false) as MeshInstance3D
	var fore_src := model.find_child("SleeveFore", true, false) as MeshInstance3D
	var two_part := upper_src != null and fore_src != null
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var src := model.find_child("Hand_L" if i == 0 else "Hand_R", true, false) as Node3D
		var rest := Vector3(side * 0.15, 0.86, 0.2)
		if src != null and src.position.length() > 0.01:
			rest = src.position
		var hand := Node3D.new()
		hand.position = rest
		add_child(hand)
		_hands.append(hand)
		_hand_rest.append(rest)
		var h := _take(src, hand)
		if h != null:
			h.transform = Transform3D.IDENTITY
		var marker := _torso.find_child("Shoulder_L" if i == 0 else "Shoulder_R", true, false) as Node3D
		_shoulders.append(marker.position if marker != null else Vector3(side * 0.40, 1.02, 0.0))
		if two_part:
			for pair in [[upper_src, _uppers], [fore_src, _fores]]:
				var seg := MeshInstance3D.new()
				seg.mesh = (pair[0] as MeshInstance3D).mesh
				add_child(seg)
				(pair[1] as Array).append(seg)
		else:
			var arm := MeshInstance3D.new()
			if sleeve_src != null:
				arm.mesh = sleeve_src.mesh
			add_child(arm)
			_arms.append(arm)

	# Requisiten auf dem Tisch (z. B. die Laterne der Hexe)
	var props := _take(model.find_child("Props", true, false), self)
	if props != null:
		var marker := props.find_child("PropLight", true, false) as Node3D
		if marker != null:
			var lamp := OmniLight3D.new()
			lamp.light_color = eye_color.lightened(0.2)
			lamp.light_energy = 1.2
			lamp.omni_range = 0.9
			lamp.position = marker.position
			props.add_child(lamp)
	model.free()
	# Hände, Arme und Requisiten liegen nicht unter dem Torso → hier noch einmal für alles
	_apply_void(self)
	_update_arms()


## Hängt einen Knoten aus dem geladenen Modell an einen neuen Elternknoten.
func _take(node: Node, new_parent: Node) -> Node3D:
	if node == null:
		return null
	node.get_parent().remove_child(node)
	_clear_owner(node)
	new_parent.add_child(node)
	return node as Node3D


func _clear_owner(node: Node) -> void:
	node.owner = null
	for c in node.get_children():
		_clear_owner(c)


## Löcher (Augenhöhlen, Mäuler) pechschwarz und unbeleuchtet,
## sonst spiegeln sie das farbige Augenlicht.
func _apply_void(root: Node) -> void:
	for mi in root.find_children("Void*", "MeshInstance3D", true, false):
		if _void_mat == null:
			_void_mat = StandardMaterial3D.new()
			_void_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_void_mat.albedo_color = Color(0.008, 0.004, 0.008)
		(mi as MeshInstance3D).material_override = _void_mat
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Fell und Haare (viele Alpha-Büschel) werfen keine Schatten aufeinander –
	# sonst wird z. B. die Mützenkappe fleckig schwarz
	for pattern in ["*_Fur", "*_Brows", "*_Fringe"]:
		for mi in root.find_children(pattern, "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# und Alpha-Flächen (Fell, Moos – auch wenn sie in einem anderen Mesh stecken, z. B. im
	# Unterarm) glänzen nicht: Godot nimmt sonst Glanz 0.5 an → Lampenlicht spiegelt lila
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var m := node as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i) as StandardMaterial3D
			if mat == null or m.get_surface_override_material(i) != null:
				continue  # kein Standardmaterial oder schon erledigt
			var spec := -1.0
			if mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
				spec = 0.08
			elif mat.roughness >= 0.6:
				spec = 0.25  # matte Stoffe/Fell/Haut: glTF bringt keinen Glanzwert mit
			if spec < 0.0:
				continue
			mat = mat.duplicate()
			mat.metallic_specular = spec
			m.set_surface_override_material(i, mat)


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


## Arme: entweder ein Schlauch zwischen Schulter und Hand (alte Modelle) oder
## Ober- und Unterarm mit Ellbogen per Zwei-Knochen-IK (Ellbogen nach außen/unten).
func _update_arms() -> void:
	for i in _hands.size():
		var side := -1.0 if i == 0 else 1.0
		var shoulder := _torso.transform * _shoulders[i]
		var hand := _hands[i].position + Vector3(0, 0.0, -0.05)
		if _uppers.is_empty():
			_place_segment(_arms[i], shoulder, hand)
			continue
		var l := ARM_SEGMENT * size_scale
		var to_hand := hand - shoulder
		var d := clampf(to_hand.length(), 0.001, l * 2.0 - 0.001)
		var dir := to_hand.normalized()
		var pole := Vector3(side * 1.0, -0.35, -0.3)
		var perp := (pole - dir * pole.dot(dir)).normalized()
		var a := d * 0.5
		var h := sqrt(maxf(l * l - a * a, 0.0))
		var elbow := shoulder + dir * a + perp * h
		_place_segment(_uppers[i], shoulder, elbow)
		_place_segment(_fores[i], elbow, hand)


func _place_segment(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.0001:
		return
	var y := dir / length
	var x := y.cross(Vector3.FORWARD).normalized()
	if x.length_squared() < 0.01:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	mi.transform = Transform3D(Basis(x * size_scale, y * length, z * size_scale), (a + b) * 0.5)


## Drehpunkt des Kartenfächers in Weltkoordinaten. Die Karten folgen der linken Hand
## (die rechte darf zum Kinn, zum Ausspielen usw.).
func card_pivot() -> Vector3:
	if _hands.is_empty():
		return card_pivot_rest()
	return card_pivot_rest() + (_hands[0].position - _hand_rest[0])


## Drehpunkt in Ruhe (Mitte zwischen den Händen, ohne Handbewegung).
func card_pivot_rest() -> Vector3:
	if _hand_rest.size() < 2:
		return to_global(Vector3(0, 0.93, 0.25))
	return to_global((_hand_rest[0] + _hand_rest[1]) * 0.5 + CARD_GRIP)


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 10
	return m
