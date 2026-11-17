extends SceneTree
## Einfache Tests ohne Plugin. Ausführen:
##   godot --headless --path . -s res://tests/run_tests.gd

var _failures := 0
var _checks := 0


func _init() -> void:
	test_can_beat()
	test_deck()
	test_take_keeps_attacker()
	test_ai_vs_ai_simulation()
	print("\n%d Checks, %d Fehler" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FEHLER: " + label)


func test_can_beat() -> void:
	var H := Card.Suit.HEARTS
	var S := Card.Suit.SPADES
	check(DurakRules.can_beat(Card.new(H, 7), Card.new(H, 9), S), "höhere Karte gleicher Farbe schlägt")
	check(not DurakRules.can_beat(Card.new(H, 9), Card.new(H, 7), S), "niedrigere Karte schlägt nicht")
	check(DurakRules.can_beat(Card.new(H, 14), Card.new(S, 6), S), "Trumpf schlägt Nicht-Trumpf")
	check(not DurakRules.can_beat(Card.new(S, 10), Card.new(H, 14), S), "Nicht-Trumpf schlägt keinen Trumpf")
	check(not DurakRules.can_beat(Card.new(H, 9), Card.new(Card.Suit.CLUBS, 14), S), "andere Farbe schlägt nicht")


func test_deck() -> void:
	var deck := Deck.new()
	check(deck.size() == 36, "Deck hat 36 Karten")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	deck.shuffle(rng)
	var seen := {}
	for c in deck.cards:
		seen[c.get_label()] = true
	check(seen.size() == 36, "keine doppelten Karten nach dem Mischen")


func test_take_keeps_attacker() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var duel := DurakMatch.new()
	duel.start(rng)
	var attacker := duel.attacker
	duel.attack(duel.legal_attacks()[0])
	var defender_cards_before := duel.hand(duel.defender()).size()
	duel.take()
	check(duel.attacker == attacker, "nach dem Nehmen bleibt der Angreifer gleich")
	check(duel.hand(1 - attacker).size() >= defender_cards_before + 1, "Verteidiger hat die Karte genommen")


## Lässt zwei KIs viele Partien spielen und prüft, dass nichts hängt
## und keine Karten verschwinden.
func test_ai_vs_ai_simulation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var finished := 0
	var card_loss := false
	for game in 500:
		var duel := DurakMatch.new()
		duel.start(rng)
		var ais := [SimpleAI.new(rng, 0.2), SimpleAI.new(rng, 0.2)]
		var steps := 0
		while not duel.is_over and steps < 2000:
			var actor := duel.current_actor()
			ais[actor].take_turn(duel, actor)
			steps += 1
			var total := duel.deck.size() + duel.player_hand.size() + duel.opponent_hand.size() \
				+ duel.table_cards().size() + duel.discard_pile.size()
			if total != 36:
				card_loss = true
		if duel.is_over:
			finished += 1
	check(finished == 500, "alle KI-Partien enden (%d/500)" % finished)
	check(not card_loss, "Kartenanzahl bleibt immer 36")
