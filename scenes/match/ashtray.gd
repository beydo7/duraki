class_name Ashtray
extends Node3D
## Aschenbecher auf dem Tisch (ersetzt das einfache Modell aus props.glb) mit einer
## Zigarette in der Kerbe. Im Duell (interactive = true):
##   1. Klick  → anzünden (Feuerzeug, Glut, feiner Rauchfaden)
##   weitere Klicks → ein Zug: Zigarette zum Mund, Glut glüht auf, sie brennt ein Stück ab,
##                    zurück in die Kerbe, Rauchwolke vor der Kamera
##   nach PUFFS Zügen → Stummel bleibt in der Kerbe liegen, qualmt noch und geht nach
##                    SMOULDER_TIME Sekunden aus
## Mit der Schachtel daneben gibt es sofort die nächste; der Stummel wandert dann in die Mulde.

## Platz des Aschenbechers hinten links (Gegnerseite, nur Deko)
const BACK_CENTER := Vector3(-0.68, 0.8, -0.42)
const PUFFS := 5
const SMOULDER_TIME := 12.0
const PAPER_LEN := 0.062
const FILTER_LEN := 0.022
const R := 0.0045

enum State { UNLIT, LIT, BUTT, OUT, EMPTY }

var interactive := false
## Ohne Zigarette starten – sie kommt aus der Schachtel daneben (CigarettePack)
var starts_empty := false
var center := BACK_CENTER
## Richtung der Kerbe mit der Zigarette (Filter zeigt dorthin)
var notch_dir := Vector3(0.55, 0, 0.83)
var state := State.UNLIT
var _puffs := 0
var _busy := false
var _burn := 0.0 # 0 = neu, 1 = bis zum Filter
var _glow := 0.0
var _glow_target := 0.0
var _t := 0.0
var _smoulder_left := 0.0

var _cig: Node3D
var _cig_rest: Transform3D
var _paper: MeshInstance3D
var _ash: MeshInstance3D
var _ember: MeshInstance3D
var _ember_mat: StandardMaterial3D
var _light: OmniLight3D
var _area: Area3D
## Rauch aus einfachen Sprites (CPU-Partikel sind im Compatibility-Renderer unzuverlässig)
var _clouds: Array[Dictionary] = []
var _trail := false
var _trail_strength := 1.0
var _trail_timer := 0.0


func _ready() -> void:
	position = center
	_build_tray()
	_build_cigarette()
	if starts_empty:
		state = State.EMPTY
		_cig.visible = false


## Kann gerade eine neue Zigarette aus der Schachtel abgelegt werden?
func wants_cigarette() -> bool:
	return not _busy and state in [State.EMPTY, State.OUT, State.BUTT]


## Neue Zigarette fliegt von `from` (global) in die Kerbe; danach kann man sie anzünden.
func receive_cigarette(from: Transform3D) -> void:
	# der aufgerauchte Stummel bleibt in der Mulde liegen, die neue kommt in die Kerbe
	if state in [State.BUTT, State.OUT]:
		var spot: Array = STUB_SPOTS[_stubs % STUB_SPOTS.size()]
		_add_stub(spot[0] + Vector3(0, 0.0015 * floorf(_stubs / float(STUB_SPOTS.size())), 0), spot[1])
		_stubs += 1
		Sfx.play(&"card_hand_hover", 0.6, -4.0)
	state = State.EMPTY
	_busy = true
	_puffs = 0
	_set_burn(0.0)
	_ash.visible = false
	_trail = false
	_glow_target = 0.0
	_cig.visible = true
	var rest := global_transform * _cig_rest
	var lift := from.translated(Vector3(0, 0.05, 0))
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _cig.global_transform = from.interpolate_with(lift, v), 0.0, 1.0, 0.25) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void:
		var xf := lift.interpolate_with(rest, v)
		xf.origin.y += sin(v * PI) * 0.03
		_cig.global_transform = xf, 0.0, 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		Sfx.play(&"card_hand_hover", 0.8)
		_cig.transform = _cig_rest
		state = State.UNLIT
		_busy = false)


## Das alte Modell ausblenden (Teile aus props.glb).
func hide_model_parts(world: Node) -> void:
	for n in ["Aschenbecher", "Zigarette", "Zigarettenfilter", "Glut"]:
		var node := world.find_child(n, true, false) as Node3D
		if node != null:
			node.visible = false


func _process(delta: float) -> void:
	_t += delta
	_glow = lerpf(_glow, _glow_target, minf(delta * 6.0, 1.0))
	if state == State.BUTT:
		_smoulder_left -= delta
		var k := clampf(_smoulder_left / SMOULDER_TIME, 0.0, 1.0)
		_glow_target = 0.35 * k
		_trail_strength = maxf(k, 0.25) # Rauch wird dünner, je weiter die Glut ausgeht
		if _smoulder_left <= 0.0:
			state = State.OUT
			_trail = false
			_glow_target = 0.0
	_update_smoke(delta)
	var flicker := 1.0 + 0.12 * sin(_t * 9.0) + 0.06 * sin(_t * 23.0)
	var g := _glow * flicker
	_ember_mat.emission_energy_multiplier = 0.2 + g * 6.0
	_ember_mat.albedo_color = Color(0.25, 0.12, 0.06).lerp(Color(1.0, 0.45, 0.12), clampf(g, 0, 1))
	_light.light_energy = g * 0.5
	_light.visible = g > 0.02


# --- Aufbau -------------------------------------------------------------------------------

func _build_tray() -> void:
	var metal := _mat(Color(0.3, 0.2, 0.11), 0.38, 0.85)
	var bright := _mat(Color(0.55, 0.4, 0.22), 0.25, 0.9)
	var well := _mat(Color(0.05, 0.045, 0.045), 0.9)
	var ash := _mat(Color(0.42, 0.41, 0.39), 1.0)
	# schwerer Messingkörper
	var body := CylinderMesh.new()
	body.top_radius = 0.066
	body.bottom_radius = 0.071
	body.height = 0.022
	body.radial_segments = 40
	_mesh(body, metal, Vector3(0, 0.011, 0))
	# Mulde (dunkel) und Rand (poliert)
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.051
	bowl.bottom_radius = 0.047
	bowl.height = 0.003
	bowl.radial_segments = 40
	_mesh(bowl, well, Vector3(0, 0.0215, 0))
	var rim := TorusMesh.new()
	rim.inner_radius = 0.05
	rim.outer_radius = 0.067
	rim.rings = 40
	rim.ring_segments = 12
	var rim_node := _mesh(rim, bright, Vector3(0, 0.022, 0))
	rim_node.scale = Vector3(1, 0.45, 1)
	# drei Kerben im Rand
	for k in 3:
		var dir := notch_dir.normalized().rotated(Vector3.UP, k * TAU / 3.0)
		var notch := BoxMesh.new()
		notch.size = Vector3(0.011, 0.006, 0.022)
		var n := _mesh(notch, well, dir * 0.059 + Vector3(0, 0.0245, 0))
		n.basis = Basis.looking_at(dir, Vector3.UP)
	# Asche und ein alter Stummel
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 9:
		var s := SphereMesh.new()
		s.radius = rng.randf_range(0.006, 0.012)
		s.height = s.radius * 0.7
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.032)
		_mesh(s, ash, Vector3(cos(a) * r, 0.0235, sin(a) * r))
	_add_stub(Vector3(-0.018, 0.027, -0.012), 2.2)


## Ausgedrückter Stummel in der Mulde (Filter, zerknicktes Papier, schwarze Spitze).
func _add_stub(pos: Vector3, yaw: float) -> void:
	var old := Node3D.new()
	old.position = pos
	old.rotation = Vector3(0.0, yaw, 0.15)
	add_child(old)
	_piece(old, 0.014, 0.0, _mat(Color(0.78, 0.5, 0.25), 0.8)) # Filter
	_piece(old, 0.008, -0.014, Cosmetics.cig_mat(&"stub")) # zerknicktes Papier
	var tip := SphereMesh.new()
	tip.radius = R
	tip.height = R * 1.4
	var tipn := _mesh(tip, _mat(Color(0.15, 0.14, 0.14), 1.0), Vector3(-0.014, 0, 0))
	remove_child(tipn)
	old.add_child(tipn)


## Plätze für aufgerauchte Stummel (der erste liegt schon von Anfang an da)
const STUB_SPOTS := [
	[Vector3(0.016, 0.027, 0.014), 0.6],
	[Vector3(0.022, 0.027, -0.018), 4.1],
	[Vector3(-0.006, 0.027, 0.028), 1.5],
	[Vector3(-0.026, 0.027, 0.012), 3.0],
	[Vector3(0.002, 0.027, -0.03), 5.2],
]
var _stubs := 0


func _build_cigarette() -> void:
	_cig = Node3D.new()
	add_child(_cig)
	# lokale X-Achse: von der Glut (x=0) zum Filter
	var dir := notch_dir.normalized()
	var tip_pos := dir * 0.02 + Vector3(0, 0.026, 0)
	# Filter zeigt nach außen und liegt leicht angehoben in der Kerbe
	_cig_rest = Transform3D(_axis_basis(dir + Vector3(0, 0.12, 0), Vector3.UP), tip_pos)
	_cig.transform = _cig_rest

	var paper_mat := Cosmetics.cig_mat(&"paper") # Deck-Belohnung: farbiges Papier
	var filter_mat := _mat(Color(0.82, 0.55, 0.28), 0.7)
	_paper = _piece(_cig, PAPER_LEN, PAPER_LEN * 0.5, paper_mat)
	_piece(_cig, FILTER_LEN, PAPER_LEN + FILTER_LEN * 0.5, filter_mat)
	var band := _piece(_cig, 0.002, PAPER_LEN + 0.001, Cosmetics.cig_mat(&"band"))
	band.scale = Vector3(1.04, 1, 1.04)
	_ash = _piece(_cig, 0.006, 0.0, _mat(Color(0.5, 0.49, 0.47), 1.0))
	_ash.visible = false
	_ember_mat = _mat(Color(0.25, 0.12, 0.06), 0.9)
	_ember_mat.emission_enabled = true
	_ember_mat.emission = Color(1.0, 0.35, 0.08)
	_ember_mat.emission_energy_multiplier = 0.2
	_ember = _piece(_cig, 0.003, 0.0, _ember_mat)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.45, 0.15)
	_light.omni_range = 0.25
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_cig.add_child(_light)
	_set_burn(0.0)

	_area = Area3D.new()
	_area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(PAPER_LEN + FILTER_LEN + 0.02, 0.03, 0.03)
	shape.shape = box
	shape.position = Vector3((PAPER_LEN + FILTER_LEN) * 0.5, 0, 0)
	_area.add_child(shape)
	_cig.add_child(_area)
	_area.input_event.connect(_on_input)


## Zylinder entlang der lokalen X-Achse (Länge len, Mitte bei x).
func _piece(parent: Node3D, len: float, x: float, mat: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = R
	c.bottom_radius = R
	c.height = len
	c.radial_segments = 14
	var m := MeshInstance3D.new()
	m.mesh = c
	m.material_override = mat
	m.rotation = Vector3(0, 0, PI / 2.0)
	m.position = Vector3(x, 0, 0)
	parent.add_child(m)
	return m


## Abbrennen: Papier wird von der Glut her kürzer, Glut und Asche wandern mit.
func _set_burn(b: float) -> void:
	_burn = clampf(b, 0.0, 1.0)
	var left := PAPER_LEN * (1.0 - 0.85 * _burn)
	var start := PAPER_LEN - left
	_paper.scale = Vector3(1, left / PAPER_LEN, 1)
	_paper.position.x = start + left * 0.5
	_ember.position.x = start
	_ash.position.x = start - 0.003
	_light.position = Vector3(start - 0.01, 0.01, 0)


# --- Bedienung ----------------------------------------------------------------------------

func _on_input(_cam: Node, event: InputEvent, _p: Vector3, _n: Vector3, _i: int) -> void:
	if not interactive or _busy:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	get_viewport().set_input_as_handled()
	match state:
		State.UNLIT:
			_light_up()
		State.LIT:
			_puff()


func _light_up() -> void:
	_busy = true
	Sfx.play(&"lighter")
	# Flamme: kurzes helles Flackern, dann glimmt die Spitze
	var tw := create_tween()
	tw.tween_interval(0.12)
	tw.tween_callback(func() -> void: _glow_target = 2.2)
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void:
		_glow_target = 0.45
		_ash.visible = true
		_trail = true
		state = State.LIT
		_busy = false)


func _puff() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_busy = true
	_puffs += 1
	var last := _puffs >= PUFFS
	var cam_xf := cam.global_transform
	# Zigarette vor den Mund, Filter zur Kamera
	var mouth := cam_xf.origin - cam_xf.basis.z * 0.16 - cam_xf.basis.y * 0.075 + cam_xf.basis.x * 0.05
	var face := _axis_basis(cam_xf.basis.z * 0.9 + cam_xf.basis.x * 0.3 - cam_xf.basis.y * 0.12, cam_xf.basis.y)
	var at_mouth := Transform3D(face, mouth - face.x * (PAPER_LEN + FILTER_LEN) * 0.95)
	var rest_global := global_transform * _cig_rest
	_trail = false # kein Rauchfaden direkt vor der Kamera
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _cig.global_transform = rest_global.interpolate_with(at_mouth, v),
		0.0, 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		Sfx.play(&"inhale", randf_range(0.95, 1.05))
		_glow_target = 1.8
		_ash.visible = false)
	tw.tween_method(func(v: float) -> void: _set_burn(v), _burn, float(_puffs) / PUFFS, 1.0)
	tw.tween_callback(func() -> void:
		_glow_target = 0.45
		_ash.visible = true)
	# zurück in die Kerbe – auch der aufgerauchte Stummel bleibt dort liegen
	tw.tween_method(func(v: float) -> void: _cig.global_transform = at_mouth.interpolate_with(rest_global, v),
		0.0, 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		Sfx.play(&"exhale")
		_exhale_cloud(cam)
		_trail = true
		if last:
			Run.cigarettes_smoked += 1
			Profile.add_cigarette(Run.cigarettes_smoked) # Erfolge Raucher / Kettenraucher
			state = State.BUTT
			_smoulder_left = SMOULDER_TIME
			_ash.visible = false
		_busy = false)


## Rauchwolke vor der Kamera (Ausatmen): ein paar Wölkchen, die in den Raum ziehen.
func _exhale_cloud(cam: Camera3D) -> void:
	var xf := cam.global_transform
	var origin := xf.origin - xf.basis.z * 0.38 - xf.basis.y * 0.07
	for i in 9:
		var dir := (-xf.basis.z + xf.basis.x * randf_range(-0.35, 0.35) + xf.basis.y * randf_range(0.0, 0.35)).normalized()
		_spawn_puff(origin + dir * randf_range(0.0, 0.05), dir * randf_range(0.1, 0.2), 0.07, 0.3,
			randf_range(1.8, 2.6), 0.1)


## Rauchfaden an der Glut, Wölkchen steigen, wachsen und verblassen.
func _update_smoke(delta: float) -> void:
	if _trail and _cig != null:
		_trail_timer -= delta
		if _trail_timer <= 0.0:
			_trail_timer = randf_range(0.09, 0.15) / _trail_strength
			var tip := _cig.global_transform * Vector3(_ember.position.x, 0.004, 0)
			var drift := Vector3(sin(_t * 1.7) * 0.008, 0.045, cos(_t * 1.3) * 0.006)
			_spawn_puff(tip, drift, 0.008, 0.05, randf_range(2.0, 2.8), 0.32 * _trail_strength)
	for i in range(_clouds.size() - 1, -1, -1):
		var p: Dictionary = _clouds[i]
		p.age += delta
		var k: float = p.age / p.life
		var s: Sprite3D = p.sprite
		if k >= 1.0:
			s.queue_free()
			_clouds.remove_at(i)
			continue
		p.vel *= 1.0 - delta * 0.6
		p.vel.y += delta * 0.012
		s.global_position += p.vel * delta
		var size: float = lerpf(p.s0, p.s1, sqrt(k))
		s.scale = Vector3.ONE * size
		var fade := smoothstep(0.0, 0.12, k) * (1.0 - smoothstep(0.45, 1.0, k))
		s.modulate = Color(0.82, 0.82, 0.85, p.alpha * fade)
		s.rotation.z += delta * p.spin


func _spawn_puff(pos: Vector3, vel: Vector3, s0: float, s1: float, life: float, alpha: float) -> void:
	var s := Sprite3D.new()
	s.texture = _puff_texture()
	s.pixel_size = 1.0 / 64.0
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.transparent = true
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.top_level = true
	s.modulate = Color(0.82, 0.82, 0.85, 0.0)
	s.scale = Vector3.ONE * s0
	add_child(s)
	s.global_position = pos
	_clouds.append({"sprite": s, "age": 0.0, "life": life, "vel": vel, "s0": s0, "s1": s1,
		"alpha": alpha, "spin": randf_range(-0.6, 0.6)})


static var _puff_tex: Texture2D


static func _puff_texture() -> Texture2D:
	if _puff_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_puff_tex = t
	return _puff_tex


## Basis, deren X-Achse in Richtung x zeigt (Y möglichst nach up).
static func _axis_basis(x: Vector3, up: Vector3) -> Basis:
	var bx := x.normalized()
	var bz := bx.cross(up).normalized()
	var by := bz.cross(bx).normalized()
	return Basis(bx, by, bz)


func _mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	add_child(m)
	return m


func _mat(color: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m
