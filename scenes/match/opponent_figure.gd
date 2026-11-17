class_name OpponentFigure
extends Node3D
## Die Gestalt gegenüber am Tisch: dunkler Mantel, langer Hals,
## bleiche Porzellanmaske mit hohlen Augen. Komplett aus Grundformen gebaut,
## damit sie später leicht durch ein echtes Modell ersetzt werden kann.
## Ursprung = Mitte der Tischkante auf Gegnerseite, Boden (y = 0), Blick nach +Z.

var mask_color := Color("d8cfb8")
var body_color := Color("1b1716")
var eye_color := Color("c4271b")
var size_scale := 1.0
var hat := false

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


func setup(data: OpponentData) -> OpponentFigure:
	if data != null:
		mask_color = data.mask_color
		body_color = data.body_color
		eye_color = data.eye_color
		size_scale = data.figure_scale
		hat = data.wears_hat
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
	if _slump > 0.0:
		_slump = minf(_slump + delta, 2.0)

	var breath := sin(_t * 1.6) * 0.012
	var lean := sin(_gesture * PI) * 0.12 - _recoil * 0.10 + minf(_slump, 1.0) * 0.18
	_torso.rotation.x = lean
	_torso.scale = Vector3(1.0, 1.0 + breath, 1.0)

	var shake := sin(_t * 38.0) * 0.03 * _laugh
	_head.rotation = Vector3(
		sin(_t * 0.7) * 0.05 + minf(_slump, 1.0) * 0.35 - _recoil * 0.2,
		sin(_t * 0.45) * 0.12 + shake,
		sin(_t * 0.9) * 0.04 + _recoil * 0.15)

	for i in _hands.size():
		var side := -1.0 if i == 0 else 1.0
		var off := Vector3(0, sin(_t * 1.6 + i) * 0.006, 0)
		if i == 1:
			off += Vector3(-0.08, 0.05, 0.18) * sin(_gesture * PI)
		off += Vector3(side * 0.04, 0.06, -0.08) * _recoil
		_hands[i].position = _hand_rest[i] + off

	_update_arms()

	var glow := 1.2 + sin(_t * 2.3) * 0.4 + _laugh * 3.0
	_eye_mat.emission_energy_multiplier = glow * (0.3 if _slump > 0.0 else 1.0)


# --- Aufbau -------------------------------------------------------------------

func _build() -> void:
	var s := size_scale
	var coat := _mat(body_color, 0.95)
	var skin := _mat(mask_color, 0.55)
	var dark := _mat(Color("070606"), 1.0)
	_eye_mat = _mat(eye_color, 0.4)
	_eye_mat.emission_enabled = true
	_eye_mat.emission = eye_color

	# Oberkörper (dreht sich um die Hüfte)
	_torso = Node3D.new()
	# größere Gestalten sitzen tiefer, damit der Kopf im Bild bleibt
	_torso.position = Vector3(0, 0.02 - (s - 1.0) * 1.45, -0.34 - (s - 1.0) * 0.3)
	add_child(_torso)

	var body := _mesh(_capsule(0.30 * s, 1.25 * s), coat)
	body.position = Vector3(0, 0.55 * s, 0)
	body.scale = Vector3(1.35, 1.0, 0.8)
	_torso.add_child(body)

	var shoulders := _mesh(_capsule(0.14 * s, 0.95 * s), coat)
	shoulders.rotation_degrees = Vector3(0, 0, 90)
	shoulders.position = Vector3(0, 1.05 * s, 0.02)
	_torso.add_child(shoulders)

	var neck := _mesh(_cylinder(0.045 * s, 0.055 * s, 0.32 * s), _mat(mask_color.darkened(0.45), 0.8))
	neck.position = Vector3(0, 1.25 * s, 0.03)
	_torso.add_child(neck)

	# Kopf
	_head = Node3D.new()
	_head.position = Vector3(0, 1.42 * s, 0.05)
	_torso.add_child(_head)

	var skull := _mesh(_sphere(0.19 * s), skin)
	skull.scale = Vector3(1.0, 1.18, 0.95)
	skull.position = Vector3(0, 0.1 * s, 0)
	_head.add_child(skull)

	for side in [-1.0, 1.0]:
		# tiefe, schwarze Augenhöhlen
		var socket := _mesh(_sphere(0.055 * s), dark)
		socket.scale = Vector3(1.0, 1.25, 0.6)
		socket.position = Vector3(side * 0.07 * s, 0.14 * s, 0.155 * s)
		_head.add_child(socket)
		# glühende Pupille
		var eye := _mesh(_sphere(0.014 * s), _eye_mat)
		eye.position = Vector3(side * 0.07 * s, 0.13 * s, 0.185 * s)
		_head.add_child(eye)
		_eyes.append(eye)

	# zugenähter Mund
	var mouth := _mesh(_box(Vector3(0.13, 0.006, 0.02) * s), dark)
	mouth.position = Vector3(0, -0.02 * s, 0.172 * s)
	_head.add_child(mouth)
	for i in 5:
		var stitch := _mesh(_box(Vector3(0.005, 0.04, 0.02) * s), dark)
		stitch.position = Vector3((-0.05 + i * 0.025) * s, -0.02 * s, 0.17 * s)
		_head.add_child(stitch)

	# schwaches Licht, das die Maske aus der Dunkelheit holt
	var face_light := SpotLight3D.new()
	face_light.position = Vector3(0, 0.45 * s, 0.75)
	face_light.rotation_degrees = Vector3(-25, 0, 0)
	face_light.light_color = Color("ffcfa0")
	face_light.light_energy = 1.6
	face_light.spot_range = 1.4
	face_light.spot_angle = 18.0
	_head.add_child(face_light)

	if hat:
		var brim := _mesh(_cylinder(0.3 * s, 0.3 * s, 0.015 * s), coat)
		brim.position = Vector3(0, 0.3 * s, 0)
		_head.add_child(brim)
		var top := _mesh(_cylinder(0.15 * s, 0.17 * s, 0.26 * s), coat)
		top.position = Vector3(0, 0.43 * s, 0)
		_head.add_child(top)

	# Arme + Hände (Hände liegen am Tisch / halten die Karten)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hand := Node3D.new()
		var rest := Vector3(side * 0.15, 0.86, 0.2)
		hand.position = rest
		add_child(hand)
		_hands.append(hand)
		_hand_rest.append(rest)

		var palm := _mesh(_sphere(0.038), skin)
		palm.scale = Vector3(1.0, 0.55, 1.25)
		hand.add_child(palm)
		for f in 4:
			var finger := _mesh(_capsule(0.009, 0.09), skin)
			finger.rotation_degrees = Vector3(70, side * (8 - f * 6), 0)
			finger.position = Vector3(side * (-0.03 + f * 0.02), 0.01, 0.06)
			hand.add_child(finger)

		var arm := _mesh(_capsule(0.065 * s, 1.0), coat)
		add_child(arm)
		_arms.append(arm)
	_update_arms()


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
		_arms[i].transform = Transform3D(Basis(x, y * length, z), (shoulder + hand) * 0.5)


func _mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	return mi


func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 16
	m.rings = 10
	return m


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 12
	m.rings = 6
	return m


func _cylinder(top: float, bottom: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = 14
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m
