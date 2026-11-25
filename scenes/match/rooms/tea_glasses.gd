class_name TeaGlasses
extends Node3D
## Teegläser in Metallhaltern (Podstakanniki) – im Bahnhofswartesaal die Leben.
## Pro Leben ein dampfendes Glas Tee mit Löffel. Verlierst du ein Leben, wird ein Glas
## leer getrunken (Tee sinkt, Dampf hört auf). Fährt draußen ein Zug vorbei, klappern
## die Gläser (`rattle`).

const SND_CLINK := preload("res://assets/rooms/station/glass_clink.wav")
const GLASS_R := 0.017
const GLASS_H := 0.06
const STEP := 0.05

var _glasses: Array[Dictionary] = []
var _rattle := 0.0
var _clink_cooldown := 0.0
var _glass_mat: StandardMaterial3D
var _tea_mat: StandardMaterial3D
var _metal: StandardMaterial3D


func _init() -> void:
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.albedo_color = Color(0.85, 0.92, 0.95, 0.22)
	_glass_mat.roughness = 0.05
	_glass_mat.metallic_specular = 1.0
	_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_tea_mat = StandardMaterial3D.new()
	_tea_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tea_mat.albedo_color = Color(0.55, 0.2, 0.04, 0.86)
	_tea_mat.roughness = 0.1
	_tea_mat.emission_enabled = true # Licht fängt sich im Tee
	_tea_mat.emission = Color(0.35, 0.12, 0.02)
	_tea_mat.emission_energy_multiplier = 0.5
	_metal = StandardMaterial3D.new()
	_metal.albedo_color = Color(0.78, 0.76, 0.72)
	_metal.metallic = 1.0
	_metal.roughness = 0.28


func _process(delta: float) -> void:
	_clink_cooldown = maxf(0.0, _clink_cooldown - delta)
	if _rattle <= 0.0:
		return
	_rattle = maxf(0.0, _rattle - delta)
	var amp := minf(_rattle, 1.0) * 0.0012
	for g in _glasses:
		var root: Node3D = g.root
		root.position = g.home + Vector3(randf_range(-amp, amp), 0, randf_range(-amp, amp))
		root.rotation.z = randf_range(-amp, amp) * 3.0
		var spoon: Node3D = g.spoon
		spoon.rotation.z = 0.22 + randf_range(-amp, amp) * 12.0
	if _rattle <= 0.0:
		for g in _glasses:
			(g.root as Node3D).position = g.home
			(g.root as Node3D).rotation.z = 0.0


## Ein Glas pro Leben aufstellen (in einer leicht versetzten Reihe).
func set_lives(count: int) -> void:
	for g in _glasses:
		(g.root as Node3D).queue_free()
	_glasses.clear()
	var step := minf(STEP, 0.3 / maxf(count - 1, 1))
	for i in count:
		var pos := Vector3((i - (count - 1) * 0.5) * step, 0, 0.012 * (i % 2))
		_glasses.append(_glass(pos, i))


## Ein Leben weg: das letzte volle Glas wird leer getrunken.
func lose_life() -> void:
	for i in range(_glasses.size() - 1, -1, -1):
		var g: Dictionary = _glasses[i]
		if g.full:
			g.full = false
			var tea: Node3D = g.tea
			var tw := create_tween()
			tw.tween_property(tea, "scale:y", 0.06, 1.1).set_trans(Tween.TRANS_SINE)
			(g.steam as CPUParticles3D).emitting = false
			_clink(-12.0)
			return


## Zug fährt vorbei: Gläser klappern `seconds` lang.
func rattle(seconds: float) -> void:
	_rattle = maxf(_rattle, seconds)
	if _clink_cooldown <= 0.0:
		_clink(-16.0)
		_clink_cooldown = 1.3


func _clink(db: float) -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX"
	p.stream = SND_CLINK
	p.volume_db = db
	p.pitch_scale = randf_range(0.95, 1.08)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _glass(pos: Vector3, i: int) -> Dictionary:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = 0.4 + i * 1.3
	add_child(root)
	# Halter: Boden, durchbrochener Korb (Ringe und Stäbe) und Henkel
	_cyl(root, GLASS_R + 0.003, GLASS_R + 0.004, 0.006, 0.003, _metal)
	for y in [0.012, 0.03]:
		var ring := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = GLASS_R + 0.0005
		rm.outer_radius = GLASS_R + 0.0035
		rm.rings = 24
		rm.ring_segments = 6
		ring.mesh = rm
		ring.material_override = _metal
		ring.position.y = y
		root.add_child(ring)
	for k in 6:
		var a := TAU * k / 6.0
		var bar := _cyl(root, 0.0012, 0.0012, 0.03, 0.018, _metal)
		bar.position.x = cos(a) * (GLASS_R + 0.002)
		bar.position.z = sin(a) * (GLASS_R + 0.002)
	var handle := MeshInstance3D.new()
	var hm := TorusMesh.new()
	hm.inner_radius = 0.008
	hm.outer_radius = 0.011
	hm.rings = 20
	hm.ring_segments = 6
	handle.mesh = hm
	handle.material_override = _metal
	handle.rotation.x = PI * 0.5
	handle.position = Vector3(GLASS_R + 0.008, 0.022, 0)
	root.add_child(handle)
	# Glas und Tee
	_cyl(root, GLASS_R * 1.05, GLASS_R * 0.95, GLASS_H, 0.004 + GLASS_H * 0.5, _glass_mat)
	var tea_pivot := Node3D.new()
	tea_pivot.position.y = 0.006
	root.add_child(tea_pivot)
	var tea := _cyl(tea_pivot, GLASS_R * 0.97, GLASS_R * 0.9, GLASS_H * 0.8, GLASS_H * 0.4, _tea_mat)
	tea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Löffel steht schräg im Glas
	var spoon := Node3D.new()
	spoon.position = Vector3(-0.006, 0.008, 0.004)
	spoon.rotation.z = 0.22
	root.add_child(spoon)
	_cyl(spoon, 0.0013, 0.0013, 0.085, 0.0425, _metal)
	# Dampf
	var steam := CPUParticles3D.new()
	steam.position.y = GLASS_H + 0.006
	steam.amount = 10
	steam.lifetime = 2.4
	steam.direction = Vector3.UP
	steam.spread = 10.0
	steam.initial_velocity_min = 0.015
	steam.initial_velocity_max = 0.03
	steam.gravity = Vector3(0.004, 0.006, 0)
	steam.scale_amount_min = 0.7
	steam.scale_amount_max = 1.6
	var sm := SphereMesh.new()
	sm.radius = 0.006
	sm.height = 0.012
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.9, 0.9, 0.92, 0.12)
	mat.vertex_color_use_as_albedo = true
	sm.material = mat
	steam.mesh = sm
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)])
	steam.color_ramp = grad
	root.add_child(steam)
	return {"root": root, "home": pos, "tea": tea_pivot, "steam": steam, "spoon": spoon, "full": true}


func _cyl(parent: Node, top: float, bottom: float, h: float, y: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 20
	mi.mesh = c
	mi.material_override = m
	mi.position.y = y
	parent.add_child(mi)
	return mi
