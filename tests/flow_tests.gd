extends Node
## Ablauf-Fehler, die bei der Fehlersuche gefunden wurden (Run, Händler, Duell-Ende, Tägliche).
##   godot --headless --path . res://tests/flow_tests.tscn

var _checks := 0
var _failures := 0


func check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FEHLER: " + label)
	else:
		print("ok   " + label)


func _ready() -> void:
	Profile.reset_for_tests()
	_run.call_deferred()


func _relic(id: String) -> RelicData:
	for r in Run.all_relics():
		if String(r.id) == id:
			return r
	return null


## Neuen Run starten und ins Duell gehen. Gibt die Duell-Szene zurück.
func _duel(p_seed: int) -> Node:
	var ph := Node.new()
	get_tree().root.add_child(ph)
	get_tree().current_scene = ph
	Run.start_new_run(p_seed)
	await get_tree().process_frame
	Run.goto(Run.SCENE_MATCH)
	await get_tree().process_frame
	await get_tree().process_frame
	return get_tree().current_scene


func _run() -> void:
	# --- „WEITER“ doppelt: nur ein Tisch weiter, Gold nur einmal
	var m := await _duel(77)
	m.score.add_bonus(100000, "Test")
	await get_tree().process_frame
	var gold0 := Run.gold
	m.hud.continue_button.pressed.emit()
	m.hud.continue_button.pressed.emit()
	Run.on_match_finished(DurakMatch.OPPONENT) # auch direkt ein zweites Mal: wird ignoriert
	check(Run.floor_index == 1, "WEITER doppelt: genau ein Tisch weiter (ist %d)" % Run.floor_index)
	check(Run.gold == gold0 + Run.last_gold_reward + Run.last_interest, "WEITER doppelt: Gold nur einmal")
	await get_tree().process_frame

	# --- Niederlage doppelt: nur ein Leben weg
	m = await _duel(78)
	var lives := Run.lives
	m.duel.force_finish(DurakMatch.PLAYER)
	m.hud.continue_button.pressed.emit()
	m.hud.continue_button.pressed.emit()
	check(Run.lives == lives - 1, "Niederlage doppelt bestätigt: nur ein Leben weg")
	await get_tree().process_frame

	# --- Boss-Händler: Geschenk-Relikt ist im Laden nicht noch einmal kaufbar
	var found := false
	for s in 60:
		Run._reset(1000 + s)
		Run.encounters = Run._build_encounters()
		Run.boss_shop = true
		Run.boss_gift_open = true
		Run.open_shop()
		var gift := Run.boss_gift_choices()
		for o in Run.shop_offers:
			if o.kind == "RELIKT" and gift.any(func(r: RelicData) -> bool: return r.id == o.relic_id):
				Run.take_boss_gift(gift.filter(func(r: RelicData) -> bool: return r.id == o.relic_id)[0])
				Run.gold = 100
				check(Run.is_owned(o) and not Run.buy(o), "Geschenk-Relikt im Laden nicht nochmal kaufbar")
				found = true
				break
		if found:
			break
	check(found, "Fall Geschenk = Ladenrelikt gefunden")
	await get_tree().process_frame

	# --- Aufgeben: nur einmal gewertet; im Endlos-Modus zählt der Run als gewonnen
	var ph := Node.new()
	get_tree().root.add_child(ph)
	get_tree().current_scene = ph
	Run.start_new_run(5)
	await get_tree().process_frame
	var played := Profile.runs_played
	Run.abandon()
	Run.abandon()
	check(Profile.runs_played == played + 1, "Aufgeben doppelt: Run nur einmal gezählt")
	check(not Run.won_run, "Aufgeben vor dem Endlos-Modus: verloren")
	await get_tree().process_frame
	Run.start_new_run(6)
	await get_tree().process_frame
	Run.dev_start_endless()
	await get_tree().process_frame
	var won := Profile.runs_won
	Run.abandon()
	check(Run.won_run and Profile.runs_won == won + 1, "Aufgeben im Endlos-Modus: Run gewonnen (alle Bosse besiegt)")
	await get_tree().process_frame

	# --- Pause → Hauptmenü wertet einen laufenden Run
	Run.start_new_run(7)
	await get_tree().process_frame
	await get_tree().process_frame
	played = Profile.runs_played
	Pause.open()
	var quit: Button = null
	for b in Pause.find_children("*", "Button", true, false):
		if (b as Button).text == "ZUM HAUPTMENÜ":
			quit = b
	quit.pressed.emit()
	quit.pressed.emit()
	check(Profile.runs_played == played + 1 and Run.finished, "Pause → Hauptmenü: Run wird gewertet")
	await get_tree().process_frame
	await get_tree().process_frame

	# --- Tägliche mit fremdem Deck: kein Abzeichen, keine Belohnung
	Run._reset(9)
	Run.encounters = Run._build_encounters()
	Run.deck = Profile.deck(&"zar") # nicht freigeschaltet
	Run.daily = true
	Run.floor_index = Run.encounters.size()
	Run._end_run(true)
	check(not Profile.has_badge(&"zar", 1) and Cosmetics.selected(&"corners") == &"", "Tägliche mit fremdem Deck: kein Abzeichen")
	await get_tree().process_frame

	# --- Tägliche: an derselben Stelle dieselben Karten und dieselbe Auslage, egal was vorher war
	var deals := []
	var shops := []
	for k in 2:
		Run._reset(4242)
		Run.encounters = Run._build_encounters()
		Run.floor_index = 2
		if k == 1:
			Run.rng.randi() # anderer Verlauf vorher
			Run.begin_duel() # ein Versuch an Tisch 2 …
			Run._table_tries.clear() # … zählt hier nicht (anderer Spieler, erster Versuch)
		Run.begin_duel()
		var d := DurakMatch.new()
		d.start(Run.duel_stream(&"deal"))
		deals.append(str(d.player_hand) + str(d.trump_card))
		Run.open_shop()
		shops.append(Run.shop_offers.map(func(o: Dictionary) -> String: return o.title))
	check(deals[0] == deals[1], "gleiche Stelle → gleiche Karten")
	check(shops[0] == shops[1], "gleiche Stelle → gleiche Auslage")
	Run._reset(4242)
	Run.encounters = Run._build_encounters()
	Run.begin_duel()
	var first := DurakMatch.new()
	first.start(Run.duel_stream(&"deal"))
	Run.begin_duel() # zweiter Versuch am selben Tisch
	var second := DurakMatch.new()
	second.start(Run.duel_stream(&"deal"))
	check(str(first.player_hand) != str(second.player_hand), "neuer Versuch am Tisch → neu gemischt")

	# --- Startspieler ohne Trumpf: Zufall
	var starts := {}
	for i in 40:
		var d := DurakMatch.new()
		var r := RandomNumberGenerator.new()
		r.seed = i
		d.deck = Deck.new()
		d.player_hand.clear()
		d.opponent_hand.clear()
		d.trump_suit = Card.Suit.SPADES
		d.player_hand.append(Card.new(Card.Suit.HEARTS, 7))
		d.opponent_hand.append(Card.new(Card.Suit.CLUBS, 8))
		starts[d._lowest_trump_holder(r)] = true
	check(starts.size() == 2, "kein Trumpf auf der Hand: mal du, mal der Gegner beginnt")

	# --- Endlos: jedes Duell in einem neuen Raum möglich
	Run._reset(11)
	Run.encounters = Run._build_encounters()
	Run.floor_index = Run.encounters.size()
	Run.endless = true
	var rooms := {}
	for i in 12:
		Run.endless_duels = i
		rooms[Rooms.for_floor(Run.floor_index)] = true
	check(rooms.size() >= 2, "Endlos: Räume wechseln (%d verschiedene)" % rooms.size())
	Run.endless = false

	# --- Falle nur, wenn sie etwas bringt; Ergebnis-Überschriften
	m = await _duel(80)
	m.duel.attacker = DurakMatch.OPPONENT
	check(not m._trap_useful(), "Falle: im Angriff des Gegners nutzlos")
	m.duel.attacker = DurakMatch.PLAYER
	m.duel.attack_cards.clear()
	m.duel.defense_cards.clear()
	check(m._trap_useful(), "Falle: in deinem Angriff einsetzbar")
	m.duel.loser = DurakMatch.OPPONENT
	check(m._result_title(false) == "ZIEL VERFEHLT", "Gegner Durak, Ziel verfehlt: nicht „DURAK!“")
	m.duel.loser = DurakMatch.PLAYER
	check(m._result_title(false) == "DURAK!", "selbst Durak: „DURAK!“")
	Run.endless = true
	m.duel.loser = DurakMatch.NO_LOSER
	check(m._result_title(false) == "UNENTSCHIEDEN" and m._result_text(false).begins_with("Unentschieden"), "Endlos-Unentschieden: richtiger Text")
	Run.endless = false

	# --- F8 nur in Debug-Builds (Tests laufen als Debug-Build)
	check(DevMenu.allowed() == OS.is_debug_build(), "F8-Menü hängt am Debug-Build")

	print("\n%d Checks, %d Fehler" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
