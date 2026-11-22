class_name TableWorld
extends Node3D
## Die 3D-Welt des Duells: dunkle Kammer, Spieltisch, Licht, Kamera
## (Ich-Perspektive) und die Gestalt gegenüber. Kümmert sich außerdem
## darum, die Karten an ihre Plätze zu bewegen (sync).
##
## Raum, Tisch und Requisiten sind Blender-Modelle (art/blender/*.blend →
## assets/models/*.glb). Licht, Kamera und Spielfeld-Markierungen bleiben hier.

signal card_clicked(card: Card)

const MODELS: Array[PackedScene] = [
	preload("res://assets/models/room.glb"),
	preload("res://assets/models/table.glb"),
	preload("res://assets/models/props.glb"),
]
## Teile der Hängelampe dürfen keinen Schatten werfen (das Licht sitzt darin).
const NO_SHADOW := ["Gluehbirne", "Lampenschirm", "Lampenschirm_Innen", "Lampenfassung", "Lampenkabel"]

const TABLE_Y := 0.80
const TABLE_SIZE := Vector2(1.6, 1.2) # x, z

const DECK_POS := Vector3(-0.60, TABLE_Y, -0.10)
const DISCARD_POS := Vector3(0.62, TABLE_Y, -0.12)
const PLAYER_HAND_POS := Vector3(0.0, 1.0, 0.5)
const PLAYER_HAND_TILT := 50.0
## Ab so vielen Handkarten werden zwei Reihen gebildet (sonst ein Fächer).
const HAND_ROW_THRESHOLD := 22
const HAND_MAX_WIDTH := 0.82
const OPP_HAND_POS := Vector3(0.0, 0.97, -0.36)
const OPP_HAND_TILT := 68.0
const TABLE_ROW_Z := -0.07
const TABLE_FIELD_WIDTH := 0.96

const TABLE_CARD_SCALE := 1.8
const MOVE_TIME := 0.32
const DISCARD_DELAY := 0.8
const DEAL_STAGGER := 0.07
const HOVER_LIFT := Vector3(0, 0.035, -0.02)

## "fan" = Fächer, erst ab HAND_ROW_THRESHOLD zwei Reihen.
## "rows" = schon ab 11 Karten zwei Reihen (zum Vergleichen).
static var hand_layout := "fan"

var camera: Camera3D
var figure: OpponentFigure

var _cards := {} # Card -> Card3D
var _base := {} # Card3D -> Transform3D (Ziel ohne Hover)
var _deck_pile: MeshInstance3D
var _discard_pile: MeshInstance3D
var _discard_count := 0
var _deal_queue_until := 0.0
var _cam_base: Transform3D
var _mouse := Vector2(0.5, 0.5)
var _env: Environment
var _lamp: SpotLight3D


func _ready() -> void:
	Settings.changed.connect(_on_settings_changed)


## Optionen live übernehmen (Leuchten, Helligkeit, Schatten).
func _on_settings_changed() -> void:
	Settings.apply_environment(_env, 1.05)
	if _lamp != null:
		_lamp.shadow_enabled = Settings.shadows_enabled()


func build(opponent: OpponentData) -> void:
	_build_environment()
	_build_models()
	_build_markings()
	_build_lights()
	_build_camera()
	figure = OpponentFigure.new().setup(opponent)
	figure.position = Vector3(0, 0, -TABLE_SIZE.y * 0.5)
	add_child(figure)
	_deck_pile = _pile_mesh()
	_deck_pile.position = DECK_POS
	_deck_pile.rotation_degrees.y = 90
	add_child(_deck_pile)
	_discard_pile = _pile_mesh()
	_discard_pile.position = DISCARD_POS
	_discard_pile.rotation_degrees.y = 12
	_discard_pile.visible = false
	add_child(_discard_pile)


func _process(_delta: float) -> void:
	# leichtes Mitschwenken der Kamera mit der Maus
	if camera == null:
		return
	var vp := get_viewport()
	if vp != null:
		var size := vp.get_visible_rect().size
		if size.x > 0:
			_mouse = _mouse.lerp(vp.get_mouse_position() / size, 0.08)
	var sway := 1.0 if Settings.camera_sway() else 0.0
	var yaw := (_mouse.x - 0.5) * -0.06 * sway
	var pitch := (_mouse.y - 0.5) * -0.04 * sway
	camera.transform = _cam_base * Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0)), Vector3.ZERO)


# --- Karten-Layout --------------------------------------------------------------

## Bringt alle Karten an die Plätze, die dem Spielstand entsprechen.
func sync(duel: DurakMatch, playable: Array[Card]) -> void:
	var targets := {} # Card -> [Transform3D, face_up: bool]

	var hand := duel.player_hand
	for i in hand.size():
		targets[hand[i]] = [_player_hand_xf(i, hand.size()), true]
	var opp := duel.opponent_hand
	for i in opp.size():
		targets[opp[i]] = [_opp_hand_xf(i, opp.size()), false]
	for i in duel.attack_cards.size():
		targets[duel.attack_cards[i]] = [_table_xf(i, duel.attack_cards.size(), false, duel.attack_cards[i]), true]
		var d: Card = duel.defense_cards[i]
		if d != null:
			targets[d] = [_table_xf(i, duel.attack_cards.size(), true, d), true]
	if not duel.deck.is_empty():
		targets[duel.trump_card] = [_trump_xf(), true]

	# Stapelhöhe
	var deck_left := duel.deck.size() - (1 if not duel.deck.is_empty() else 0)
	_deck_pile.visible = deck_left > 0
	_set_pile_height(_deck_pile, DECK_POS, deck_left)

	var now := Time.get_ticks_msec() / 1000.0
	var deal_start := maxf(now, _deal_queue_until)
	var new_count := 0

	for card: Card in targets:
		var xf: Transform3D = targets[card][0]
		var face_up: bool = targets[card][1]
		if not face_up:
			xf.basis = xf.basis * Basis(Vector3.FORWARD, PI) # umdrehen
		var node: Card3D = _cards.get(card)
		var delay := 0.0
		if node == null:
			node = Card3D.create(card, card.suit == duel.trump_suit)
			node.transform = _deck_top_xf()
			add_child(node)
			node.clicked.connect(func(c: Card) -> void: card_clicked.emit(c))
			node.hover_changed.connect(_on_hover)
			_cards[card] = node
			if card != duel.trump_card or duel.deck.is_empty():
				delay = deal_start - now + new_count * DEAL_STAGGER
				new_count += 1
			else:
				node.transform = xf # Trumpfkarte liegt von Anfang an
		node.set_state(playable.has(card))
		if not _base.has(node) or not _base[node].is_equal_approx(xf):
			_base[node] = xf
			_move(node, _with_hover(node, xf), delay)
	if new_count > 0:
		_deal_queue_until = deal_start + new_count * DEAL_STAGGER

	# Karten, die nirgends mehr sind → Ablagestapel
	var discard_i := 0
	for card: Card in _cards.keys():
		if targets.has(card):
			continue
		var node: Card3D = _cards[card]
		_cards.erase(card)
		_base.erase(node)
		node.set_state(false)
		var xf := Transform3D(Basis(Vector3.UP, randf_range(-0.3, 0.3)) * Basis(Vector3.FORWARD, PI), DISCARD_POS + Vector3(0, 0.02, 0))
		# Karten bleiben kurz liegen, bevor sie abgeräumt werden
		var tw := _move(node, xf, DISCARD_DELAY + discard_i * 0.06)
		discard_i += 1
		tw.finished.connect(func() -> void:
			_discard_count += 1
			_discard_pile.visible = true
			_set_pile_height(_discard_pile, DISCARD_POS, _discard_count)
			node.queue_free())


func _on_hover(node: Card3D, _hovered: bool) -> void:
	if _base.has(node):
		_move(node, _with_hover(node, _base[node]), 0.0, 0.12)


func _with_hover(node: Card3D, xf: Transform3D) -> Transform3D:
	if node.hovered and node.playable:
		return Transform3D(xf.basis, xf.origin + HOVER_LIFT)
	return xf


func _move(node: Node3D, to: Transform3D, delay: float, time := MOVE_TIME) -> Tween:
	if node.has_meta("tween"):
		var old: Tween = node.get_meta("tween")
		if old.is_valid():
			old.kill()
	var from := node.transform
	var tw := create_tween()
	node.set_meta("tween", tw)
	var f := Settings.anim_time_factor()
	time *= f
	delay *= f
	if delay > 0.0:
		tw.tween_interval(delay)
	var lift := 0.05 if from.origin.distance_to(to.origin) > 0.15 else 0.0
	var q_from := from.basis.get_rotation_quaternion()
	var q_to := to.basis.get_rotation_quaternion()
	var s_from := from.basis.get_scale()
	var s_to := to.basis.get_scale()
	tw.tween_method(func(t: float) -> void:
		var b := Basis(q_from.slerp(q_to, t)).scaled_local(s_from.lerp(s_to, t))
		var pos := from.origin.lerp(to.origin, t) + Vector3(0, sin(t * PI) * lift, 0)
		node.transform = Transform3D(b, pos),
		0.0, 1.0, time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw


func _player_hand_xf(i: int, n: int) -> Transform3D:
	var threshold := 10 if hand_layout == "rows" else HAND_ROW_THRESHOLD
	if n > threshold:
		# zwei Reihen: erste Hälfte hinten, zweite Hälfte tiefer und näher davor.
		# Von der hinteren Reihe bleibt die obere Hälfte mit Rang/Farbe sichtbar.
		var back := ceili(n / 2.0)
		if i < back:
			return _hand_row_xf(i, back, Vector3.ZERO, 0.95)
		return _hand_row_xf(i - back, n - back, Vector3(0, -0.04, 0.035), 1.0)
	return _hand_row_xf(i, n, Vector3.ZERO, 1.0)


## Eine Reihe Handkarten als leichter Fächer. Der Abstand schrumpft bei vielen
## Karten, bleibt aber so groß, dass die Ecke mit Rang und Farbe sichtbar ist.
func _hand_row_xf(i: int, n: int, offset_pos: Vector3, width_factor: float) -> Transform3D:
	var spacing := clampf(HAND_MAX_WIDTH * width_factor / maxf(1, n), 0.036, 0.085)
	var offset := i - (n - 1) * 0.5
	var fan := -offset * minf(0.07, 0.45 / maxf(1, n))
	var curve := 0.004 if n <= 8 else 0.0015
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(PLAYER_HAND_TILT))
	var basis := tilt * Basis(Vector3.UP, fan)
	# Bogen innerhalb der Kartenebene (lokal +Z = nach unten auf der Karte),
	# damit sich die Stapelreihenfolge nicht verschiebt
	var pos := PLAYER_HAND_POS + offset_pos + tilt * Vector3(offset * spacing, 0, absf(offset) * curve * 1.6)
	# jede Karte liegt etwas über der linken Nachbarin → linke Ecke bleibt frei
	pos += tilt.y * (i * 0.0015)
	return Transform3D(basis, pos)


func _opp_hand_xf(i: int, n: int) -> Transform3D:
	var spacing := minf(0.05, 0.45 / maxf(1, n))
	var offset := i - (n - 1) * 0.5
	var fan := offset * 0.09
	var pos := OPP_HAND_POS + Vector3(offset * spacing, -absf(offset) * 0.006, -i * 0.0015)
	var basis := Basis(Vector3.RIGHT, deg_to_rad(OPP_HAND_TILT)) * Basis(Vector3.UP, fan)
	return Transform3D(basis, pos)


func _table_xf(i: int, n: int, defense: bool, card: Card) -> Transform3D:
	# Bei vielen Paaren werden die Karten kleiner, damit alles ins Mittelfeld passt.
	var scale := minf(TABLE_CARD_SCALE, TABLE_FIELD_WIDTH / (n * Card3D.WIDTH * 1.5))
	var spacing := minf(0.26, TABLE_FIELD_WIDTH / n)
	var x := (i - (n - 1) * 0.5) * spacing - 0.02 * scale
	var jitter := (hash(card.get_label()) % 100) / 100.0 - 0.5
	var pos := Vector3(x, TABLE_Y + 0.002, TABLE_ROW_Z)
	var rot := jitter * 0.08
	if defense:
		# nach rechts unten versetzt: Rang und Farbe der Angriffskarte bleiben frei
		pos += Vector3(0.036 * scale, 0.004, 0.045 * scale)
		rot += 0.12
	return Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * scale), pos)


func _trump_xf() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, 0.0), DECK_POS + Vector3(0.065, 0.0015, 0.0))


func _deck_top_xf() -> Transform3D:
	var top := DECK_POS + Vector3(0, 0.004 + _deck_pile.scale.y * Card3D.THICKNESS, 0)
	return Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.FORWARD, PI), top)


func _set_pile_height(pile: MeshInstance3D, base: Vector3, count: int) -> void:
	pile.scale.y = maxf(1.0, count)
	pile.position = base + Vector3(0, pile.scale.y * Card3D.THICKNESS * 0.5, 0)


func _pile_mesh() -> MeshInstance3D:
	# Ein Stapel als Box, die nach oben skaliert wird (1 Einheit = 1 Karte).
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(Card3D.WIDTH, Card3D.THICKNESS, Card3D.HEIGHT)
	box.material = _mat(Card3D.COLOR_BACK_BORDER.darkened(0.15), 0.9)
	mi.mesh = box
	# Pivot unten: Mesh um halbe Dicke anheben
	var top := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(Card3D.WIDTH - 0.012, Card3D.HEIGHT - 0.012)
	top.mesh = quad
	var back := _mat(Color.WHITE, 0.7)
	back.albedo_texture = Card3D.back_texture()
	back.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	top.material_override = back
	top.rotation_degrees.x = -90
	top.position.y = Card3D.THICKNESS * 0.5 + 0.0003
	mi.add_child(top)
	return mi


# --- Aufbau der Kammer ----------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("05040a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("2c2246")
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color("0d0a1a")
	env.fog_density = 0.08
	# leichtes Leuchten um Glühbirne, Glut und Scheinwerferlinsen
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 2.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env
	Settings.apply_environment(env, 1.05)


func _build_models() -> void:
	for scene in MODELS:
		add_child(scene.instantiate())
	for part in NO_SHADOW:
		var node := find_child(part, true, false) as GeometryInstance3D
		if node != null:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Aufgemalte Spielfelder auf dem Filz (hängen an den Konstanten oben,
## deshalb hier im Code statt im Modell).
func _build_markings() -> void:
	var line := _mat(Color(0.86, 0.82, 0.7, 0.55), 1.0)
	line.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var y := TABLE_Y + 0.0006
	var w := 0.006
	_flat_rect(Vector3(0, y, TABLE_ROW_Z + 0.02), Vector2(0.96, 0.4), w, line) # Mittelfeld
	_flat_rect(Vector3(DECK_POS.x, y, DECK_POS.z), Vector2(0.24, 0.2), w, line) # Stapel
	_flat_rect(Vector3(DISCARD_POS.x, y, DISCARD_POS.z), Vector2(0.2, 0.24), w, line) # Ablage
	_flat_line(Vector3(0, y, 0.36), Vector2(1.3, w), line)
	_flat_line(Vector3(0, y, -0.33), Vector2(1.3, w), line)


func _build_lights() -> void:
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0, 2.05, 0)
	lamp.rotation_degrees = Vector3(-90, 0, 0)
	lamp.light_color = Color("ffd9a0")
	lamp.light_energy = 1.9
	lamp.spot_range = 3.5
	lamp.spot_angle = 48.0
	lamp.spot_attenuation = 1.1
	lamp.shadow_enabled = Settings.shadows_enabled()
	add_child(lamp)
	_lamp = lamp

	for side in [-1, 1]:
		var stage := SpotLight3D.new()
		stage.position = Vector3(side * 1.25, 1.95, -1.6)
		add_child(stage)
		stage.look_at(Vector3(side * -0.2, TABLE_Y, 0.1))
		stage.light_color = Color("b06aa0") if side < 0 else Color("7f8fd0")
		stage.light_energy = 2.5
		stage.spot_range = 4.0
		stage.spot_angle = 22.0

	# rotes Gegenlicht hinter dem Gegner
	var rim := OmniLight3D.new()
	rim.position = Vector3(0, 1.9, -1.5)
	rim.light_color = Color("7a4fd6")
	rim.light_energy = 2.2
	rim.omni_range = 2.2
	add_child(rim)

	# eigener Lichtkegel auf das Mittelfeld, damit die Tischkarten herausstechen
	var field := SpotLight3D.new()
	field.position = Vector3(0, 1.75, TABLE_ROW_Z + 0.35)
	add_child(field)
	field.look_at(Vector3(0, TABLE_Y, TABLE_ROW_Z + 0.02))
	field.light_color = Color("fff1d8")
	field.light_energy = 1.6
	field.spot_range = 2.0
	field.spot_angle = 24.0
	field.spot_angle_attenuation = 0.6
	field.shadow_enabled = false

	# schwaches Fülllicht von vorne, damit die Hand lesbar bleibt
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 1.5, 1.1)
	fill.light_color = Color("ffe6c4")
	fill.light_energy = 0.35
	fill.omni_range = 1.4
	add_child(fill)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 64.0
	camera.near = 0.03
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 1.36, 0.86), Vector3(0, 1.0, -0.3))
	_cam_base = camera.transform
	camera.current = true


# --- Bausteine ------------------------------------------------------------------


func _flat_line(center: Vector3, size: Vector2, material: Material) -> void:
	var m := QuadMesh.new()
	m.size = size
	var mi := _add(m, center, material)
	mi.rotation_degrees.x = -90
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _flat_rect(center: Vector3, size: Vector2, w: float, material: Material) -> void:
	_flat_line(center + Vector3(0, 0, -size.y * 0.5), Vector2(size.x, w), material)
	_flat_line(center + Vector3(0, 0, size.y * 0.5), Vector2(size.x, w), material)
	_flat_line(center + Vector3(-size.x * 0.5, 0, 0), Vector2(w, size.y), material)
	_flat_line(center + Vector3(size.x * 0.5, 0, 0), Vector2(w, size.y), material)


func _add(mesh: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	add_child(mi)
	return mi


func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m
