extends Node
## Prüft jedes Relikt einzeln im echten Spielablauf (Run + Duell-Szene).
##   godot --headless --path . res://tests/relic_tests.tscn

var _checks := 0
var _failures := 0


func _ready() -> void:
	# eigenes, leeres Profil: sonst zählt z. B. das gewählte Deck (Riese: +1 Mult) mit
	Profile.reset_for_tests()
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FEHLER: " + label)
	else:
		print("ok   " + label)


func _relic(id: String) -> RelicData:
	for r in Run.all_relics():
		if String(r.id) == id:
			return r
	return null


## Neuen Run starten, Relikte geben und ins Duell gehen. Gibt die Duell-Szene zurück.
func _duel_with(ids: Array, opponent := "bandit") -> Node:
	var ph := Node.new()
	get_tree().root.add_child(ph)
	get_tree().current_scene = ph
	Run.start_new_run(1234)
	await get_tree().process_frame
	Run.encounters[0] = load("res://data/opponents/%s.tres" % opponent)
	for id in ids:
		Run.add_relic(_relic(id))
	Run.goto(Run.SCENE_MATCH)
	await get_tree().process_frame
	await get_tree().process_frame
	return get_tree().current_scene


func _run() -> void:
	check(Run.all_relics().size() == 11, "11 Relikte gefunden")
	for r in Run.all_relics():
		check(r.description != "" and r.display_name != "", "%s hat Name und Beschreibung" % r.id)

	# Ass im Ärmel: 7 statt 6 Handkarten – auch wenn es mitten im Duell dazukommt
	var m := await _duel_with(["ace_up_sleeve"])
	check(m.duel.player_hand.size() == 7, "Ass im Ärmel: 7 Karten auf der Hand (ist %d)" % m.duel.player_hand.size())
	m = await _duel_with([])
	check(m.duel.player_hand.size() == 6, "ohne Relikt: 6 Karten")
	Run.add_relic(_relic("ace_up_sleeve"))
	check(m.duel.hand_sizes[0] == 7, "Ass im Ärmel mitten im Duell: Hand wächst auf 7")

	# Böser Blick: Gegner startet mit einer Karte weniger
	m = await _duel_with(["evil_eye"])
	check(m.duel.hand_sizes[1] == 5 and m.duel.opponent_hand.size() <= 5, "Böser Blick: Gegner hat 5 statt 6 Karten")

	# Gezinkter Würfel, Hufeisen, Wolfszahn, Wirbel, Wodka: Werte in der Wertung
	m = await _duel_with(["loaded_dice", "horseshoe", "wolf_tooth", "whirl", "vodka"])
	check(is_equal_approx(m.score.lucky_chance, 0.5), "Gezinkter Würfel: Glück 1 zu 2")
	check(m.score.lucky_gold == 2, "Hufeisen: +2 Gold pro Glückstreffer")
	check(m.score.trump_defense_chips == 10, "Wolfszahn: +10 Chips")
	check(m.score.first_transfer_mult == 3, "Wirbel: +3 Mult beim ersten Schieben")
	check(m.score.base_mult == 2 and m.score.mult == 2, "Wodka: Start-Mult 2")
	# Relikte, die mitten im Duell dazukommen, wirken sofort
	m = await _duel_with([])
	Run.add_relic(_relic("wolf_tooth"))
	Run.add_relic(_relic("vodka"))
	check(m.score.trump_defense_chips == 10 and m.score.base_mult == 2, "Relikte mitten im Duell wirken sofort")

	# Hufeisen + Gezinkter Würfel im Ablauf: Glückskarte trifft und gibt Gold
	var st := ScoreTracker.new(10000)
	st.lucky_chance = 1.0
	st.lucky_gold = 2
	var gold := [0]
	st.gold_found.connect(func(a: int, _s: String) -> void: gold[0] += a)
	var d := DurakMatch.new()
	d.player_hand = [Card.new(Card.Suit.HEARTS, 9)] as Array[Card]
	d.opponent_hand = [Card.new(Card.Suit.CLUBS, 6)] as Array[Card]
	d.trump_suit = Card.Suit.SPADES
	d.player_hand[0].enhancement = Card.Enhancement.LUCKY
	st.attach(d)
	d.attacker = DurakMatch.PLAYER
	d.attack(d.player_hand[0])
	check(gold[0] == 2 and st.mult >= 1 + ScoreTracker.LUCKY_MULT, "Hufeisen: Glückstreffer gibt +2 Gold")

	# Wirbel im Ablauf: erstes Schieben +3 Mult
	var st2 := ScoreTracker.new(10000)
	st2.first_transfer_mult = 3
	var d2 := DurakMatch.new()
	d2.player_hand = [Card.new(Card.Suit.HEARTS, 8), Card.new(Card.Suit.CLUBS, 6)] as Array[Card]
	d2.opponent_hand = [Card.new(Card.Suit.DIAMONDS, 8), Card.new(Card.Suit.CLUBS, 7), Card.new(Card.Suit.CLUBS, 9)] as Array[Card]
	d2.trump_suit = Card.Suit.SPADES
	st2.attach(d2)
	d2.attacker = DurakMatch.OPPONENT
	d2.attack(d2.opponent_hand[0])
	var before := st2.mult
	d2.transfer(d2.player_hand[0])
	check(st2.mult >= before + 3, "Wirbel: Schieben gibt +3 Mult (vorher %d, nachher %d)" % [before, st2.mult])

	# Glücksmünze und Sparstrumpf: Gold nach dem Sieg
	m = await _duel_with(["lucky_coin", "sock"])
	Run.gold = 100
	var opp := Run.current_opponent()
	Run.on_match_finished(DurakMatch.OPPONENT)
	check(Run.last_gold_reward == opp.gold_reward + 5, "Glücksmünze: +5 Gold pro Sieg")
	check(Run.last_interest == 8, "Sparstrumpf: Zinsen bis 8 (ist %d)" % Run.last_interest)
	await get_tree().create_timer(0.3).timeout

	# Med-Kit: +1 Leben (auch in der Anzeige)
	Run.start_new_run(1)
	var lives := Run.lives
	Run.add_relic(_relic("medkit"))
	check(Run.lives == lives + 1, "Med-Kit: +1 Leben")

	# Matrjoschka: nach dem Sieg wird eine Karte verbessert
	var n := Run.card_enhancements.size()
	var note := Run.enhance_random_card()
	check(note != "" and Run.card_enhancements.size() == n + 1, "Matrjoschka: eine Karte wird verbessert")

	print("\n%d Checks, %d Fehler" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
