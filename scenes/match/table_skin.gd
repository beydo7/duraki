class_name TableSkin
extends Node3D
## Deck-Belohnungen am Tisch (siehe Cosmetics): Filz, Rand, Ecken-Figuren und Extras.
## Funktioniert in jedem Raum: der Raum sagt mit `table_info()`, welche Materialien Filz und
## Rand sind und wo der Rand verläuft (Umriss, Höhe, Ecken). TableWorld legt den Knoten an.

const SND_CAW := preload("res://assets/cosmetics/caw.wav")
const SND_BELLS := preload("res://assets/cosmetics/bells.wav")
const SND_HOWL := preload("res://assets/cosmetics/howl.wav")
const GOLD := Color(0.95, 0.74, 0.32)

var _t := 0.0
var _crow: Node3D
var _crow_head: Node3D
var _crow_beak: Node3D
var _next_caw := 14.0
var _bells: Array[Node3D] = []
var _flames: Array[Dictionary] = []
var _howl := false
var _restore: Array = [] # [Mesh, altes Material] – zum Zurücksetzen beim Umschalten


## Tisch-Infos für einen rechteckigen Tisch. `half` = halbe Größe der Platte,
## `frame` = eigenen Rahmen um die Platte bauen, wenn ein Rand gewählt ist (Tisch hat keinen).
static func rect_info(felt: Array, rim: Array, half: Vector2, frame: bool, lift: float) -> Dictionary:
	var h := half + (Vector2(0.025, 0.025) if frame else Vector2.ZERO)
	var outline := PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y), Vector2(-h.x, -h.y)])
	return {"felt": felt, "rim": rim, "outline": outline,
		"rim_y": TableWorld.TABLE_Y + lift + (0.015 if frame else 0.0),
		"corners": [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(-h.x, h.y), Vector2(h.x, h.y)],
		"frame": half if frame else Vector2.ZERO}


## Alles anwenden. `root` = Knoten, unter dem die Tischteile hängen (Raum oder TableWorld).
func apply(root: Node, info: Dictionary) -> void:
	var felt_id := Cosmetics.selected(&"felt")
	var rim_id := Cosmetics.selected(&"rim")
	var felt_mats: Array = info.get("felt", [])
	var rim_mats: Array = info.get("rim", [])
	if felt_id != &"":
		var m := Cosmetics.felt_material(felt_id)
		_swap(root, felt_mats, m)
		for n: MeshInstance3D in info.get("felt_nodes", []):
			_set_mat(n, m)
		_howl = Cosmetics.ITEMS[felt_id].get("howl", false)
	if rim_id != &"":
		var it: Dictionary = Cosmetics.ITEMS[rim_id]
		var m := Cosmetics.rim_material(rim_id)
		_swap(root, rim_mats, m)
		for n: MeshInstance3D in info.get("rim_nodes", []):
			_set_mat(n, m)
		var frame: Vector2 = info.get("frame", Vector2.ZERO)
		if frame != Vector2.ZERO:
			_build_frame(frame, m)
		if it.get("trim", false):
			_build_trim(info)
		if it.get("lily", false):
			_build_lilies(info)
	match Cosmetics.selected(&"corners"):
		&"corner_skulls":
			for c: Vector2 in info.corners:
				_skull(_corner_pos(info, c))
		&"corner_eagles":
			for c: Vector2 in info.corners:
				_eagle(_corner_pos(info, c))
	match Cosmetics.selected(&"extra"):
		&"extra_crow":
			var c: Vector2 = info.corners[1]
			_build_crow(Vector3(c.x * 0.82, info.rim_y, c.y))
		&"extra_bells":
			_build_bells(info)
		&"extra_fireflies":
			_build_fireflies(info)
		&"extra_green_candles":
			for i in 2:
				_candle(_extra_pos(info, i), Color(0.25, 1.0, 0.35), RoomKit.mat(Color(0.12, 0.3, 0.12), 0.7))
		&"extra_faberge":
			for i in 2:
				_faberge(_extra_pos(info, i))


## Alles wieder wie vorher (Materialien zurück) und den Knoten entfernen.
func remove() -> void:
	for p in _restore:
		if is_instance_valid(p[0]):
			(p[0] as MeshInstance3D).material_override = p[1]
	_restore.clear()
	queue_free()


func _set_mat(mi: MeshInstance3D, m: Material) -> void:
	_restore.append([mi, mi.material_override])
	mi.material_override = m


## Eine Karte wurde ausgespielt (Glöckchen klingeln).
func on_card_played() -> void:
	if _bells.is_empty():
		return
	RoomKit.play(self, SND_BELLS, -20.0, randf_range(0.95, 1.08))
	for b in _bells:
		var tw := b.create_tween()
		tw.tween_property(b, "rotation:z", randf_range(-0.6, 0.6), 0.08)
		tw.tween_property(b, "rotation:z", 0.0, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Duell gewonnen: beim Vollmond-Filz heult ein Wolf.
func on_duel_won() -> void:
	if _howl:
		RoomKit.play(self, SND_HOWL, -12.0)


func _process(delta: float) -> void:
	_t += delta
	for f in _flames:
		var k := 0.85 + 0.15 * sin(_t * 13.0 + f.phase) + 0.08 * sin(_t * 31.0 + f.phase)
		(f.node as Node3D).scale = Vector3(1.0, k, 1.0)
		(f.light as OmniLight3D).light_energy = f.energy * k
	if _crow != null:
		_crow_head.rotation.y = sin(_t * 0.7) * 0.6 + (0.5 if fmod(_t, 9.0) < 1.5 else 0.0)
		_next_caw -= delta
		if _next_caw <= 0.0:
			_next_caw = randf_range(18.0, 40.0)
			caw()


func caw() -> void:
	if _crow == null:
		return
	RoomKit.play(self, SND_CAW, -16.0)
	var tw := create_tween()
	for k in 2:
		tw.tween_property(_crow_beak, "rotation:z", -0.5, 0.06)
		tw.tween_property(_crow, "scale", Vector3(1.5, 1.62, 1.5), 0.06)
		tw.tween_interval(0.2)
		tw.tween_property(_crow_beak, "rotation:z", 0.0, 0.06)
		tw.tween_property(_crow, "scale", Vector3.ONE * 1.5, 0.06)
		tw.tween_interval(0.1)


# --- Bausteine -----------------------------------------------------------------------

func _swap(root: Node, mats: Array, m: Material) -> void:
	if mats.is_empty():
		return
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.material_override != null and mats.has(mi.material_override):
			_set_mat(mi, m)


## Position auf dem Rand an einer Ecke, `inset` m Richtung Tischmitte.
func _corner_pos(info: Dictionary, c: Vector2, inset := 0.0) -> Vector3:
	var p := c - c.normalized() * inset
	return Vector3(p.x, info.rim_y, p.y)


## Platz für Extras an den hinteren Ecken: etwas zur Mitte gerückt (Ecke bleibt frei für Figuren).
func _extra_pos(info: Dictionary, i: int) -> Vector3:
	var c: Vector2 = info.corners[i]
	return Vector3(c.x * 0.8, info.rim_y, c.y)


func _build_frame(half: Vector2, m: Material) -> void:
	var y := TableWorld.TABLE_Y
	var w := 0.05
	var h := 0.06
	for s: float in [-1.0, 1.0]:
		RoomKit.box(self, Vector3(half.x * 2.0 + w * 2.0, h, w), Vector3(0, y + 0.015 - h * 0.5, s * (half.y + w * 0.5)), m)
		RoomKit.box(self, Vector3(w, h, half.y * 2.0), Vector3(s * (half.x + w * 0.5), y + 0.015 - h * 0.5, 0), m)


func _segments(info: Dictionary) -> Array:
	var out := []
	var path: PackedVector2Array = info.outline
	for i in path.size() - 1:
		out.append([path[i], path[i + 1]])
	return out


func _build_trim(info: Dictionary) -> void:
	var gold := RoomKit.mat(GOLD, 0.28, 1.0)
	for seg in _segments(info):
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var mid := (a + b) * 0.5
		var bx := RoomKit.box(self, Vector3(a.distance_to(b) + 0.004, 0.006, 0.014), Vector3(mid.x, info.rim_y + 0.002, mid.y), gold)
		bx.rotation.y = -(b - a).angle()


## Punkte entlang des Umrisses im Abstand `step` (nur hintere Hälfte und Seiten: vorne sieht man nichts).
func _along(info: Dictionary, step: float, max_z := 0.3) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var carry := 0.0
	for seg in _segments(info):
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var len := a.distance_to(b)
		var d := step - carry
		while d <= len:
			var p := a.lerp(b, d / len)
			if p.y < max_z:
				out.append(p)
			d += step
		carry = len - (d - step)
	return out


func _build_lilies(info: Dictionary) -> void:
	var pad := RoomKit.mat(Color(0.25, 0.5, 0.2), 0.7)
	var flower := RoomKit.mat(Color(0.95, 0.65, 0.8), 0.6)
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var i := 0
	for p in _along(info, 0.33):
		var c := RoomKit.cyl(self, 0.03, 0.03, 0.004, Vector3(p.x, info.rim_y + 0.002, p.y), pad, 14)
		c.rotation.y = r.randf() * TAU
		c.scale = Vector3.ONE * r.randf_range(0.8, 1.2)
		if i % 3 == 1:
			for k in 5:
				var a := TAU * k / 5.0
				var petal := RoomKit.sphere(self, 0.008, Vector3(p.x + cos(a) * 0.009, info.rim_y + 0.01, p.y + sin(a) * 0.009), flower, Vector3(1.0, 0.6, 1.0))
				petal.rotation.y = -a
		i += 1


func _skull(pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = randf_range(-0.3, 0.3)
	add_child(root)
	var bone := RoomKit.mat(Color(0.9, 0.86, 0.74), 0.6)
	var dark := RoomKit.mat(Color(0.05, 0.04, 0.04), 0.9)
	RoomKit.sphere(root, 0.032, Vector3(0, 0.035, 0), bone, Vector3(1.0, 0.95, 1.1))
	RoomKit.box(root, Vector3(0.036, 0.018, 0.03), Vector3(0, 0.01, 0.012), bone) # Kiefer
	for s: float in [-1.0, 1.0]:
		RoomKit.sphere(root, 0.009, Vector3(s * 0.012, 0.035, 0.029), dark)
	RoomKit.sphere(root, 0.005, Vector3(0, 0.022, 0.033), dark, Vector3(1.0, 1.3, 1.0))
	for k in 4: # Zähne
		RoomKit.box(root, Vector3(0.005, 0.006, 0.002), Vector3(-0.009 + k * 0.006, 0.012, 0.0275), RoomKit.mat(Color(0.95, 0.93, 0.85), 0.5))


func _eagle(pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var gold := RoomKit.mat(GOLD, 0.25, 1.0)
	RoomKit.cyl(root, 0.022, 0.026, 0.012, Vector3(0, 0.006, 0), gold, 16) # Sockel
	RoomKit.sphere(root, 0.02, Vector3(0, 0.035, 0), gold, Vector3(0.8, 1.3, 0.6)) # Körper
	for s: float in [-1.0, 1.0]:
		var neck := RoomKit.cyl(root, 0.005, 0.007, 0.03, Vector3(s * 0.012, 0.062, 0), gold, 8)
		neck.rotation.z = -s * 0.5
		RoomKit.sphere(root, 0.009, Vector3(s * 0.022, 0.078, 0), gold)
		var beak := RoomKit.cyl(root, 0.0, 0.004, 0.012, Vector3(s * 0.032, 0.077, 0), gold, 6)
		beak.rotation.z = -s * PI * 0.5
		var wing := RoomKit.box(root, Vector3(0.04, 0.035, 0.004), Vector3(s * 0.03, 0.05, -0.004), gold)
		wing.rotation.z = s * 0.6
		RoomKit.cyl(root, 0.004, 0.005, 0.008, Vector3(s * 0.022, 0.09, 0), gold, 8) # Krönchen
	RoomKit.cyl(root, 0.006, 0.008, 0.012, Vector3(0, 0.098, 0), gold, 8) # große Krone
	RoomKit.sphere(root, 0.004, Vector3(0, 0.108, 0), RoomKit.glow(Color(0.9, 0.1, 0.15), 1.0))


func _build_crow(pos: Vector3) -> void:
	_crow = Node3D.new()
	_crow.position = pos
	_crow.rotation.y = -2.3 # schaut schräg zur Tischmitte / zum Spieler
	_crow.scale = Vector3.ONE * 1.5
	add_child(_crow)
	var black := RoomKit.mat(Color(0.05, 0.05, 0.07), 0.35, 0.2)
	var beak_m := RoomKit.mat(Color(0.2, 0.2, 0.22), 0.4)
	for s: float in [-1.0, 1.0]: # Beine
		RoomKit.cyl(_crow, 0.0025, 0.0025, 0.03, Vector3(0, 0.015, s * 0.012), beak_m, 6)
	RoomKit.sphere(_crow, 0.045, Vector3(0, 0.07, 0), black, Vector3(1.4, 1.0, 0.85)) # Körper
	var tail := RoomKit.box(_crow, Vector3(0.07, 0.008, 0.04), Vector3(-0.08, 0.06, 0), black)
	tail.rotation.z = 0.35
	for s: float in [-1.0, 1.0]: # Flügel
		var w := RoomKit.sphere(_crow, 0.04, Vector3(-0.01, 0.075, s * 0.033), black, Vector3(1.5, 0.7, 0.3))
		w.rotation.z = 0.25
	_crow_head = Node3D.new()
	_crow_head.position = Vector3(0.055, 0.115, 0)
	_crow.add_child(_crow_head)
	RoomKit.sphere(_crow_head, 0.026, Vector3.ZERO, black)
	for s: float in [-1.0, 1.0]:
		RoomKit.sphere(_crow_head, 0.005, Vector3(0.012, 0.007, s * 0.019), RoomKit.glow(Color(0.9, 0.75, 0.2), 0.8))
	_crow_beak = Node3D.new()
	_crow_beak.position = Vector3(0.02, -0.002, 0)
	_crow_head.add_child(_crow_beak)
	var beak := RoomKit.cyl(_crow_beak, 0.0, 0.009, 0.04, Vector3(0.02, 0, 0), beak_m, 8)
	beak.rotation.z = -PI * 0.5


func _build_bells(info: Dictionary) -> void:
	var gold := RoomKit.mat(GOLD, 0.25, 1.0)
	var ribbon := [RoomKit.mat(Color(0.75, 0.1, 0.1), 0.7), RoomKit.mat(Color(0.85, 0.7, 0.15), 0.7)]
	var i := 0
	for p in _along(info, 0.22):
		var b := Node3D.new()
		b.position = Vector3(p.x, info.rim_y + 0.002, p.y)
		add_child(b)
		RoomKit.cyl(b, 0.005, 0.005, 0.02, Vector3(0, 0.01, 0), ribbon[i % 2], 6)
		RoomKit.sphere(b, 0.019, Vector3(0, 0.038, 0), gold)
		RoomKit.box(b, Vector3(0.026, 0.003, 0.005), Vector3(0, 0.032, 0.017), RoomKit.mat(Color(0.1, 0.08, 0.05), 0.6)) # Schlitz
		_bells.append(b)
		i += 1


func _build_fireflies(info: Dictionary) -> void:
	var c: Vector2 = info.corners[3]
	var p := CPUParticles3D.new()
	p.position = Vector3(0, TableWorld.TABLE_Y + 0.4, -0.1)
	p.amount = 26
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(absf(c.x) + 0.2, 0.3, absf(c.y))
	p.direction = Vector3.UP
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.02
	p.initial_velocity_max = 0.06
	p.angular_velocity_min = 0.0
	var m := SphereMesh.new()
	m.radius = 0.005
	m.height = 0.01
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.material = mat
	p.mesh = m
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.55, 0.75, 1.0])
	g.colors = PackedColorArray([Color(0.8, 1.0, 0.3, 0.0), Color(0.8, 1.0, 0.3, 1.0), Color(0.8, 1.0, 0.3, 0.2),
		Color(0.8, 1.0, 0.3, 1.0), Color(0.8, 1.0, 0.3, 0.3), Color(0.8, 1.0, 0.3, 0.0)])
	p.color_ramp = g
	add_child(p)


func _candle(pos: Vector3, flame_col: Color, wax: Material) -> void:
	RoomKit.cyl(self, 0.016, 0.018, 0.11, pos + Vector3(0, 0.055, 0), wax, 14)
	RoomKit.cyl(self, 0.024, 0.028, 0.008, pos + Vector3(0, 0.004, 0), RoomKit.mat(Color(0.25, 0.22, 0.2), 0.4, 0.8), 14)
	_flame(pos + Vector3(0, 0.122, 0), flame_col)


func _flame(pos: Vector3, col: Color) -> void:
	var f := Node3D.new()
	f.position = pos
	add_child(f)
	RoomKit.sphere(f, 0.008, Vector3(0, 0.008, 0), RoomKit.glow(col, 4.0), Vector3(1.0, 2.0, 1.0))
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, 0.03, 0)
	l.light_color = col
	l.light_energy = 0.5
	l.omni_range = 0.7
	add_child(l)
	_flames.append({"node": f, "light": l, "energy": 0.5, "phase": randf() * TAU})


func _faberge(pos: Vector3) -> void:
	var gold := RoomKit.mat(GOLD, 0.25, 1.0)
	var enamel := RoomKit.mat(Color(0.55, 0.05, 0.12), 0.15, 0.3)
	enamel.clearcoat_enabled = true
	RoomKit.cyl(self, 0.02, 0.028, 0.012, pos + Vector3(0, 0.006, 0), gold, 16) # Fuß
	RoomKit.cyl(self, 0.006, 0.008, 0.03, pos + Vector3(0, 0.027, 0), gold, 10)
	var egg := pos + Vector3(0, 0.075, 0)
	RoomKit.sphere(self, 0.03, egg, enamel, Vector3(1.0, 1.3, 1.0))
	for k in 3: # Goldbänder
		var band := RoomKit.torus(self, 0.031 - abs(k - 1) * 0.006, 0.002, egg + Vector3(0, (k - 1) * 0.022, 0), gold)
		band.scale = Vector3(1, 1, 1)
	for k in 6: # Edelsteine
		var a := TAU * k / 6.0
		RoomKit.sphere(self, 0.004, egg + Vector3(cos(a) * 0.03, 0.0, sin(a) * 0.03),
			RoomKit.glow([Color(0.2, 0.5, 1.0), Color(0.1, 0.9, 0.4), Color(1, 1, 1)][k % 3], 1.2))
	RoomKit.cyl(self, 0.012, 0.012, 0.006, egg + Vector3(0, 0.04, 0), gold, 12) # Tülle
	RoomKit.cyl(self, 0.008, 0.008, 0.05, egg + Vector3(0, 0.068, 0), RoomKit.mat(Color(0.95, 0.92, 0.85), 0.6), 10)
	_flame(egg + Vector3(0, 0.095, 0), Color(1.0, 0.7, 0.3))
