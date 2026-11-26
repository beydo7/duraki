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
	check(Run.daily and Run.daily_counts, "erster Versuch zählt")
	check(Run.difficulty == Run.DAILY_DIFFICULTY, "Tägliche immer auf Normal")
	check(Run.deck != null and Run.deck.id == Profile.DEFAULT_DECK, "Tägliche mit Standard-Deck")
	check(Run.encounters.size() == 12, "12 Tische")
	Run.start_daily()
	await get_tree().process_frame
	check(Run.seed_value == seed1, "gleicher Tag → gleicher Seed")
	check(Run.encounters.map(func(o: OpponentData) -> String: return o.resource_path) == opps1, "gleiche Gegner")
	check(range(12).map(func(i: int) -> StringName: return Rooms.for_floor(i)) == rooms1, "gleiche Räume")
	check(not Run.daily_counts, "zweiter Versuch zählt nicht")
	check(Run.daily_seed("2026-11-26") != Run.daily_seed("2026-11-27"), "anderer Tag → anderer Seed")
	# Ergebnis eintragen (nur der erste Versuch)
	Profile.daily_finish(Profile.today(), 4321, 7, 0)
	check(int(Profile.daily_entry().points) == 4321 and bool(Profile.daily_entry().done), "Ergebnis gespeichert")
	Profile.daily_finish(Profile.today(), 9999, 12, 500)
	check(int(Profile.daily_entry().points) == 4321, "zweites Ergebnis überschreibt nicht")
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
