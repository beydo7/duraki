class_name CasinoRoom
extends Node3D
## Raum „Altes Casino“. Formen aus Blender (assets/rooms/casino/casino.glb, gebaut mit
## art/blender/casino.py), Materialien, Lichter und alles Bewegliche hier im Code.
## Boden, Decke und die tapezierten Wände sind schlichte Flächen und bleiben Code.
##
## Damast-Tapete über dunkler Holzvertäfelung, Casino-Teppich, schwere rote Vorhänge,
## Kronleuchter, Wandleuchter und ein Neonschild. Hinten zwei alte Spielautomaten mit
## großem Hebel. Der Pokertisch ist größer als im Hinterzimmer (abgerundet, gepolsterter
## Lederrand). Auf dem Tisch: ein kleines Roulette, Würfel und ein Cocktailglas –
## kein Aschenbecher, keine Zigaretten. Statt Goldmünzen liegen Pokerchips da
## (TableProps.chip_style).
##
## Die Spielfläche (Filz) liegt wie im Hinterzimmer auf TableWorld.TABLE_Y, damit alle
## Kartenplätze gleich bleiben.

const TEX := "res://assets/rooms/casino/"
const MODEL := preload("res://assets/rooms/casino/casino.glb")
const ROOM_W := 4.4 # Wand links bis rechts (x = ±2.2)
const BACK_Z := -2.3
const CEIL := 3.0
## Pokertisch: Filz 2,1 × 1,2 m (Hinterzimmer: 1,6 × 1,2), Rand 0,1 m
const FELT := Vector2(2.1, 1.2)
const RAIL := 0.1

var slots: Array[SlotMachine] = []
var roulette: MiniRoulette

var _sign_mat: StandardMaterial3D
var _sign_label: Label3D
var _sign_bulbs: Array[StandardMaterial3D] = []
var _t := 0.0
var _flicker := 1.0


var _model: Node3D # casino.glb
var _skin_felt: Array[Material] = []
var _skin_rim: Array[Material] = []


func _ready() -> void:
	_build_shell()
	_build_model()
	_build_on_table()
	_build_slots()
	_build_sign()
	_build_sconces()


func _process(delta: float) -> void:
	_t += delta
	# Neonschild: ruhig, ab und zu kurzes Flackern
	if randf() < delta * 0.25:
		_flicker = 0.25
	_flicker = move_toward(_flicker, 1.0, delta * 3.0)
	if _sign_label != null:
		var e := _flicker * (0.92 + 0.08 * sin(_t * 9.0))
		_sign_label.modulate = Color(2.4, 0.5, 0.7) * e
	for i in _sign_bulbs.size():
		_sign_bulbs[i].emission_energy_multiplier = 2.6 if (int(_t * 4.0) + i) % 2 == 0 else 0.6


## Licht und Stimmung: wärmer als das Hinterzimmer (Rot und Gold statt Violett).
func apply_environment(env: Environment) -> void:
	env.background_color = Color("070405")
	env.ambient_light_color = Color("3a2420")
	env.ambient_light_energy = 0.45
	env.fog_light_color = Color("140a08")
	env.adjustment_saturation = 0.95


## Eigene Lichter (Kronleuchter, Wandleuchter, Neon, Automaten). Tischlampe und
## Lichtkegel auf das Spielfeld baut TableWorld wie gewohnt.
func add_lights(parent: Node3D) -> void:
	var crown := OmniLight3D.new()
	crown.position = Vector3(0, 2.25, -0.2)
	crown.light_color = Color("ffcf8a")
	crown.light_energy = 1.3
	crown.omni_range = 3.6
	parent.add_child(crown)
	# warmes Gegenlicht hinter dem Gegner (statt Violett)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0, 1.9, -1.5)
	rim.light_color = Color("d0503c")
	rim.light_energy = 1.8
	rim.omni_range = 2.2
	parent.add_child(rim)
	# die Automaten leuchten von vorne an
	for s in [-1.0, 1.0]:
		var spot := SpotLight3D.new()
		spot.position = Vector3(s * 1.0, 2.4, -1.0)
		parent.add_child(spot)
		spot.look_at(Vector3(s * 1.45, 1.0, -1.95))
		spot.light_color = Color("ffb070")
		spot.light_energy = 2.2
		spot.spot_range = 3.0
		spot.spot_angle = 24.0


# --- Hülle: Boden, Wände, Decke --------------------------------------------------

func _build_shell() -> void:
	var carpet := _tex_mat("carpet.png", 0.95, Vector3(5, 5, 5))
	var floor_ := _plane(Vector2(ROOM_W, 6.0), Vector3(0, 0, 0.7), carpet)
	floor_.name = "Boden"
	var ceiling := _mat(Color(0.09, 0.05, 0.04), 0.8)
	var c := _plane(Vector2(ROOM_W, 6.0), Vector3(0, CEIL, 0.7), ceiling)
	c.rotation.x = PI
	var paper := _tex_mat("wallpaper.png", 0.85, Vector3(1, 1, 1))
	paper.uv1_triplanar = true
	paper.uv1_scale = Vector3(2.4, 2.4, 2.4)
	# Rückwand und Seitenwände: nur die Tapete; Vertäfelung und Leisten kommen aus Blender
	var walls := [
		[Vector3(0, 0, BACK_Z), Vector2(ROOM_W, 0), 0.0],
		[Vector3(-ROOM_W * 0.5, 0, 0.7), Vector2(6.0, 0), PI * 0.5],
		[Vector3(ROOM_W * 0.5, 0, 0.7), Vector2(6.0, 0), -PI * 0.5],
	]
	for w in walls:
		var root := Node3D.new()
		root.position = w[0]
		root.rotation.y = w[2]
		add_child(root)
		var len: float = (w[1] as Vector2).x
		_box_in(root, Vector3(len, CEIL, 0.1), Vector3(0, CEIL * 0.5, -0.05), paper)


## Alles aus Blender: Vertäfelung und Leisten, Vorhänge mit Querbehang, Pokertisch, Würfel und
## Cocktailglas, Schildtafel, Kronleuchter, Wandleuchter. Die Materialien gehören zu den
## Namen, die sie in Blender haben (siehe art/blender/casino.py).
func _build_model() -> void:
	var felt := StandardMaterial3D.new()
	felt.albedo_texture = preload("res://assets/models/table_felt_color.png")
	felt.normal_enabled = true
	felt.normal_texture = preload("res://assets/models/table_felt_normal.png")
	felt.albedo_color = Color(0.62, 1.0, 0.72) # etwas sattgrüner als im Hinterzimmer
	felt.roughness = 0.95
	felt.uv1_triplanar = true
	felt.uv1_scale = Vector3(1.2, 1.2, 1.2)
	var leather := _mat(Color(0.26, 0.09, 0.06), 0.38)
	leather.clearcoat_enabled = true
	leather.clearcoat = 0.4
	leather.normal_enabled = true
	leather.normal_texture = load(TEX + "leather_normal.png")
	leather.normal_scale = 0.3
	leather.uv1_scale = Vector3(9, 9, 9)
	var table_wood := _wood()
	_skin_felt = [felt]
	_skin_rim = [leather, table_wood]
	var velvet := _mat(Color(0.42, 0.03, 0.06), 0.75)
	velvet.rim_enabled = true
	velvet.rim = 0.5
	velvet.rim_tint = 0.6
	velvet.normal_enabled = true
	velvet.normal_texture = load(TEX + "velvet_normal.png")
	velvet.normal_scale = 0.5
	velvet.uv1_scale = Vector3(6, 6, 6)
	var crystal := StandardMaterial3D.new()
	crystal.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crystal.albedo_color = Color(0.95, 0.97, 1.0, 0.55)
	crystal.roughness = 0.02
	crystal.metallic_specular = 1.0
	crystal.emission_enabled = true
	crystal.emission = Color(1, 0.85, 0.6)
	crystal.emission_energy_multiplier = 0.3
	var candle := _mat(Color(1, 0.9, 0.7), 0.3)
	candle.emission_enabled = true
	candle.emission = Color(1, 0.8, 0.5)
	candle.emission_energy_multiplier = 4.0
	var shade := _mat(Color(0.95, 0.7, 0.45), 0.7)
	shade.emission_enabled = true
	shade.emission = Color(1, 0.6, 0.3)
	shade.emission_energy_multiplier = 1.2
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.85, 0.92, 1.0, 0.25)
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	var drink := _mat(Color(0.95, 0.9, 0.6), 0.1)
	drink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drink.albedo_color.a = 0.6
	_model = RoomKit.model(self, MODEL, {
		"Filz": felt, "Leder": leather, "Tischholz": table_wood, "Holz": _wood(), "Gold": _gold(),
		"Samt": velvet, "Schild": _mat(Color(0.05, 0.02, 0.03), 0.6), "Kristall": crystal,
		"Kerzenlicht": candle, "Lampenschirm": shade, "Glas": glass, "Drink": drink,
		"Wuerfel": _mat(Color(0.95, 0.93, 0.88), 0.25), "Wuerfelauge": _mat(Color(0.08, 0.06, 0.06), 0.5),
		"Olive": _mat(Color(0.35, 0.45, 0.12), 0.4),
	})
	# der Kronleuchter wirft wie bisher keinen Schatten
	for n in _model.find_child("Kronleuchter", true, false).find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Umriss eines Stadions in der xz-Ebene: zwei Halbkreise (Radius `r`) im Abstand `straight`.
static func _stadium_path(straight: float, r: float, seg: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var cx := straight * 0.5
	for i in seg + 1: # rechte Rundung (von hinten nach vorne)
		var a := -PI * 0.5 + PI * i / seg
		pts.append(Vector3(cx + cos(a) * r, 0, sin(a) * r))
	for i in seg + 1: # linke Rundung (von vorne nach hinten)
		var a := PI * 0.5 + PI * i / seg
		pts.append(Vector3(-cx + cos(a) * r, 0, sin(a) * r))
	return pts


# --- Deko auf dem Tisch -------------------------------------------------------------

func _build_on_table() -> void:
	var y := TableWorld.TABLE_Y
	roulette = MiniRoulette.new()
	roulette.position = Vector3(TableWorld.PLAYER_ASHTRAY_POS.x + 0.02, y, TableWorld.PLAYER_ASHTRAY_POS.z - 0.08)
	roulette.scale = Vector3.ONE * 1.45 # deutlich größer als der Aschenbecher
	add_child(roulette)
	# Würfel und Cocktailglas (Martini mit Olive) sind Teil des Blender-Modells


# --- Hintergrund: Spielautomaten, Neonschild, Licht -----------------------------------

func _build_slots() -> void:
	var colors := [Color(0.62, 0.06, 0.08), Color(0.1, 0.22, 0.42)]
	for k in 2:
		var s := SlotMachine.new()
		var side := -1.0 if k == 0 else 1.0
		s.body_color = colors[k]
		s.position = Vector3(side * 1.4, 0, -1.95)
		s.rotation.y = -side * 0.3
		add_child(s)
		slots.append(s)


func _build_sign() -> void:
	var y := 2.35 # die Tafel selbst („Neonschild“) kommt aus Blender
	_sign_label = Label3D.new()
	_sign_label.text = "CASINO"
	_sign_label.font = preload("res://assets/fonts/RussoOne-Regular.ttf")
	_sign_label.font_size = 160
	_sign_label.pixel_size = 0.0016
	_sign_label.outline_size = 18
	_sign_label.outline_modulate = Color(0.6, 0.05, 0.15, 0.8)
	_sign_label.modulate = Color(2.4, 0.5, 0.7)
	_sign_label.position = Vector3(0, y, BACK_Z + 0.06)
	add_child(_sign_label)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, y, BACK_Z + 0.35)
	glow.light_color = Color("ff4a6a")
	glow.light_energy = 0.9
	glow.omni_range = 1.4
	add_child(glow)
	# Glühbirnen-Rahmen ums Schild: jede Birne („Schildbirne_00“ … „_23“) hat ihr eigenes
	# Material, damit das Lauflicht sie einzeln schalten kann
	for i in 24:
		var b := _model.find_child("Schildbirne_%02d" % i, true, false) as MeshInstance3D
		var m := _mat(Color(1, 0.9, 0.6), 0.3)
		m.emission_enabled = true
		m.emission = Color(1, 0.78, 0.4)
		b.material_override = m
		_sign_bulbs.append(m)


## Licht der vier Wandleuchter (die Leuchter selbst kommen aus Blender).
func _build_sconces() -> void:
	for s in [-1.0, 1.0]:
		for z in [-1.4, 0.2]:
			var l := OmniLight3D.new()
			l.position = Vector3(s * (ROOM_W * 0.5 - 0.02) - s * 0.15, 1.85, z)
			l.light_color = Color("ffa860")
			l.light_energy = 0.7
			l.omni_range = 1.4
			add_child(l)


# --- Bausteine ------------------------------------------------------------------------

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


func _tex_mat(file: String, rough: float, scale: Vector3) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + file)
	m.roughness = rough
	m.uv1_scale = scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _wood() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = preload("res://assets/models/table_wood_color.png")
	m.albedo_color = Color(0.55, 0.3, 0.18)
	m.normal_enabled = true
	m.normal_texture = preload("res://assets/models/table_wood_normal.png")
	m.roughness = 0.5
	m.uv1_scale = Vector3(1.5, 1.5, 1.5) # UVs der Blender-Modelle sind in Metern, Maserung längs
	return m


func _gold() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.68, 0.3)
	m.metallic = 1.0
	m.roughness = 0.3
	return m


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## Für die Deck-Belohnungen (TableSkin): Filz, Rand und Umriss des Lederrands (Stadion).
func table_info() -> Dictionary:
	var r := FELT.y * 0.5 + RAIL * 0.5
	var path := PackedVector2Array()
	for p in _stadium_path(FELT.x - FELT.y, r, 20):
		path.append(Vector2(p.x, p.z))
	var cx := (FELT.x - FELT.y) * 0.5 + r * 0.7071
	var cz := r * 0.7071
	return {"felt": _skin_felt, "rim": _skin_rim, "outline": path, "rim_y": TableWorld.TABLE_Y + 0.012 + RAIL * 0.5,
		"corners": [Vector2(-cx, -cz), Vector2(cx, -cz), Vector2(-cx, cz), Vector2(cx, cz)], "frame": Vector2.ZERO}
