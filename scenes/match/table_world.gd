class_name TableWorld
extends Node3D
## Die 3D-Welt des Duells: dunkle Kammer, Spieltisch, Licht, Kamera
## (Ich-Perspektive) und die Gestalt gegenüber. Kümmert sich außerdem
## darum, die Karten an ihre Plätze zu bewegen (sync).
##
## Raum, Tisch und Requisiten sind Blender-Modelle (art/blender/*.blend →
## assets/models/*.glb). Licht, Kamera und Spielfeld-Markierungen bleiben hier.

signal card_clicked(card: Card)
## Maus über einer Karte (für die Shift-Info) bzw. über dem Nachziehstapel
signal card_hovered(card: Card, on: bool)
signal deck_hovered(on: bool)
## Karte aus der Hand auf den Tisch gezogen: `target` = Angriffskarte darunter (-1: freie Fläche)
## `slot`: Platz in der Angriffsreihe nach der Mausposition (links/rechts von den anderen)
signal card_dropped(card: Card, target: int, slot: int)
## Der sichtbare Ablagestapel ist gewachsen oder geschrumpft (Magnet ein-/ausgrauen).
signal discard_changed

const MODELS: Array[PackedScene] = [
	preload("res://assets/models/room.glb"),
	preload("res://assets/models/table.glb"),
	preload("res://assets/models/props.glb"),
]
## Teile der Hängelampe dürfen keinen Schatten werfen (das Licht sitzt darin).
const NO_SHADOW := ["Gluehbirne", "Lampenschirm", "Lampenschirm_Innen", "Lampenfassung", "Lampenkabel"]

const TABLE_Y := 0.80
const TABLE_SIZE := Vector2(1.6, 1.2) # x, z

## so lange bleibt eine nachgeworfene Karte liegen, bevor alles aufgenommen wird
const THROWN_PAUSE := 0.9
## Flugzeit des Spiegels hinter dem Gegner (langsam, damit man ihn sieht)
const MIRROR_TIME := 4.2
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
const DISCARD_DELAY := 1.5
const PLAYER_ASHTRAY_POS := Vector3(-0.6, TABLE_Y, 0.27)
const DEAL_STAGGER := 0.07
const HOVER_LIFT := Vector3(0, 0.035, -0.02)

## "fan" = Fächer, erst ab HAND_ROW_THRESHOLD zwei Reihen.
## "rows" = schon ab 11 Karten zwei Reihen (zum Vergleichen).
static var hand_layout := "fan"

var camera: Camera3D
var figure: OpponentFigure
var props: TableProps
## Aschenbecher: hinten (Deko) und im Duell deiner vorne links (anklickbar)
var ashtray: Ashtray
## Whiskeyflasche (im Hauptmenü zum Nachschenken anklickbar)
var whiskey: WhiskeyBottle
## Welcher Raum gebaut wird (Rooms.HINTERZIMMER, Rooms.CASINO …) – vor build()/build_room() setzen.
var room_id: StringName = Rooms.HINTERZIMMER
## Nur im Casino: Raum mit Roulette und Spielautomaten
var casino: CasinoRoom
## nur im Bahnhofswartesaal gesetzt
var station: StationRoom
## Kamera schwenkt leicht mit der Maus (aus im Menü-Hintergrund möglich).
var sway_strength := 1.0

var _cards := {} # Card -> Card3D
var _base := {} # Card3D -> Transform3D (Ziel ohne Hover)
## Gegnerkarten, die der Spiegel verraten hat (liegen offen in seiner Hand)
var revealed := {}
## Neue Karte startet hier statt auf dem Stapel (Card → Transform3D)
var spawn_from := {}
## Handkarten, die bis zum Austeilen zusammengerückt sind: Card3D -> Transform3D
var _hold := {}
## Kartentausch: diese Karten wandern in den Nachziehstapel (statt auf den Ablagestapel)
var into_deck := {}
var _animate_trump := false
## Tisch beim letzten sync (um eine Karte, die die Runde sofort beendet, noch hinzulegen)
var _last_attacks: Array[Card] = []
var _last_defs: Array[Card] = []
var _deck_pile: MeshInstance3D
var _discard_pile: MeshInstance3D
var _discard_count := 0
var _deal_queue_until := 0.0
var _busy_until := 0.0
var _cam_base: Transform3D
var _mouse := Vector2(0.5, 0.5)
var _env: Environment
var _lamp: SpotLight3D
## Wo jede Karte gerade liegt ("hand", "opp", "table_a", "table_d", "trump") –
## daraus ergibt sich, welche Bewegung sie beim nächsten sync macht.
var _zone := {}
## Karte, die gerade geschoben wurde (bekommt den Wirbel-Flug)
var _transfer_card: Card
var _shake := 0.0
var _ring_tex: Texture2D


func _ready() -> void:
	Settings.changed.connect(_on_settings_changed)


## Nur Raum, Licht, Kamera und (optional) die Gestalt – ohne Karten.
## Wird auch vom 3D-Hauptmenü und als Hintergrund benutzt.
func build_room(opponent: OpponentData, markings := true) -> void:
	_build_environment()
	_build_models()
	if room_id == Rooms.HINTERZIMMER: # Aschenbecher und Whiskey gehören zum Hinterzimmer
		ashtray = Ashtray.new()
		# Zigarette des Gegners: Filter zeigt zu ihm (Platz gegenüber)
		ashtray.notch_dir = (Vector3(0, 0, -TABLE_SIZE.y * 0.5) - Ashtray.BACK_CENTER) * Vector3(1, 0, 1)
		add_child(ashtray)
		ashtray.hide_model_parts(self)
		whiskey = WhiskeyBottle.new()
		add_child(whiskey)
		whiskey.hide_model_parts(self)
	if markings:
		_build_markings()
	_build_lights()
	_build_camera()
	if opponent != null:
		figure = OpponentFigure.new().setup(opponent)
		figure.position = Vector3(0, 0, -TABLE_SIZE.y * 0.5)
		add_child(figure)


## Kamera auf eine neue Grundstellung setzen (Menü-Kamerafahrten).
func set_camera_pose(xf: Transform3D) -> void:
	_cam_base = xf


func get_camera_pose() -> Transform3D:
	return _cam_base


## Optionen live übernehmen (Leuchten, Helligkeit, Schatten).
func _on_settings_changed() -> void:
	Settings.apply_environment(_env, 1.05)
	if _lamp != null:
		_lamp.shadow_enabled = Settings.shadows_enabled()


func build(opponent: OpponentData) -> void:
	build_room(opponent)
	if room_id == Rooms.HINTERZIMMER:
		# eigener Aschenbecher mit Zigarette vorne links neben den Kerzen (anklickbar)
		ashtray = Ashtray.new()
		ashtray.center = PLAYER_ASHTRAY_POS
		ashtray.notch_dir = Vector3(0.5, 0, 0.87)
		ashtray.interactive = true
		ashtray.starts_empty = true # die Zigarette kommt aus der Schachtel daneben
		add_child(ashtray)
		var pack := CigarettePack.new()
		pack.ashtray = ashtray
		pack.position = Vector3(-0.52, TABLE_Y, 0.2) # rechts neben dem Aschenbecher, vor den Kerzen
		pack.rotation.y = 0.35
		add_child(pack)
	elif casino != null:
		# im Casino: Roulette und Spielautomaten zum Anklicken
		casino.roulette.interactive = true
		for s in casino.slots:
			s.interactive = true
	props = TableProps.new()
	props.chip_style = room_id == Rooms.CASINO # Pokerchips statt Goldmünzen
	props.lamp_style = room_id == Rooms.CASINO # grüne Bankerlampe statt Kerzen
	if station != null:
		props.external_lives = station.lives_panel # LED-Anzeige an der Wand statt Kerzen
		# vorbeifahrender Zug: Bild zittert leicht
		station.train_passing.connect(func(strength: float) -> void: shake(0.35 * strength))
	add_child(props)
	_deck_pile = _pile_mesh()
	_deck_pile.position = DECK_POS
	_deck_pile.rotation_degrees.y = 90
	add_child(_deck_pile)
	# Maus über dem Stapel (samt Trumpfkarte) → Anzahl der Karten anzeigen
	var deck_area := Area3D.new()
	deck_area.input_ray_pickable = true
	var deck_shape := CollisionShape3D.new()
	var deck_box := BoxShape3D.new()
	deck_box.size = Vector3(Card3D.HEIGHT + 0.07, 0.06, Card3D.WIDTH + 0.02)
	deck_shape.shape = deck_box
	deck_area.add_child(deck_shape)
	deck_area.position = DECK_POS + Vector3(0.03, 0.03, 0)
	deck_area.mouse_entered.connect(func() -> void: deck_hovered.emit(true))
	deck_area.mouse_exited.connect(func() -> void: deck_hovered.emit(false))
	add_child(deck_area)
	_discard_pile = _pile_mesh()
	_discard_pile.position = DISCARD_POS
	_discard_pile.rotation_degrees.y = 12
	_discard_pile.visible = false
	add_child(_discard_pile)


func _process(delta: float) -> void:
	# leichtes Mitschwenken der Kamera mit der Maus
	if camera == null:
		return
	var vp := get_viewport()
	if vp != null:
		var size := vp.get_visible_rect().size
		if size.x > 0:
			_mouse = _mouse.lerp(vp.get_mouse_position() / size, 0.08)
	var sway := sway_strength if Settings.camera_sway() else 0.0
	var yaw := (_mouse.x - 0.5) * -0.06 * sway
	var pitch := (_mouse.y - 0.5) * -0.04 * sway
	_follow_hand()
	var shake := Vector3.ZERO
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)
		var amp := _shake * _shake * 0.012
		shake = Vector3(randf_range(-amp, amp), randf_range(-amp, amp), 0)
	camera.transform = _cam_base * Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0)), shake)


# --- Karten-Layout --------------------------------------------------------------

## Bringt alle Karten an die Plätze, die dem Spielstand entsprechen.
func sync(duel: DurakMatch, playable: Array[Card]) -> void:
	var targets := {} # Card -> [Transform3D, face_up: bool, zone: String]
	var beats := {} # Verteidigungskarte -> Angriffskarte darunter

	var hand := duel.player_hand
	for i in hand.size():
		targets[hand[i]] = [_player_hand_xf(i, hand.size()), true, "hand"]
	var opp := duel.opponent_hand
	for i in opp.size():
		var oxf := _opp_hand_xf(i, opp.size())
		if revealed.has(opp[i]):
			# verratene Karte ragt offen und größer aus seinem Fächer heraus
			oxf = Transform3D(oxf.basis.scaled_local(Vector3.ONE * 1.3), oxf.origin + oxf.basis * Vector3(0, 0.004, -0.07))
		targets[opp[i]] = [oxf, revealed.has(opp[i]), "opp"]
	for i in duel.attack_cards.size():
		targets[duel.attack_cards[i]] = [_table_xf(i, duel.attack_cards.size(), false, duel.attack_cards[i]), true, "table_a"]
		var d: Card = duel.defense_cards[i]
		if d != null:
			targets[d] = [_table_xf(i, duel.attack_cards.size(), true, d), true, "table_d"]
			beats[d] = duel.attack_cards[i]
	if not duel.deck.is_empty() and not duel.trump_hidden:
		targets[duel.trump_card] = [_trump_xf(), true, "trump"]

	# Stapelhöhe
	var deck_left := duel.deck.size() - (1 if not duel.deck.is_empty() and not duel.trump_hidden else 0)
	_deck_pile.visible = deck_left > 0
	_set_pile_height(_deck_pile, DECK_POS, deck_left)

	var now := Time.get_ticks_msec() / 1000.0
	var deal_start := maxf(now, _deal_queue_until)
	# Erst abräumen bzw. aufnehmen, dann nachziehen (besser zu verstehen):
	# verschwinden Karten vom Tisch, warten neue Karten, bis das erledigt ist.
	# (Verzögerungen werden in _move noch mit dem Animationstempo verrechnet)
	for c: Card in _cards:
		if not targets.has(c):
			deal_start = maxf(deal_start, now + DISCARD_DELAY + MOVE_TIME + 0.55)
			break
	for c: Card in _cards:
		if _zone.get(c, "") in ["table_a", "table_d"] and targets.has(c) and targets[c][2] in ["hand", "opp"]:
			deal_start = maxf(deal_start, now + 0.75)
			break
	var new_count := 0
	var take_i := 0
	# Nachgeworfene Karte, die die Runde sofort beendet (Gegner nimmt alles): direkt von einer
	# Hand in die andere. Sie soll erst sichtbar auf dem Tisch landen, dann wird alles genommen.
	var thrown: Array[Card] = []
	for c: Card in targets:
		var pz: String = _zone.get(c, "")
		var nz: String = targets[c][2]
		if pz in ["hand", "opp"] and nz in ["hand", "opp"] and pz != nz:
			thrown.append(c)
	var take_wait := (MOVE_TIME + THROWN_PAUSE) if not thrown.is_empty() else 0.0
	if take_wait > 0.0:
		deal_start = maxf(deal_start, now + take_wait + 0.9)

	# Neue Handkarten (Austeilen) und aufgenommene Karten warten oft, bis der Tisch abgeräumt
	# bzw. die nachgeworfene Karte gelandet ist. Bis dahin rücken die Handkarten zusammen
	# (sonst klafft an den späteren Plätzen eine Lücke) und machen erst Platz, wenn die
	# Karten wirklich kommen.
	var compact := {} # Card -> Transform3D ohne die noch fehlenden Karten
	var make_room_at := INF # wann die erste fehlende Karte losfliegt (Sekunden ab jetzt)
	var present: Array[Card] = []
	for c: Card in hand:
		var pz: String = _zone.get(c, "new")
		if pz == "hand":
			present.append(c)
		elif not _cards.has(c) and not spawn_from.has(c):
			make_room_at = minf(make_room_at, deal_start - now)
		elif pz in ["table_a", "table_d", "opp"]:
			make_room_at = minf(make_room_at, take_wait)
		else:
			make_room_at = 0.0 # z. B. Magnet, Kartentausch: kommt sofort
	if present.size() < hand.size() and make_room_at > 0.15 and make_room_at < INF:
		for i in present.size():
			compact[present[i]] = _player_hand_xf(i, present.size())

	for card: Card in targets:
		var xf: Transform3D = targets[card][0]
		var face_up: bool = targets[card][1]
		var zone: String = targets[card][2]
		if not face_up:
			xf.basis = xf.basis * Basis(Vector3.FORWARD, PI) # umdrehen
		var node: Card3D = _cards.get(card)
		var delay := 0.0
		var style := ""
		var prev: String = _zone.get(card, "new")
		if node == null:
			node = Card3D.create(card, card.suit == duel.trump_suit)
			node.transform = _deck_top_xf()
			var from_pile := spawn_from.has(card)
			if from_pile: # z. B. Magnet: kommt vom Ablagestapel
				node.transform = spawn_from[card]
				spawn_from.erase(card)
			add_child(node)
			node.grabbed.connect(_on_grabbed)
			node.hover_changed.connect(_on_hover)
			_cards[card] = node
			if from_pile:
				delay = 0.35 # kurz am Stapel „ziehen“ lassen, dann fliegt sie in die Hand
				style = "magnet"
			elif card != duel.trump_card or duel.deck.is_empty():
				delay = deal_start - now + new_count * DEAL_STAGGER
				new_count += 1
				style = "deal"
			elif _animate_trump: # Kartentausch: neue offene Karte unter dem Stapel
				_animate_trump = false
				delay = 0.6
				style = "deal"
			else:
				node.transform = xf # Trumpfkarte liegt von Anfang an
		elif prev in ["hand", "opp"] and zone in ["table_a", "table_d"]:
			style = "whirl" if card == _transfer_card else "play"
		elif prev in ["table_a", "table_d"] and zone in ["hand", "opp"]:
			style = "take"
			delay = take_wait + take_i * 0.06
			take_i += 1
		elif thrown.has(card):
			_zone[card] = zone
			node.in_hand = zone == "hand"
			node.set_state(false)
			_base[node] = xf
			var slot := _last_attacks.size() + thrown.find(card)
			var txf := _table_xf(slot, _last_attacks.size() + thrown.size(), false, card)
			var tw0 := _move(node, txf, 0.0, MOVE_TIME, "play")
			var final_xf := xf
			var i_take := take_i
			take_i += 1
			tw0.finished.connect(func() -> void:
				_on_landed(node, "play", card.suit == duel.trump_suit, null)
				if is_instance_valid(node) and _cards.get(card) == node:
					_move(node, final_xf, THROWN_PAUSE + i_take * 0.06, MOVE_TIME, "take"))
			continue
		elif prev == "trump" and zone in ["hand", "opp"]:
			style = "deal"
		_zone[card] = zone
		node.in_hand = zone == "hand"
		node.set_state(playable.has(card))
		if compact.has(card) and zone == "hand" and style == "" \
				and not (compact[card] as Transform3D).is_equal_approx(xf):
			# erst zusammenrücken, Platz machen erst, wenn die neuen Karten kommen
			_base[node] = xf
			_hold[node] = compact[card]
			_move(node, _with_hover(node, compact[card]), delay, MOVE_TIME)
			_make_room_later(node, xf, make_room_at)
		elif not _base.has(node) or not _base[node].is_equal_approx(xf):
			_base[node] = xf
			_hold.erase(node)
			var tw := _move(node, _with_hover(node, xf), delay, MOVE_TIME, style)
			if style != "":
				var strong := card.suit == duel.trump_suit and style in ["play", "whirl"]
				var under: Card = beats.get(card)
				tw.finished.connect(_on_landed.bind(node, style, strong, under))
		if card == _transfer_card:
			_transfer_card = null
	if new_count > 0:
		_deal_queue_until = deal_start + new_count * DEAL_STAGGER
		var f := Settings.anim_time_factor()
		_busy_until = now + (deal_start - now + new_count * DEAL_STAGGER + 0.42) * f
	var last_attacks := _last_attacks
	var last_defs := _last_defs
	_last_attacks = duel.attack_cards.duplicate()
	_last_defs = duel.defense_cards.duplicate()

	# Karten, die nirgends mehr sind → Ablagestapel (Fertig: umdrehen, wegwirbeln)
	var discard_i := 0
	for card: Card in _cards.keys():
		if targets.has(card):
			continue
		var node: Card3D = _cards[card]
		var prev_zone: String = _zone.get(card, "")
		_cards.erase(card)
		_base.erase(node)
		_hold.erase(node)
		_zone.erase(card)
		node.in_hand = false
		node.set_state(false)
		if into_deck.has(card):
			into_deck.erase(card)
			# verdeckt in den Stapel stecken und dort verschwinden
			var dxf := Transform3D(Basis(Vector3.FORWARD, PI) * Basis(Vector3.UP, 0.4), DECK_POS + Vector3(0.0, 0.06, 0.0))
			var twd := _move(node, dxf, 0.0, 0.6, "take")
			twd.finished.connect(node.queue_free)
			continue
		var wait := DISCARD_DELAY + discard_i * 0.07
		discard_i += 1
		# Letzte Verteidigungskarte direkt aus der Hand (Runde endet sofort): erst sichtbar
		# auf die geschlagene Karte legen, dann mit den anderen abräumen.
		var idx := _beaten_slot(card, last_attacks, last_defs, duel.trump_suit) if prev_zone in ["hand", "opp"] else -1
		if idx >= 0:
			last_defs[idx] = card
			var txf := _table_xf(idx, last_attacks.size(), true, card)
			var tw0 := _move(node, txf, 0.0, MOVE_TIME, "play")
			var under: Card = last_attacks[idx]
			tw0.finished.connect(func() -> void:
				_on_landed(node, "play", card.suit == duel.trump_suit, under)
				if is_instance_valid(node):
					_to_discard(node, DISCARD_DELAY))
		else:
			_to_discard(node, wait)
	into_deck.clear()
	_animate_trump = false


## Handkarte rückt nach `wait` Sekunden an ihren endgültigen Platz – falls bis dahin kein
## neuer sync etwas anderes vorhat.
func _make_room_later(node: Card3D, xf: Transform3D, wait: float) -> void:
	get_tree().create_timer(wait * Settings.anim_time_factor(), false).timeout.connect(func() -> void:
		if not is_instance_valid(node):
			return
		if _hold.has(node) and _base.has(node) and (_base[node] as Transform3D).is_equal_approx(xf):
			_hold.erase(node)
			_move(node, _with_hover(node, xf), 0.0, MOVE_TIME))


## Wo eine Handkarte gerade ruht (zusammengerückt oder an ihrem Platz).
func _rest_xf(node: Card3D) -> Transform3D:
	return _hold.get(node, _base[node])


## Welche Angriffskarte der letzten Runde hat `card` geschlagen? (-1: keine)
func _beaten_slot(card: Card, attacks: Array, defs: Array, trump: Card.Suit) -> int:
	for i in attacks.size():
		if i < defs.size() and defs[i] == null and DurakRules.can_beat(attacks[i], card, trump):
			return i
	return -1


func _to_discard(node: Card3D, delay: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, randf_range(-0.3, 0.3)) * Basis(Vector3.FORWARD, PI), DISCARD_POS + Vector3(0, 0.02, 0))
	var tw := _move(node, xf, delay, 0.45, "bito")
	tw.finished.connect(func() -> void:
		_discard_count += 1
		_discard_pile.visible = true
		_set_pile_height(_discard_pile, DISCARD_POS, _discard_count)
		discard_changed.emit()
		node.queue_free())


## Gegnerkarten bewegen sich mit der Hand der Gestalt (Atmen, Ausspielen, Trommeln …).
func _follow_hand() -> void:
	if figure == null:
		return
	var delta := figure.card_pivot() - figure.card_pivot_rest()
	for card: Card in _cards:
		if _zone.get(card, "") != "opp":
			continue
		var node: Card3D = _cards[card]
		if node.has_meta("tween") and (node.get_meta("tween") as Tween).is_running():
			continue
		if _base.has(node):
			node.position = (_base[node] as Transform3D).origin + delta


## Solange noch ausgeteilt wird (Zeitpunkt in Sekunden, wie Time.get_ticks_msec()/1000):
## so lange darf der Spieler nicht ausspielen – sonst könnte er mit Karten angreifen,
## die er noch gar nicht sieht.
func busy_until() -> float:
	return _busy_until


## Die nächste Karte, die aus einer Hand auf den Tisch geht, wurde geschoben.
func note_transfer(card: Card) -> void:
	_transfer_card = card


## Bildschirm kurz wackeln lassen (nur wenn Kamera-Schwenk an ist).
func shake(amount: float) -> void:
	if Settings.camera_sway():
		_shake = maxf(_shake, amount)


func _on_landed(node: Card3D, style: String, strong: bool, under: Card) -> void:
	if not is_instance_valid(node):
		return
	match style:
		"deal":
			node.land(0.45)
		"take":
			node.land(0.35)
		"play", "whirl":
			_sfx(&"card_play", randf_range(0.92, 1.05) * (0.9 if strong else 1.0), 2.0 if strong else 0.0)
			node.land(1.0)
			_impact(node.global_position, strong)
			shake(0.9 if strong else 0.45)
			if under != null and _cards.has(under):
				var below: Card3D = _cards[under]
				below.nudge(below.global_position - node.global_position, 1.0)


## Staubring auf dem Filz, wo eine Karte aufschlägt (Trumpf: goldener Blitz).
func _impact(pos: Vector3, strong: bool) -> void:
	if _ring_tex == null:
		var grad := Gradient.new()
		grad.set_offset(0, 0.0)
		grad.set_color(0, Color(1, 1, 1, 0))
		grad.set_offset(1, 1.0)
		grad.set_color(1, Color(1, 1, 1, 0))
		grad.add_point(0.62, Color(1, 1, 1, 0.0))
		grad.add_point(0.8, Color(1, 1, 1, 1))
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 128
		gt.height = 128
		_ring_tex = gt
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = _ring_tex
	mat.albedo_color = Color(1, 0.85, 0.5, 0.8) if strong else Color(0.95, 0.9, 0.8, 0.45)
	mat.no_depth_test = false
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation_degrees.x = -90
	mi.position = Vector3(pos.x, TABLE_Y + 0.0012, pos.z)
	mi.scale = Vector3.ONE * 0.35
	add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * (1.4 if strong else 1.0), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tw.tween_callback(mi.queue_free)


# --- Items ------------------------------------------------------------------------------

## Liegt sichtbar mindestens eine Karte auf dem Ablagestapel?
func has_discard() -> bool:
	return _discard_count > 0


## Magnet: eine Karte vom Ablagestapel holen – Stapel wird niedriger, Karte fliegt von dort.
func take_from_discard(card: Card) -> void:
	_discard_count = maxi(0, _discard_count - 1)
	_set_pile_height(_discard_pile, DISCARD_POS, _discard_count)
	_discard_pile.visible = _discard_count > 0
	discard_changed.emit()
	spawn_from[card] = Transform3D(Basis(Vector3.FORWARD, PI), DISCARD_POS + Vector3(0, 0.03, 0))


## Kartentausch: `card` geht gleich in den Nachziehstapel, unten erscheint eine neue offene Karte.
## Vor der Änderung am Duell aufrufen.
func send_to_deck(card: Card) -> void:
	into_deck[card] = true


## Feuerzeug gezückt: diese Gegnerkarten bekommen einen leuchtenden Rahmen (leer = aus).
func set_burn_targets(cards: Array) -> void:
	for c: Card in _cards:
		(_cards[c] as Card3D).set_target(cards.has(c))


## Feuerzeug: Karte auf dem Tisch verbrennt (Flammen, Glut, Knistern) und löst sich auf.
## Vor dem nächsten sync aufrufen – die Karte wird nicht mehr abgeräumt.
func burn(card: Card) -> void:
	var node: Card3D = _cards.get(card)
	if node == null:
		return
	_cards.erase(card)
	_base.erase(node)
	_hold.erase(node)
	_zone.erase(card)
	if node.has_meta("tween"):
		(node.get_meta("tween") as Tween).kill()
	Sfx.play(&"burn")
	node.burn_away(1.1)
	var base := node.global_position
	for i in 14:
		var flame := Sprite3D.new()
		flame.texture = Ashtray._puff_texture()
		flame.pixel_size = 1.0 / 64.0
		flame.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		flame.shaded = false
		flame.transparent = true
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.top_level = true
		flame.modulate = Color(1.0, randf_range(0.45, 0.75), 0.15, 0.0)
		flame.scale = Vector3.ONE * randf_range(0.03, 0.06)
		add_child(flame)
		flame.global_position = base + Vector3(randf_range(-0.05, 0.05), 0.01, randf_range(-0.07, 0.07))
		var start := i * 0.06
		var tw := flame.create_tween()
		tw.tween_interval(start)
		tw.tween_property(flame, "modulate:a", 0.9, 0.08)
		tw.parallel().tween_property(flame, "global_position:y", base.y + randf_range(0.06, 0.14), 0.6).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(flame, "scale", Vector3.ONE * 0.012, 0.6)
		tw.parallel().tween_property(flame, "modulate", Color(0.25, 0.22, 0.2, 0.0), 0.6).set_delay(0.15)
		tw.tween_callback(flame.queue_free)
	# kurzes Glutlicht
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.omni_range = 0.5
	light.light_energy = 0.0
	add_child(light)
	light.global_position = base + Vector3(0, 0.08, 0)
	var lt := light.create_tween()
	lt.tween_property(light, "light_energy", 1.6, 0.15)
	lt.tween_property(light, "light_energy", 0.0, 1.0)
	lt.tween_callback(light.queue_free)


## Spiegel: schwebt hinter dem Gegner von links nach rechts vorbei; in der Mitte blitzt er auf
## und `on_reveal` wird aufgerufen (dann wird eine Karte seiner Hand aufgedeckt).
func mirror_flight(on_reveal: Callable) -> void:
	var mirror := Node3D.new()
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color("c99a4a")
	frame_mat.metallic = 0.8
	frame_mat.roughness = 0.35
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.3, 0.36, 0.48)
	glass_mat.metallic = 1.0
	glass_mat.roughness = 0.05
	glass_mat.emission_enabled = true
	glass_mat.emission = Color(0.35, 0.4, 0.55)
	glass_mat.emission_energy_multiplier = 0.25
	var frame := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.16
	fm.bottom_radius = 0.16
	fm.height = 0.02
	fm.radial_segments = 32
	frame.mesh = fm
	frame.material_override = frame_mat
	frame.rotation_degrees.x = 90
	frame.scale = Vector3(0.8, 1, 1.1)
	mirror.add_child(frame)
	var glass := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.14
	gm.bottom_radius = 0.14
	gm.height = 0.024
	gm.radial_segments = 32
	glass.mesh = gm
	glass.material_override = glass_mat
	glass.rotation_degrees.x = 90
	glass.scale = Vector3(0.8, 1, 1.1)
	mirror.add_child(glass)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.75, 0.82, 1.0)
	glow.omni_range = 0.8
	glow.light_energy = 0.4
	mirror.add_child(glow)
	add_child(mirror)
	var z := -TABLE_SIZE.y * 0.5 - 0.75
	var from := Vector3(-1.6, 1.45, z)
	var to := Vector3(1.6, 1.45, z)
	mirror.position = from
	Sfx.play(&"mirror")
	var flashed := [false]
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		var p := from.lerp(to, v)
		p.y += sin(v * PI) * 0.18 + sin(v * TAU * 2.0) * 0.02
		mirror.position = p
		mirror.rotation = Vector3(0.1, sin(v * PI * 1.5) * 0.5, sin(v * TAU) * 0.12)
		if v >= 0.5 and not flashed[0]:
			flashed[0] = true
			glow.light_energy = 3.0
			glass_mat.emission_energy_multiplier = 4.0
			on_reveal.call()
		glow.light_energy = move_toward(glow.light_energy, 0.4, 0.08)
		glass_mat.emission_energy_multiplier = move_toward(glass_mat.emission_energy_multiplier, 0.25, 0.1),
		0.0, 1.0, MIRROR_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(mirror.queue_free)


# --- Klicken und Ziehen -----------------------------------------------------------------

const DRAG_START_PX := 10.0
const DROP_RADIUS := 0.09
var _drag_node: Card3D
var _drag_from := Vector2.ZERO
var _dragging := false


func _on_grabbed(node: Card3D) -> void:
	_drag_node = node
	_drag_from = get_viewport().get_mouse_position()
	_dragging = false


func _input(event: InputEvent) -> void:
	if _drag_node == null:
		return
	if not is_instance_valid(_drag_node):
		_drag_node = null
		return
	if event is InputEventMouseMotion and not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		# Loslassen verpasst (z. B. über der Oberfläche): Ziehen abbrechen
		if _dragging and _base.has(_drag_node):
			_move(_drag_node, _rest_xf(_drag_node), 0.0, 0.18)
		_drag_node = null
		_dragging = false
		return
	if event is InputEventMouseMotion:
		var pos: Vector2 = event.position
		if not _dragging and pos.distance_to(_drag_from) > DRAG_START_PX and _drag_node.in_hand:
			_dragging = true
			if _drag_node.has_meta("tween"):
				(_drag_node.get_meta("tween") as Tween).kill()
		if _dragging:
			var p := _mouse_on_table(pos, 0.07)
			var flat := Basis(Vector3.UP, 0.0).scaled(Vector3.ONE * TABLE_CARD_SCALE)
			_drag_node.transform = _drag_node.transform.interpolate_with(Transform3D(flat, p), 0.5)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var node := _drag_node
		var was_drag := _dragging
		_drag_node = null
		_dragging = false
		if not was_drag:
			card_clicked.emit(node.card)
			return
		var p := _mouse_on_table(event.position, 0.0)
		# erst zurück an den Platz – klappt der Zug, legt sync die Karte gleich auf den Tisch
		if _base.has(node):
			_move(node, _rest_xf(node), 0.0, 0.18)
		if p.z > PLAYER_HAND_POS.z - 0.18:
			return # zurück in die Hand gezogen: nichts tun
		card_dropped.emit(node.card, _drop_target(p), _drop_slot(p))


## Punkt auf der Tischebene (plus `lift`) unter der Maus.
func _mouse_on_table(pos: Vector2, lift: float) -> Vector3:
	var o := camera.project_ray_origin(pos)
	var d := camera.project_ray_normal(pos)
	var y := TABLE_Y + 0.01 + lift
	if absf(d.y) < 0.0001:
		return o
	var t := (y - o.y) / d.y
	return o + d * maxf(t, 0.0)


## Einfügeplatz in der Angriffsreihe: so viele Angriffskarten liegen links vom Punkt.
func _drop_slot(p: Vector3) -> int:
	var slot := 0
	for c in _last_attacks:
		var a: Card3D = _cards.get(c)
		if a != null and a.global_position.x < p.x:
			slot += 1
	return slot


## Welche Angriffskarte liegt unter dem Ablagepunkt? (-1: keine)
func _drop_target(p: Vector3) -> int:
	var best := -1
	var best_d := DROP_RADIUS
	for i in _last_attacks.size():
		var a: Card3D = _cards.get(_last_attacks[i])
		if a == null:
			continue
		var d := Vector2(a.global_position.x - p.x, a.global_position.z - p.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best


func _on_hover(node: Card3D, hovered: bool) -> void:
	if node == _drag_node and _dragging:
		return
	if node.card != null and (node.in_hand or _base.has(node)):
		card_hovered.emit(node.card, hovered)
	if hovered and node.in_hand:
		_sfx(&"card_hand_hover", randf_range(0.94, 1.1)) # Handkarte ansehen: ganz leises Rascheln
	# nur Handkarten heben/senken – eine Karte, die gerade auf den Tisch fliegt, darf ihre
	# Bewegung nicht verlieren (sonst fehlen Landegeräusch und Aufprall)
	if _base.has(node) and node.in_hand:
		# Karte wartet noch im Stapel aufs Austeilen: nicht vorziehen
		if Time.get_ticks_msec() / 1000.0 < float(node.get_meta("move_starts", 0.0)):
			return
		_move(node, _with_hover(node, _rest_xf(node)), 0.0, 0.12)


func _with_hover(node: Card3D, xf: Transform3D) -> Transform3D:
	if node.hovered and (node.playable if Card3D.hints else node.in_hand):
		return Transform3D(xf.basis, xf.origin + HOVER_LIFT)
	return xf


## Kartensound, aber nicht mehrfach gleichzeitig (z. B. mehrere Karten nehmen = ein Geräusch).
var _sfx_last := {}


func _sfx(sound: StringName, pitch := 1.0, db := 0.0) -> void:
	var now := Time.get_ticks_msec()
	var gap := 60 if sound == &"card_deal" else 160
	if now - int(_sfx_last.get(sound, -1000)) < gap:
		return
	_sfx_last[sound] = now
	Sfx.play(sound, pitch, db)


## Bewegt eine Karte. `style`:
##   ""      Umordnen (kurz, weich)
##   "deal"  Austeilen: Bogen vom Stapel, dreht sich dabei um, federt beim Landen
##   "play"  Ausspielen: hoher Bogen, schnell herunter (Wumms)
##   "whirl" Schieben: wirbelt einmal um sich selbst
##   "take"  Nehmen: hoch und zurück in die Hand
##   "bito"  Abwerfen: umdrehen und mit Drall zum Ablagestapel
func _move(node: Node3D, to: Transform3D, delay: float, time := MOVE_TIME, style := "") -> Tween:
	if node.has_meta("tween"):
		var old: Tween = node.get_meta("tween")
		if old.is_valid():
			old.kill()
	var from := node.transform
	var tw := create_tween()
	node.set_meta("tween", tw)
	var lift := 0.05 if from.origin.distance_to(to.origin) > 0.15 else 0.0
	var spin := 0.0 # volle Drehungen um die Hochachse (Vielfache von TAU)
	var sway := 0.0 # Drehung hin und zurück (Bogenmaß)
	var trans := Tween.TRANS_CUBIC
	var ease_mode := Tween.EASE_OUT
	match style:
		"magnet": # vom Ablagestapel angezogen: hebt ab, wird immer schneller
			time = 0.8
			lift = 0.22
			sway = 0.3
			trans = Tween.TRANS_EXPO
			ease_mode = Tween.EASE_IN
		"deal":
			time = 0.42
			lift = 0.1
			sway = 0.5
			trans = Tween.TRANS_QUART
		"play":
			time = 0.3
			lift = 0.09
			trans = Tween.TRANS_SINE
			ease_mode = Tween.EASE_IN_OUT
		"whirl":
			time = 0.5
			lift = 0.14
			spin = TAU
			trans = Tween.TRANS_SINE
			ease_mode = Tween.EASE_IN_OUT
		"take":
			time = 0.5
			lift = 0.16
			trans = Tween.TRANS_SINE
			ease_mode = Tween.EASE_IN_OUT
		"bito":
			lift = 0.12
			spin = TAU
			trans = Tween.TRANS_QUAD
			ease_mode = Tween.EASE_IN_OUT
	var f := Settings.anim_time_factor()
	time *= f
	delay *= f
	node.set_meta("move_starts", Time.get_ticks_msec() / 1000.0 + delay)
	if delay > 0.0:
		tw.tween_interval(delay)
	match style:
		"deal":
			tw.tween_callback(func() -> void: _sfx(&"card_deal", randf_range(0.92, 1.08)))
		"take":
			tw.tween_callback(func() -> void: _sfx(&"card_take", randf_range(0.95, 1.05)))
		"bito":
			tw.tween_callback(func() -> void: _sfx(&"cards_discard", randf_range(0.95, 1.05)))
	var q_from := from.basis.get_rotation_quaternion()
	var q_to := to.basis.get_rotation_quaternion()
	var s_from := from.basis.get_scale()
	var s_to := to.basis.get_scale()
	tw.tween_method(func(t: float) -> void:
		var rot := q_from.slerp(q_to, t)
		var turn := spin * t + sway * sin(t * PI)
		if turn != 0.0:
			rot = Quaternion(Vector3.UP, turn) * rot
		var b := Basis(rot).scaled_local(s_from.lerp(s_to, t))
		var pos := from.origin.lerp(to.origin, t) + Vector3(0, sin(t * PI) * lift, 0)
		node.transform = Transform3D(b, pos),
		0.0, 1.0, time).set_trans(trans).set_ease(ease_mode)
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


## Gegnerkarten als echter Fächer, gehalten zwischen den Händen der Gestalt:
## alle Karten drehen sich um einen Punkt an der Unterkante (figure.card_pivot_rest()).
func _opp_hand_xf(i: int, n: int) -> Transform3D:
	var pivot := OPP_HAND_POS + Vector3(0, -0.06, 0.03)
	if figure != null:
		pivot = figure.card_pivot_rest()
	var offset := i - (n - 1) * 0.5
	var spread := minf(0.21, 1.25 / maxf(1, n))
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(OPP_HAND_TILT))
	var fan := Basis(Vector3.UP, -offset * spread)
	var basis := tilt * fan
	# Kartenmitte liegt ein Stück über dem Drehpunkt (Karten-„oben“ = lokal -Z)
	var pos := pivot + basis * Vector3(0, 0, -Card3D.HEIGHT * 0.38) + tilt * Vector3(0, i * 0.0012, 0)
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
	quad.size = Vector2(Card3D.WIDTH - 0.001, Card3D.HEIGHT - 0.001) # Rückseite deckt den ganzen Stapel
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
	if room_id == Rooms.CASINO: # ganz in Code gebaut, ohne die Hinterzimmer-Modelle
		casino = CasinoRoom.new()
		add_child(casino)
		casino.apply_environment(_env)
		return
	if room_id == Rooms.STATION:
		station = StationRoom.new()
		add_child(station)
		station.apply_environment(_env)
		return
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

	if casino != null:
		casino.add_lights(self) # Kronleuchter, Neonschild, Automaten
		_build_lights_common()
		return
	if station != null:
		station.add_lights(self) # Neonröhren, Fenster, Gegenlicht
		_build_lights_common()
		return
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
	_build_lights_common()


## Lichtkegel aufs Spielfeld und Fülllicht – in jedem Raum gleich.
func _build_lights_common() -> void:
	# eigener Lichtkegel auf das Mittelfeld, damit die Tischkarten herausstechen
	var field := SpotLight3D.new()
	field.position = Vector3(0, 1.75, TABLE_ROW_Z + 0.35)
	add_child(field)
	field.look_at(Vector3(0, TABLE_Y, TABLE_ROW_Z + 0.02))
	field.light_color = Color("fff1d8")
	field.light_energy = 1.15
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
