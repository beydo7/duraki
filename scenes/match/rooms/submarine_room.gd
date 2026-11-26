class_name SubmarineRoom
extends Node3D
## Raum „U-Boot“. Formen aus Blender (assets/rooms/submarine/submarine.glb und sea.glb, gebaut
## mit art/blender/submarine.py), Materialien, Lichter und alles Bewegliche hier im Code.
## Boden, Decke, Wandplatten, das Meer hinter dem Bullauge, Sonarstrahl und Luftblasen bleiben Code.
##
## Enge Messe eines alten U-Boots: grüne Stahlwände mit Nieten und Spanten, Rohre und
## Ventilräder an der Decke, Gitterlampen, ein rotes Notlicht. Hinten links ein rundes Bullauge,
## draußen ziehen Fische und Luftblasen vorbei. Rechts eine Sonar-Konsole: der grüne Strahl
## kreist, bei jedem Umlauf ein „Ping“. Leben = Druckanzeigen an der Rückwand (`lives_panel`).
## Im Hintergrund brummt die Maschine, ab und zu tropft Wasser und Metall knarzt.
##
## Easter Egg: Das Periskop über dem Tisch lässt sich drehen (anklicken = eine Umdrehung).
## Dreimal kurz hintereinander herumgedreht → draußen am Bullauge schwimmt ein Wal vorbei
## (Walgesang) und es gibt den geheimen Erfolg „Moby Durak“.

const DIR := "res://assets/rooms/submarine/"
const MODEL := preload("res://assets/rooms/submarine/submarine.glb")
const SEA := preload("res://assets/rooms/submarine/sea.glb")
const SND_HUM := preload("res://assets/rooms/submarine/hum.wav")
const SND_SONAR := preload("res://assets/rooms/submarine/sonar.wav")
const SND_CREAK := preload("res://assets/rooms/submarine/creak.wav")
const SND_DRIP := preload("res://assets/rooms/submarine/drip.wav")
const SND_CRANK := preload("res://assets/rooms/submarine/crank.wav")
const SND_WHALE := preload("res://assets/rooms/submarine/whale.wav")

const ROOM_W := 4.6
const BACK_Z := -2.2
const CEIL := 2.75
const TOP := Vector2(1.84, 1.3)
const PORT := Vector3(-1.15, 1.3, BACK_Z) # Bullauge (Mitte)
const PORT_R := 0.3
const SONAR_TIME := 6.0 # eine Umdrehung des Sonarstrahls
const PERISCOPE_POS := Vector3(1.5, 0.0, -0.95)
const TURNS_FOR_WHALE := 3
const TURN_WINDOW := 6.0 # so viele Sekunden zwischen zwei Drehungen, sonst zählt es neu
const WHALE_DEPTH := 2.6 # wie weit draußen der Wal vorbeischwimmt
const CAM := Vector3(0, 1.36, 0.86) # ungefähre Kameraposition im Duell

## Leben an der Rückwand (TableProps schaltet sie)
var lives_panel: GaugeLives
## Periskop anklickbar (nur im Duell)
var interactive := false:
	set(v):
		interactive = v
		if _periscope_area != null:
			_periscope_area.input_ray_pickable = v

var _t := 0.0
var _fish: Array[Dictionary] = []
var _whale: Node3D
var _whale_t := -1.0
var _sweep: Node3D
var _blips: Array[MeshInstance3D] = []
var _sonar_angle := 0.0
var _red_light: OmniLight3D
var _red_mat: StandardMaterial3D
var _periscope: Node3D
var _periscope_area: Area3D
var _turning := false
var _turns := 0
var _last_turn := -10.0
var _next_drip := 4.0
var _next_creak := 12.0
var _hum: AudioStreamPlayer


var _model: Node3D # submarine.glb
var _skin_felt: Array[Material] = []
var _skin_rim: Array[Material] = []


func _ready() -> void:
	_build_shell()
	_build_model()
	_build_porthole()
	_build_sonar()
	_build_periscope()
	lives_panel = GaugeLives.new()
	lives_panel.position = Vector3(1.55, 1.0, BACK_Z)
	lives_panel.floor_drop = lives_panel.position.y # Rohre bis zum Boden
	add_child(lives_panel)
	_hum = RoomKit.loop(self, SND_HUM, -24.0)


func _process(delta: float) -> void:
	_t += delta
	# Fische und Luftblasen vor dem Bullauge
	for f in _fish:
		var n: Node3D = f.node
		n.position.x += f.speed * delta
		n.position.y = f.y + sin(_t * f.wobble + f.phase) * 0.05
		var cx := _view_x(BACK_Z - n.position.z)
		if n.position.x > cx + 1.3:
			n.position.x = cx - 1.3
			f.y = PORT.y + randf_range(-0.35, 0.35)
	if _whale_t >= 0.0:
		_whale_t += delta
		var wx := _view_x(WHALE_DEPTH)
		_whale.position.x = lerpf(wx - 4.0, wx + 4.0, _whale_t / 9.0)
		_whale.position.y = PORT.y - 0.05 + sin(_whale_t * 0.8) * 0.12
		_whale.rotation.z = sin(_whale_t * 0.8 + 1.0) * 0.06
		if _whale_t > 9.0:
			_whale_t = -1.0
			_whale.visible = false
	# Sonar: Strahl kreist, bei jeder vollen Umdrehung „Ping“ und ein Echo-Punkt
	var prev := _sonar_angle
	_sonar_angle = fmod(_sonar_angle + delta * TAU / SONAR_TIME, TAU)
	_sweep.rotation.z = -_sonar_angle
	if _sonar_angle < prev:
		RoomKit.play(self, SND_SONAR, -31.0)
		_blip()
	for b in _blips:
		var m := b.material_override as StandardMaterial3D
		m.albedo_color.a = maxf(0.0, m.albedo_color.a - delta * 0.25)
	# Notlicht pulsiert langsam
	var pulse := 0.5 + 0.5 * sin(_t * 1.6)
	_red_light.light_energy = 0.35 + 0.65 * pulse
	_red_mat.emission_energy_multiplier = 1.0 + 3.0 * pulse
	# Tropfen und Knarzen in zufälligen Abständen
	_next_drip -= delta
	if _next_drip <= 0.0:
		_next_drip = randf_range(5.0, 12.0)
		RoomKit.play(self, SND_DRIP, -26.0, randf_range(0.85, 1.2))
	_next_creak -= delta
	if _next_creak <= 0.0:
		_next_creak = randf_range(16.0, 32.0)
		RoomKit.play(self, SND_CREAK, -22.0, randf_range(0.8, 1.1))


## Wo man in dieser Tiefe hinter der Wand durchs Bullauge hinsieht (x).
static func _view_x(depth: float) -> float:
	return PORT.x + (PORT.x - CAM.x) / (CAM.z - BACK_Z) * depth


## Licht und Stimmung: dunkel, grünlich-blau, eng.
func apply_environment(env: Environment) -> void:
	env.background_color = Color("020506")
	env.ambient_light_color = Color("1f3a36")
	env.ambient_light_energy = 0.6
	env.fog_light_color = Color("061012")
	env.adjustment_saturation = 0.9


func add_lights(parent: Node3D) -> void:
	for x: float in [-1.1, 1.1]: # Gitterlampen an der Decke
		var l := OmniLight3D.new()
		l.position = Vector3(x, CEIL - 0.35, -0.4)
		l.light_color = Color("ffd59a")
		l.light_energy = 1.3
		l.omni_range = 3.2
		l.omni_attenuation = 1.4
		parent.add_child(l)
	var rim := OmniLight3D.new() # Gegenlicht hinter dem Gegner, kühl
	rim.position = Vector3(0, 1.9, -1.6)
	rim.light_color = Color("5fa3a0")
	rim.light_energy = 1.5
	rim.omni_range = 2.2
	parent.add_child(rim)
	var wall := OmniLight3D.new() # Wandlampe über den Druckanzeigen
	wall.position = Vector3(1.55, 1.5, BACK_Z + 0.35)
	wall.light_color = Color("ffd59a")
	wall.light_energy = 0.9
	wall.omni_range = 1.4
	parent.add_child(wall)
	var sea := OmniLight3D.new() # blaues Wasserlicht durchs Bullauge
	sea.position = PORT + Vector3(0, 0, 0.4)
	sea.light_color = Color("3d8cc8")
	sea.light_energy = 0.9
	sea.omni_range = 1.8
	parent.add_child(sea)


## Periskop eine Umdrehung weiterdrehen (Klick). Dreimal schnell → Wal.
func turn_periscope() -> void:
	if _turning:
		return
	_turning = true
	var now := Time.get_ticks_msec() / 1000.0
	_turns = _turns + 1 if now - _last_turn < TURN_WINDOW else 1
	_last_turn = now
	RoomKit.play(self, SND_CRANK, -12.0)
	var tw := create_tween()
	tw.tween_property(_periscope, "rotation:y", _periscope.rotation.y + TAU, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		_turning = false
		if _turns >= TURNS_FOR_WHALE:
			_turns = 0
			show_whale())


## Easter Egg: Wal schwimmt am Bullauge vorbei.
func show_whale() -> void:
	if _whale_t >= 0.0:
		return
	_whale_t = 0.0
	_whale.visible = true
	RoomKit.play(self, SND_WHALE, -8.0)
	if interactive:
		Profile.unlock_achievement(&"moby_durak")


# --- Aufbau --------------------------------------------------------------------------

func _build_shell() -> void:
	var hull := RoomKit.tex(DIR + "hull.png", 0.55, 0.9)
	hull.metallic = 0.45
	var floor_mat := RoomKit.tex(DIR + "floor.png", 0.45, 1.6)
	floor_mat.metallic = 0.6
	RoomKit.plane(self, Vector2(ROOM_W, 6.0), Vector3(0, 0, 0.6), floor_mat)
	var ceil := RoomKit.plane(self, Vector2(ROOM_W, 6.0), Vector3(0, CEIL, 0.6), hull)
	ceil.rotation.x = PI
	for s: float in [-1.0, 1.0]:
		RoomKit.box(self, Vector3(0.1, CEIL, 6.0), Vector3(s * (ROOM_W * 0.5 + 0.05), CEIL * 0.5, 0.6), hull)
	# Rückwand mit Loch fürs Bullauge: Platte mit rundem Loch + Wand drumherum
	var ph := 0.45
	var px0 := PORT.x - ph
	var px1 := PORT.x + ph
	var py0 := PORT.y - ph
	var py1 := PORT.y + ph
	RoomKit.box(self, Vector3(px0 + ROOM_W * 0.5, CEIL, 0.1), Vector3((-ROOM_W * 0.5 + px0) * 0.5, CEIL * 0.5, BACK_Z - 0.05), hull)
	RoomKit.box(self, Vector3(ROOM_W * 0.5 - px1, CEIL, 0.1), Vector3((px1 + ROOM_W * 0.5) * 0.5, CEIL * 0.5, BACK_Z - 0.05), hull)
	RoomKit.box(self, Vector3(ph * 2, py0, 0.1), Vector3(PORT.x, py0 * 0.5, BACK_Z - 0.05), hull)
	RoomKit.box(self, Vector3(ph * 2, CEIL - py1, 0.1), Vector3(PORT.x, (py1 + CEIL) * 0.5, BACK_Z - 0.05), hull)
	var plate := RoomKit.plate_with_hole(ph, PORT_R, hull)
	plate.position = PORT + Vector3(0, 0, -0.005)
	add_child(plate)
	# Spanten, Rohre, Ventilräder und Lampen kommen aus Blender


## Alles aus Blender: Spanten mit Nieten, Rohre mit Flanschen und Ventilrädern, Notlicht im Korb,
## Bullauge, Sonar-Konsole, Tisch mit Blechbecher und Seekarte, Lampen, Periskop.
## Die Materialien gehören zu den Namen, die sie in Blender haben (art/blender/submarine.py).
func _build_model() -> void:
	var cols := [Color(0.55, 0.12, 0.1), Color(0.75, 0.6, 0.2), Color(0.42, 0.45, 0.44), Color(0.3, 0.4, 0.55)]
	_red_mat = RoomKit.glow(Color(1.0, 0.1, 0.06), 2.0)
	var top := RoomKit.mat(Color(0.18, 0.22, 0.2), 0.75) # Linoleum
	var steel := RoomKit.mat(Color(0.45, 0.48, 0.47), 0.35, 0.8)
	_skin_felt = [top]
	_skin_rim = [steel]
	var tube := RoomKit.mat(Color(0.2, 0.26, 0.24), 0.5, 0.5)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.6, 0.85, 0.9, 0.12)
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	var chart := StandardMaterial3D.new()
	chart.albedo_color = Color(0.82, 0.8, 0.68)
	chart.roughness = 0.95
	chart.cull_mode = BaseMaterial3D.CULL_DISABLED # aufgerollte Ecke: auch die Unterseite zeigen
	_model = RoomKit.model(self, MODEL, {
		"Spant": RoomKit.mat(Color(0.2, 0.27, 0.23), 0.5, 0.5),
		"Rohr_Rot": RoomKit.mat(cols[0], 0.5, 0.4), "Rohr_Gelb": RoomKit.mat(cols[1], 0.5, 0.4),
		"Rohr_Grau": RoomKit.mat(cols[2], 0.5, 0.4), "Rohr_Blau": RoomKit.mat(cols[3], 0.5, 0.4),
		"Ventilrad": RoomKit.mat(Color(0.75, 0.12, 0.1), 0.5), "Notlicht": _red_mat,
		"Gitter": RoomKit.mat(Color(0.15, 0.15, 0.15), 0.5, 0.6), "Messing": RoomKit.mat(Color(0.8, 0.6, 0.3), 0.28, 1.0),
		"Bullaugenrohr": tube, "Bullaugenglas": glass,
		"Konsole": RoomKit.mat(Color(0.32, 0.36, 0.34), 0.45, 0.6), "Konsole_Dunkel": RoomKit.mat(Color(0.12, 0.12, 0.12), 0.4, 0.5),
		"Sonarschirm": RoomKit.glow(Color(0.02, 0.25, 0.08), 0.8), "Sonargitter": RoomKit.glow(Color(0.2, 0.9, 0.35), 1.2),
		"Sonarknopf_0": RoomKit.glow(Color(1, 0.2, 0.1), 1.5), "Sonarknopf_1": RoomKit.glow(Color(1, 0.8, 0.2), 1.5),
		"Sonarknopf_2": RoomKit.glow(Color(0.3, 1, 0.4), 1.5), "Sonarknopf_3": RoomKit.glow(Color(0.3, 1, 0.4), 1.5),
		"Linoleum": top, "Tischstahl": steel, "Blechbecher": RoomKit.mat(Color(0.62, 0.64, 0.62), 0.35, 0.8),
		"Seekarte": chart, "Tinte": RoomKit.mat(Color(0.3, 0.4, 0.55), 0.9),
		"Periskop_Lack": RoomKit.mat(Color(0.36, 0.42, 0.38), 0.45, 0.35),
		"Periskop_Dunkel": RoomKit.mat(Color(0.22, 0.26, 0.23), 0.5, 0.35), "Okular": RoomKit.mat(Color(0.05, 0.05, 0.05), 0.4),
		"Lampenglas": RoomKit.glow(Color(1.0, 0.85, 0.6), 3.0),
	})
	# Rotes Notlicht an der linken Wand (pulsiert, siehe _process)
	_red_light = OmniLight3D.new()
	_red_light.position = Vector3(-ROOM_W * 0.5 + 0.35, 2.1, -1.2)
	_red_light.light_color = Color(1.0, 0.15, 0.1)
	_red_light.omni_range = 2.6
	add_child(_red_light)


func _build_porthole() -> void:
	# Messingring, Rohr und Glas sind im Modell
	# Meer dahinter: dunkles Blau, Lichtstrahlen von oben, Fische, Blasen
	var sea := StandardMaterial3D.new()
	sea.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sea.albedo_color = Color(0.05, 0.24, 0.36)
	RoomKit.quad(self, Vector2(8.0, 5.0), PORT + Vector3(0, 0.3, -2.5), sea)
	var ray := StandardMaterial3D.new()
	ray.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ray.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ray.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ray.albedo_color = Color(0.2, 0.45, 0.6, 0.25)
	for k in 3:
		var r := RoomKit.quad(self, Vector2(0.25, 3.0), PORT + Vector3(-0.6 + k * 0.55, 0.6, -2.0 + k * 0.2), ray)
		r.rotation.z = 0.35
	var sea_model := SEA.instantiate() # Vorlage für die Fische und der Wal
	var fish_mesh := (sea_model.find_child("Fisch_Koerper", true, false) as MeshInstance3D).mesh
	var fish_mat := RoomKit.glow(Color(0.55, 0.72, 0.75), 0.5)
	var fish_mat2 := RoomKit.glow(Color(0.95, 0.65, 0.25), 0.5)
	for k in 10:
		var f := Node3D.new()
		var y := PORT.y + randf_range(-0.3, 0.3)
		var dz := randf_range(0.3, 0.9)
		f.position = Vector3(_view_x(dz) + randf_range(-1.2, 1.2), y, BACK_Z - dz)
		add_child(f)
		var m := fish_mat if k % 3 else fish_mat2
		var body := MeshInstance3D.new()
		body.mesh = fish_mesh
		body.material_override = m
		f.add_child(body)
		var sc := randf_range(0.9, 1.6)
		f.scale = Vector3.ONE * sc
		_fish.append({"node": f, "y": y, "speed": randf_range(0.12, 0.3), "wobble": randf_range(0.8, 1.6), "phase": randf() * TAU})
	var bubbles := CPUParticles3D.new()
	bubbles.position = PORT + Vector3(0, -0.6, -0.5)
	bubbles.amount = 14
	bubbles.lifetime = 4.0
	bubbles.direction = Vector3.UP
	bubbles.spread = 8.0
	bubbles.gravity = Vector3(0, 0.08, 0)
	bubbles.initial_velocity_min = 0.15
	bubbles.initial_velocity_max = 0.3
	bubbles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	bubbles.emission_box_extents = Vector3(0.4, 0.05, 0.3)
	var bm := SphereMesh.new()
	bm.radius = 0.012
	bm.height = 0.024
	var bmat := StandardMaterial3D.new()
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.albedo_color = Color(0.8, 0.95, 1.0, 0.35)
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.material = bmat
	bubbles.mesh = bm
	add_child(bubbles)
	# der Wal (unsichtbar bis zum Easter Egg)
	_whale = sea_model.find_child("Wal", true, false) as Node3D
	_whale.owner = null # gehört nicht mehr zur Vorlagen-Szene
	for n in _whale.find_children("*", "", true, false):
		n.owner = null
	_whale.get_parent().remove_child(_whale)
	add_child(_whale)
	sea_model.free()
	RoomKit.apply_materials(_whale, {
		"Wal_Haut": RoomKit.glow(Color(0.16, 0.22, 0.3), 0.6), "Wal_Bauch": RoomKit.glow(Color(0.5, 0.56, 0.6), 0.5),
		"Wal_Auge": RoomKit.mat(Color(0.02, 0.02, 0.02), 0.2), "Wal_Maul": RoomKit.mat(Color(0.05, 0.06, 0.08), 0.6),
	})
	_whale.position = PORT + Vector3(-7.0, -0.2, -WHALE_DEPTH)
	_whale.scale = Vector3.ONE * 0.7
	_whale.visible = false


func _build_sonar() -> void:
	var pos := Vector3(-1.65, 0.62, BACK_Z + 0.25)
	var screen_pos := pos + Vector3(0, 0.22, 0.21) # Gehäuse, Schirm, Gitter und Knöpfe sind im Modell
	_sweep = Node3D.new()
	_sweep.position = screen_pos + Vector3(0, 0, 0.027)
	add_child(_sweep)
	RoomKit.box(_sweep, Vector3(0.16, 0.006, 0.002), Vector3(0.08, 0, 0), RoomKit.glow(Color(0.4, 1.0, 0.5), 3.0))
	for k in 4: # Echo-Punkte, leuchten nach jedem Ping kurz auf
		var b := RoomKit.sphere(self, 0.008, screen_pos + Vector3(0, 0, 0.028), null)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.5, 1.0, 0.6, 0.0)
		b.material_override = m
		_blips.append(b)


func _blip() -> void:
	var b := _blips[randi() % _blips.size()]
	var a := randf() * TAU
	var r := randf_range(0.04, 0.15)
	b.position = _sweep.position + Vector3(cos(a) * r, sin(a) * r, 0.001)
	(b.material_override as StandardMaterial3D).albedo_color.a = 1.0


func _build_periscope() -> void:
	# Rohr mit Ringen, Nieten, Okular und Griffen ist im Modell; der Knoten dreht sich als Ganzes
	_periscope = _model.find_child("Periskop", true, false) as Node3D
	var low := 1.25
	_periscope_area = RoomKit.click_area(_periscope, Vector3(0.5, 0.5, 0.4), Vector3(0, low, 0.04), turn_periscope)
	_periscope_area.input_ray_pickable = interactive


## Für die Deck-Belohnungen (TableSkin): welche Materialien Filz und Rand sind, Umriss des Rands.
func table_info() -> Dictionary:
	return TableSkin.rect_info(_skin_felt, _skin_rim, Vector2(TOP.x * 0.5 + 0.0125, TOP.y * 0.5 + 0.0125), false, 0)
