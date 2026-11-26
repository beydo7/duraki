class_name TableSkin
extends Node3D
## Deck-Belohnungen am Tisch (siehe Cosmetics): Filz, Rand, Ecken-Figuren und Extras.
## Funktioniert in jedem Raum: der Raum sagt mit `table_info()`, welche Materialien Filz und
## Rand sind und wo der Rand verläuft (Umriss, Höhe, Ecken). TableWorld legt den Knoten an.

const SND_CAW := preload("res://assets/cosmetics/caw.wav")
const SND_BELLS := preload("res://assets/cosmetics/bells.wav")
const SND_HOWL := preload("res://assets/cosmetics/howl.wav")
## Vorlagen aus Blender (art/blender/cosmetics.py): Figuren, Extras, Rahmenteile
const MODEL := preload("res://assets/cosmetics/cosmetics.glb")
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
var _lib: Node # instanzierte Vorlagen, nur während apply()


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
	_lib = MODEL.instantiate()
	_apply(root, info)
	_lib.free()
	_lib = null


## Kopie einer Vorlage aus cosmetics.glb; mats = { Materialname aus Blender: Material }.
func _part(part_name: String, parent: Node, mats := {}) -> Node3D:
	return RoomKit.part(_lib, part_name, parent, mats)


func _apply(root: Node, info: Dictionary) -> void:
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


## Rahmen um eine Platte ohne eigenen Rand (5 cm breit, 6 cm hoch wie bisher, jetzt mit Profil):
## vier Eckstücke auf Gehrung und dazwischen vier Leisten, die auf die Länge gestreckt werden.
func _build_frame(half: Vector2, m: Material) -> void:
	var y := TableWorld.TABLE_Y
	var arm := 0.07 # Schenkellänge des Eckstücks (FRAME_ARM in cosmetics.py)
	# Vorlage: Ecke vorne rechts, Leiste mit Außenseite nach +Z
	var turns := [0.0, PI * 0.5, PI, -PI * 0.5]
	var corners := [Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1)]
	var sides := [Vector3(0, half.x, half.y), Vector3(half.x, half.y, 0), Vector3(0, half.x, -half.y), Vector3(-half.x, half.y, 0)]
	for i in 4:
		var corner := _part("Tischrahmen_Ecke", self) as MeshInstance3D
		corner.material_override = m
		corner.position = Vector3(corners[i].x * half.x, y, corners[i].y * half.y)
		corner.rotation.y = turns[i]
		var bar := _part("Tischrahmen_Leiste", self) as MeshInstance3D # 1 m lang
		bar.material_override = m
		bar.position = Vector3(sides[i].x, y, sides[i].z)
		bar.rotation.y = turns[i]
		bar.scale.x = (sides[i].y - arm) * 2.0 # sides[i].y = halbe Länge dieser Seite


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
	var heart := RoomKit.mat(Color(0.95, 0.8, 0.25), 0.6)
	for p in _along(info, 0.33):
		var c := _part("Seerosenblatt", self, {"Seerose_Blatt": pad})
		c.position = Vector3(p.x, info.rim_y, p.y)
		c.rotation.y = r.randf() * TAU
		c.scale = Vector3.ONE * r.randf_range(0.8, 1.2)
		if i % 3 == 1:
			var bloom := _part("Seerose", self, {"Seerose_Bluete": flower, "Seerose_Mitte": heart})
			bloom.position = Vector3(p.x, info.rim_y + 0.001, p.y)
		i += 1


func _skull(pos: Vector3) -> void:
	var skull := _part("Totenkopf", self, {
		"Knochen": RoomKit.mat(Color(0.9, 0.86, 0.74), 0.6),
		"Knochen_Dunkel": RoomKit.mat(Color(0.05, 0.04, 0.04), 0.9),
		"Zahn": RoomKit.mat(Color(0.95, 0.93, 0.85), 0.5)})
	skull.position = pos
	skull.rotation.y = randf_range(-0.3, 0.3)


func _eagle(pos: Vector3) -> void:
	var eagle := _part("Doppeladler", self, {
		"Skin_Gold": RoomKit.mat(GOLD, 0.25, 1.0),
		"Juwel_Rot": RoomKit.glow(Color(0.9, 0.1, 0.15), 1.0)})
	eagle.position = pos


func _build_crow(pos: Vector3) -> void:
	# Modell mit zwei Gelenken: „Kraehe_Kopf“ dreht sich, „Kraehe_Schnabel“ (Unterschnabel) klappt auf
	_crow = _part("Kraehe", self, {
		"Kraehe_Federn": RoomKit.mat(Color(0.05, 0.05, 0.07), 0.35, 0.2),
		"Kraehe_Schnabel": RoomKit.mat(Color(0.2, 0.2, 0.22), 0.4),
		"Kraehe_Auge": RoomKit.glow(Color(0.9, 0.75, 0.2), 0.8)})
	_crow.position = pos
	_crow.rotation.y = -2.3 # schaut schräg zur Tischmitte / zum Spieler
	_crow.scale = Vector3.ONE * 1.5
	_crow_head = _crow.find_child("Kraehe_Kopf", true, false)
	_crow_beak = _crow.find_child("Kraehe_Schnabel", true, false)


func _build_bells(info: Dictionary) -> void:
	var gold := RoomKit.mat(GOLD, 0.25, 1.0)
	var slit := RoomKit.mat(Color(0.1, 0.08, 0.05), 0.6)
	var ribbon := [RoomKit.mat(Color(0.75, 0.1, 0.1), 0.7), RoomKit.mat(Color(0.85, 0.7, 0.15), 0.7)]
	var i := 0
	for p in _along(info, 0.22):
		# Drehpunkt unten am Rand: so wackeln die Glöckchen wie bisher
		var b := _part("Gloeckchen", self, {"Skin_Gold": gold, "Glocke_Schlitz": slit, "Glocke_Band": ribbon[i % 2]})
		b.position = Vector3(p.x, info.rim_y + 0.002, p.y)
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
	var candle := _part("Hexenkerze", self, {
		"Kerzenwachs": wax,
		"Kerzenhalter": RoomKit.mat(Color(0.25, 0.22, 0.2), 0.4, 0.8),
		"Docht": RoomKit.mat(Color(0.05, 0.04, 0.03), 0.9)})
	candle.position = pos
	_flame(pos + Vector3(0, 0.122, 0), flame_col)


func _flame(pos: Vector3, col: Color) -> void:
	var f := Node3D.new()
	f.position = pos
	add_child(f)
	_part("Skinflamme", f, {"Skinflamme": RoomKit.glow(col, 4.0)})
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, 0.03, 0)
	l.light_color = col
	l.light_energy = 0.5
	l.omni_range = 0.7
	add_child(l)
	_flames.append({"node": f, "light": l, "energy": 0.5, "phase": randf() * TAU})


func _faberge(pos: Vector3) -> void:
	var enamel := RoomKit.mat(Color(0.55, 0.05, 0.12), 0.15, 0.3)
	enamel.clearcoat_enabled = true
	var egg := _part("Faberge", self, {
		"Skin_Gold": RoomKit.mat(GOLD, 0.25, 1.0),
		"Faberge_Emaille": enamel,
		"Faberge_Juwel_0": RoomKit.glow(Color(0.2, 0.5, 1.0), 1.2),
		"Faberge_Juwel_1": RoomKit.glow(Color(0.1, 0.9, 0.4), 1.2),
		"Faberge_Juwel_2": RoomKit.glow(Color(1, 1, 1), 1.2),
		"Faberge_Kerze": RoomKit.mat(Color(0.95, 0.92, 0.85), 0.6),
		"Docht": RoomKit.mat(Color(0.05, 0.04, 0.03), 0.9)})
	egg.position = pos
	_flame(pos + Vector3(0, 0.17, 0), Color(1.0, 0.7, 0.3))
