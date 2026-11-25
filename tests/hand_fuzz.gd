extends Node
## Fuzz-Test fürs Hand-Layout: spielt 90 s lang Duelle (klickt Karten, fährt mit der „Maus“
## über Karten, setzt zufällig Items ein) und prüft laufend, dass
##   - jede Handkarte an ihrem Platz ankommt (HÄNGT),
##   - das Layout zum Spielstand passt (LAYOUT VERALTET),
##   - keine Karte an zwei Orten liegt (DOPPELT),
##   - in der Hand keine Lücke länger als 1 s klafft (LÜCKE).
## Ausführen:  godot --headless --path . res://tests/hand_fuzz.tscn

var _bot := SimpleAI.new(RandomNumberGenerator.new(), 0.0)
var _rng := RandomNumberGenerator.new()
var _stuck := {}
var _fails := 0
var _magnets := 0
var _turns := 0
var _cool := 0.0
var _dbg := 0.0
var _lay := 0.0
var _gap := 0.0
var USE_MAGNET := false

func _ready() -> void:
	Profile.reset_for_tests()
	_rng.seed = 23
	Engine.time_scale = 5.0
	_go.call_deferred()

func _go() -> void:
	var placeholder := Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	Run.start_new_run(4223)
	await get_tree().create_timer(0.3).timeout
	Run.goto(Run.SCENE_MATCH)
	await get_tree().create_timer(90.0, true, false, true).timeout
	print("Züge %d, Magnete %d, Fehler %d" % [_turns, _magnets, _fails])
	get_tree().quit()

func _process(delta: float) -> void:
	var scene := get_tree().current_scene
	if scene == null or scene.name != "Match":
		return
	var duel: DurakMatch = scene.duel
	var w: TableWorld = scene.world
	if duel == null or w == null:
		return
	# Invariante 4: sichtbare Lage (inkl. Federn im Körper) – Abstände in der Hand gleichmäßig
	var xs: Array[float] = []
	var skipped: Array[String] = []
	var all_still := true
	for c: Card in duel.player_hand:
		var nd: Card3D = w._cards.get(c)
		if nd == null:
			all_still = false
			break
		var tw2: Tween = nd.get_meta("tween") if nd.has_meta("tween") else null
		if tw2 != null and tw2.is_valid() and tw2.is_running():
			# noch unterwegs: zählt nur, wenn sie schon in der Hand angekommen sein müsste
			if nd.global_position.distance_to(w._rest_xf(nd).origin) < 0.02:
				all_still = false
				break
			skipped.append("%s(d=%.2f hold=%s)" % [c, nd.global_position.distance_to(w._rest_xf(nd).origin), w._hold.has(nd)])
			continue
		xs.append(nd._body.global_position.x)
	if all_still and xs.size() >= 3:
		var gaps: Array[float] = []
		for k in xs.size() - 1:
			gaps.append(xs[k + 1] - xs[k])
		var mn: float = gaps.min()
		var mx: float = gaps.max()
		if mx > mn * 1.6 + 0.01 or mn < -0.001:
			_gap += delta
			if _gap > 1.0 and _gap - delta <= 1.0:
				_fails += 1
				print("LÜCKE: hand ", duel.player_hand, " unterwegs ", skipped, " busy ", snappedf(w.busy_until() - Time.get_ticks_msec() / 1000.0, 0.1), " held ", w._hold.size())
		else:
			_gap = 0.0
	# Invariante 3: keine Karte an zwei Orten
	var seen := {}
	for c in duel.player_hand + duel.opponent_hand + duel.attack_cards + duel.defense_cards + duel.discard_pile:
		if c == null:
			continue
		if seen.has(c):
			_fails += 1
			print("DOPPELT: ", c)
		seen[c] = true
	# Invariante 2: Platz entspricht dem aktuellen Layout (sync gelaufen?)
	var n := duel.player_hand.size()
	for i in n:
		var nd: Card3D = w._cards.get(duel.player_hand[i])
		if nd == null or not w._base.has(nd):
			continue
		var want := w._player_hand_xf(i, n).origin
		if (w._base[nd] as Transform3D).origin.distance_to(want) > 0.005:
			_lay += delta
			if _lay > 0.5 and _lay - delta <= 0.5:
				_fails += 1
				print("LAYOUT VERALTET: ", duel.player_hand[i], " i=", i, "/", n)
			break
		if i == n - 1:
			_lay = 0.0
	# Invariante: Handkarte ohne laufende Bewegung liegt an ihrem Platz
	for c: Card in duel.player_hand:
		var node: Card3D = w._cards.get(c)
		if node == null or not w._base.has(node):
			continue
		var tw: Tween = node.get_meta("tween") if node.has_meta("tween") else null
		var moving := tw != null and tw.is_valid() and tw.is_running()
		var d := node.transform.origin.distance_to(w._rest_xf(node).origin)
		if not moving and d > 0.03 and not node.hovered:
			_stuck[c] = _stuck.get(c, 0.0) + delta
			if _stuck[c] > 0.5 and _stuck[c] - delta <= 0.5:
				_fails += 1
				print("HÄNGT: ", c, " abstand ", snappedf(d, 0.01), " tween ", tw != null, " gültig ", tw != null and tw.is_valid())
		else:
			_stuck.erase(c)
	_dbg += delta
	if _dbg > 10.0:
		_dbg = 0.0
		print("t actor=", duel.current_actor(), " over=", duel.is_over, " hand=", duel.player_hand.size(), " busy=", w.busy_until() - Time.get_ticks_msec() / 1000.0)
	if duel.is_over:
		Run.start_new_run(_rng.randi())
		Run.goto(Run.SCENE_MATCH)
		return
	_cool -= delta
	if _cool > 0.0:
		return
	_cool = _rng.randf_range(0.05, 0.6)
	if _rng.randf() < 0.15:
		var it: StringName = [&"magnet", &"lighter", &"swap", &"mirror", &"schnaps"][_rng.randi_range(0, 4)]
		Run.items.clear()
		Run.items.append(it)
		_magnets += 1
		scene._use_item(0)
		if it == &"lighter" and scene._burning >= 0 and not scene._playable.is_empty():
			scene._on_player_card(scene._playable[0])
		if it == &"swap" and scene._swapping >= 0:
			scene._swapping = -1
			scene.hud.close_card_picker() if scene.hud.has_method("close_card_picker") else null
	# Maus: zufällig über Karten fahren (auch über fliegende)
	var nodes: Array = w._cards.values()
	if not nodes.is_empty():
		for k in 2:
			var hn: Card3D = nodes[_rng.randi_range(0, nodes.size() - 1)]
			hn._set_hovered(_rng.randf() < 0.5)
	if Time.get_ticks_msec() / 1000.0 < w.busy_until():
		return
	if duel.current_actor() == DurakMatch.PLAYER or (duel.defender() != DurakMatch.PLAYER and _rng.randf() < 0.3):
		var pl: Array = scene._playable
		if not pl.is_empty() and _rng.randf() < 0.8:
			_turns += 1
			scene._on_player_card(pl[_rng.randi_range(0, pl.size() - 1)])
			if scene.hud.has_method("close_choice"):
				pass
		elif duel.current_actor() == DurakMatch.PLAYER:
			_turns += 1
			_bot.take_turn(duel, DurakMatch.PLAYER)
