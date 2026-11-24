class_name TableProps
extends Node3D
## Lebendige Gegenstände auf deiner Tischseite – das „diegetische“ HUD:
##   Kerzen   = deine Leben (verlierst du, erlischt eine mit Rauch)
##   Münzen   = dein Gold (neue Münzen fallen klimpernd auf den Stapel)

const CANDLE_ORIGIN := Vector3(-0.72, 0.80, 0.08)
const COIN_ORIGIN := Vector3(0.6, 0.80, 0.24)
const COINS_PER_STACK := 8
const MAX_COINS := 40

var _candles: Array[Dictionary] = []
var _coins: Array[MeshInstance3D] = []
var _t := 0.0
var _wax: StandardMaterial3D
var _flame: StandardMaterial3D
var _brass: StandardMaterial3D
var _gold: StandardMaterial3D
var _coin_mesh: CylinderMesh
## Nur ein gemeinsames Licht pro Kerzenkranz (spart Leistung, z. B. im Shop-Hintergrund)
var _single_light := false
## Maus über den Kerzen → sie werden dunkler (1 = normal, ~0.35 = gedimmt)
var _dim := 1.0
var _dim_target := 1.0
var _hover_area: Area3D


func _init() -> void:
	_wax = _mat(Color(0.86, 0.8, 0.66), 0.65)
	_wax.subsurf_scatter_enabled = false
	_wax.rim_enabled = true
	_wax.rim = 0.3
	_flame = StandardMaterial3D.new()
	_flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame.albedo_color = Color(1.0, 0.72, 0.3)
	_flame.emission_enabled = true
	_flame.emission = Color(1.0, 0.6, 0.2)
	_flame.emission_energy_multiplier = 3.0
	_flame.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_brass = _mat(Color(0.28, 0.2, 0.1), 0.55)
	_brass.metallic = 0.7
	_gold = _mat(Color(0.95, 0.72, 0.28), 0.32)
	_gold.metallic = 1.0
	_coin_mesh = CylinderMesh.new()
	_coin_mesh.top_radius = 0.016
	_coin_mesh.bottom_radius = 0.016
	_coin_mesh.height = 0.0032
	_coin_mesh.radial_segments = 20


func _process(delta: float) -> void:
	_t += delta
	_dim = lerpf(_dim, _dim_target, minf(delta * 3.0, 1.0))
	for i in _candles.size():
		var c: Dictionary = _candles[i]
		var flame: MeshInstance3D = c.flame
		var light: OmniLight3D = c.light
		var life: float = c.life
		if life <= 0.001:
			flame.visible = false
			light.visible = false
			continue
		var flicker := 0.82 + 0.1 * sin(_t * 11.0 + i * 2.3) + 0.08 * sin(_t * 23.0 + i)
		flame.scale = Vector3(1.0, 0.9 + 0.2 * flicker, 1.0) * life * lerpf(0.45, 1.0, _dim)
		flame.position.x = sin(_t * 3.0 + i) * 0.0012
		if _single_light:
			light.visible = i == 0
			light.light_energy = 0.32 * flicker * life * minf(_candles.size(), 4) * lerpf(0.3, 1.0, _dim)
		else:
			light.light_energy = 0.32 * flicker * life * lerpf(0.3, 1.0, _dim)


## Kerzen für die Leben aufstellen (einmal beim Aufbau).
func set_lives(count: int) -> void:
	for c in _candles:
		(c.root as Node3D).queue_free()
	_candles.clear()
	var dish := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.062
	dm.bottom_radius = 0.066
	dm.height = 0.008
	dish.mesh = dm
	dish.material_override = _brass
	dish.position = CANDLE_ORIGIN + Vector3(0, 0.004, 0)
	add_child(dish)
	for i in count:
		var a := TAU * i / maxf(count, 1) + 0.6
		var r := 0.0 if count == 1 else 0.042
		var pos := CANDLE_ORIGIN + Vector3(cos(a) * r, 0.008, sin(a) * r)
		_candles.append(_candle(pos, 0.07 + 0.02 * ((i * 7) % 3) / 2.0))
	_add_hover_area()


## Fläche über dem Kerzenkranz: Maus drüber → Kerzen werden dunkler.
func _add_hover_area() -> void:
	if _hover_area != null:
		return
	_hover_area = Area3D.new()
	_hover_area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.075
	cyl.height = 0.16
	shape.shape = cyl
	_hover_area.add_child(shape)
	_hover_area.position = CANDLE_ORIGIN + Vector3(0, 0.08, 0)
	add_child(_hover_area)
	_hover_area.mouse_entered.connect(func() -> void:
		_dim_target = 0.35
		Sfx.play(&"candle_dim", 1.0, -8.0))
	_hover_area.mouse_exited.connect(func() -> void: _dim_target = 1.0)


## Ein Licht für den ganzen Kranz statt eines pro Kerze (vor oder nach set_lives aufrufen).
func use_single_light() -> void:
	_single_light = true


## Die letzte brennende Kerze erlischt (mit Rauchfaden).
func snuff_candle() -> void:
	for i in range(_candles.size() - 1, -1, -1):
		var c: Dictionary = _candles[i]
		if c.life > 0.0:
			var tw := create_tween()
			tw.tween_method(func(v: float) -> void: c.life = v, 1.0, 0.0, 0.9).set_trans(Tween.TRANS_SINE)
			tw.tween_callback(func() -> void: _smoke((c.flame as Node3D).global_position))
			return


## Münzstapel auf die Goldmenge bringen (neue Münzen fallen herunter).
func set_gold(amount: int, animate := true) -> void:
	var target := mini(amount, MAX_COINS)
	while _coins.size() > target:
		_coins.pop_back().queue_free()
	var start := _coins.size()
	for i in range(start, target):
		var coin := MeshInstance3D.new()
		coin.mesh = _coin_mesh
		coin.material_override = _gold
		var stack := i / COINS_PER_STACK
		var level := i % COINS_PER_STACK
		var jitter := Vector3(sin(i * 12.9) * 0.002, 0, cos(i * 7.1) * 0.002)
		var base := COIN_ORIGIN + Vector3((stack % 3) * 0.036 - (stack / 3) * 0.018, 0, (stack / 3) * 0.034) + jitter
		var final_pos := base + Vector3(0, 0.0016 + level * 0.0033, 0)
		coin.rotation.y = i * 1.7
		add_child(coin)
		_coins.append(coin)
		if animate and start > 0:
			coin.position = final_pos + Vector3(0, 0.25, 0)
			coin.rotation.x = 1.2
			var tw := create_tween()
			tw.tween_interval((i - start) * 0.08)
			tw.tween_property(coin, "position", final_pos, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(coin, "rotation:x", 0.0, 0.3)
		else:
			coin.position = final_pos


# --- Bausteine ------------------------------------------------------------------

func _candle(pos: Vector3, height: float) -> Dictionary:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.0115
	bm.bottom_radius = 0.0125
	bm.height = height
	bm.radial_segments = 16
	body.mesh = bm
	body.material_override = _wax
	body.position.y = height * 0.5
	root.add_child(body)
	# Wachstropfen am Rand
	for k in 3:
		var drip := MeshInstance3D.new()
		var dm := CapsuleMesh.new()
		dm.radius = 0.0028
		dm.height = 0.012 + k * 0.006
		drip.mesh = dm
		drip.material_override = _wax
		var a := k * 2.2 + pos.x * 40.0
		drip.position = Vector3(cos(a) * 0.0115, height - dm.height * 0.4, sin(a) * 0.0115)
		root.add_child(drip)
	var wick := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.0009
	wm.bottom_radius = 0.0009
	wm.height = 0.008
	wick.mesh = wm
	wick.material_override = _mat(Color(0.05, 0.04, 0.03), 0.9)
	wick.position.y = height + 0.003
	root.add_child(wick)
	var flame := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.0055
	fm.height = 0.024
	fm.radial_segments = 12
	fm.rings = 8
	flame.mesh = fm
	flame.material_override = _flame
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pivot := Node3D.new()
	pivot.position.y = height + 0.012
	root.add_child(pivot)
	pivot.add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.66, 0.32)
	light.light_energy = 0.3
	light.omni_range = 0.55
	light.omni_attenuation = 1.6
	light.position.y = height + 0.03
	root.add_child(light)
	return {"root": root, "flame": flame, "light": light, "life": 1.0}


func _smoke(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = to_local(at)
	p.amount = 18
	p.lifetime = 2.2
	p.one_shot = true
	p.explosiveness = 0.2
	p.direction = Vector3.UP
	p.spread = 12.0
	p.initial_velocity_min = 0.04
	p.initial_velocity_max = 0.08
	p.gravity = Vector3(0.01, 0.02, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var m := SphereMesh.new()
	m.radius = 0.006
	m.height = 0.012
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.7, 0.68, 0.75, 0.25)
	mat.vertex_color_use_as_albedo = true
	m.material = mat
	p.mesh = m
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.5))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = grad
	add_child(p)
	p.emitting = true
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)


func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m
