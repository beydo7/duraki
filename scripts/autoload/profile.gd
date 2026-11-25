extends Node
## Autoload „Profile“: dauerhafter Fortschritt über alle Runs hinweg.
## Seelen (Währung), freigeschaltete Decks, gewähltes Deck, kleine Statistik.
## Gespeichert in user://profile.cfg.

signal changed
## Ein Deck wurde frisch freigeschaltet (für Meldungen).
signal deck_unlocked(deck: DeckData)
## Ein Erfolg wurde gerade erreicht (Meldung zeigt der Autoload Pause).
signal achievement_unlocked(id: StringName)

## Erfolge: id → [Symbol, Name, Aufgabe, geheim?]. Geheime zeigen ihre Aufgabe erst, wenn erreicht.
## Belohnungen sind noch offen (Leon überlegt sich die noch).
const ACHIEVEMENTS := {
	&"tutorial": ["🎓", "Lehrling", "Schließe das Tutorial ab.", false],
	&"first_win": ["🏆", "Erster Sieg", "Gewinne deinen ersten Tisch.", false],
	&"transfer": ["🌀", "Weitergeschoben", "Schiebe einen Angriff weiter.", false],
	&"burn": ["🔥", "Brandstifter", "Verbrenne eine Karte mit dem Feuerzeug.", false],
	&"big_bout": ["💥", "Volltreffer", "Mach 100 Punkte oder mehr in einer einzigen Runde.", false],
	&"relics5": ["🧺", "Sammler", "Besitze 5 Relikte gleichzeitig.", false],
	&"boss": ["🗿", "Riesentöter", "Besiege einen Boss.", false],
	&"run_win": ["👑", "Durchgezogen", "Besiege alle drei Bosse eines Runs.", false],
	&"hard_win": ["💀", "Eiskalt", "Gewinne einen Run auf Schwer.", false],
	&"smoker": ["🚬", "Raucher", "Rauche eine Zigarette zu Ende.", true],
	&"chain_smoker": ["📦", "Kettenraucher", "Rauche in einem Run die ganze Schachtel (6 Zigaretten).", true],
	&"alcoholic": ["🥃", "Alkoholiker", "Trink die Whiskeyflasche leer.", true],
	&"all_green": ["🟢", "Alles auf Grün", "Lass im Casino die Roulettekugel auf der grünen 0 landen.", true],
	&"jackpot": ["🎰", "Jackpot", "Zieh im Casino am Spielautomaten drei Siebenen.", true],
}
## Zigaretten pro Schachtel (pro Run eine Schachtel: zweimal 3 Stück)
const PACK_SIZE := 6

const PATH := "user://profile.cfg"
const DECK_DIR := "res://data/decks/"
const DEFAULT_DECK := &"hinterzimmer"
## Seelen am Ende eines Runs
const SOULS_PER_TABLE := 3
const SOULS_RUN_WIN := 10

var souls := 0
var unlocked: Array[StringName] = []
## Abzeichen: Deck-id → gewonnene Schwierigkeiten (0 Leicht, 1 Normal, 2 Schwer)
var badges := {}
var selected: StringName = DEFAULT_DECK
var runs_played := 0
var runs_won := 0
var best_floor := 0
## Erreichte Erfolge (ids) und Zähler dafür
var achievements: Array[StringName] = []
var cigarettes_smoked := 0
## Bestenliste (vorerst nur lokal): die besten Endlos-Ergebnisse, höchste zuerst.
## Je Eintrag {name, score, decks, deck, date}. Online-Vergleich mit Freunden kommt später.
var endless_records: Array[Dictionary] = []
const ENDLESS_RECORDS := 10
## Name in der Bestenliste
var player_name := "Du"
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
	unlock_achievement(&"first_win")
	if opponent.is_boss:
		unlock_achievement(&"boss")
	var oid := StringName(opponent.resource_path.get_file().get_basename())
	for d in _decks:
		if d.unlock_opponent == oid and not is_unlocked(d.id):
			_unlock(d, true)
	save_profile()


## Ende eines Runs: Seelen gutschreiben, Statistik, ggf. Decks freischalten.
## Gibt die erhaltenen Seelen zurück.
## Hat man mit diesem Deck schon auf Stufe `level` gewonnen?
func has_badge(deck_id: StringName, level: int) -> bool:
	return (badges.get(String(deck_id), []) as Array).has(level)


func _give_badge(deck_id: StringName, level: int) -> void:
	if deck_id == &"" or has_badge(deck_id, level):
		return
	var list: Array = badges.get(String(deck_id), [])
	list.append(level)
	badges[String(deck_id)] = list


func on_run_finished(won: bool, tables_won: int, factor := 1.0, deck_id: StringName = &"", level := -1) -> int:
	if won:
		unlock_achievement(&"run_win")
		if level == 2:
			unlock_achievement(&"hard_win")
	if won and level >= 0:
		_give_badge(deck_id, level)
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


## Endlos-Ergebnis in die (lokale) Bestenliste eintragen. Gibt den Platz zurück (1 = bester)
## oder 0, wenn es nicht unter die besten ENDLESS_RECORDS kommt.
func record_endless(score: int, decks: int, deck_name: String) -> int:
	var entry := {"name": player_name, "score": score, "decks": decks, "deck": deck_name,
		"date": Time.get_date_string_from_system()}
	endless_records.append(entry)
	endless_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.score) > int(b.score))
	var place := endless_records.find(entry) + 1
	if endless_records.size() > ENDLESS_RECORDS:
		endless_records.resize(ENDLESS_RECORDS)
	save_profile()
	changed.emit()
	return place if place <= ENDLESS_RECORDS else 0


## Bester Endlos-Wert (0, wenn noch keiner).
func endless_best() -> int:
	return int(endless_records[0].score) if not endless_records.is_empty() else 0


## Entwicklermenü: alle Decks freischalten und alle Abzeichen vergeben.
func unlock_all() -> void:
	for d in decks():
		if not unlocked.has(d.id):
			unlocked.append(d.id)
		badges[String(d.id)] = [0, 1, 2]
	save_profile()


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


# --- Erfolge --------------------------------------------------------------------------

func has_achievement(id: StringName) -> bool:
	return achievements.has(id)


## Erfolg freischalten (nur beim ersten Mal: speichern und melden).
func unlock_achievement(id: StringName) -> void:
	if not ACHIEVEMENTS.has(id) or achievements.has(id):
		return
	achievements.append(id)
	save_profile()
	achievement_unlocked.emit(id)


## Eine Zigarette zu Ende geraucht (Aschenbecher). `in_run`: so viele schon in diesem Run.
func add_cigarette(in_run: int) -> void:
	cigarettes_smoked += 1
	save_profile()
	unlock_achievement(&"smoker")
	if in_run >= PACK_SIZE:
		unlock_achievement(&"chain_smoker")


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
	badges = cfg.get_value("profile", "badges", {})
	achievements.clear()
	for id in cfg.get_value("achievements", "done", PackedStringArray()):
		achievements.append(StringName(id))
	cigarettes_smoked = int(cfg.get_value("stats", "cigarettes", 0))
	endless_records.assign(cfg.get_value("endless", "records", []))
	player_name = String(cfg.get_value("profile", "name", "Du"))


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
	cfg.set_value("profile", "badges", badges)
	cfg.set_value("stats", "runs_played", runs_played)
	cfg.set_value("stats", "runs_won", runs_won)
	cfg.set_value("stats", "best_floor", best_floor)
	cfg.set_value("stats", "cigarettes", cigarettes_smoked)
	var done := PackedStringArray()
	for id in achievements:
		done.append(String(id))
	cfg.set_value("achievements", "done", done)
	cfg.set_value("endless", "records", endless_records)
	cfg.set_value("profile", "name", player_name)
	cfg.save(PATH)


## Nur für Tests: alles zurücksetzen; ab jetzt wird nichts mehr gespeichert.
func reset_for_tests() -> void:
	_no_save = true
	souls = 0
	unlocked.clear()
	badges.clear()
	achievements.clear()
	cigarettes_smoked = 0
	selected = DEFAULT_DECK
	pending_unlocks.clear()
	endless_records.clear()
