class_name CasinoRoom
extends Node3D
## Raum „Altes Casino“ – ganz in Code gebaut (kein Blender-Modell).
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


func _ready() -> void:
	_build_shell()
	_build_curtains()
	_build_table()
	_build_on_table()
	_build_slots()
	_build_sign()
	_build_chandelier()
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
	var wood := _wood()
	var gold := _gold()
	# Rückwand und Seitenwände: unten Holz, darüber Tapete, oben Zierleiste
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
		_box_in(root, Vector3(len, 1.0, 0.04), Vector3(0, 0.5, 0.02), wood) # Vertäfelung
		_box_in(root, Vector3(len, 0.04, 0.06), Vector3(0, 1.0, 0.03), gold) # Stuhlleiste
		_box_in(root, Vector3(len, 0.14, 0.06), Vector3(0, 0.07, 0.03), wood) # Sockelleiste
		_box_in(root, Vector3(len, 0.18, 0.08), Vector3(0, CEIL - 0.09, 0.04), wood) # Kranzleiste
		_box_in(root, Vector3(len, 0.025, 0.09), Vector3(0, CEIL - 0.19, 0.045), gold)
		# Felder in der Vertäfelung
		var n := int(len / 0.7)
		for k in n:
			var x := -len * 0.5 + (k + 0.5) * len / n
			_box_in(root, Vector3(len / n - 0.12, 0.6, 0.012), Vector3(x, 0.52, 0.045), wood)


func _build_curtains() -> void:
	var velvet := _mat(Color(0.42, 0.03, 0.06), 0.75)
	velvet.rim_enabled = true
	velvet.rim = 0.5
	velvet.rim_tint = 0.6
	# zwei schwere Vorhänge an der Rückwand, je mit Raffhalter
	for s in [-1.0, 1.0]:
		var root := Node3D.new()
		root.position = Vector3(s * 1.92, 0, BACK_Z + 0.12)
		add_child(root)
		for k in 7:
			var fold := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.045
			cm.bottom_radius = 0.05 + (k % 2) * 0.012
			cm.height = CEIL - 0.25
			cm.radial_segments = 12
			fold.mesh = cm
			fold.material_override = velvet
			fold.position = Vector3(-s * k * 0.06, (CEIL - 0.25) * 0.5, (k % 2) * 0.03)
			root.add_child(fold)
		var tie := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.17
		tm.outer_radius = 0.2
		tie.mesh = tm
		tie.material_override = _gold()
		tie.rotation.x = PI * 0.5
		tie.scale = Vector3(1.3, 1, 0.5)
		tie.position = Vector3(-s * 0.18, 1.05, 0.03)
		root.add_child(tie)
	# Querbehang oben: Samtblende mit Falten und goldener Fransenkante
	_box_in(self, Vector3(ROOM_W - 0.1, 0.34, 0.08), Vector3(0, CEIL - 0.37, BACK_Z + 0.14), velvet)
	for k in 30:
		var fold := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.035
		cm.bottom_radius = 0.035
		cm.height = 0.34
		cm.radial_segments = 10
		fold.mesh = cm
		fold.material_override = velvet
		fold.position = Vector3(-2.1 + k * 0.145, CEIL - 0.37, BACK_Z + 0.18)
		add_child(fold)
	_box_in(self, Vector3(ROOM_W - 0.1, 0.03, 0.03), Vector3(0, CEIL - 0.55, BACK_Z + 0.2), _gold())


# --- Pokertisch -------------------------------------------------------------------

func _build_table() -> void:
	var y := TableWorld.TABLE_Y
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
	leather.cull_mode = BaseMaterial3D.CULL_DISABLED # Röhre aus SurfaceTool: beide Seiten zeichnen
	var wood := _wood()
	# Filz: abgerundetes Rechteck (Stadion), Oberkante knapp unter TABLE_Y
	_stadium(FELT, 0.04, y - 0.0006, felt)
	# Holzzarge unter dem Rand
	_stadium(FELT + Vector2(RAIL, RAIL) * 2.0 + Vector2(0.02, 0.02), 0.1, y - 0.035, wood)
	# gepolsterter Lederrand ringsum (Röhre entlang des Stadion-Umrisses)
	var ring_r := FELT.y * 0.5 + RAIL * 0.5
	var rail := MeshInstance3D.new()
	rail.mesh = _tube(_stadium_path(FELT.x - FELT.y, ring_r, 40), RAIL * 0.5, 14, true, 0.9)
	rail.material_override = leather
	rail.position.y = y + 0.012
	add_child(rail)
	# goldene Ziernaht auf dem Filz
	var seam := MeshInstance3D.new()
	seam.mesh = _tube(_stadium_path(FELT.x - FELT.y, FELT.y * 0.5 - 0.04, 40), 0.003, 6, true, 0.2)
	var seam_mat := _gold()
	seam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	seam.material_override = seam_mat
	seam.position.y = y - 0.0002
	add_child(seam)
	# zwei schwere Säulenfüße
	for s in [-1.0, 1.0]:
		var foot := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = 0.09
		fm.bottom_radius = 0.12
		fm.height = y - 0.12
		foot.mesh = fm
		foot.material_override = wood
		foot.position = Vector3(s * 0.55, (y - 0.12) * 0.5, 0)
		add_child(foot)
		_box_in(self, Vector3(0.5, 0.05, 0.6), Vector3(s * 0.55, 0.025, 0), wood)


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


## Röhre entlang eines Pfades (Querschnitt: Kreis, in der Höhe mit `squash` gestaucht).
static func _tube(path: PackedVector3Array, radius: float, sides: int, closed: bool, squash := 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := path.size()
	var rings: Array = []
	for i in n:
		var prev := path[(i - 1 + n) % n] if (closed or i > 0) else path[i]
		var next := path[(i + 1) % n] if (closed or i < n - 1) else path[i]
		var tangent := (next - prev).normalized()
		var side := tangent.cross(Vector3.UP).normalized()
		var ring := []
		for k in sides:
			var a := TAU * k / sides
			var nrm := side * cos(a) + Vector3.UP * sin(a)
			ring.append([path[i] + side * cos(a) * radius + Vector3.UP * sin(a) * radius * squash, nrm])
		rings.append(ring)
	var segs := n if closed else n - 1
	for i in segs:
		var r0: Array = rings[i]
		var r1: Array = rings[(i + 1) % n]
		for k in sides:
			var k1 := (k + 1) % sides
			for v in [r0[k], r1[k], r1[k1], r0[k], r1[k1], r0[k1]]:
				st.set_normal(v[1])
				st.add_vertex(v[0])
	return st.commit()


## Abgerundete Platte (Kasten + zwei Zylinder) mit Oberkante bei `top`.
func _stadium(size: Vector2, h: float, top: float, m: Material) -> void:
	var r := size.y * 0.5
	var cx := (size.x - size.y) * 0.5
	_box_in(self, Vector3(cx * 2.0, h, size.y), Vector3(0, top - h * 0.5, 0), m)
	for s in [-1.0, 1.0]:
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = h
		cm.radial_segments = 48
		c.mesh = cm
		c.material_override = m
		c.position = Vector3(s * cx, top - h * 0.5, 0)
		add_child(c)


# --- Deko auf dem Tisch -------------------------------------------------------------

func _build_on_table() -> void:
	var y := TableWorld.TABLE_Y
	roulette = MiniRoulette.new()
	roulette.position = Vector3(TableWorld.PLAYER_ASHTRAY_POS.x, y, TableWorld.PLAYER_ASHTRAY_POS.z)
	add_child(roulette)
	# zwei Würfel rechts neben dem Ablagestapel
	var die_mat := _mat(Color(0.95, 0.93, 0.88), 0.25)
	var dot := _mat(Color(0.08, 0.06, 0.06), 0.5)
	for k in 2:
		var die := Node3D.new()
		die.position = Vector3(0.9 + k * 0.05, y + 0.0085, 0.08 + k * 0.03)
		die.rotation.y = 0.5 + k * 0.9
		add_child(die)
		var cube := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.017, 0.017, 0.017)
		cube.mesh = bm
		cube.material_override = die_mat
		die.add_child(cube)
		var pips: int = [5, 3][k]
		var spots := {1: [Vector2.ZERO], 3: [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)],
			5: [Vector2(-1, -1), Vector2(1, -1), Vector2.ZERO, Vector2(-1, 1), Vector2(1, 1)]}
		for p: Vector2 in spots[pips]:
			var d := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.0018
			sm.height = 0.0012
			d.mesh = sm
			d.material_override = dot
			d.position = Vector3(p.x * 0.0045, 0.0085, p.y * 0.0045)
			die.add_child(d)
	# Cocktailglas (Martini) mit Olive, hinten rechts
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.85, 0.92, 1.0, 0.25)
	glass.roughness = 0.05
	glass.metallic_specular = 1.0
	var gx := Vector3(0.86, y, -0.28)
	_cyl_in(self, 0.025, 0.025, 0.003, gx + Vector3(0, 0.0015, 0), glass)
	_cyl_in(self, 0.0025, 0.0025, 0.07, gx + Vector3(0, 0.038, 0), glass)
	_cyl_in(self, 0.045, 0.002, 0.045, gx + Vector3(0, 0.095, 0), glass)
	var drink := _mat(Color(0.95, 0.9, 0.6), 0.1)
	drink.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drink.albedo_color.a = 0.6
	_cyl_in(self, 0.036, 0.004, 0.034, gx + Vector3(0, 0.09, 0), drink)
	var olive := MeshInstance3D.new()
	var om := SphereMesh.new()
	om.radius = 0.008
	om.height = 0.016
	olive.mesh = om
	olive.material_override = _mat(Color(0.35, 0.45, 0.12), 0.4)
	olive.position = gx + Vector3(0.004, 0.09, 0)
	add_child(olive)


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
	var y := 2.35
	var board := _box_in(self, Vector3(1.3, 0.38, 0.05), Vector3(0, y, BACK_Z + 0.03), _mat(Color(0.05, 0.02, 0.03), 0.6))
	board.name = "Neonschild"
	_sign_label = Label3D.new()
	_sign_label.text = "КАЗИНО"
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
	# Glühbirnen-Rahmen ums Schild
	var bm := SphereMesh.new()
	bm.radius = 0.014
	bm.height = 0.028
	for i in 24:
		var t := float(i) / 24.0
		var p: Vector2
		var per := 2.0 * (1.3 + 0.38)
		var d := t * per
		if d < 1.3:
			p = Vector2(-0.65 + d, 0.19)
		elif d < 1.68:
			p = Vector2(0.65, 0.19 - (d - 1.3))
		elif d < 2.98:
			p = Vector2(0.65 - (d - 1.68), -0.19)
		else:
			p = Vector2(-0.65, -0.19 + (d - 2.98))
		var b := MeshInstance3D.new()
		b.mesh = bm
		var m := _mat(Color(1, 0.9, 0.6), 0.3)
		m.emission_enabled = true
		m.emission = Color(1, 0.78, 0.4)
		b.material_override = m
		b.position = Vector3(p.x, y + p.y, BACK_Z + 0.07)
		add_child(b)
		_sign_bulbs.append(m)


func _build_chandelier() -> void:
	var gold := _gold()
	var root := Node3D.new()
	root.position = Vector3(0, 2.4, -0.35)
	add_child(root)
	_cyl_in(root, 0.008, 0.008, CEIL - 2.4, Vector3(0, (CEIL - 2.4) * 0.5, 0), gold) # Kette
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.3
	tm.outer_radius = 0.32
	tm.rings = 48
	ring.mesh = tm
	ring.material_override = gold
	root.add_child(ring)
	_cyl_in(root, 0.05, 0.02, 0.18, Vector3(0, -0.04, 0), gold)
	var crystal := StandardMaterial3D.new()
	crystal.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crystal.albedo_color = Color(0.95, 0.97, 1.0, 0.55)
	crystal.roughness = 0.02
	crystal.metallic_specular = 1.0
	crystal.emission_enabled = true
	crystal.emission = Color(1, 0.85, 0.6)
	crystal.emission_energy_multiplier = 0.3
	var bulb := _mat(Color(1, 0.9, 0.7), 0.3)
	bulb.emission_enabled = true
	bulb.emission = Color(1, 0.8, 0.5)
	bulb.emission_energy_multiplier = 4.0
	var drop := SphereMesh.new()
	drop.radius = 0.014
	drop.height = 0.04
	for k in 8:
		var a := TAU * k / 8.0
		var p := Vector3(cos(a) * 0.31, 0, sin(a) * 0.31)
		_cyl_in(root, 0.016, 0.012, 0.04, p + Vector3(0, 0.02, 0), gold) # Kerzenhalter
		var b := MeshInstance3D.new()
		var bs := SphereMesh.new()
		bs.radius = 0.016
		bs.height = 0.04
		b.mesh = bs
		b.material_override = bulb
		b.position = p + Vector3(0, 0.06, 0)
		root.add_child(b)
		for j in 2: # Kristalle
			var c := MeshInstance3D.new()
			c.mesh = drop
			c.material_override = crystal
			c.position = Vector3(cos(a + 0.2) * (0.3 - j * 0.1), -0.07 - j * 0.06, sin(a + 0.2) * (0.3 - j * 0.1))
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(c)
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_sconces() -> void:
	for s in [-1.0, 1.0]:
		for z in [-1.4, 0.2]:
			var root := Node3D.new()
			root.position = Vector3(s * (ROOM_W * 0.5 - 0.02), 1.75, z)
			add_child(root)
			_box_in(root, Vector3(0.03, 0.18, 0.1), Vector3(0, 0, 0), _gold())
			var shade := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.05
			cm.bottom_radius = 0.08
			cm.height = 0.12
			shade.mesh = cm
			var sm := _mat(Color(0.95, 0.7, 0.45), 0.7)
			sm.emission_enabled = true
			sm.emission = Color(1, 0.6, 0.3)
			sm.emission_energy_multiplier = 1.2
			shade.material_override = sm
			shade.position = Vector3(-s * 0.1, 0.1, 0)
			root.add_child(shade)
			var l := OmniLight3D.new()
			l.position = Vector3(-s * 0.15, 0.1, 0)
			l.light_color = Color("ffa860")
			l.light_energy = 0.7
			l.omni_range = 1.4
			root.add_child(l)


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


func _wood() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = preload("res://assets/models/table_wood_color.png")
	m.albedo_color = Color(0.55, 0.3, 0.18)
	m.roughness = 0.5
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.5, 1.5, 1.5)
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
