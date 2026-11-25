class_name SlotMachine
extends Node3D
## Alter Spielautomat („einarmiger Bandit“) für das Casino: Holzsockel, rotes Gehäuse
## mit Chromkanten, runder Kopf mit Lauflichtern, drei Walzen hinter Glas und ein
## großer Hebel an der rechten Seite. Kein Touchscreen.
##
## `interactive`: Klick auf den Automaten zieht den Hebel, die Walzen drehen sich und
## halten nacheinander an. Drei Siebenen (ca. 1 %) → Glocke, Münzen, die Lichter blinken
## und der geheime Erfolg „Jackpot“. Ändert sonst nichts am Spiel.

signal pulled
signal jackpot

const REELS := preload("res://assets/rooms/casino/reels.png")
const SND_PULL := preload("res://assets/rooms/casino/slot_pull.wav")
const SND_SPIN := preload("res://assets/rooms/casino/slot_spin.wav")
const SND_WIN := preload("res://assets/rooms/casino/slot_win.wav")
const SYMBOLS := 5 # 7, Kirsche, Glocke, BAR, Zitrone (wie im Walzenband)
## Drei Siebenen: etwa 1 von 100 Zügen (Erfolg „Jackpot“)
const JACKPOT_CHANCE := 0.01

const W := 0.46 # Breite des Gehäuses
const D := 0.36 # Tiefe
const BASE_H := 0.55 # Sockel
const BODY_H := 0.78
const REEL_Y := BASE_H + 0.5
const REEL_R := 0.1

var interactive := false
var body_color := Color(0.62, 0.06, 0.08)

var _reels: Array[Node3D] = []
var _lever: Node3D
var _bulbs: Array[StandardMaterial3D] = []
var _busy := false
var _t := 0.0
var _flash := 0.0


func _ready() -> void:
	_build()
	# Walzen zufällig stehen lassen
	for r in _reels:
		r.rotation.x = _symbol_angle(randi() % SYMBOLS)


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(_flash - delta * 0.25, 0.0)
	# Lauflicht im Kopf: jede dritte Birne hell, wandert weiter; beim Gewinn blinkt alles
	for i in _bulbs.size():
		var on := (int(_t * 6.0) + i) % 3 == 0
		if _flash > 0.0:
			on = int(_t * 10.0) % 2 == 0
		_bulbs[i].emission_energy_multiplier = 3.2 if on else 0.5


# --- Aufbau ---------------------------------------------------------------------

func _build() -> void:
	var wood := _mat(Color(0.2, 0.1, 0.05), 0.55)
	wood.albedo_texture = preload("res://assets/models/table_wood_color.png")
	wood.uv1_triplanar = true
	wood.uv1_scale = Vector3(2, 2, 2)
	var chrome := _mat(Color(0.86, 0.86, 0.9), 0.18)
	chrome.metallic = 1.0
	var gold := _mat(Color(0.92, 0.7, 0.3), 0.3)
	gold.metallic = 1.0
	var red := _mat(body_color, 0.35)
	red.clearcoat_enabled = true
	red.clearcoat = 0.8
	var dark := _mat(Color(0.03, 0.03, 0.04), 0.6)

	# Sockel mit Messingleiste
	_box(Vector3(W + 0.06, BASE_H, D + 0.06), Vector3(0, BASE_H * 0.5, 0), wood)
	_box(Vector3(W + 0.07, 0.02, D + 0.07), Vector3(0, BASE_H, 0), gold)
	# Gehäuse
	var top := BASE_H + BODY_H
	_box(Vector3(W, BODY_H, D), Vector3(0, BASE_H + BODY_H * 0.5, 0), red)
	for s in [-1.0, 1.0]: # Chromkanten
		_box(Vector3(0.022, BODY_H, 0.022), Vector3(s * W * 0.5, BASE_H + BODY_H * 0.5, D * 0.5), chrome)
	# runder Kopf
	var head := MeshInstance3D.new()
	var hc := CylinderMesh.new()
	hc.top_radius = W * 0.5
	hc.bottom_radius = W * 0.5
	hc.height = D
	hc.radial_segments = 32
	head.mesh = hc
	head.material_override = red
	head.rotation.x = PI * 0.5
	head.position = Vector3(0, top, 0)
	add_child(head)
	var arch := MeshInstance3D.new() # Chrombogen um den Kopf
	var pts := PackedVector3Array()
	for i in 33:
		var a := PI * i / 32.0
		pts.append(Vector3(cos(a) * (W * 0.5 + 0.004), sin(a) * (W * 0.5 + 0.004), 0))
	arch.mesh = _arc_tube(pts, 0.011)
	var chrome2 := chrome.duplicate() as StandardMaterial3D
	chrome2.cull_mode = BaseMaterial3D.CULL_DISABLED
	arch.material_override = chrome2
	arch.position = Vector3(0, top, D * 0.5)
	add_child(arch)
	# Schild im Kopf
	var plate := _box(Vector3(W * 0.78, 0.1, 0.01), Vector3(0, top + 0.06, D * 0.5 + 0.002), dark)
	plate.name = "Schild"
	var sign := Label3D.new()
	sign.text = "DURAKI"
	sign.font = preload("res://assets/fonts/RussoOne-Regular.ttf")
	sign.font_size = 64
	sign.pixel_size = 0.00075
	sign.modulate = Color(1.6, 1.15, 0.4)
	sign.outline_size = 8
	sign.outline_modulate = Color(0.5, 0.08, 0.04)
	sign.position = Vector3(0, top + 0.06, D * 0.5 + 0.009)
	add_child(sign)
	# Lauflicht-Birnen im Bogen
	var bm := SphereMesh.new()
	bm.radius = 0.011
	bm.height = 0.022
	for i in 13:
		var a := PI * (0.06 + 0.88 * i / 12.0)
		var b := MeshInstance3D.new()
		b.mesh = bm
		var m := _mat(Color(1, 0.85, 0.5), 0.3)
		m.emission_enabled = true
		m.emission = Color(1, 0.72, 0.3)
		b.material_override = m
		_bulbs.append(m)
		b.position = Vector3(cos(a) * (W * 0.5 - 0.03), top + sin(a) * (W * 0.5 - 0.03), D * 0.5 + 0.012)
		add_child(b)

	# Walzenfenster: tiefer schwarzer Rahmen, drei Walzen dahinter, Glas davor.
	# Die Walzen ragen etwas aus dem Gehäuse; der Rahmen verdeckt alles außer dem Fenster.
	var win_w := W * 0.8
	var win_h := 0.17
	var fz := D * 0.5
	var depth := 0.065
	_box(Vector3(win_w + 0.06, 0.09, depth), Vector3(0, REEL_Y + win_h * 0.5 + 0.045, fz + depth * 0.5), dark)
	_box(Vector3(win_w + 0.06, 0.09, depth), Vector3(0, REEL_Y - win_h * 0.5 - 0.045, fz + depth * 0.5), dark)
	for s in [-1.0, 1.0]:
		_box(Vector3(0.03, win_h, depth), Vector3(s * (win_w * 0.5 + 0.015), REEL_Y, fz + depth * 0.5), dark)
		_box(Vector3(win_w + 0.08, 0.016, 0.012), Vector3(0, REEL_Y + s * (win_h * 0.5 + 0.008), fz + depth + 0.002), chrome)
		_box(Vector3(0.016, win_h + 0.03, 0.012), Vector3(s * (win_w * 0.5 + 0.008), REEL_Y, fz + depth + 0.002), chrome)
	var reel_mat := _mat(Color.WHITE, 0.45)
	reel_mat.albedo_texture = REELS
	reel_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var reel_mesh := _reel_mesh(REEL_R, win_w / 3.0 - 0.012)
	for i in 3:
		var r := MeshInstance3D.new()
		r.mesh = reel_mesh
		r.material_override = reel_mat
		r.position = Vector3((i - 1) * win_w / 3.0, REEL_Y, fz + depth - 0.012 - REEL_R)
		add_child(r)
		_reels.append(r)
		if i > 0: # Trennstege
			_box(Vector3(0.006, win_h, 0.02), Vector3((i - 1.5) * win_w / 3.0, REEL_Y, fz + depth - 0.008), dark)
	var glass := _box(Vector3(win_w, win_h, 0.004), Vector3(0, REEL_Y, fz + depth - 0.002), _glass())
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Gewinnlinie
	_box(Vector3(win_w, 0.003, 0.002), Vector3(0, REEL_Y, fz + depth + 0.001), _mat(Color(0.9, 0.1, 0.1), 0.5))
	# Münzschlitz, Knöpfe und Auffangschale
	_box(Vector3(0.05, 0.008, 0.004), Vector3(W * 0.28, REEL_Y - 0.16, fz + 0.003), dark)
	_box(Vector3(W * 0.7, 0.06, 0.08), Vector3(0, BASE_H + 0.06, fz + 0.035), chrome)
	_box(Vector3(W * 0.6, 0.04, 0.06), Vector3(0, BASE_H + 0.075, fz + 0.042), dark)
	var knob := SphereMesh.new()
	knob.radius = 0.016
	knob.height = 0.02
	for k in 3:
		var bt := MeshInstance3D.new()
		bt.mesh = knob
		bt.material_override = _mat([Color(0.9, 0.2, 0.1), Color(0.95, 0.75, 0.2), Color(0.2, 0.6, 0.3)][k], 0.3)
		bt.position = Vector3(-W * 0.25 + k * 0.05, REEL_Y - 0.17, fz + 0.004)
		add_child(bt)

	# Großer Hebel rechts: Lager, Chromstange, roter Knauf
	_lever = Node3D.new()
	_lever.position = Vector3(W * 0.5 + 0.035, REEL_Y - 0.08, 0.02)
	add_child(_lever)
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.035
	hm.bottom_radius = 0.035
	hm.height = 0.05
	hub.mesh = hm
	hub.material_override = chrome
	hub.rotation.z = PI * 0.5
	_lever.add_child(hub)
	var rod := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.011
	rm.bottom_radius = 0.014
	rm.height = 0.42
	rod.mesh = rm
	rod.material_override = chrome
	rod.position = Vector3(0.012, 0.21, 0)
	_lever.add_child(rod)
	var ball := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.04
	bs.height = 0.08
	ball.mesh = bs
	var bmat := _mat(Color(0.8, 0.04, 0.05), 0.2)
	bmat.clearcoat_enabled = true
	ball.material_override = bmat
	ball.position = Vector3(0.012, 0.44, 0)
	_lever.add_child(ball)

	# Klickfläche über den ganzen Automaten
	var area := Area3D.new()
	area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(W + 0.2, BASE_H + BODY_H + W * 0.5, D + 0.1)
	shape.shape = box
	shape.position = Vector3(0.04, box.size.y * 0.5, 0)
	area.add_child(shape)
	add_child(area)
	area.input_event.connect(_on_input)


## Walze als Zylindermantel um die x-Achse; v läuft einmal rundherum (5 Symbole).
static func _reel_mesh(radius: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 40
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p := []
		for a in [a0, a1]:
			p.append(Vector3(-width * 0.5, sin(a) * radius, cos(a) * radius))
			p.append(Vector3(width * 0.5, sin(a) * radius, cos(a) * radius))
		var v0 := float(i) / n
		var v1 := float(i + 1) / n
		# v gespiegelt, damit die Symbole im Fenster aufrecht und lesbar stehen
		var quad := [[p[0], Vector2(0, 1 - v0)], [p[3], Vector2(1, 1 - v1)], [p[1], Vector2(1, 1 - v0)],
			[p[0], Vector2(0, 1 - v0)], [p[2], Vector2(0, 1 - v1)], [p[3], Vector2(1, 1 - v1)]]
		for q in quad:
			var pos: Vector3 = q[0]
			st.set_normal(Vector3(0, pos.y, pos.z).normalized())
			st.set_uv(q[1])
			st.add_vertex(pos)
	st.generate_tangents()
	return st.commit()


## Röhre entlang eines Bogens (für den Chrombogen am Kopf).
static func _arc_tube(path: PackedVector3Array, radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 10
	var rings: Array = []
	for i in path.size():
		var t := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var a1 := t.cross(Vector3.FORWARD).normalized()
		var a2 := t.cross(a1).normalized()
		var ring := []
		for k in sides:
			var ang := TAU * k / sides
			var nrm := a1 * cos(ang) + a2 * sin(ang)
			ring.append([path[i] + nrm * radius, nrm])
		rings.append(ring)
	for i in path.size() - 1:
		for k in sides:
			var k1 := (k + 1) % sides
			for v in [rings[i][k], rings[i + 1][k], rings[i + 1][k1], rings[i][k], rings[i + 1][k1], rings[i][k1]]:
				st.set_normal(v[1])
				st.add_vertex(v[0])
	return st.commit()


## Drehwinkel, bei dem Symbol `k` mittig im Fenster steht.
static func _symbol_angle(k: int) -> float:
	return TAU * (k + 4.5) / SYMBOLS


# --- Spielen ----------------------------------------------------------------------

func _on_input(_cam: Node, event: InputEvent, _p: Vector3, _n: Vector3, _i: int) -> void:
	if not interactive or _busy:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		pull()


## Hebel ziehen, Walzen drehen lassen.
func pull() -> void:
	if _busy:
		return
	_busy = true
	pulled.emit()
	_play(SND_PULL, -6.0)
	var tw := create_tween()
	tw.tween_property(_lever, "rotation:x", deg_to_rad(75.0), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_spin)
	tw.tween_property(_lever, "rotation:x", 0.0, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _spin() -> void:
	_play(SND_SPIN, -8.0)
	var win := randf() < JACKPOT_CHANCE
	var result: Array[int] = []
	for i in 3:
		result.append(0 if win else randi() % SYMBOLS)
	if not win and result[0] == 0 and result[1] == 0 and result[2] == 0:
		result[2] = 1 + randi() % (SYMBOLS - 1) # Drei Siebenen gibt es nur über den Zufall oben
	for i in 3:
		var r := _reels[i]
		var start := fposmod(r.rotation.x, TAU)
		r.rotation.x = start
		var target := _symbol_angle(result[i]) + TAU * (4 + i * 2)
		while target < start + TAU * 3:
			target += TAU
		var tw := create_tween()
		tw.tween_property(r, "rotation:x", target, 1.0 + i * 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if i == 2:
			tw.tween_callback(func() -> void:
				_busy = false
				if win:
					_flash = 1.0
					_play(SND_WIN, -6.0)
					if interactive:
						Profile.unlock_achievement(&"jackpot")
					jackpot.emit())


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


# --- Bausteine ------------------------------------------------------------------

func _box(size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	add_child(mi)
	return mi


static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


static func _glass() -> StandardMaterial3D:
	var g := StandardMaterial3D.new()
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.albedo_color = Color(0.8, 0.9, 1.0, 0.12)
	g.roughness = 0.05
	g.metallic_specular = 1.0
	return g
