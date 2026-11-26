class_name GaugeLives
extends Node3D
## Druckanzeigen an der Wand im U-Boot – zeigen die Leben.
## Pro Leben eine runde Anzeige; der Zeiger zittert im grünen Bereich. Verlierst du ein Leben,
## schnellt ein Zeiger in den roten Bereich und bleibt dort zitternd stehen, Dampf zischt, die
## Kontrollleuchte darunter wechselt von Grün auf Rot. Die Anzeige bleibt stehen.

const SND_HISS := preload("res://assets/rooms/submarine/hiss.wav")
const GAUGE := preload("res://assets/rooms/submarine/gauge.png")
const STEP := 0.25
const R := 0.095
const GREEN := Color(0.2, 1.0, 0.35)
const RED := Color(1.0, 0.12, 0.08)

## Wie weit die Rohre unter den Anzeigen nach unten gehen (bis zum Boden = Höhe der Anzeigen).
var floor_drop := 0.35:
	set(v):
		floor_drop = v
		var alive := 0
		for g in _gauges:
			alive += int(g.ok)
		_gauges_rebuild(alive)

var _gauges: Array[Dictionary] = []
var _max := 0 # höchste Zahl an Leben bisher (so viele Anzeigen stehen da)
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


## Anzeigen für `count` Leben. Verlorene Leben bleiben als Anzeige stehen (Zeiger im Roten,
## Lampe rot); es kommen nur neue dazu, wenn man mehr Leben hat als bisher.
func set_lives(count: int) -> void:
	_max = maxi(maxi(count, 1), Run.max_lives)
	if _gauges.size() != _max:
		_build(_max)
	for i in _gauges.size():
		_set_state(_gauges[i], i < count)


func _gauges_rebuild(alive: int) -> void:
	_build(maxi(_gauges.size(), 1))
	for i in _gauges.size():
		_set_state(_gauges[i], i < alive)


func _build(n: int) -> void:
	for g in _gauges:
		(g.root as Node3D).queue_free()
	_gauges.clear()
	var step := minf(STEP, 1.0 / maxf(n - 1, 1))
	for i in n:
		var root := Node3D.new()
		root.position = Vector3((i - (n - 1) * 0.5) * step, 0, 0)
		add_child(root)
		RoomKit.cyl(root, R + 0.018, R + 0.018, 0.04, Vector3(0, 0, 0.02), _brass).rotation.x = PI * 0.5
		RoomKit.quad(root, Vector2(R * 2.0, R * 2.0), Vector3(0, 0, 0.041), _face)
		RoomKit.torus(root, R + 0.012, 0.008, Vector3(0, 0, 0.042), _brass).rotation.x = PI * 0.5
		var needle := Node3D.new()
		needle.position.z = 0.046
		root.add_child(needle)
		RoomKit.box(needle, Vector3(R * 0.85, 0.006, 0.003), Vector3(R * 0.32, 0, 0), RoomKit.mat(Color(0.75, 0.1, 0.08), 0.4))
		RoomKit.cyl(needle, 0.011, 0.011, 0.006, Vector3.ZERO, _brass).rotation.x = PI * 0.5
		# Rohr unter der Anzeige bis zum Boden
		var top := -R + 0.01
		RoomKit.cyl(root, 0.018, 0.018, floor_drop + top, Vector3(0, (top - floor_drop) * 0.5, 0.03), _pipe)
		RoomKit.cyl(root, 0.035, 0.035, 0.02, Vector3(0, -floor_drop + 0.01, 0.03), _brass) # Flansch am Boden
		# Kontrollleuchte am Rohr: grün = Leben da, rot = Leben weg
		var lamp_pos := Vector3(0, -R - 0.12, 0.05)
		var bezel := RoomKit.cyl(root, 0.03, 0.03, 0.02, lamp_pos, _brass, 20)
		bezel.rotation.x = PI * 0.5
		var lamp_mat := RoomKit.glow(GREEN, 2.5)
		RoomKit.sphere(root, 0.022, lamp_pos + Vector3(0, 0, 0.012), lamp_mat, Vector3(1.0, 1.0, 0.6))
		var light := OmniLight3D.new()
		light.position = lamp_pos + Vector3(0, 0, 0.06)
		light.light_color = GREEN
		light.light_energy = 0.2
		light.omni_range = 0.35
		root.add_child(light)
		var steam := _steam()
		steam.position = Vector3(0.02, -R - 0.12, 0.07)
		root.add_child(steam)
		_gauges.append({"root": root, "needle": needle, "steam": steam, "value": 3.0 + i * 0.4,
			"ok": true, "seed": i * 1.7, "lamp": lamp_mat, "light": light, "i": i})


func _set_state(g: Dictionary, ok: bool) -> void:
	g.ok = ok
	g.value = 3.0 + int(g.i) * 0.4 if ok else 9.3
	_color_lamp(g, GREEN if ok else RED)


func _color_lamp(g: Dictionary, c: Color) -> void:
	var m: StandardMaterial3D = g.lamp
	m.albedo_color = c
	m.emission = c
	(g.light as OmniLight3D).light_color = c


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
			# Leuchte flackert kurz und bleibt dann rot
			var lt := create_tween()
			for k in 3:
				lt.tween_callback(func() -> void: _color_lamp(g, RED))
				lt.tween_interval(0.12)
				lt.tween_callback(func() -> void: _color_lamp(g, Color(0.15, 0.05, 0.04)))
				lt.tween_interval(0.1)
			lt.tween_callback(func() -> void: _color_lamp(g, RED))
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
