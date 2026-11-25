class_name MiniRoulette
extends Node3D
## Kleines Tisch-Roulette (Deko im Casino, steht dort, wo im Hinterzimmer der
## Aschenbecher steht). Holzschale, drehender Kessel mit Zahlenfächern, goldenes
## Drehkreuz und eine weiße Kugel.
##
## Kleines Easter Egg (`interactive`): Die ersten Klicks stupsen den Kessel nur leicht an,
## beim 5. Klick kurz hintereinander wird richtig gedreht. Die Kugel läuft gegenläufig, wird
## langsamer, hüpft eine Weile über die Stege und bleibt in einem Fach liegen; das Fach
## und sein Zahlenfeld außen blinken kurz und dezent in ihrer Farbe (rot, silbrig für Schwarz,
## grün). Jedes Fach ist
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
## So lange hüpft die Kugel über die Stege, bevor sie liegen bleibt (passt zu roulette_land.wav)
const BOUNCE_TIME := 1.9
const HOPS := 6

const TEX := preload("res://assets/rooms/casino/roulette.png")
const SND := preload("res://assets/rooms/casino/roulette.wav")
const ORDER := [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10,
	5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]
const R := 0.08 # Außenradius der Schale
## Abstand der Fächermitte von der Achse (zwischen den Stegen)
const POCKET_R := R * 0.53
const REDS := [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]

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
var _bounce := -1.0 # Sekunden seit Beginn des Hüpfens, sonst < 0
var _bounce_from := 0.0
var _bounce_v0 := 0.0 # Geschwindigkeit relativ zum Kessel beim ersten Aufprall
var _bounce_len := 0.0 # Dauer des Hüpfens (Sekunden)
var _bounce_r0 := 0.0
var _flash: MeshInstance3D
var _flash_outer: MeshInstance3D # Zahlenfeld außen, blinkt mit
var _flash_mat: StandardMaterial3D
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
	# Stege zwischen den Fächern (leicht erhöht → die Fächer wirken eingekerbt)
	var fret_mat := gold.duplicate() as StandardMaterial3D
	fret_mat.roughness = 0.35
	var step := TAU / ORDER.size()
	for p in ORDER.size():
		var a := _pocket_angle(p) + step * 0.5
		var fret := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(R * 0.26, 0.0032, 0.0011)
		fret.mesh = fm
		fret.material_override = fret_mat
		fret.position = Vector3(cos(a) * R * 0.54, 0.0016, -sin(a) * R * 0.54)
		fret.rotation.y = a
		_wheel.add_child(fret)
	for rr in [R * 0.41, R * 0.67]: # Ringe innen und außen
		var ring := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = rr - 0.0008
		rm.outer_radius = rr + 0.0008
		rm.rings = 64
		rm.ring_segments = 4
		ring.mesh = rm
		ring.material_override = fret_mat
		ring.position.y = 0.0012
		ring.scale = Vector3(1, 2.0, 1)
		_wheel.add_child(ring)
	# Leuchtfleck für das Fach, in dem die Kugel landet (unsichtbar bis dahin)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1, 1, 1, 0)
	_flash = MeshInstance3D.new()
	var flm := PlaneMesh.new()
	flm.size = Vector2(R * 0.28, step * R * 0.53 * 0.9)
	_flash.mesh = flm
	_flash.material_override = _flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	_wheel.add_child(_flash)
	# äußeres Zahlenfeld (Ring mit den Zahlen, im Bild zwischen 0,65 R und 0,82 R)
	_flash_outer = MeshInstance3D.new()
	var fom := PlaneMesh.new()
	fom.size = Vector2(R * 0.16, step * R * 0.737 * 0.92)
	_flash_outer.mesh = fom
	_flash_outer.material_override = _flash_mat
	_flash_outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_outer.visible = false
	_wheel.add_child(_flash_outer)
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
		_ball_r = lerpf(R * 0.86, R * 0.66, slow * slow)
		_set_ball(_ball_angle, _ball_r, 0.0)
		# Hüpfen beginnt, sobald die Kugel bei gleichmäßigem Abbremsen genau im Zielfach
		# zur Ruhe käme – so geht die Bewegung ohne Ruck ins Hüpfen über.
		var v0 := _wheel_speed - _ball_speed # Geschwindigkeit relativ zum Kessel (> 0)
		var reach := v0 * BOUNCE_TIME * 0.5
		var ahead := _ahead_of_target()
		if reach <= TAU and ahead <= reach and ahead >= reach - v0 * delta * 3.0:
			_start_bounce(v0)
	elif _bounce >= 0.0:
		_bounce += delta
		var u := minf(_bounce / _bounce_len, 1.0)
		var tt := u * _bounce_len
		# gleichmäßig abbremsen, bis die Kugel im Zielfach steht (relativ zum Kessel)
		var rel := _bounce_from - (_bounce_v0 * tt - 0.5 * _bounce_v0 / _bounce_len * tt * tt)
		# Sprünge werden kürzer und flacher (Aufpralle bei u = √(k/HOPS))
		var hop := absf(sin(PI * HOPS * u * u)) * 0.0075 * pow(1.0 - u, 0.8)
		var r := lerpf(_bounce_r0, POCKET_R, smoothstep(0.0, 0.5, u))
		_set_ball(_wheel.rotation.y + rel, r, hop)
		if u >= 1.0:
			_bounce = -1.0
			_spinning = false
			_pocket = _target
			landed.emit(ORDER[_pocket])
			_flash_pocket(_pocket)
			if ORDER[_pocket] == 0:
				Profile.unlock_achievement(&"all_green")
	if _pocket >= 0:
		_place_ball()


## Winkel eines Fachs relativ zum Kessel. Im Bild liegt Fach 0 oben (-z), die Fächer
## laufen von oben gesehen im Uhrzeigersinn – der Winkel der Kugel dagegen.
static func _pocket_angle(p: int) -> float:
	return PI * 0.5 - TAU * p / ORDER.size()


func _place_ball() -> void:
	_set_ball(_wheel.rotation.y + _pocket_angle(_pocket), POCKET_R, 0.0)


func _set_ball(a: float, r: float, lift: float) -> void:
	var y := (0.039 if r > R * 0.62 else 0.0372) + lift
	_ball.position = Vector3(cos(a) * r, y, -sin(a) * r)


## Wie weit das Zielfach noch vor der Kugel liegt (in ihrer Laufrichtung, relativ zum Kessel).
func _ahead_of_target() -> float:
	return fposmod((_ball_angle - _wheel.rotation.y) - _pocket_angle(_target), TAU)


## Kugel trifft auf die Stege: ab hier hüpft sie bis ins Zielfach.
func _start_bounce(v0: float) -> void:
	_bounce_from = _ball_angle - _wheel.rotation.y
	_bounce_v0 = v0
	_bounce_len = maxf(2.0 * _ahead_of_target() / v0, 0.3)
	_bounce_r0 = _ball_r
	_bounce = 0.0
	_play(SND_LAND, VOLUME_DB)


## Ganz dezentes Aufleuchten im Fach: rot, grün oder silbrig (für Schwarz).
func _flash_pocket(p: int) -> void:
	var num: int = ORDER[p]
	var col := Color(0.3, 1.0, 0.45) if num == 0 else (Color(1.0, 0.35, 0.25) if num in REDS else Color(0.85, 0.9, 1.0))
	var a := _pocket_angle(p)
	_flash.position = Vector3(cos(a) * POCKET_R, 0.0006, -sin(a) * POCKET_R)
	_flash.rotation.y = a
	_flash_outer.position = Vector3(cos(a) * R * 0.737, 0.0006, -sin(a) * R * 0.737)
	_flash_outer.rotation.y = a
	_flash_mat.albedo_color = Color(col, 0.0)
	_flash.visible = true
	_flash_outer.visible = true
	# zweimal kurz aufblinken, dann langsam ausklingen (Fach und Zahlenfeld gemeinsam)
	var tw := create_tween()
	tw.tween_property(_flash_mat, "albedo_color:a", 0.9, 0.12)
	tw.tween_property(_flash_mat, "albedo_color:a", 0.15, 0.16)
	tw.tween_property(_flash_mat, "albedo_color:a", 0.9, 0.12)
	tw.tween_property(_flash_mat, "albedo_color:a", 0.0, 1.3).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		_flash.visible = false
		_flash_outer.visible = false)


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
