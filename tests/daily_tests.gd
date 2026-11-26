extends Node
## Tägliche Herausforderung und Statistik.
##   godot --headless --path . res://tests/daily_tests.tscn

var _checks := 0
var _failures := 0


func check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FEHLER: " + label)


func _ready() -> void:
	Profile.reset_for_tests()
	_run.call_deferred()


func _run() -> void:
	var ph := Node.new()
	get_tree().root.add_child(ph)
	get_tree().current_scene = ph
	Settings._values["general/difficulty"] = 2 # darf die Tägliche nicht beeinflussen
	Run.start_daily()
	await get_tree().process_frame
	var seed1 := Run.seed_value
	var opps1 := Run.encounters.map(func(o: OpponentData) -> String: return o.resource_path)
	var rooms1 := range(12).map(func(i: int) -> StringName: return Rooms.for_floor(i))
	check(Run.daily and Run.daily_counts and Run.daily_attempt == 1, "erster Versuch zählt")
	check(Run.difficulty == Run.DAILY_DIFFICULTY, "Tägliche immer auf Normal")
	check(Run.deck != null and Run.deck == Run.daily_deck(Profile.today()), "Tägliche mit Deck des Tages")
	var seen := {}
	for day in range(1, 29):
		var dd := Run.daily_deck("2026-12-%02d" % day)
		if dd != null:
			seen[dd.id] = true
	check(seen.size() >= 5, "über einen Monat kommen verschiedene Decks dran (%d)" % seen.size())
	var rooms_seen := {}
	for day in range(1, 8):
		Run.seed_value = Run.daily_seed("2026-12-%02d" % day)
		for i in 12:
			rooms_seen[Rooms.for_floor(i)] = true
	check(rooms_seen.size() == Rooms.ALL.size(), "alle Räume kommen vor")
	check(Run.encounters.size() == 12, "12 Tische")
	var deck1 := Run.deck
	Run.start_daily()
	await get_tree().process_frame
	check(Run.seed_value == seed1, "gleicher Tag → gleicher Seed")
	check(Run.encounters.map(func(o: OpponentData) -> String: return o.resource_path) == opps1, "gleiche Gegner")
	check(range(12).map(func(i: int) -> StringName: return Rooms.for_floor(i)) == rooms1, "gleiche Räume")
	check(Run.daily_counts and Run.daily_attempt == 2, "zweiter Versuch zählt auch")
	check(Run.deck == deck1, "gleiches Deck beim zweiten Versuch")
	Profile.daily_finish(Profile.today(), 2, 4321, 7, 0)
	Run.start_daily()
	await get_tree().process_frame
	check(Run.daily_counts and Run.daily_attempt == 3, "dritter Versuch zählt")
	Profile.daily_finish(Profile.today(), 3, 1200, 4, 0)
	Run.start_daily()
	await get_tree().process_frame
	check(not Run.daily_counts and Run.daily_attempt == 0, "vierter Versuch ist nur Übung")
	check(Profile.daily_tries_used() == 3, "3 Versuche verbraucht")
	check(Run.daily_seed("2026-11-26") != Run.daily_seed("2026-11-27"), "anderer Tag → anderer Seed")
	var e := Profile.daily_entry()
	check(int(e.points) == 4321 and int(e.tables) == 7, "der beste Versuch zählt (4321)")
	check(e.tries == [0, 4321, 1200], "Versuche einzeln gespeichert (1. abgebrochen = 0)")
	Profile.daily_finish(Profile.today(), 4, 9999, 12, 500)
	check(int(Profile.daily_entry().points) == 4321, "Übung ändert nichts")
	check(Profile.daily_streak() == 1, "Serie 1")
	# Statistik
	var bandit := load("res://data/opponents/bandit.tres") as OpponentData
	Profile.record_duel(bandit, true, 300)
	Profile.record_duel(bandit, false, 50)
	Profile.record_duel(bandit, true, 100)
	check(int(Profile.stats.duels_won) == 2 and int(Profile.stats.duels_lost) == 1, "Duelle gezählt")
	check(int(Profile.stats.points) == 450, "Punkte summiert")
	check(Profile.top_opponent(true) == ["bandit", 2], "Lieblingsgegner")
	Profile.max_stat("best_bout", 80)
	Profile.max_stat("best_bout", 40)
	check(int(Profile.stats.best_bout) == 80, "beste Runde bleibt Höchstwert")
	print("\n%d Checks, %d Fehler" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
