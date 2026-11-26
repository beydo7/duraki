class_name CircusRoom
extends Node3D
## Raum „Zirkuswagen“. Formen aus Blender (assets/rooms/circus/circus.glb und music_box.glb, gebaut
## mit art/blender/circus.py), Materialien, Lichter und alles Bewegliche hier im Code.
## Boden, Bretterwände, Rückwand, Zelt und Manege draußen und das Plakat bleiben Code.
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
const MODEL := preload("res://assets/rooms/circus/circus.glb")
const BOX_MODEL := preload("res://assets/rooms/circus/music_box.glb")
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
const BOX_POS := Vector3(0.74, 0.0, -0.5) # hinten rechts in der Tischecke # Spieluhr auf dem Tisch (y kommt dazu)
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


var _skin_felt: Array[Material] = []
var _skin_rim: Array[Material] = []


func _ready() -> void:
	_build_shell()
	_build_back()
	_build_model()
	_build_music_box()
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
		RoomKit.play(self, SND_BOX, -27.0)
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
	# Deckenbretter und Leisten kommen aus Blender


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
	# Vorhang und Stange am Spalt sind im Modell
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


## Holz mit Maserung als Relief (Farbe wie bisher einfarbig).
static func _wood(c: Color, rough: float, tiles: float) -> StandardMaterial3D:
	var m := RoomKit.mat(c, rough)
	m.normal_enabled = true
	m.normal_texture = preload("res://assets/models/table_wood_normal.png")
	m.uv1_scale = Vector3.ONE * tiles # UVs des Modells sind in Metern
	return m


## Alles aus Blender: Decke, Leisten, Vorhang mit Stange, Kostüme und Hüte, Schminkspiegel mit
## Birnen, Schminktisch, Spieltisch auf der Trommel, Lichterkette.
## Die Materialien gehören zu den Namen, die sie in Blender haben (art/blender/circus.py).
func _build_model() -> void:
	var wood := _wood(Color(0.36, 0.2, 0.12), 0.6, 1.5)
	var cloth := RoomKit.mat(Color(0.07, 0.17, 0.12), 0.95) # grünes Tuch, wie ein Spieltisch
	_skin_felt = [cloth]
	_skin_rim = [wood]
	var stripe := RoomKit.mat(Color(0.85, 0.65, 0.2), 0.4, 0.7)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.6, 0.62)
	glass.metallic = 1.0
	glass.roughness = 0.08
	var costumes := [Color(0.9, 0.75, 0.2), Color(0.2, 0.55, 0.45), Color(0.85, 0.3, 0.55), Color(0.9, 0.9, 0.85)]
	var mats := {
		"Decke_Dunkel": RoomKit.mat(Color(0.42, 0.26, 0.16), 0.8), "Decke_Hell": RoomKit.mat(Color(0.75, 0.66, 0.5), 0.8),
		"Goldleiste": RoomKit.mat(Color(0.75, 0.55, 0.15), 0.45, 0.6), "Vorhang": RoomKit.mat(Color(0.55, 0.05, 0.08), 0.85),
		"Gold": RoomKit.mat(Color(0.85, 0.65, 0.2), 0.35, 0.9), "Holz_Dunkel": _wood(Color(0.35, 0.22, 0.12), 0.7, 2.0),
		"Haken": RoomKit.mat(Color(0.6, 0.5, 0.3), 0.4, 0.8), "Kragen": RoomKit.mat(Color(0.95, 0.95, 0.92), 0.8),
		"Pailletten": RoomKit.glow(Color(1, 0.85, 0.4), 1.2), "Zylinderhut": RoomKit.mat(Color(0.08, 0.08, 0.1), 0.5),
		"Clownshut": RoomKit.mat(Color(0.2, 0.5, 0.9), 0.6), "Bommel": RoomKit.mat(Color(0.95, 0.3, 0.2), 0.6),
		"Spiegelrahmen": RoomKit.mat(Color(0.2, 0.12, 0.08), 0.5), "Spiegelglas": glass,
		"Spiegelbirne": RoomKit.glow(Color(1.0, 0.9, 0.7), 3.0), "Schminktisch": _wood(Color(0.4, 0.24, 0.14), 0.7, 2.0),
		"Puderdose": RoomKit.mat(Color(0.95, 0.75, 0.75), 0.4), "Lippenstift": RoomKit.mat(Color(0.9, 0.1, 0.15), 0.4),
		"Tischholz": wood, "Tischtuch": cloth, "Tischgold": stripe, "Trommel": RoomKit.mat(Color(0.75, 0.1, 0.1), 0.5),
		"Trommelseil": RoomKit.mat(Color(0.9, 0.86, 0.72), 0.8), "Kabel": RoomKit.mat(Color(0.1, 0.1, 0.1), 0.6),
	}
	for k in 4:
		mats["Kostuem_%d" % k] = RoomKit.mat(costumes[k], 0.7)
	var model := RoomKit.model(self, MODEL, mats)
	# Lichterkette: jede Birne („Lichterkette_00“ … „_21“) hat ihr eigenes Material und blinkt im Wechsel
	var cols := [Color(1, 0.3, 0.2), Color(1, 0.85, 0.3), Color(0.3, 0.6, 1), Color(0.4, 1, 0.5)]
	for i in 22:
		var m := RoomKit.glow(cols[(i % 11) % cols.size()], 1.6)
		_bulbs.append(m)
		(model.find_child("Lichterkette_%02d" % i, true, false) as MeshInstance3D).material_override = m
	# Plakat an der Rückwand links
	var poster := RoomKit.tex(DIR + "poster.png", 0.9)
	RoomKit.quad(self, Vector2(0.36, 0.5), Vector3(-1.95, 1.3, BACK_Z + 0.005), poster)


func _build_music_box() -> void:
	var y := TableWorld.TABLE_Y
	# Kasten, Deckel („Deckel“ klappt am Scharnier), Tänzerin, Springteufel und Schlüssel („Key“)
	# kommen aus Blender; Farben der Figuren stehen dort
	var scene := RoomKit.model(self, BOX_MODEL, {
		"Spieluhr_Holz": _wood(Color(0.5, 0.25, 0.14), 0.45, 10.0), "Spieluhr_Gold": RoomKit.mat(Color(0.9, 0.7, 0.3), 0.3, 0.9),
	})
	_box = scene.find_child("Spieluhr", true, false) as Node3D
	_box.position = BOX_POS + Vector3(0, y, 0)
	_box.rotation.y = 0.5
	_lid = _box.find_child("Deckel", true, false) as Node3D
	_dancer = _box.find_child("Taenzerin", true, false) as Node3D
	_jack = _box.find_child("Springteufel", true, false) as Node3D
	_jack.visible = false
	_box_area = RoomKit.click_area(_box, Vector3(0.18, 0.14, 0.14), Vector3(0, 0.05, 0), wind_music_box)
	_box_area.input_ray_pickable = interactive


## Für die Deck-Belohnungen (TableSkin): welche Materialien Filz und Rand sind, Umriss des Rands.
func table_info() -> Dictionary:
	return TableSkin.rect_info(_skin_felt, _skin_rim, Vector2(TOP.x * 0.5 - 0.03, TOP.y * 0.5 - 0.03), false, 0)
