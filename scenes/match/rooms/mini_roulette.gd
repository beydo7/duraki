class_name MiniRoulette
extends Node3D
## Kleines Tisch-Roulette (Deko im Casino, steht dort, wo im Hinterzimmer der
## Aschenbecher steht). Holzschale, drehender Kessel mit Zahlenfächern, goldenes
## Drehkreuz und eine weiße Kugel.
##
## Kleines Easter Egg (`interactive`): Die ersten Klicks stupsen den Kessel nur leicht an,
## beim 5. Klick kurz hintereinander wird richtig gedreht. Die Kugel läuft gegenläufig, wird
## langsamer, springt über ein paar Stege und bleibt in einem Fach liegen. Jedes Fach ist
## gleich wahrscheinlich wie beim echten (europäischen) Roulette: 37 Fächer, die grüne 0
## kommt also mit 1/37 (ca. 2,7 %). Grün → Erfolg „Alles auf Grün“.

signal landed(number: int)

## So oft kurz hintereinander klicken, bis gedreht wird
const CLICKS_TO_SPIN := 5
## Längere Pause zwischen zwei Klicks → Zählung beginnt von vorn
const CLICK_WINDOW := 1.2
const SND_LAND := preload("res://assets/rooms/casino/roulette_land.wav")
const SND_TICK := preload("res://assets/rooms/casino/roulette_tick.wav")
## Angenehm leise (nicht nervig, auch wenn man öfter dreht)
const VOLUME_DB := -14.0

const TEX := preload("res://assets/rooms/casino/roulette.png")
const SND := preload("res://assets/rooms/casino/roulette.wav")
const ORDER := [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10,
	5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]
const R := 0.08 # Außenradius der Schale

var interactive := false

var _wheel: Node3D
var _ball: MeshInstance3D
var _wheel_speed := 0.0
var _ball_angle := 0.0
var _ball_speed := 0.0
var _ball_r := R * 0.8
var _pocket := -1 # Fach, in dem die Kugel liegt (-1: rollt noch)
var _spinning := false
var _target := 0 # Fach, in dem die Kugel landen wird (vorher gleichverteilt gezogen)
var _bounce := -1.0 # 0..1 während die Kugel ins Zielfach hüpft, sonst < 0
var _bounce_from := 0.0
var _bounce_to := 0.0
var _clicks := 0
var _last_click := -10.0


func _ready() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_texture = preload("res://assets/models/table_wood_color.png")
	wood.albedo_color = Color(0.55, 0.32, 0.18)
	wood.roughness = 0.45
	wood.uv1_triplanar = true
	wood.uv1_scale = Vector3(8, 8, 8)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.92, 0.7, 0.3)
	gold.metallic = 1.0
	gold.roughness = 0.28
	# Schale (Fuß, Wand, Rand)
	_cyl(R * 0.75, R * 0.8, 0.012, Vector3(0, 0.006, 0), wood)
	_cyl(R, R * 0.86, 0.022, Vector3(0, 0.022, 0), wood)
	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = R - 0.004
	tm.outer_radius = R + 0.004
	tm.rings = 48
	rim.mesh = tm
	rim.material_override = gold
	rim.position.y = 0.033
	add_child(rim)
	# Kessel mit den Fächern (Bild von oben, rund ausgeschnitten)
	_wheel = Node3D.new()
	_wheel.position.y = 0.0335
	add_child(_wheel)
	var disc := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(R * 1.86, R * 1.86)
	disc.mesh = pm
	var dm := StandardMaterial3D.new()
	dm.albedo_texture = TEX
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	dm.alpha_scissor_threshold = 0.5
	dm.roughness = 0.85
	dm.metallic_specular = 0.15
	dm.albedo_color = Color(0.85, 0.85, 0.85) # unter der Tischlampe sonst überstrahlt
	dm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	disc.material_override = dm
	_wheel.add_child(disc)
	# Drehkreuz in der Mitte
	var post := _cyl(0.006, 0.009, 0.022, Vector3(0, 0.011, 0), gold)
	post.reparent(_wheel, false)
	for k in 2:
		var bar := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.0022
		bm.bottom_radius = 0.0022
		bm.height = 0.04
		bar.mesh = bm
		bar.material_override = gold
		bar.rotation = Vector3(PI * 0.5, k * PI * 0.5, 0)
		bar.position.y = 0.02
		_wheel.add_child(bar)
	# Kugel
	_ball = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0045
	sm.height = 0.009
	_ball.mesh = sm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.97, 0.96, 0.92)
	bmat.roughness = 0.15
	_ball.material_override = bmat
	add_child(_ball)
	# liegt am Anfang in einem zufälligen Fach
	_wheel.rotation.y = randf() * TAU
	_pocket = randi() % ORDER.size()
	_place_ball()
	# Klickfläche
	var area := Area3D.new()
	area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = R + 0.01
	cs.height = 0.06
	shape.shape = cs
	shape.position.y = 0.03
	area.add_child(shape)
	add_child(area)
	area.input_event.connect(_on_input)


func _process(delta: float) -> void:
	if _wheel_speed != 0.0:
		_wheel.rotation.y += _wheel_speed * delta
		_wheel_speed = move_toward(_wheel_speed, 0.0, delta * (0.9 if _spinning else 1.4))
	if _spinning and _bounce < 0.0:
		_ball_angle += _ball_speed * delta
		_ball_speed = move_toward(_ball_speed, -2.2, delta * 4.5) # rollt langsam weiter bis vors Zielfach
		# langsamer werdend nach innen fallen
		var slow := clampf(1.0 - absf(_ball_speed) / 14.0, 0.0, 1.0)
		_ball_r = lerpf(R * 0.86, R * 0.6, slow * slow)
		_set_ball(_ball_angle, _ball_r, 0.0)
		if absf(_ball_speed) < 2.4 and _ahead_of_target() < TAU / ORDER.size() * 2.5:
			_start_bounce()
	elif _bounce >= 0.0:
		# über ein paar Stege ins Zielfach hüpfen (Winkel relativ zum Kessel)
		_bounce = minf(_bounce + delta / 0.7, 1.0)
		var e := 1.0 - pow(1.0 - _bounce, 2.0)
		var rel := lerpf(_bounce_from, _bounce_to, e)
		var hop := absf(sin(_bounce * PI * 3.0)) * 0.006 * (1.0 - _bounce)
		_set_ball(_wheel.rotation.y + rel, R * 0.6, hop)
		if _bounce >= 1.0:
			_bounce = -1.0
			_spinning = false
			_pocket = _target
			landed.emit(ORDER[_pocket])
			if ORDER[_pocket] == 0:
				Profile.unlock_achievement(&"all_green")
	if _pocket >= 0:
		_place_ball()


## Winkel eines Fachs relativ zum Kessel. Im Bild liegt Fach 0 oben (-z), die Fächer
## laufen von oben gesehen im Uhrzeigersinn – der Winkel der Kugel dagegen.
static func _pocket_angle(p: int) -> float:
	return PI * 0.5 - TAU * p / ORDER.size()


func _place_ball() -> void:
	_set_ball(_wheel.rotation.y + _pocket_angle(_pocket), R * 0.6, 0.0)


func _set_ball(a: float, r: float, lift: float) -> void:
	var y := (0.039 if r > R * 0.65 else 0.0375) + lift
	_ball.position = Vector3(cos(a) * r, y, -sin(a) * r)


## Wie weit das Zielfach noch vor der Kugel liegt (in ihrer Laufrichtung, relativ zum Kessel).
func _ahead_of_target() -> float:
	return fposmod((_ball_angle - _wheel.rotation.y) - _pocket_angle(_target), TAU)


## Kugel ist langsam und kurz vor dem Zielfach: über die letzten Stege hineinhüpfen.
func _start_bounce() -> void:
	_bounce_from = _ball_angle - _wheel.rotation.y
	_bounce_to = _bounce_from - _ahead_of_target()
	_bounce = 0.0
	_play(SND_LAND, VOLUME_DB)


func _on_input(_cam: Node, event: InputEvent, _p: Vector3, _n: Vector3, _i: int) -> void:
	if not interactive or _spinning:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		click()


## Ein Klick aufs Roulette: die ersten stupsen nur an, der 5. dreht richtig.
func click() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_click > CLICK_WINDOW:
		_clicks = 0
	_last_click = now
	_clicks += 1
	if _clicks >= CLICKS_TO_SPIN:
		_clicks = 0
		spin()
	else:
		_wheel_speed = maxf(_wheel_speed, 0.5 + 0.25 * _clicks) # kleiner Schubs
		_play(SND_TICK, VOLUME_DB - 4.0)


## Kessel andrehen, Kugel gegenläufig einwerfen. Das Zielfach wird gleichverteilt
## gezogen (1/37 pro Fach), die Kugel rollt dann dorthin.
func spin(target := -1) -> void:
	_spinning = true
	_pocket = -1
	_bounce = -1.0
	_target = target if target >= 0 else randi() % ORDER.size()
	_wheel_speed = randf_range(3.5, 4.5)
	_ball_angle = randf() * TAU
	_ball_speed = -randf_range(15.0, 17.0)
	_ball_r = R * 0.86
	_play(SND, VOLUME_DB)


func _play(stream: AudioStream, db: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX"
	p.stream = stream
	p.volume_db = db
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _cyl(top: float, bottom: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 40
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	return mi
