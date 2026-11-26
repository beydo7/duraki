class_name CircusRoom
extends Node3D
## Raum „Zirkuswagen“ – ganz in Code gebaut (kein Blender-Modell).
##
## Enger Wohnwagen eines Wanderzirkus: bunt gestrichene Bretter, gewölbte Decke mit
## Lichterkette, links Kostüme an Haken und ein Zirkusplakat, rechts ein Schminkspiegel mit
## Glühbirnenrahmen. Hinten ein Vorhangspalt: draußen das rot-weiße Zelt mit wandernden
## Scheinwerfern, von dort klingt gedämpfte Zirkusmusik, ab und zu Applaus und Lachen.
## Leben = Luftballons an der Tischkante (`lives_panel`), sie platzen mit Konfetti.
##
## Easter Egg: Die Spieluhr auf dem Tisch anklicken = einmal aufziehen, die Tänzerin dreht
## sich zur Melodie. Fünfmal aufgezogen → der Deckel springt auf, ein Springteufel schnellt
## heraus und es gibt den geheimen Erfolg „Überraschung!“.

const DIR := "res://assets/rooms/circus/"
const SND_MUSIC := preload("res://assets/rooms/circus/music.wav")
const SND_APPLAUSE := preload("res://assets/rooms/circus/applause.wav")
const SND_BOX := preload("res://assets/rooms/circus/musicbox.wav")
const SND_WIND := preload("res://assets/rooms/circus/wind.wav")
const SND_BOING := preload("res://assets/rooms/circus/boing.wav")

const ROOM_W := 4.4
const BACK_Z := -2.1
const WALL_H := 2.1 # Wandhöhe, darüber die gewölbte Decke
const VAULT := 0.55 # Höhe der Wölbung
const TOP := Vector2(1.84, 1.3)
const GAP_X := -1.2 # Vorhangspalt (Mitte)
const GAP_W := 0.7
const BOX_POS := Vector3(0.95, 0.0, -0.42) # Spieluhr auf dem Tisch (y kommt dazu)
const WINDS_FOR_JACK := 5
const WIND_WINDOW := 8.0

## Luftballons an der Tischkante (TableProps schaltet sie)
var lives_panel: BalloonLives
## Spieluhr anklickbar (nur im Duell)
var interactive := false:
	set(v):
		interactive = v
		if _box_area != null:
			_box_area.input_ray_pickable = v

var _t := 0.0
var _spots: Array[SpotLight3D] = []
var _bulbs: Array[StandardMaterial3D] = []
var _music: AudioStreamPlayer
var _next_applause := 14.0
var _box: Node3D
var _lid: Node3D
var _dancer: Node3D
var _jack: Node3D
var _box_area: Area3D
var _spin := 0.0 # wie lange die Tänzerin sich noch dreht
var _winds := 0
var _last_wind := -10.0
var _jack_out := false


func _ready() -> void:
	_build_shell()
	_build_back()
	_build_costumes()
	_build_mirror()
	_build_table()
	_build_music_box()
	_build_string_lights()
	lives_panel = BalloonLives.new()
	lives_panel.position = Vector3(-0.66, TableWorld.TABLE_Y, -0.58) # hinten links an der Tischkante
	add_child(lives_panel)
	_music = RoomKit.loop(self, SND_MUSIC, -27.0)


func _process(delta: float) -> void:
	_t += delta
	# Scheinwerfer im Zelt wandern
	for i in _spots.size():
		var a := _t * (0.5 + 0.2 * i) + i * 2.0
		_spots[i].rotation = Vector3(-1.2 + 0.15 * sin(a * 0.7), sin(a) * 0.5, 0)
	# Lichterkette blinkt sanft im Wechsel
	for i in _bulbs.size():
		_bulbs[i].emission_energy_multiplier = 1.4 + 0.9 * sin(_t * 2.2 + i * 1.7)
	# Tänzerin dreht sich, solange die Spieluhr läuft
	if _spin > 0.0:
		_spin -= delta
		_dancer.rotation.y += delta * 3.2
		_dancer.position.y = 0.075 + 0.004 * sin(_t * 9.0)
	_next_applause -= delta
	if _next_applause <= 0.0:
		_next_applause = randf_range(22.0, 45.0)
		RoomKit.play(self, SND_APPLAUSE, -24.0)


func apply_environment(env: Environment) -> void:
	env.background_color = Color("0a0505")
	env.ambient_light_color = Color("6b4a3a")
	env.ambient_light_energy = 0.5
	env.fog_light_color = Color("1a0c08")
	env.adjustment_saturation = 1.1


func add_lights(parent: Node3D) -> void:
	var warm := OmniLight3D.new() # Lichterkette unter der Decke
	warm.position = Vector3(0, WALL_H + 0.1, -0.6)
	warm.light_color = Color("ffc890")
	warm.light_energy = 1.1
	warm.omni_range = 3.5
	parent.add_child(warm)
	var mirror := OmniLight3D.new() # Spiegel-Glühbirnen rechts
	mirror.position = Vector3(ROOM_W * 0.5 - 0.4, 1.45, -1.2)
	mirror.light_color = Color("ffe0b0")
	mirror.light_energy = 1.0
	mirror.omni_range = 1.8
	parent.add_child(mirror)
	var rim := OmniLight3D.new() # Gegenlicht aus dem Vorhangspalt
	rim.position = Vector3(GAP_X + 0.3, 1.6, BACK_Z + 0.4)
	rim.light_color = Color("ff9a7a")
	rim.light_energy = 1.3
	rim.omni_range = 2.3
	parent.add_child(rim)


## Spieluhr einmal aufziehen (Klick). Fünfmal → Springteufel.
func wind_music_box() -> void:
	if _jack_out:
		return
	var now := Time.get_ticks_msec() / 1000.0
	_winds = _winds + 1 if now - _last_wind < WIND_WINDOW else 1
	_last_wind = now
	RoomKit.play(self, SND_WIND, -12.0)
	var key: Node3D = _box.get_node(^"Key")
	var tw := create_tween()
	tw.tween_property(key, "rotation:x", key.rotation.x + TAU, 0.6)
	if _winds >= WINDS_FOR_JACK:
		_winds = 0
		tw.tween_callback(pop_jack)
		return
	if _spin <= 0.0:
		RoomKit.play(self, SND_BOX, -16.0)
	_spin = 4.6


## Easter Egg: Deckel springt auf, Springteufel schnellt heraus.
func pop_jack() -> void:
	_jack_out = true
	_spin = 0.0
	RoomKit.play(self, SND_BOING, -8.0)
	_dancer.visible = false
	_jack.visible = true
	_jack.scale = Vector3(1, 0.05, 1)
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", -1.9, 0.12)
	tw.parallel().tween_property(_jack, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.0)
	tw.tween_property(_jack, "scale", Vector3(1, 0.05, 1), 0.3)
	tw.tween_callback(func() -> void:
		_jack.visible = false
		_dancer.visible = true)
	tw.tween_property(_lid, "rotation:x", 0.0, 0.25)
	tw.tween_callback(func() -> void: _jack_out = false)
	if interactive:
		Profile.unlock_achievement(&"surprise")


# --- Aufbau --------------------------------------------------------------------------

func _build_shell() -> void:
	var boards := RoomKit.tex(DIR + "boards.png", 0.75, 0.55)
	boards.albedo_color = Color(0.75, 0.7, 0.68)
	var floor_mat := RoomKit.tex(DIR + "floor.png", 0.8, 0.8)
	RoomKit.plane(self, Vector2(ROOM_W, 6.0), Vector3(0, 0, 0.6), floor_mat)
	for s: float in [-1.0, 1.0]:
		RoomKit.box(self, Vector3(0.1, WALL_H, 6.0), Vector3(s * (ROOM_W * 0.5 + 0.05), WALL_H * 0.5, 0.6), boards)
	# gewölbte Decke aus schmalen Brettern (Tonnengewölbe)
	var ceil := RoomKit.mat(Color(0.42, 0.26, 0.16), 0.8)
	var ceil2 := RoomKit.mat(Color(0.75, 0.66, 0.5), 0.8)
	var n := 14
	for i in n:
		var a0 := PI * i / n
		var a1 := PI * (i + 1) / n
		var p0 := Vector2(-cos(a0) * ROOM_W * 0.5, WALL_H + sin(a0) * VAULT)
		var p1 := Vector2(-cos(a1) * ROOM_W * 0.5, WALL_H + sin(a1) * VAULT)
		var mid := (p0 + p1) * 0.5
		var b := RoomKit.box(self, Vector3(p0.distance_to(p1) + 0.01, 0.04, 6.0), Vector3(mid.x, mid.y, 0.6), ceil if i % 2 else ceil2)
		b.rotation.z = (p1 - p0).angle()
	# Leisten oben an den Wänden
	var trim := RoomKit.mat(Color(0.75, 0.55, 0.15), 0.45, 0.6)
	for s: float in [-1.0, 1.0]:
		RoomKit.box(self, Vector3(0.06, 0.06, 6.0), Vector3(s * (ROOM_W * 0.5 - 0.02), WALL_H - 0.03, 0.6), trim)


func _build_back() -> void:
	var boards := RoomKit.tex(DIR + "boards.png", 0.75, 0.55)
	boards.albedo_color = Color(0.75, 0.7, 0.68)
	var h := WALL_H + VAULT
	var g0 := GAP_X - GAP_W * 0.5
	var g1 := GAP_X + GAP_W * 0.5
	# Rückwand links und rechts vom Spalt, oben ein Sturz
	RoomKit.box(self, Vector3(g0 + ROOM_W * 0.5, h, 0.08), Vector3((g0 - ROOM_W * 0.5) * 0.5, h * 0.5, BACK_Z - 0.04), boards)
	RoomKit.box(self, Vector3(ROOM_W * 0.5 - g1, h, 0.08), Vector3((g1 + ROOM_W * 0.5) * 0.5, h * 0.5, BACK_Z - 0.04), boards)
	RoomKit.box(self, Vector3(GAP_W, h - 1.95, 0.08), Vector3(GAP_X, (h + 1.95) * 0.5, BACK_Z - 0.04), boards)
	# Vorhang: zwei rote Samtbahnen aus Falten, in der Mitte offen
	var velvet := RoomKit.mat(Color(0.55, 0.05, 0.08), 0.85)
	var velvet2 := RoomKit.mat(Color(0.42, 0.03, 0.06), 0.85)
	for s: float in [-1.0, 1.0]:
		for k in 5:
			var x := GAP_X + s * (0.14 + k * 0.065) # zur Seite gerafft, Mitte offen
			var f := RoomKit.cyl(self, 0.035, 0.045, 1.95, Vector3(x, 0.975, BACK_Z + 0.06 + (k % 2) * 0.02), velvet if k % 2 else velvet2, 10)
	var gold := RoomKit.mat(Color(0.85, 0.65, 0.2), 0.35, 0.9)
	var rod := RoomKit.cyl(self, 0.015, 0.015, GAP_W + 0.3, Vector3(GAP_X, 1.97, BACK_Z + 0.08), gold)
	rod.rotation.z = PI * 0.5
	# Draußen: Zeltwand, Manege-Rand, Scheinwerferkegel
	var tent := RoomKit.tex(DIR + "tent.png", 0.9)
	tent.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tent.albedo_color = Color(0.5, 0.42, 0.4)
	tent.uv1_scale = Vector3(3, 1, 1)
	RoomKit.quad(self, Vector2(5.0, 3.5), Vector3(GAP_X, 1.6, BACK_Z - 2.4), tent)
	var ring := RoomKit.cyl(self, 1.6, 1.6, 0.25, Vector3(GAP_X, 0.12, BACK_Z - 1.6), RoomKit.mat(Color(0.7, 0.1, 0.1), 0.6), 48)
	ring.scale = Vector3(1, 1, 0.5)
	var sand := RoomKit.mat(Color(0.75, 0.6, 0.4), 0.95)
	RoomKit.plane(self, Vector2(6, 4), Vector3(GAP_X, 0.01, BACK_Z - 1.8), sand)
	for i in 2:
		var spot := SpotLight3D.new()
		spot.position = Vector3(GAP_X + (i * 2 - 1) * 0.8, 3.0, BACK_Z - 1.2)
		spot.light_color = [Color(1.0, 0.85, 0.6), Color(0.8, 0.85, 1.0)][i]
		spot.light_energy = 6.0
		spot.spot_range = 5.0
		spot.spot_angle = 18.0
		add_child(spot)
		_spots.append(spot)


func _build_costumes() -> void:
	var x := -ROOM_W * 0.5 + 0.12
	var hook := RoomKit.mat(Color(0.6, 0.5, 0.3), 0.4, 0.8)
	RoomKit.box(self, Vector3(0.04, 0.06, 1.6), Vector3(x - 0.04, 1.75, -0.9), RoomKit.mat(Color(0.35, 0.22, 0.12), 0.7))
	var cols := [Color(0.9, 0.75, 0.2), Color(0.2, 0.55, 0.45), Color(0.85, 0.3, 0.55), Color(0.9, 0.9, 0.85)]
	for k in 4:
		var z := -1.5 + k * 0.38
		RoomKit.cyl(self, 0.008, 0.008, 0.08, Vector3(x, 1.75, z), hook).rotation.z = PI * 0.5
		var c := RoomKit.mat(cols[k], 0.7)
		# Kostüm: Kegel (Kleid / Mantel) mit Kragen
		RoomKit.cyl(self, 0.06, 0.2, 0.75, Vector3(x + 0.08, 1.33, z), c, 16).scale = Vector3(0.55, 1, 1)
		RoomKit.torus(self, 0.07, 0.025, Vector3(x + 0.08, 1.7, z), RoomKit.mat(Color(0.95, 0.95, 0.92), 0.8))
		if k == 2: # Pailletten
			for j in 12:
				RoomKit.sphere(self, 0.008, Vector3(x + 0.19, 1.05 + (j % 4) * 0.15, z - 0.09 + (j / 4) * 0.09), RoomKit.glow(Color(1, 0.85, 0.4), 1.2))
	# Clownshut und Ringmeister-Zylinder auf einem Bord darüber
	RoomKit.box(self, Vector3(0.25, 0.03, 1.0), Vector3(x + 0.07, 1.95, -0.3), RoomKit.mat(Color(0.35, 0.22, 0.12), 0.7))
	RoomKit.cyl(self, 0.07, 0.07, 0.16, Vector3(x + 0.08, 2.05, -0.55), RoomKit.mat(Color(0.08, 0.08, 0.1), 0.5))
	RoomKit.cyl(self, 0.12, 0.12, 0.01, Vector3(x + 0.08, 1.97, -0.55), RoomKit.mat(Color(0.08, 0.08, 0.1), 0.5))
	RoomKit.cyl(self, 0.0, 0.07, 0.18, Vector3(x + 0.08, 2.06, -0.15), RoomKit.mat(Color(0.2, 0.5, 0.9), 0.6))
	RoomKit.sphere(self, 0.02, Vector3(x + 0.08, 2.16, -0.15), RoomKit.mat(Color(0.95, 0.3, 0.2), 0.6))
	# Plakat an der Rückwand links
	var poster := RoomKit.tex(DIR + "poster.png", 0.9)
	RoomKit.quad(self, Vector2(0.36, 0.5), Vector3(-1.95, 1.3, BACK_Z + 0.005), poster)


func _build_mirror() -> void:
	var x := ROOM_W * 0.5 - 0.05
	var root := Node3D.new()
	root.position = Vector3(x, 1.35, -1.2)
	root.rotation.y = -PI * 0.5
	add_child(root)
	var frame := RoomKit.mat(Color(0.2, 0.12, 0.08), 0.5)
	RoomKit.box(root, Vector3(0.75, 0.6, 0.03), Vector3.ZERO, frame)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.6, 0.62)
	glass.metallic = 1.0
	glass.roughness = 0.08
	RoomKit.box(root, Vector3(0.6, 0.45, 0.01), Vector3(0, 0, 0.018), glass)
	var bulb := RoomKit.glow(Color(1.0, 0.9, 0.7), 3.0)
	for k in 5:
		RoomKit.sphere(root, 0.022, Vector3(-0.3 + k * 0.15, 0.27, 0.03), bulb)
	for k in 4:
		for s: float in [-1.0, 1.0]:
			RoomKit.sphere(root, 0.022, Vector3(s * 0.345, 0.15 - k * 0.12, 0.03), bulb)
	# Schminktisch darunter mit Puderdose und Pinsel
	var wood := RoomKit.mat(Color(0.4, 0.24, 0.14), 0.7)
	RoomKit.box(self, Vector3(0.35, 0.04, 0.9), Vector3(x - 0.17, 0.85, -1.2), wood)
	RoomKit.box(self, Vector3(0.3, 0.8, 0.04), Vector3(x - 0.17, 0.43, -1.62), wood)
	RoomKit.box(self, Vector3(0.3, 0.8, 0.04), Vector3(x - 0.17, 0.43, -0.78), wood)
	RoomKit.cyl(self, 0.05, 0.05, 0.03, Vector3(x - 0.15, 0.885, -1.0), RoomKit.mat(Color(0.95, 0.75, 0.75), 0.4))
	RoomKit.cyl(self, 0.012, 0.012, 0.12, Vector3(x - 0.2, 0.93, -1.35), RoomKit.mat(Color(0.9, 0.1, 0.15), 0.4))


func _build_table() -> void:
	var y := TableWorld.TABLE_Y
	var wood := RoomKit.mat(Color(0.36, 0.2, 0.12), 0.6)
	var cloth := RoomKit.mat(Color(0.07, 0.17, 0.12), 0.95) # grünes Tuch, wie ein Spieltisch
	RoomKit.box(self, Vector3(TOP.x, 0.04, TOP.y), Vector3(0, y - 0.02, 0), wood)
	RoomKit.box(self, Vector3(TOP.x - 0.12, 0.003, TOP.y - 0.12), Vector3(0, y - 0.001, 0), cloth)
	var stripe := RoomKit.mat(Color(0.85, 0.65, 0.2), 0.4, 0.7)
	for s: float in [-1.0, 1.0]: # Goldkante
		RoomKit.box(self, Vector3(TOP.x + 0.02, 0.012, 0.02), Vector3(0, y - 0.03, s * (TOP.y * 0.5 + 0.005)), stripe)
	# Tisch steht auf einer Trommel (Zirkuspodest)
	var drum := RoomKit.mat(Color(0.75, 0.1, 0.1), 0.5)
	RoomKit.cyl(self, 0.45, 0.45, y - 0.04, Vector3(0, (y - 0.04) * 0.5, 0), drum, 40)
	for k in 2:
		RoomKit.torus(self, 0.455, 0.015, Vector3(0, 0.06 + k * (y - 0.16), 0), stripe)


func _build_music_box() -> void:
	var y := TableWorld.TABLE_Y
	_box = Node3D.new()
	_box.position = BOX_POS + Vector3(0, y, 0)
	_box.rotation.y = 0.5
	add_child(_box)
	var wood := RoomKit.mat(Color(0.5, 0.25, 0.14), 0.45)
	var gold := RoomKit.mat(Color(0.9, 0.7, 0.3), 0.3, 0.9)
	RoomKit.box(_box, Vector3(0.12, 0.06, 0.09), Vector3(0, 0.03, 0), wood)
	RoomKit.box(_box, Vector3(0.124, 0.008, 0.094), Vector3(0, 0.058, 0), gold)
	# Deckel hängt hinten am Scharnier
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.062, -0.045)
	_box.add_child(_lid)
	RoomKit.box(_lid, Vector3(0.12, 0.012, 0.09), Vector3(0, 0.006, 0.045), wood)
	_lid.rotation.x = 0.0
	# Tänzerin oben auf dem Deckel (dreht sich beim Spielen)
	_dancer = Node3D.new()
	_dancer.position = Vector3(0, 0.075, 0)
	_box.add_child(_dancer)
	RoomKit.cyl(_dancer, 0.0, 0.022, 0.028, Vector3(0, 0.014, 0), RoomKit.mat(Color(1.0, 0.7, 0.8), 0.6), 12) # Röckchen
	RoomKit.cyl(_dancer, 0.004, 0.006, 0.02, Vector3(0, 0.035, 0), RoomKit.mat(Color(1.0, 0.7, 0.8), 0.6), 8)
	RoomKit.sphere(_dancer, 0.006, Vector3(0, 0.05, 0), RoomKit.mat(Color(0.95, 0.85, 0.75), 0.5))
	var arm := RoomKit.cyl(_dancer, 0.0015, 0.0015, 0.03, Vector3(0, 0.044, 0), RoomKit.mat(Color(0.95, 0.85, 0.75), 0.5), 4)
	arm.rotation.z = PI * 0.5
	# Springteufel (versteckt)
	_jack = Node3D.new()
	_jack.position = Vector3(0, 0.06, 0)
	_jack.visible = false
	_box.add_child(_jack)
	var spring := RoomKit.mat(Color(0.7, 0.7, 0.72), 0.3, 0.9)
	for k in 6:
		RoomKit.torus(_jack, 0.016, 0.003, Vector3(0, 0.008 + k * 0.012, 0), spring)
	RoomKit.sphere(_jack, 0.03, Vector3(0, 0.1, 0), RoomKit.mat(Color(0.98, 0.92, 0.85), 0.5)) # Gesicht
	RoomKit.sphere(_jack, 0.009, Vector3(0, 0.098, 0.03), RoomKit.mat(Color(0.95, 0.1, 0.1), 0.4)) # Nase
	for s: float in [-1.0, 1.0]:
		RoomKit.sphere(_jack, 0.004, Vector3(s * 0.011, 0.11, 0.027), RoomKit.mat(Color(0.05, 0.05, 0.05), 0.4))
		var horn := RoomKit.cyl(_jack, 0.0, 0.014, 0.04, Vector3(s * 0.022, 0.135, 0), RoomKit.mat([Color(0.95, 0.75, 0.15), Color(0.2, 0.45, 0.9)][int(s > 0)], 0.5), 8)
		horn.rotation.z = -s * 0.6
		RoomKit.sphere(_jack, 0.006, Vector3(s * 0.034, 0.152, 0), RoomKit.mat(Color(0.95, 0.2, 0.2), 0.5))
	var collar := RoomKit.torus(_jack, 0.03, 0.008, Vector3(0, 0.07, 0), RoomKit.mat(Color(0.95, 0.95, 0.9), 0.7))
	collar.scale = Vector3(1, 0.6, 1)
	# Aufziehschlüssel an der Seite
	var key := Node3D.new()
	key.name = "Key"
	key.position = Vector3(0.068, 0.03, 0)
	_box.add_child(key)
	RoomKit.cyl(key, 0.004, 0.004, 0.02, Vector3(0.01, 0, 0), gold, 8).rotation.z = PI * 0.5
	RoomKit.box(key, Vector3(0.004, 0.03, 0.012), Vector3(0.022, 0, 0), gold)
	_box_area = RoomKit.click_area(_box, Vector3(0.18, 0.14, 0.14), Vector3(0, 0.05, 0), wind_music_box)
	_box_area.input_ray_pickable = interactive


func _build_string_lights() -> void:
	var wire := RoomKit.mat(Color(0.1, 0.1, 0.1), 0.6)
	var cols := [Color(1, 0.3, 0.2), Color(1, 0.85, 0.3), Color(0.3, 0.6, 1), Color(0.4, 1, 0.5)]
	for z: float in [-1.4, -0.2]:
		var n := 11
		for i in n:
			var u := float(i) / (n - 1)
			var x := lerpf(-ROOM_W * 0.5 + 0.1, ROOM_W * 0.5 - 0.1, u)
			var sag := 0.25 * sin(PI * u)
			var y := WALL_H + 0.05 - sag
			var m := RoomKit.glow(cols[i % cols.size()], 1.6)
			_bulbs.append(m)
			RoomKit.sphere(self, 0.022, Vector3(x, y, z), m, Vector3(1, 1.3, 1))
			if i < n - 1:
				var u2 := float(i + 1) / (n - 1)
				var p2 := Vector3(lerpf(-ROOM_W * 0.5 + 0.1, ROOM_W * 0.5 - 0.1, u2), WALL_H + 0.05 - 0.25 * sin(PI * u2), z)
				var p1 := Vector3(x, y, z)
				var w := RoomKit.box(self, Vector3(p1.distance_to(p2), 0.004, 0.004), (p1 + p2) * 0.5 + Vector3(0, 0.025, 0), wire)
				w.rotation.z = atan2(p2.y - p1.y, p2.x - p1.x)
