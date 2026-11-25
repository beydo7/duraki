class_name StationRoom
extends Node3D
## Raum „Bahnhofswartesaal“ – ganz in Code gebaut (kein Blender-Modell).
##
## Unten grüne, darüber weiße Wandkacheln, Schachbrett-Fliesenboden, Holzbänke an den
## Wänden, ein Kipjatok (Heißwasserkessel). Hinten zwei hohe Fenster zum Bahnsteig, dazwischen
## eine Fahrplantafel „DURAKI BAHNHOF“ mit deutschen Städten und darüber eine Bahnhofsuhr (zeigt die
## echte Uhrzeit). Über dem Tisch hängt eine Neonröhre, die brummt und ab und zu flackert.
##
## Ab und zu rauscht draußen ein Zug vorbei: Licht aus den Abteilfenstern huscht durch den
## Raum, das Bild zittert leicht und die Teegläser klirren (Signal `train_passing`).
## Danach ist der Zug von der Tafel verschwunden und die Zeilen rücken nach.
##
## Der Spieltisch ist ein alter Holztisch; die Spielfläche liegt wie im Hinterzimmer auf
## TableWorld.TABLE_Y, damit alle Kartenplätze gleich bleiben.

## Während der Zug vorbeifährt, jeden Frame: Stärke 0..1
signal train_passing(strength: float)

const TEX := "res://assets/rooms/station/"
const SND_TRAIN := preload("res://assets/rooms/station/train_pass.wav")
const SND_BUZZ := preload("res://assets/rooms/station/neon_buzz.wav")
const SND_TICK := preload("res://assets/rooms/station/neon_tick.wav")
const FONT_BOARD := preload("res://assets/fonts/DejaVuSans-Bold.ttf")
const FONT_SIGN := preload("res://assets/fonts/RussoOne-Regular.ttf")

const ROOM_W := 5.0 # x = ±2.5
const BACK_Z := -2.4
const CEIL := 3.3
const TOP := Vector2(1.84, 1.3) # Tischplatte
const WIN_X := 1.65 # Fenstermitten bei x = ±WIN_X
const WIN_W := 0.9
const WIN_Y := Vector2(1.0, 2.65) # Unter- und Oberkante
const TRACK_Z := BACK_Z - 2.2
## Wartezeit zwischen zwei Zügen (Sekunden)
const TRAIN_GAP := Vector2(40.0, 80.0)
const FIRST_TRAIN := Vector2(12.0, 25.0)
const TRAIN_SPEED := 22.0
const TRAIN_CARS := 7
const CAR_LEN := 6.2

## Abfahrten auf der Tafel: Zug-Nr., Ziel, Zeit, Gleis. Oben fährt als Nächstes ab.
const DEPARTURES := [
	["017", "HANNOVER", "23:40", "1"],
	["105", "FRANKFURT", "00:15", "2"],
	["042", "MÜNCHEN", "01:05", "1"],
	["211", "KÖLN", "02:30", "3"],
	["088", "BERLIN", "03:10", "2"],
	["002", "NEUSTADT AM RÜBENBERGE", "05:55", "4"],
	["133", "HAMBURG", "06:20", "1"],
	["076", "DRESDEN", "07:45", "3"],
	["019", "LEIPZIG", "08:30", "2"],
	["154", "STUTTGART", "09:05", "4"],
	["061", "BREMEN", "10:40", "1"],
	["120", "NÜRNBERG", "11:15", "3"],
]
const ROWS := 6

var _t := 0.0
## Neonröhren: Material und Licht, Helligkeit 0..1
var _tubes: Array[Dictionary] = []
var _buzz: AudioStreamPlayer
var _train: Node3D
var _train_light: OmniLight3D
var _train_x := 1000.0 # außerhalb = kein Zug
var _next_train := 0.0
var _board_rows: Array[Array] = [] # pro Zeile die Label3D (Nr, Ziel, Zeit, Gleis)
var _first_departure := 0
var _clock_hands: Array[Node3D] = [] # Stunde, Minute, Sekunde


func _ready() -> void:
	_next_train = randf_range(FIRST_TRAIN.x, FIRST_TRAIN.y)
	_build_shell()
	_build_windows()
	_build_outside()
	_build_board()
	_build_clock()
	_build_table()
	_build_on_table()
	_build_benches()
	_build_kettle()
	_build_tubes()
	_build_train()
	if DisplayServer.get_name() != "headless":
		var st := SND_BUZZ.duplicate() as AudioStreamWAV
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = int(st.get_length() * st.mix_rate)
		_buzz = AudioStreamPlayer.new()
		_buzz.bus = &"SFX"
		_buzz.stream = st
		_buzz.volume_db = -32.0 # ganz leise im Hintergrund
		add_child(_buzz)
		_buzz.play()


func _process(delta: float) -> void:
	_t += delta
	_update_tubes(delta)
	_update_clock()
	# Zug
	_next_train -= delta
	if _next_train <= 0.0 and _train_x > 999.0:
		start_train()
	if _train_x < 999.0:
		_train_x += TRAIN_SPEED * delta
		_train.position.x = _train_x
		var length := TRAIN_CARS * CAR_LEN
		var head := _train_x
		var tail := _train_x - length
		# wie viel vom Zug gerade vor den Fenstern ist (0..1), weich ein- und ausblenden
		var near := clampf(minf(head + 4.0, 4.0 - tail) / 6.0, 0.0, 1.0)
		var flick := 0.55 + 0.45 * absf(sin(_train_x * 1.6)) # Abteilfenster huschen vorbei
		_train_light.light_energy = 1.5 * near * flick
		if near > 0.01:
			train_passing.emit(near)
		if tail > 30.0:
			_train_x = 1000.0
			_train_light.light_energy = 0.0
			_next_train = randf_range(TRAIN_GAP.x, TRAIN_GAP.y)
			_advance_board()


## Licht und Stimmung: kühl und etwas grünlich (Neonlicht, Nacht draußen).
func apply_environment(env: Environment) -> void:
	env.background_color = Color("040607")
	env.ambient_light_color = Color("26332e")
	env.ambient_light_energy = 0.5
	env.fog_light_color = Color("0a100e")
	env.adjustment_saturation = 0.82


## Eigene Lichter: Neonröhren, kaltes Licht durch die Fenster, Gegenlicht hinter dem
## Gegner. Tischlampe und Lichtkegel auf das Spielfeld baut TableWorld wie gewohnt.
func add_lights(parent: Node3D) -> void:
	for tube in _tubes:
		var light := OmniLight3D.new()
		light.position = tube.pos + Vector3(0, -0.15, 0)
		light.light_color = Color("d8f4ec")
		light.omni_range = 3.4
		light.omni_attenuation = 1.3
		parent.add_child(light)
		tube.light = light
		tube.base_energy = tube.energy
	var rim := OmniLight3D.new()
	rim.position = Vector3(0, 1.9, -1.5)
	rim.light_color = Color("5f9e8c")
	rim.light_energy = 1.6
	rim.omni_range = 2.2
	parent.add_child(rim)
	# Mondlicht / Bahnsteiglampen durch die Fenster
	for s in [-1.0, 1.0]:
		var win := SpotLight3D.new()
		win.position = Vector3(s * WIN_X, 2.5, BACK_Z - 0.3)
		parent.add_child(win)
		win.look_at(Vector3(s * WIN_X * 0.6, 0.0, BACK_Z + 2.2))
		win.light_color = Color("8fb0d8")
		win.light_energy = 1.1
		win.spot_range = 4.0
		win.spot_angle = 30.0


## Nächsten Zug sofort losschicken (auch fürs Testen).
func start_train() -> void:
	_train_x = -50.0 # Spitze ca. 2 s vor den Fenstern, passt zum Geräusch
	if DisplayServer.get_name() != "headless":
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		p.stream = SND_TRAIN
		p.volume_db = -9.0
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)


# --- Neonröhren -------------------------------------------------------------------

func _update_tubes(delta: float) -> void:
	for tube in _tubes:
		# ab und zu ein Flacker-Anfall: kurz an/aus/an, mit leisem Klicken
		tube.timer -= delta
		if tube.timer <= 0.0:
			tube.flicker = randf_range(0.35, 1.1)
			tube.timer = randf_range(tube.gap.x, tube.gap.y)
			_tick(tube)
		var on := 1.0
		if tube.flicker > 0.0:
			tube.flicker -= delta
			on = 1.0 if sin(_t * 47.0 + tube.seed) > 0.2 else 0.12
			if randf() < delta * 6.0:
				_tick(tube)
		tube.level = lerpf(tube.level, on, minf(delta * 40.0, 1.0))
		var hum := 0.97 + 0.03 * sin(_t * 100.0 + tube.seed)
		(tube.mat as StandardMaterial3D).emission_energy_multiplier = 3.2 * tube.level * hum
		if tube.has("light"):
			(tube.light as OmniLight3D).light_energy = tube.base_energy * tube.level * hum


func _tick(tube: Dictionary) -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX"
	p.stream = SND_TICK
	p.volume_db = -24.0 if tube.main else -30.0
	p.pitch_scale = randf_range(0.9, 1.15)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _build_tubes() -> void:
	# Hauptröhre über dem Tisch (flackert selten), zweite weiter hinten (flackert öfter)
	var defs := [
		[Vector3(0, 2.55, -0.15), 1.6, 1.5, Vector2(14.0, 30.0), true],
		[Vector3(-1.2, 2.85, -1.7), 1.2, 0.9, Vector2(4.0, 10.0), false],
		[Vector3(1.3, 2.85, 1.2), 1.2, 0.7, Vector2(20.0, 45.0), false],
	]
	var housing := _mat(Color(0.82, 0.84, 0.8), 0.5)
	housing.metallic = 0.4
	var wire := _mat(Color(0.1, 0.1, 0.1), 0.6)
	for i in defs.size():
		var d: Array = defs[i]
		var pos: Vector3 = d[0]
		var len: float = d[1]
		var root := Node3D.new()
		root.position = pos
		add_child(root)
		# Blechschiene und Röhre darunter, an zwei Drähten von der Decke
		_box_in(root, Vector3(len + 0.06, 0.04, 0.12), Vector3(0, 0.03, 0), housing)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.92, 1.0, 0.97)
		mat.emission_enabled = true
		mat.emission = Color(0.86, 1.0, 0.95)
		mat.emission_energy_multiplier = 3.0
		var tube := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.016
		cm.bottom_radius = 0.016
		cm.height = len
		tube.mesh = cm
		tube.material_override = mat
		tube.rotation.z = PI * 0.5
		tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(tube)
		for s in [-1.0, 1.0]:
			_box_in(root, Vector3(0.03, 0.05, 0.05), Vector3(s * len * 0.5, 0.0, 0), housing) # Fassungen
			_cyl_in(root, 0.003, 0.003, CEIL - pos.y, Vector3(s * len * 0.35, (CEIL - pos.y) * 0.5, 0), wire)
		_tubes.append({"mat": mat, "pos": pos, "energy": d[2], "gap": d[3], "main": d[4],
			"timer": randf_range(1.0, (d[3] as Vector2).x), "flicker": 0.0, "level": 1.0, "seed": i * 2.7})


# --- Hülle: Boden, Wände, Decke ----------------------------------------------------

func _build_shell() -> void:
	var floor_mat := _tex_mat("floor.png", 0.7, Vector3(1, 1, 1))
	floor_mat.uv1_triplanar = true
	floor_mat.uv1_world_triplanar = true
	floor_mat.uv1_scale = Vector3(0.9, 0.9, 0.9) # eine Fliese ca. 28 cm
	_plane(Vector2(ROOM_W, 6.0), Vector3(0, 0, 0.6), floor_mat)
	var ceil_mat := _tex_mat("plaster.png", 0.9, Vector3(1, 1, 1))
	ceil_mat.albedo_color = Color(0.55, 0.56, 0.52)
	var c := _plane(Vector2(ROOM_W, 6.0), Vector3(0, CEIL, 0.6), ceil_mat)
	c.rotation.x = PI
	var green := _tiles(Color(0.36, 0.6, 0.46))
	var trim := _tiles(Color(0.14, 0.3, 0.2))
	var white := _tiles(Color(1, 1, 1))
	var plaster := _tex_mat("plaster.png", 0.92, Vector3(1, 1, 1))
	plaster.uv1_triplanar = true
	plaster.uv1_world_triplanar = true
	plaster.uv1_scale = Vector3(0.5, 0.5, 0.5)
	var bands := [[0.0, 1.1, green], [1.1, 1.17, trim], [1.17, 1.85, white], [1.85, 1.9, trim], [1.9, CEIL, plaster]]
	# Seitenwände (durchgehend)
	for s in [-1.0, 1.0]:
		for b in bands:
			var h: float = b[1] - b[0]
			_box_in(self, Vector3(0.1, h, 6.0), Vector3(s * (ROOM_W * 0.5 + 0.05), b[0] + h * 0.5, 0.6), b[2])
	# Rückwand mit zwei Fensteröffnungen: in senkrechte Streifen zerlegt
	var xs := [-ROOM_W * 0.5, -WIN_X - WIN_W * 0.5, -WIN_X + WIN_W * 0.5, WIN_X - WIN_W * 0.5, WIN_X + WIN_W * 0.5, ROOM_W * 0.5]
	for k in xs.size() - 1:
		var x0: float = xs[k]
		var x1: float = xs[k + 1]
		var is_window := k == 1 or k == 3
		for b in bands:
			var y0: float = b[0]
			var y1: float = b[1]
			if is_window: # nur unter und über dem Fenster Wand
				var parts := [[y0, minf(y1, WIN_Y.x)], [maxf(y0, WIN_Y.y), y1]]
				for p in parts:
					if p[1] - p[0] > 0.001:
						_box_in(self, Vector3(x1 - x0, p[1] - p[0], 0.1), Vector3((x0 + x1) * 0.5, (p[0] + p[1]) * 0.5, BACK_Z - 0.05), b[2])
			else:
				_box_in(self, Vector3(x1 - x0, y1 - y0, 0.1), Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, BACK_Z - 0.05), b[2])
	# Sockelleiste und Deckenkehle
	var dark := _mat(Color(0.12, 0.16, 0.13), 0.6)
	_box_in(self, Vector3(ROOM_W, 0.1, 0.03), Vector3(0, 0.05, BACK_Z + 0.015), dark)
	for s in [-1.0, 1.0]:
		_box_in(self, Vector3(0.03, 0.1, 6.0), Vector3(s * (ROOM_W * 0.5 - 0.015), 0.05, 0.6), dark)
	var cove := _mat(Color(0.6, 0.6, 0.55), 0.9)
	_box_in(self, Vector3(ROOM_W, 0.12, 0.12), Vector3(0, CEIL - 0.06, BACK_Z + 0.06), cove)


func _tiles(tint: Color) -> StandardMaterial3D:
	var m := _tex_mat("tiles.png", 0.18, Vector3(1, 1, 1))
	m.albedo_color = tint
	m.metallic_specular = 0.7 # glasierte Kacheln glänzen
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(1.6, 1.6, 1.6) # eine Kachel ca. 15 cm
	return m


# --- Fenster, Bahnsteig, Zug ---------------------------------------------------------

func _build_windows() -> void:
	var frame := _mat(Color(0.2, 0.28, 0.24), 0.55)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.55, 0.7, 0.75, 0.12)
	glass.roughness = 0.08
	glass.metallic_specular = 1.0
	var sill := _mat(Color(0.5, 0.5, 0.46), 0.7)
	var iron := _mat(Color(0.32, 0.34, 0.32), 0.5)
	for s in [-1.0, 1.0]:
		var cx: float = s * WIN_X
		var cy := (WIN_Y.x + WIN_Y.y) * 0.5
		var h := WIN_Y.y - WIN_Y.x
		var z := BACK_Z - 0.04
		# Rahmen, Kreuz und Sprossen
		for p in [[Vector3(WIN_W, 0.06, 0.08), Vector3(cx, WIN_Y.x + 0.03, z)],
				[Vector3(WIN_W, 0.06, 0.08), Vector3(cx, WIN_Y.y - 0.03, z)],
				[Vector3(0.06, h, 0.08), Vector3(cx - WIN_W * 0.5 + 0.03, cy, z)],
				[Vector3(0.06, h, 0.08), Vector3(cx + WIN_W * 0.5 - 0.03, cy, z)],
				[Vector3(0.045, h, 0.06), Vector3(cx, cy, z)],
				[Vector3(WIN_W, 0.04, 0.06), Vector3(cx, WIN_Y.x + h * 0.68, z)],
				[Vector3(WIN_W, 0.03, 0.05), Vector3(cx, WIN_Y.x + h * 0.34, z)]]:
			_box_in(self, p[0], p[1], frame)
		var pane := _plane(Vector2(WIN_W, h), Vector3(cx, cy, z), glass)
		pane.rotation.x = PI * 0.5
		_box_in(self, Vector3(WIN_W + 0.12, 0.04, 0.2), Vector3(cx, WIN_Y.x - 0.01, BACK_Z + 0.06), sill)
		# Heizkörper unter dem Fenster (Gussrippen)
		for k in 9:
			var x := cx - 0.32 + k * 0.08
			_box_in(self, Vector3(0.055, 0.5, 0.08), Vector3(x, 0.45, BACK_Z + 0.09), iron)
		_box_in(self, Vector3(0.7, 0.03, 0.05), Vector3(cx, 0.68, BACK_Z + 0.09), iron)
		_box_in(self, Vector3(0.7, 0.03, 0.05), Vector3(cx, 0.22, BACK_Z + 0.09), iron)


func _build_outside() -> void:
	# Nachthimmel weit hinten
	var sky := StandardMaterial3D.new()
	sky.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky.albedo_color = Color(0.03, 0.05, 0.09)
	var back := _plane(Vector2(40.0, 12.0), Vector3(0, 3.0, TRACK_Z - 4.0), sky)
	back.rotation.x = PI * 0.5
	# Bahnsteig (Betonkante) und Gleis
	var concrete := _mat(Color(0.25, 0.26, 0.26), 0.9)
	_box_in(self, Vector3(40.0, 0.9, 1.6), Vector3(0, 0.45, BACK_Z - 0.9), concrete)
	_box_in(self, Vector3(40.0, 0.06, 0.12), Vector3(0, 0.9, BACK_Z - 1.66), _mat(Color(0.75, 0.7, 0.3), 0.7)) # gelbe Kante
	var rail := _mat(Color(0.35, 0.33, 0.3), 0.4)
	rail.metallic = 0.8
	for dz in [-0.72, 0.72]:
		_box_in(self, Vector3(40.0, 0.08, 0.06), Vector3(0, 0.06, TRACK_Z + dz), rail)
	# Bahnsteiglampen mit warmem Licht
	var lamp_glow := StandardMaterial3D.new()
	lamp_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_glow.albedo_color = Color(1.0, 0.85, 0.55)
	var pole := _mat(Color(0.12, 0.12, 0.12), 0.5)
	for x in [-WIN_X - 0.6, WIN_X + 0.4]:
		_cyl_in(self, 0.03, 0.04, 3.0, Vector3(x, 2.4, BACK_Z - 1.2), pole)
		var bulb := MeshInstance3D.new()
		var bm := SphereMesh.new()
		bm.radius = 0.09
		bm.height = 0.18
		bulb.mesh = bm
		bulb.material_override = lamp_glow
		bulb.position = Vector3(x, 3.6, BACK_Z - 1.2)
		add_child(bulb)
		var l := OmniLight3D.new()
		l.position = Vector3(x, 3.4, BACK_Z - 1.0)
		l.light_color = Color("ffcf88")
		l.light_energy = 1.4
		l.omni_range = 3.0
		add_child(l)


func _build_train() -> void:
	_train = Node3D.new()
	_train.position = Vector3(_train_x, 0, TRACK_Z)
	add_child(_train)
	var body := _mat(Color(0.12, 0.26, 0.18), 0.55) # dunkelgrüne Waggons
	var roof := _mat(Color(0.2, 0.2, 0.2), 0.6)
	var stripe := _mat(Color(0.75, 0.68, 0.4), 0.5)
	var lit := StandardMaterial3D.new()
	lit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lit.albedo_color = Color(1.0, 0.86, 0.5)
	var dark := _mat(Color(0.05, 0.05, 0.05), 0.8)
	for c in TRAIN_CARS:
		var x0 := -c * CAR_LEN - CAR_LEN * 0.5
		_box_in(_train, Vector3(CAR_LEN - 0.35, 2.7, 2.9), Vector3(x0, 1.85, 0), body)
		_box_in(_train, Vector3(CAR_LEN - 0.35, 0.2, 2.7), Vector3(x0, 3.28, 0), roof)
		_box_in(_train, Vector3(CAR_LEN - 0.35, 0.06, 2.92), Vector3(x0, 1.45, 0), stripe)
		_box_in(_train, Vector3(CAR_LEN - 0.6, 0.4, 2.4), Vector3(x0, 0.35, 0), dark) # Fahrgestell
		# Abteilfenster (einige dunkel)
		for k in 8:
			var x := x0 - CAR_LEN * 0.5 + 0.55 + k * 0.72
			var m: Material = lit if (c * 8 + k) % 5 != 3 else dark
			_box_in(_train, Vector3(0.5, 0.55, 2.94), Vector3(x, 2.25, 0), m)
	_train.visible = true
	# Licht aus den Fenstern, das durch den Wartesaal huscht
	_train_light = OmniLight3D.new()
	_train_light.position = Vector3(0, 2.0, BACK_Z + 0.4)
	_train_light.light_color = Color("ffd890")
	_train_light.light_energy = 0.0
	_train_light.omni_range = 4.5
	add_child(_train_light)


# --- Fahrplantafel und Uhr ----------------------------------------------------------

func _build_board() -> void:
	var y := 2.12
	var z := BACK_Z + 0.03
	var w := 1.9
	var h := 0.95
	_box_in(self, Vector3(w + 0.08, h + 0.08, 0.05), Vector3(0, y, z), _mat(Color(0.3, 0.3, 0.28), 0.5)) # Rahmen
	_box_in(self, Vector3(w, h, 0.06), Vector3(0, y, z + 0.01), _mat(Color(0.03, 0.035, 0.04), 0.8))
	var head := _label("DURAKI BAHNHOF", FONT_SIGN, 64, Color(0.95, 0.95, 0.9))
	head.position = Vector3(0, y + h * 0.5 - 0.07, z + 0.045)
	add_child(head)
	var cols := [[-0.86, "ZUG"], [-0.62, "ZIEL"], [0.38, "ZEIT"], [0.7, "GLEIS"]]
	for col in cols:
		var l := _label(col[1], FONT_BOARD, 26, Color(0.7, 0.72, 0.7))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.position = Vector3(col[0], y + h * 0.5 - 0.16, z + 0.045)
		add_child(l)
	var slot := _mat(Color(0.08, 0.085, 0.09), 0.6)
	for r in ROWS:
		var ry := y + h * 0.5 - 0.25 - r * 0.112
		var labels: Array = []
		for ci in cols.size():
			var cx: float = cols[ci][0]
			var cw: float = [0.18, 0.9, 0.24, 0.12][ci]
			_box_in(self, Vector3(cw, 0.085, 0.01), Vector3(cx + cw * 0.5 - 0.02, ry, z + 0.04), slot) # Klappfeld
			var l := _label("", FONT_BOARD, 40, Color(1.0, 0.78, 0.3))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			l.position = Vector3(cx, ry, z + 0.048)
			add_child(l)
			labels.append(l)
		_board_rows.append(labels)
	_fill_board()


func _fill_board() -> void:
	for r in ROWS:
		_fill_row(r)


func _fill_row(r: int) -> void:
	var dep: Array = DEPARTURES[(_first_departure + r) % DEPARTURES.size()]
	var labels: Array = _board_rows[r]
	for ci in 4:
		(labels[ci] as Label3D).text = dep[ci]


## Der Zug ist weg: oberste Zeile verschwindet, die anderen klappen von oben nach unten um.
func _advance_board() -> void:
	_first_departure = (_first_departure + 1) % DEPARTURES.size()
	for r in ROWS:
		var tw := create_tween()
		tw.tween_interval(0.3 + r * 0.14)
		for ci in 4:
			var l: Label3D = _board_rows[r][ci]
			(tw.parallel() if ci > 0 else tw).tween_property(l, "scale:y", 0.05, 0.07)
		tw.tween_callback(func() -> void:
			_fill_row(r)
			_tick({"main": false}))
		for ci in 4:
			var l: Label3D = _board_rows[r][ci]
			(tw.parallel() if ci > 0 else tw).tween_property(l, "scale:y", 1.0, 0.07)


func _build_clock() -> void:
	# runde Bahnhofsuhr über der Tafel, an einer Stange von der Decke
	var pos := Vector3(0, 2.92, BACK_Z + 0.25)
	var metal := _mat(Color(0.15, 0.16, 0.16), 0.4)
	metal.metallic = 0.6
	_cyl_in(self, 0.012, 0.012, CEIL - pos.y, Vector3(pos.x, (CEIL + pos.y) * 0.5, pos.z), metal)
	var case := _cyl_in(self, 0.2, 0.2, 0.07, pos, metal)
	case.rotation.x = PI * 0.5
	var face := _cyl_in(self, 0.18, 0.18, 0.072, pos, _mat(Color(0.95, 0.94, 0.9), 0.6))
	face.rotation.x = PI * 0.5
	var ink := _mat(Color(0.05, 0.05, 0.05), 0.5)
	for k in 12: # Striche
		var a := TAU * k / 12.0
		var tick := _box_in(self, Vector3(0.012, 0.04 if k % 3 == 0 else 0.025, 0.004), pos + Vector3(sin(a) * 0.15, cos(a) * 0.15, 0.037), ink)
		tick.rotation.z = -a
	var red := _mat(Color(0.85, 0.1, 0.08), 0.5)
	for spec in [[0.09, 0.012, ink], [0.14, 0.008, ink], [0.15, 0.003, red]]:
		var hand := Node3D.new()
		hand.position = pos + Vector3(0, 0, 0.04 + _clock_hands.size() * 0.003)
		add_child(hand)
		_box_in(hand, Vector3(spec[1], spec[0], 0.003), Vector3(0, spec[0] * 0.4, 0), spec[2])
		_clock_hands.append(hand)


func _update_clock() -> void:
	if _clock_hands.is_empty():
		return
	var tm := Time.get_time_dict_from_system()
	var sec := float(tm.second)
	var minute := float(tm.minute) + sec / 60.0
	var hour := fmod(float(tm.hour), 12.0) + minute / 60.0
	_clock_hands[0].rotation.z = -TAU * hour / 12.0
	_clock_hands[1].rotation.z = -TAU * minute / 60.0
	_clock_hands[2].rotation.z = -TAU * sec / 60.0


# --- Tisch und Deko -----------------------------------------------------------------

func _build_table() -> void:
	var y := TableWorld.TABLE_Y
	var top := StandardMaterial3D.new()
	top.albedo_texture = preload("res://assets/models/table_wood_color.png")
	top.albedo_color = Color(0.42, 0.26, 0.16)
	top.roughness = 0.4
	top.clearcoat_enabled = true
	top.clearcoat = 0.3
	top.uv1_triplanar = true
	top.uv1_scale = Vector3(0.9, 0.9, 0.9)
	var wood := top.duplicate() as StandardMaterial3D
	wood.albedo_color = Color(0.3, 0.18, 0.1)
	_box_in(self, Vector3(TOP.x, 0.045, TOP.y), Vector3(0, y - 0.0225, 0), top)
	_box_in(self, Vector3(TOP.x - 0.1, 0.09, TOP.y - 0.1), Vector3(0, y - 0.09, 0), wood) # Zarge
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box_in(self, Vector3(0.07, y - 0.05, 0.07), Vector3(sx * (TOP.x * 0.5 - 0.1), (y - 0.05) * 0.5, sz * (TOP.y * 0.5 - 0.1)), wood)


func _build_on_table() -> void:
	var y := TableWorld.TABLE_Y
	# zusammengefaltete Zeitung hinten rechts
	var paper := _mat(Color(0.86, 0.83, 0.74), 0.9)
	var news := Node3D.new()
	news.position = Vector3(0.82, y + 0.004, -0.3)
	news.rotation.y = -0.35
	add_child(news)
	_box_in(news, Vector3(0.2, 0.008, 0.28), Vector3.ZERO, paper)
	var title := _label("ВЕЧЕРНИЙ ВОКЗАЛ", FONT_SIGN, 34, Color(0.1, 0.1, 0.1))
	title.rotation.x = -PI * 0.5
	title.position = Vector3(0, 0.0045, -0.1)
	title.shaded = true
	title.pixel_size = 0.0005 # passt auf die Zeitung
	news.add_child(title)
	var ink := _mat(Color(0.35, 0.34, 0.32), 0.9)
	for k in 9: # Textspalten
		for col in 2:
			_box_in(news, Vector3(0.078, 0.001, 0.006), Vector3(-0.045 + col * 0.09, 0.0045, -0.06 + k * 0.016), ink)
	# Fahrkarte vorne rechts
	var ticket := Node3D.new()
	ticket.position = Vector3(0.95, y + 0.0015, 0.1)
	ticket.rotation.y = 0.5
	add_child(ticket)
	_box_in(ticket, Vector3(0.06, 0.002, 0.03), Vector3.ZERO, _mat(Color(0.82, 0.74, 0.5), 0.8))
	var tl := _label("БИЛЕТ", FONT_SIGN, 18, Color(0.35, 0.15, 0.1))
	tl.rotation.x = -PI * 0.5
	tl.position.y = 0.0012
	tl.shaded = true
	tl.pixel_size = 0.0008
	ticket.add_child(tl)
	# Zuckerstückchen
	var sugar := _mat(Color(0.97, 0.96, 0.93), 0.9)
	for k in 3:
		var cube := _box_in(self, Vector3(0.014, 0.012, 0.014), Vector3(0.74 + k * 0.018, y + 0.006, -0.06 + (k % 2) * 0.012), sugar)
		cube.rotation.y = k * 0.7


func _build_benches() -> void:
	# an den Seitenwänden (zur Mitte gedreht) und hinten unter den Fenstern
	for s in [-1.0, 1.0]:
		_bench(Vector3(s * (ROOM_W * 0.5 - 0.32), 0, -0.9), -s * PI * 0.5, 2.0)
		_bench(Vector3(s * (ROOM_W * 0.5 - 0.32), 0, 1.4), -s * PI * 0.5, 2.0)
		_bench(Vector3(s * WIN_X, 0, BACK_Z + 0.5), 0.0, 1.5)
	# Koffer neben der linken hinteren Bank
	var leather := _mat(Color(0.36, 0.22, 0.12), 0.6)
	var case := _box_in(self, Vector3(0.55, 0.38, 0.18), Vector3(-WIN_X + 0.95, 0.19, BACK_Z + 0.45), leather)
	case.rotation.y = 0.25
	_box_in(case, Vector3(0.12, 0.03, 0.03), Vector3(0, 0.205, 0), _mat(Color(0.15, 0.1, 0.06), 0.5))


func _bench(pos: Vector3, rot: float, length: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = rot
	add_child(root)
	var slat := StandardMaterial3D.new()
	slat.albedo_texture = preload("res://assets/models/table_wood_color.png")
	slat.albedo_color = Color(0.55, 0.36, 0.2)
	slat.roughness = 0.55
	slat.uv1_triplanar = true
	var iron := _mat(Color(0.08, 0.09, 0.08), 0.5)
	for k in 4: # Sitzlatten
		_box_in(root, Vector3(length, 0.03, 0.08), Vector3(0, 0.45, -0.15 + k * 0.1), slat)
	for k in 3: # Lehne
		var b := _box_in(root, Vector3(length, 0.08, 0.025), Vector3(0, 0.6 + k * 0.12, -0.24 - k * 0.02), slat)
		b.rotation.x = -0.18
	var n := 3 if length > 1.6 else 2
	for k in n: # gusseiserne Seitenteile
		var x := -length * 0.5 + 0.1 + k * (length - 0.2) / (n - 1)
		_box_in(root, Vector3(0.04, 0.44, 0.04), Vector3(x, 0.22, 0.12), iron)
		_box_in(root, Vector3(0.04, 0.88, 0.04), Vector3(x, 0.44, -0.22), iron)
		_box_in(root, Vector3(0.04, 0.04, 0.4), Vector3(x, 0.42, -0.04), iron)
	for sx in [-1.0, 1.0]: # Armlehnen
		_box_in(root, Vector3(0.05, 0.03, 0.4), Vector3(sx * length * 0.5, 0.65, -0.04), iron)


## Kipjatok: Heißwasserkessel mit Hahn an der rechten Wand.
func _build_kettle() -> void:
	var tin := _mat(Color(0.55, 0.57, 0.52), 0.4)
	tin.metallic = 0.7
	var x := ROOM_W * 0.5 - 0.3
	var z := 0.25
	_box_in(self, Vector3(0.4, 0.8, 0.5), Vector3(x, 0.4, z), _mat(Color(0.2, 0.3, 0.24), 0.6)) # Sockel
	_cyl_in(self, 0.2, 0.2, 0.6, Vector3(x, 1.1, z), tin)
	_cyl_in(self, 0.21, 0.21, 0.04, Vector3(x, 1.42, z), tin)
	var tap := _cyl_in(self, 0.015, 0.015, 0.12, Vector3(x - 0.24, 0.92, z), _mat(Color(0.7, 0.55, 0.3), 0.3))
	tap.rotation.z = PI * 0.5
	var sign := _label("КИПЯТОК", FONT_SIGN, 48, Color(0.95, 0.92, 0.8))
	sign.position = Vector3(x - 0.205, 1.15, z)
	sign.rotation.y = -PI * 0.5
	sign.shaded = true
	add_child(sign)


# --- Bausteine ------------------------------------------------------------------------

func _label(text: String, font: Font, size: int, color: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font
	l.font_size = size
	l.pixel_size = 0.0012
	l.modulate = color
	l.outline_size = 0
	return l


func _plane(size: Vector2, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	return mi


func _box_in(parent: Node, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl_in(parent: Node, top: float, bottom: float, h: float, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 24
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _tex_mat(file: String, rough: float, scale: Vector3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + file)
	m.roughness = rough
	m.uv1_scale = scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m
