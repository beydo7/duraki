class_name GaugeLives
extends Node3D
## Druckanzeigen an der Wand der U-Boot – zeigen die Leben.
## Pro Leben eine runde Anzeige; der Zeiger zittert im grünen Bereich. Verlierst du ein Leben,
## schnellt ein Zeiger in den roten Bereich, das Ventil darunter zischt Dampf.

const SND_HISS := preload("res://assets/rooms/submarine/hiss.wav")
const GAUGE := preload("res://assets/rooms/submarine/gauge.png")
const STEP := 0.25
const R := 0.095

## Wie weit die Rohre unter den Anzeigen nach unten gehen (bis zum Boden = Höhe der Anzeigen).
var floor_drop := 0.35:
	set(v):
		floor_drop = v
		set_lives(maxi(_gauges.size(), 1))

var _gauges: Array[Dictionary] = []
var _t := 0.0
var _face: StandardMaterial3D
var _brass: StandardMaterial3D
var _pipe: StandardMaterial3D


func _init() -> void:
	_face = StandardMaterial3D.new()
	_face.albedo_texture = GAUGE
	_face.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_face.roughness = 0.5
	_face.emission_enabled = true # leicht hinterleuchtet, damit man sie im Halbdunkel liest
	_face.emission_texture = GAUGE
	_face.emission_energy_multiplier = 0.35
	_brass = RoomKit.mat(Color(0.78, 0.6, 0.3), 0.3, 1.0)
	_pipe = RoomKit.mat(Color(0.35, 0.38, 0.36), 0.45, 0.6)
	set_lives(3)


func _process(delta: float) -> void:
	_t += delta
	for g in _gauges:
		var needle: Node3D = g.needle
		var jitter := sin(_t * (7.0 + g.seed) + g.seed) * 0.6 * (0.3 if g.ok else 1.4)
		needle.rotation.z = _needle_angle(float(g.value) + jitter * 0.1)


## Zeigerwinkel für Wert 0–10 (Skala im Bild von -225° bis +45°, im Uhrzeigersinn).
static func _needle_angle(v: float) -> float:
	return -deg_to_rad(-225.0 + 27.0 * clampf(v, 0.0, 10.0))


func set_lives(count: int) -> void:
	for g in _gauges:
		(g.root as Node3D).queue_free()
	_gauges.clear()
	count = maxi(count, 1)
	var step := minf(STEP, 1.0 / maxf(count - 1, 1))
	for i in count:
		var root := Node3D.new()
		root.position = Vector3((i - (count - 1) * 0.5) * step, 0, 0)
		add_child(root)
		RoomKit.cyl(root, R + 0.018, R + 0.018, 0.04, Vector3(0, 0, 0.02), _brass).rotation.x = PI * 0.5
		RoomKit.quad(root, Vector2(R * 2.0, R * 2.0), Vector3(0, 0, 0.041), _face)
		RoomKit.torus(root, R + 0.012, 0.008, Vector3(0, 0, 0.042), _brass).rotation.x = PI * 0.5
		var needle := Node3D.new()
		needle.position.z = 0.046
		root.add_child(needle)
		RoomKit.box(needle, Vector3(R * 0.85, 0.006, 0.003), Vector3(R * 0.32, 0, 0), RoomKit.mat(Color(0.75, 0.1, 0.08), 0.4))
		RoomKit.cyl(needle, 0.011, 0.011, 0.006, Vector3.ZERO, _brass).rotation.x = PI * 0.5
		# Rohr mit Ventil unter der Anzeige
		var top := -R + 0.01
		RoomKit.cyl(root, 0.018, 0.018, floor_drop + top, Vector3(0, (top - floor_drop) * 0.5, 0.03), _pipe)
		RoomKit.cyl(root, 0.035, 0.035, 0.02, Vector3(0, -floor_drop + 0.01, 0.03), _brass) # Flansch am Boden
		var wheel := RoomKit.torus(root, 0.035, 0.006, Vector3(0, -R - 0.12, 0.065), RoomKit.mat(Color(0.7, 0.12, 0.1), 0.5))
		wheel.rotation.x = PI * 0.5
		var steam := _steam()
		steam.position = Vector3(0.02, -R - 0.12, 0.07)
		root.add_child(steam)
		_gauges.append({"root": root, "needle": needle, "steam": steam, "value": 3.0 + i * 0.4,
			"ok": true, "seed": i * 1.7})


## Ein Leben weg: letzter Zeiger im grünen Bereich schnellt in den roten, Dampf zischt.
func lose_life() -> void:
	for i in range(_gauges.size() - 1, -1, -1):
		var g: Dictionary = _gauges[i]
		if g.ok:
			g.ok = false
			var tw := create_tween()
			tw.tween_method(func(v: float) -> void: g.value = v, float(g.value), 10.6, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_method(func(v: float) -> void: g.value = v, 10.6, 9.3, 0.6).set_trans(Tween.TRANS_ELASTIC)
			(g.steam as CPUParticles3D).emitting = true
			RoomKit.play(self, SND_HISS, -10.0)
			return


func _steam() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 40
	p.lifetime = 1.4
	p.explosiveness = 0.2
	p.direction = Vector3(0.6, 1, 0.5)
	p.spread = 25.0
	p.initial_velocity_min = 0.25
	p.initial_velocity_max = 0.5
	p.gravity = Vector3(0, 0.15, 0)
	p.damping_min = 0.4
	p.damping_max = 0.8
	p.scale_amount_min = 1.0
	p.scale_amount_max = 3.0
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.024
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	sm.material = m
	p.mesh = sm
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(0.95, 0.95, 0.95, 0.45), Color(1, 1, 1, 0.0)])
	p.color_ramp = grad
	return p
