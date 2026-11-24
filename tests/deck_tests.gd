extends Node
## Tests für Decks und Profil (brauchen die Autoloads, darum als Szene).
##   godot --headless --path . res://tests/deck_tests.tscn

var _fail := 0
var _checks := 0


func check(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fail += 1
		printerr("FEHLER: " + label)


func _ready() -> void:
	Settings._values["general/difficulty"] = 1 # Tests unabhängig von der eigenen Einstellung
	Settings._values["general/hints"] = true
	Profile.reset_for_tests()
	check(Profile.decks().size() >= 12, "alle Decks geladen (%d)" % Profile.decks().size())
	check(Profile.is_unlocked(&"hinterzimmer"), "Startdeck frei")
	check(not Profile.is_unlocked(&"crow"), "Krähen-Deck gesperrt")
	for d in Profile.decks():
		check(d.back != null, "Rückseite für %s" % d.id)
		check(d.starter or d.unlock_opponent != &"" or d.unlock_run_win or d.price_souls > 0,
			"%s lässt sich freischalten" % d.id)
	# Gegner besiegen schaltet sein Deck frei
	Profile.on_opponent_defeated(load("res://data/opponents/crow.tres"))
	check(Profile.is_unlocked(&"crow"), "Krähe besiegt → Krähen-Deck frei")
	check(Profile.take_pending_unlocks().size() == 1, "eine Freischalt-Meldung")
	# Kaufen mit Seelen
	check(not Profile.buy(&"zar"), "ohne Seelen kein Kauf")
	Profile.souls = 100
	check(Profile.buy(&"zar") and Profile.souls == 60, "Zaren-Deck gekauft (40 Seelen)")
	# Seelen am Run-Ende
	var before := Profile.souls
	var got := Profile.on_run_finished(true, 4)
	check(got == 4 * Profile.SOULS_PER_TABLE + Profile.SOULS_RUN_WIN and Profile.souls == before + got, "Seelen gutgeschrieben")
	check(Profile.is_unlocked(&"giant"), "Run gewonnen → Riesen-Deck frei")
	# Deck-Effekte im Run
	Profile.select(&"crow")
	Run.start_new_run(77)
	check(Run.deck.id == &"crow", "Run nutzt gewähltes Deck")
	check(int(Run.suit_chip_bonus.get(Card.Suit.SPADES, 0)) == 3, "Krähen-Deck: Pik +3 Chips")
	check(Card3D.back_texture() == Run.deck.back, "Kartenrücken = Deck-Rückseite")
	Profile.select(&"zar")
	Run.start_new_run(78)
	check(Run.trump_mult_bonus == 1, "Zaren-Deck: Trumpf +1 Mult")
	Profile.unlocked.append(&"witch")
	Profile.select(&"witch")
	Run.start_new_run(79)
	var glass := 0
	for k in Run.card_enhancements:
		if Run.card_enhancements[k] == Card.Enhancement.GLASS:
			glass += 1
	check(glass == 2, "Hexen-Deck: 2 Glaskarten")
	Profile.unlocked.append(&"giant")
	Profile.select(&"giant")
	Run.start_new_run(80)
	check(Run.base_mult() == 2, "Riesen-Deck: +1 Mult")
	# Schwierigkeit und Hinweise
	Settings._values["general/hints"] = true
	Settings._values["general/difficulty"] = 0
	Run.start_new_run(81)
	var easy := Run.score_target(0)
	var easy_lives := Run.lives
	Settings._values["general/difficulty"] = 2
	Run.start_new_run(81)
	check(Run.score_target(0) > easy and Run.lives == easy_lives - 2, "Schwer: höheres Ziel, weniger Leben")
	check(Run.mistake_chance(Run.encounters[0]) < Run.encounters[0].mistake_chance, "Schwer: Gegner machen weniger Fehler")
	Settings._values["general/hints"] = false
	Settings._values["general/difficulty"] = 1
	Run.start_new_run(82)
	check(is_equal_approx(Run.souls_factor(), 1.5), "Ohne Hinweise: Seelen ×1,5")
	check(Profile.on_run_finished(false, 2, Run.souls_factor()) == 9, "2 Tische ohne Hinweise = 9 Seelen")
	Settings._values["general/hints"] = true
	# Abzeichen
	check(not Profile.has_badge(&"crow", 2), "noch kein Abzeichen")
	Profile.on_run_finished(true, 4, 1.0, &"crow", 2)
	check(Profile.has_badge(&"crow", 2) and not Profile.has_badge(&"crow", 1), "Sieg auf Schwer → Abzeichen Schwer")
	Profile.on_run_finished(false, 2, 1.0, &"crow", 1)
	check(not Profile.has_badge(&"crow", 1), "Niederlage gibt kein Abzeichen")
	print("\n%d Checks, %d Fehler" % [_checks, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
