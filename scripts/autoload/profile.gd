extends Node
## Autoload „Profile“: dauerhafter Fortschritt über alle Runs hinweg.
## Seelen (Währung), freigeschaltete Decks, gewähltes Deck, kleine Statistik.
## Gespeichert in user://profile.cfg.

signal changed
## Ein Deck wurde frisch freigeschaltet (für Meldungen).
signal deck_unlocked(deck: DeckData)

const PATH := "user://profile.cfg"
const DECK_DIR := "res://data/decks/"
const DEFAULT_DECK := &"hinterzimmer"
## Seelen am Ende eines Runs
const SOULS_PER_TABLE := 3
const SOULS_RUN_WIN := 10

var souls := 0
var unlocked: Array[StringName] = []
var selected: StringName = DEFAULT_DECK
var runs_played := 0
var runs_won := 0
var best_floor := 0
## Frisch freigeschaltete Decks, die noch nicht angezeigt wurden.
var pending_unlocks: Array[DeckData] = []

var _decks: Array[DeckData] = []
## In Tests nie auf die Platte schreiben (sonst würde das echte Profil verändert).
var _no_save := false


func _ready() -> void:
	_load_decks()
	load_profile()


# --- Decks -----------------------------------------------------------------------------

func decks() -> Array[DeckData]:
	return _decks


func deck(id: StringName) -> DeckData:
	for d in _decks:
		if d.id == id:
			return d
	return null


func selected_deck() -> DeckData:
	var d := deck(selected)
	return d if d != null and is_unlocked(d.id) else deck(DEFAULT_DECK)


func is_unlocked(id: StringName) -> bool:
	var d := deck(id)
	return d != null and (d.starter or unlocked.has(id))


func select(id: StringName) -> bool:
	if not is_unlocked(id):
		return false
	selected = id
	save_profile()
	changed.emit()
	return true


func can_buy(id: StringName) -> bool:
	var d := deck(id)
	return d != null and not is_unlocked(id) and d.price_souls > 0 and souls >= d.price_souls


func buy(id: StringName) -> bool:
	if not can_buy(id):
		return false
	souls -= deck(id).price_souls
	_unlock(deck(id), false)
	save_profile()
	changed.emit()
	return true


## Nach einem gewonnenen Duell: Decks dieses Gegners freischalten.
func on_opponent_defeated(opponent: OpponentData) -> void:
	if opponent == null:
		return
	var oid := StringName(opponent.resource_path.get_file().get_basename())
	for d in _decks:
		if d.unlock_opponent == oid and not is_unlocked(d.id):
			_unlock(d, true)
	save_profile()


## Ende eines Runs: Seelen gutschreiben, Statistik, ggf. Decks freischalten.
## Gibt die erhaltenen Seelen zurück.
func on_run_finished(won: bool, tables_won: int, factor := 1.0) -> int:
	var gained := int(roundf((tables_won * SOULS_PER_TABLE + (SOULS_RUN_WIN if won else 0)) * factor))
	souls += gained
	runs_played += 1
	if won:
		runs_won += 1
		for d in _decks:
			if d.unlock_run_win and not is_unlocked(d.id):
				_unlock(d, true)
	best_floor = maxi(best_floor, tables_won)
	save_profile()
	changed.emit()
	return gained


func take_pending_unlocks() -> Array[DeckData]:
	var out := pending_unlocks.duplicate()
	pending_unlocks.clear()
	return out


func _unlock(d: DeckData, notify: bool) -> void:
	if not unlocked.has(d.id):
		unlocked.append(d.id)
	if notify:
		pending_unlocks.append(d)
	deck_unlocked.emit(d)


func _load_decks() -> void:
	_decks.clear()
	var dir := DirAccess.open(DECK_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		f = f.trim_suffix(".remap")
		if f.ends_with(".tres"):
			var d := load(DECK_DIR + f) as DeckData
			if d != null:
				_decks.append(d)
	_decks.sort_custom(func(a: DeckData, b: DeckData) -> bool: return a.sort_order < b.sort_order)


# --- Speichern ------------------------------------------------------------------------

func load_profile() -> void:
	var cfg := ConfigFile.new()
	if not FileAccess.file_exists(PATH) or cfg.load(PATH) != OK:
		return
	souls = int(cfg.get_value("profile", "souls", 0))
	selected = StringName(cfg.get_value("profile", "selected", String(DEFAULT_DECK)))
	runs_played = int(cfg.get_value("stats", "runs_played", 0))
	runs_won = int(cfg.get_value("stats", "runs_won", 0))
	best_floor = int(cfg.get_value("stats", "best_floor", 0))
	unlocked.clear()
	for id in cfg.get_value("profile", "unlocked", PackedStringArray()):
		unlocked.append(StringName(id))


func save_profile() -> void:
	if _no_save:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "souls", souls)
	cfg.set_value("profile", "selected", String(selected))
	var ids := PackedStringArray()
	for id in unlocked:
		ids.append(String(id))
	cfg.set_value("profile", "unlocked", ids)
	cfg.set_value("stats", "runs_played", runs_played)
	cfg.set_value("stats", "runs_won", runs_won)
	cfg.set_value("stats", "best_floor", best_floor)
	cfg.save(PATH)


## Nur für Tests: alles zurücksetzen; ab jetzt wird nichts mehr gespeichert.
func reset_for_tests() -> void:
	_no_save = true
	souls = 0
	unlocked.clear()
	selected = DEFAULT_DECK
	pending_unlocks.clear()
