extends Node
## Autoload „Run“: Zustand des aktuellen Roguelike-Runs und Szenenwechsel.

signal changed

const SCENE_MENU := "res://scenes/menu/main_menu.tscn"
const SCENE_MAP := "res://scenes/run/run_map.tscn"
const SCENE_MATCH := "res://scenes/match/match.tscn"
const SCENE_SHOP := "res://scenes/run/shop.tscn"
const SCENE_RUN_END := "res://scenes/run/run_end.tscn"

const OPPONENT_DIR := "res://data/opponents/"
const RELIC_DIR := "res://data/relics/"

const START_LIVES := 3
const BASE_HAND_SIZE := 6
const NORMAL_FIGHTS := 3 # danach folgt der Boss
## Ein Run hat 3 Akte mit je 3 Gegnern und einem Boss (12 Tische). Nach jedem Boss kommt der
## besondere Händler; nach dem 3. Boss beginnt der Endlos-Modus.
const ACTS := 3
const FIGHTS_PER_ACT := NORMAL_FIGHTS + 1
## Punkteziele steigen pro Akt um diesen Faktor
const ACT_GROWTH := 1.6
## Händler nach einem Boss: so viel Rabatt auf alles, dazu ein Relikt geschenkt (1 von 3)
const BOSS_DISCOUNT := 0.3
const BOSS_GIFT_CHOICES := 3
## Tägliche Herausforderung: feste Schwierigkeit (Normal)
const DAILY_DIFFICULTY := 1
## Zinsen nach jedem Sieg: +1 Gold pro 5 Gold, höchstens so viel.
const INTEREST_PER := 5
const INTEREST_MAX := 4 # Balance: weniger Gold-Überschuss (Boni gibt es nicht mehr zu kaufen)
const REROLL_BASE_PRICE := 2
## Punkteziel pro Etage (wie die Blinds bei Balatro). Letzter Eintrag = Boss.
## Gibt es mehr Etagen als Einträge, wird der letzte Wert weiter gesteigert.
const SCORE_TARGETS: Array[int] = [300, 380, 450, 550]
const SCORE_TARGET_GROWTH := 1.25

## Schwierigkeit (Index wie Settings.DIFFICULTY_NAMES): Punkteziel-Faktor, Fehlerquote der
## Gegner (Faktor), Leben, Seelen-Faktor
const DIFF_TARGET: Array[float] = [0.8, 1.15, 1.4]
const DIFF_MISTAKE: Array[float] = [1.3, 0.6, 0.25]
const DIFF_LIVES: Array[int] = [1, 0, -1]
const DIFF_SOULS: Array[float] = [0.75, 1.0, 1.25]
## Seelen-Bonus, wenn ohne Hinweise (keine Hervorhebung spielbarer Karten) gespielt wird
const NO_HINTS_SOULS := 1.5

## Items: einmal einsetzbar im Duell, höchstens ITEM_SLOTS gleichzeitig (Kauf beim Händler).
const ITEM_SLOTS := 2
const ITEMS := {
	&"lighter": {"name": "Feuerzeug", "emoji": "🔥", "price": 6,
		"text": "Verbrennt eine Gegnerkarte auf dem Tisch: seinen Angriff oder seine Verteidigung. Er muss neu legen."},
	&"mirror": {"name": "Spiegel", "emoji": "🪞", "price": 4,
		"text": "Schwebt hinter dem Gegner vorbei und verrät dir eine zufällige Karte seiner Hand."},
	&"magnet": {"name": "Magnet", "emoji": "🧲", "price": 4,
		"text": "Holt eine zufällige Karte vom Ablagestapel auf deine Hand."},
	&"schnaps": {"name": "Runde Schnaps", "emoji": preload("res://assets/items/schnaps.png"), "price": 5,
		"text": "Der Gegner trinkt mit: bis zum Ende der Runde spielt er betrunken und macht Fehler."},
	&"swap": {"name": "Kartentausch", "emoji": "🔄", "price": 4,
		"text": "Wähle eine Handkarte: Sie wird in den Stapel gemischt, du bekommst die offene Karte unter dem Stapel."},
	&"mask": {"name": "Maske", "emoji": "🎭", "price": 6,
		"text": "Die nächste Runde, in der du Punkte machst, zählt doppelt (Mult ×2)."},
	&"trap": {"name": "Falle", "emoji": "🪤", "price": 4,
		"text": "Der Gegner darf in dieser Runde nicht weiterschieben."},
	&"bribe": {"name": "Bestechung", "emoji": "💰", "price": 5,
		"text": "Sofort +50 Punkte auf dein Konto."},
}
## so viele Items liegen pro Händlerbesuch aus (zufällig)
const SHOP_ITEMS := 3

## Tutorial: leichter Gegner und kleines Punkteziel
const TUTORIAL_OPPONENT := "res://data/opponents/jester.tres"
const TUTORIAL_TARGET := 150

## Zufall für den Aufbau des Runs (Gegnerfolge, Startkarten des Decks). Alles, was während des
## Runs passiert, hat eigene Zufallsströme aus Seed + Stelle im Run (`stream`): so bekommen bei
## der Täglichen Herausforderung alle an derselben Stelle dieselben Karten, dieselbe Auslage und
## dieselben Glückswürfe – egal, wie sie vorher gespielt haben.
var rng := RandomNumberGenerator.new()
var seed_value := 0
## Zufall des aktuellen Händlerbesuchs (Auslage, Neu-Mischen, Boss-Geschenk)
var shop_rng := RandomNumberGenerator.new()
## Endlos-Modus: so viele Duelle sind schon gespielt (Stelle im Endlos-Lauf)
var endless_duels := 0
## Wie oft an einer Stelle schon ein Duell begonnen wurde ("Tisch:Endlos-Duell" → Anzahl)
var _table_tries := {}
## Stelle des laufenden Duells (für seine Zufallsströme), siehe begin_duel()
var duel_key: Array = []
var _handled_duel: Array = []
## Run ist gewertet (Run-Ende erreicht): kein zweites Mal werten
var finished := false
var lives := 0:
	set(v):
		lives = v
		max_lives = maxi(max_lives, v)
## Höchste Zahl an Leben in diesem Run (Lebensanzeigen, die verlorene Leben weiter zeigen)
var max_lives := 0
var gold := 0
var floor_index := 0
var encounters: Array[OpponentData] = []
var relics: Array[RelicData] = []
## Items im Besitz (ids aus ITEMS)
var items: Array[StringName] = []
## Zigarettenschachtel: eine pro Run (Profile.PACK_SIZE Stück), gilt über alle Duelle des Runs
var cigarettes_taken := 0
var cigarettes_smoked := 0
var last_gold_reward := 0
var last_interest := 0
var won_run := false

# Gekaufte Verbesserungen
## Card.key() → Card.Enhancement
var card_enhancements := {}
## Card.Suit → zusätzliche Chips
var suit_chip_bonus := {}
var trump_mult_bonus := 0
var extra_hand := 0
var interest_max_bonus := 0

## Deck dieses Runs (Skin + Effekt, siehe DeckData / Profile)
var deck: DeckData
## Schwierigkeit dieses Runs (0 Leicht, 1 Normal, 2 Schwer) und ob Hinweise an sind
var difficulty := 1
var hints := true
## Tutorial-Runde (eigene Szene, kein echter Run)
var tutorial := false
## Nach gewonnenem Tutorial: der Händler wird einmal mit Erklärungen gezeigt
var tutorial_shop := false
## Startgold für den Tutorial-Händler
const TUTORIAL_SHOP_GOLD := 15
## Seelen, die am Ende dieses Runs gutgeschrieben wurden
var last_souls := 0

## Händler nach einem Boss (Rabatt, Geschenk). `boss_gift_open`: Geschenk noch nicht gewählt.
var boss_shop := false
var boss_gift_open := false

## Endlos-Modus (nach dem 3. Boss): kein Punkteziel, Punkte sammeln, bis die Leben weg sind.
## Gegner Durak → neues Deck und neuer Gegner; eigenes Leben verloren → Händler, dann weiter.
var endless := false
var endless_score := 0
var endless_decks := 0
var endless_opponent: OpponentData
## Punkte des letzten Duells (setzt die Duell-Szene vor on_match_finished)
var last_duel_points := 0
## Platz in der Bestenliste nach dem letzten Endlos-Run (0 = nicht drin)
var last_endless_place := 0
## Punkte aller Duelle dieses Runs (für Statistik und Tägliche Herausforderung)
var run_points := 0

## Tägliche Herausforderung: alle spielen am selben Tag denselben Run (gleicher Seed, Deck des Tages,
## Schwierigkeit Normal). Pro Tag 3 Versuche (`daily_attempt` 1–3), der beste zählt; danach Übung.
var daily := false
var daily_date := ""
var daily_counts := false
var daily_attempt := 0

## Aktuelle Shop-Auslage (siehe make_shop_offers) und Preis fürs Neu-Mischen.
var shop_offers: Array[Dictionary] = []
var reroll_price := REROLL_BASE_PRICE


## Tägliche Herausforderung starten (Seed aus dem Datum).
func start_daily() -> void:
	var date := Profile.today()
	var attempt := Profile.daily_begin(date)
	_reset(daily_seed(date))
	daily = true
	daily_date = date
	daily_attempt = attempt
	daily_counts = attempt > 0
	difficulty = DAILY_DIFFICULTY
	hints = bool(Settings.get_value("general/hints"))
	max_lives = 0
	lives = maxi(1, START_LIVES + DIFF_LIVES[difficulty])
	encounters = _build_encounters()
	_apply_deck(daily_deck(date))
	changed.emit()
	goto(SCENE_MAP)


## Deck des Tages: jeden Tag ein anderes, für alle gleich – auch noch nicht freigeschaltete.
static func daily_deck(date: String) -> DeckData:
	var list: Array[DeckData] = Profile.decks().duplicate()
	if list.is_empty():
		return null
	list.sort_custom(func(a: DeckData, b: DeckData) -> bool: return String(a.id) < String(b.id))
	var r := RandomNumberGenerator.new()
	r.seed = hash("duraki-deck-" + date)
	return list[r.randi_range(0, list.size() - 1)]


## Seed für einen Tag – für alle Spieler gleich.
static func daily_seed(date: String) -> int:
	return maxi(1, absi(hash("duraki-tag-" + date)))


func start_new_run(p_seed := 0) -> void:
	_reset(p_seed)
	difficulty = clampi(int(Settings.get_value("general/difficulty")), 0, 2)
	hints = bool(Settings.get_value("general/hints"))
	max_lives = 0
	lives = maxi(1, START_LIVES + DIFF_LIVES[difficulty])
	encounters = _build_encounters()
	_apply_deck(Profile.selected_deck())
	changed.emit()
	goto(SCENE_MAP)


## Geführte Übungsrunde (Tutorial-Karte im Hauptmenü): ein leichter Gegner, Hinweise an,
## niedriges Ziel. Gewonnen → die Tutorial-Karte verschwindet (Einstellung general/show_tutorial).
func start_tutorial() -> void:
	_reset(0)
	tutorial = true
	tutorial_shop = false
	difficulty = 0
	hints = true
	max_lives = 0
	lives = 1
	# zum Zeigen: ein Relikt und ein Item (oben rechts im Duell, wird im Tutorial erklärt)
	var coin := load("res://data/relics/lucky_coin.tres") as RelicData
	if coin != null:
		relics.append(coin)
	items.append(&"mirror")
	var o := load(TUTORIAL_OPPONENT) as OpponentData
	if o != null:
		encounters.assign([o])
	else:
		encounters = _build_encounters().slice(0, 1)
	deck = null
	changed.emit()
	goto(SCENE_MATCH)


func _reset(p_seed: int) -> void:
	seed_value = p_seed if p_seed != 0 else randi()
	rng.seed = seed_value
	tutorial = false
	tutorial_shop = false
	gold = 0
	floor_index = 0
	relics.clear()
	items.clear()
	cigarettes_taken = 0
	cigarettes_smoked = 0
	won_run = false
	card_enhancements.clear()
	suit_chip_bonus.clear()
	trump_mult_bonus = 0
	extra_hand = 0
	interest_max_bonus = 0
	shop_offers.clear()
	last_souls = 0
	boss_shop = false
	boss_gift_open = false
	endless = false
	endless_score = 0
	endless_decks = 0
	endless_opponent = null
	endless_duels = 0
	_table_tries.clear()
	duel_key = []
	_handled_duel = []
	finished = false
	last_duel_points = 0
	run_points = 0
	daily = false
	daily_date = ""
	daily_counts = false
	daily_attempt = 0


## Effekte des gewählten Decks auf den neuen Run anwenden.
func _apply_deck(d: DeckData) -> void:
	deck = d
	if d == null:
		return
	gold += d.start_gold
	lives += d.extra_lives
	extra_hand += d.extra_hand
	trump_mult_bonus += d.trump_mult_bonus
	interest_max_bonus += d.interest_max_bonus
	if d.suit_bonus_suit >= 0 and d.suit_bonus_chips > 0:
		suit_chip_bonus[d.suit_bonus_suit] = int(suit_chip_bonus.get(d.suit_bonus_suit, 0)) + d.suit_bonus_chips
	for pair in [[d.start_gold_cards, Card.Enhancement.GOLD], [d.start_glass_cards, Card.Enhancement.GLASS],
			[d.start_lucky_cards, Card.Enhancement.LUCKY]]:
		for i in int(pair[0]):
			for attempt in 30:
				var key := "%d:%d" % [rng.randi_range(0, 3), rng.randi_range(Card.MIN_RANK, Card.MAX_RANK)]
				if not card_enhancements.has(key):
					card_enhancements[key] = pair[1]
					break


func deck_name() -> String:
	return deck.display_name if deck != null else "Hinterzimmer"


func deck_description() -> String:
	if deck == null or deck.effect_text.is_empty():
		return "Keine Besonderheiten."
	return deck.effect_text


## Rückseite der Karten in diesem Run.
func deck_back() -> Texture2D:
	return deck.back if deck != null and deck.back != null else null


## Eigener, fester Zufallsstrom für eine Stelle im Run (`parts`, z. B. ["shop", 3]).
func stream(parts: Array) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value] + parts)
	return r


## Ein Duell beginnt (Duell-Szene): Stelle merken – Tisch, Endlos-Duell und der wievielte Versuch
## an diesem Tisch. Aus ihr kommen Austeilen, Gegner-KI, Glückskarten und Items.
func begin_duel() -> Array:
	var spot := "%d:%d" % [floor_index, endless_duels if endless else -1]
	var tries := int(_table_tries.get(spot, 0)) + 1
	_table_tries[spot] = tries
	duel_key = [floor_index, endless_duels if endless else -1, tries]
	return duel_key


## Zufallsstrom des laufenden Duells für einen Zweck (&"deal", &"ai", &"luck", &"item" …).
func duel_stream(what: StringName) -> RandomNumberGenerator:
	return stream(duel_key + [String(what)])


func current_opponent() -> OpponentData:
	if endless:
		return endless_opponent
	if floor_index < encounters.size():
		return encounters[floor_index]
	return null


func player_hand_size() -> int:
	var size := BASE_HAND_SIZE + extra_hand
	for r in relics:
		size += r.hand_size_bonus
	return size


## Punkteziel für die aktuelle Etage.
func score_target(floor_i := floor_index) -> int:
	if tutorial:
		return TUTORIAL_TARGET
	if endless:
		return 0 # kein Ziel
	return int(roundf(_base_target(floor_i) * DIFF_TARGET[difficulty] / 10.0)) * 10


## Fehlerquote eines Gegners in diesem Run (Schwierigkeit eingerechnet).
func mistake_chance(o: OpponentData) -> float:
	return clampf(o.mistake_chance * DIFF_MISTAKE[difficulty], 0.0, 0.9)


## Faktor für die Seelen am Ende (Schwierigkeit × Hinweise aus).
func souls_factor() -> float:
	return DIFF_SOULS[difficulty] * (1.0 if hints else NO_HINTS_SOULS)


func _base_target(floor_i: int) -> int:
	var opponent := encounters[floor_i] if floor_i < encounters.size() else null
	if opponent != null and opponent.score_target > 0:
		return opponent.score_target
	var pos := act_pos(floor_i)
	var idx := SCORE_TARGETS.size() - 1 if opponent != null and opponent.is_boss else mini(pos, SCORE_TARGETS.size() - 1)
	var base := SCORE_TARGETS[idx]
	if pos >= SCORE_TARGETS.size(): # (falls ein Akt einmal mehr Tische hat)
		base = int(SCORE_TARGETS[-1] * pow(SCORE_TARGET_GROWTH, pos - SCORE_TARGETS.size() + 1))
	return int(base * pow(ACT_GROWTH, act_of(floor_i)))


## Akt (0, 1, 2) eines Tisches und Platz im Akt (0–2 Gegner, 3 Boss).
func act_of(floor_i := floor_index) -> int:
	return floor_i / FIGHTS_PER_ACT


func act_pos(floor_i := floor_index) -> int:
	return floor_i % FIGHTS_PER_ACT


## Tische (Indizes in `encounters`) des Akts, in dem `floor_i` liegt.
func act_floors(floor_i := floor_index) -> Array[int]:
	var first := act_of(floor_i) * FIGHTS_PER_ACT
	var list: Array[int] = []
	for i in range(first, mini(first + FIGHTS_PER_ACT, encounters.size())):
		list.append(i)
	return list


## Start-Mult pro Runde (1 + Boni aus Relikten und Deck).
func base_mult() -> int:
	var m := 1 + (deck.bonus_mult if deck != null else 0)
	for r in relics:
		m += r.bonus_mult
	return m


## Wird von der Match-Szene aufgerufen, sobald ein Duell vorbei ist.
## `loser` ist OPPONENT, wenn das Punkteziel erreicht wurde, sonst PLAYER.
func on_match_finished(loser: int) -> void:
	# jedes Duell nur einmal werten (z. B. „WEITER“ doppelt gedrückt)
	if not duel_key.is_empty():
		if duel_key == _handled_duel:
			return
		_handled_duel = duel_key.duplicate()
	if tutorial:
		tutorial = false
		if loser == DurakMatch.OPPONENT:
			Settings.set_value("general/show_tutorial", false) # geschafft: Karte ausblenden
			Profile.unlock_achievement(&"tutorial")
			# zum Abschluss den Händler zeigen und erklären (danach zurück ins Menü)
			tutorial_shop = true
			gold = TUTORIAL_SHOP_GOLD
			last_gold_reward = 0
			last_interest = 0
			open_shop()
			return
		goto(SCENE_MENU)
		return
	_record_duel(loser)
	if endless:
		_on_endless_finished(loser)
		return
	match loser:
		DurakMatch.OPPONENT:
			var opponent := current_opponent()
			Profile.on_opponent_defeated(opponent)
			_pay_win(opponent)
			floor_index += 1
			if opponent.is_boss:
				# nach jedem Boss: besonderer Händler (nach dem 3. Boss geht es danach endlos weiter)
				boss_shop = true
				boss_gift_open = true
				open_shop()
			elif floor_index >= encounters.size():
				start_endless()
			else:
				open_shop()
		DurakMatch.PLAYER:
			lives -= 1
			if lives <= 0:
				_end_run(false)
			else:
				changed.emit()
				goto(SCENE_MAP)
		_:
			goto(SCENE_MAP) # Unentschieden: nochmal gegen denselben Gegner


## Statistik für das gerade beendete Duell.
func _record_duel(loser: int) -> void:
	run_points += last_duel_points
	var won := loser == DurakMatch.OPPONENT
	Profile.record_duel(current_opponent(), won, last_duel_points)
	if not endless:
		Profile.max_stat("best_act", act_of() + (1 if won and current_opponent() != null and current_opponent().is_boss else 0))


## Gold für einen Sieg (Belohnung des Gegners, Relikte, Zinsen).
func _pay_win(opponent: OpponentData) -> void:
	last_gold_reward = opponent.gold_reward
	for r in relics:
		last_gold_reward += r.bonus_gold_per_win
	var interest_cap := INTEREST_MAX + interest_max_bonus + (4 if has_relic(&"sock") else 0)
	last_interest = mini(gold / INTEREST_PER, interest_cap)
	gold += last_gold_reward + last_interest
	Profile.add_stat("gold_won", last_gold_reward + last_interest)


## Weiter nach dem Händler: normal zum nächsten Tisch; nach dem letzten Boss in den
## Endlos-Modus; im Endlos-Modus direkt ins nächste Duell.
func leave_shop() -> void:
	boss_shop = false
	boss_gift_open = false
	if endless:
		goto(SCENE_MAP)
	elif floor_index >= encounters.size():
		start_endless()
	else:
		goto(SCENE_MAP)


# --- Endlos-Modus -------------------------------------------------------------

## Nach dem 3. Boss: kein Punkteziel mehr, Punkte sammeln, bis die Leben weg sind.
func start_endless() -> void:
	endless = true
	endless_score = 0
	endless_decks = 0
	endless_opponent = _next_endless_opponent()
	Profile.unlock_achievement(&"run_win") # alle drei Bosse besiegt
	changed.emit()
	goto(SCENE_MAP)


func _on_endless_finished(loser: int) -> void:
	endless_score += last_duel_points
	endless_duels += 1
	match loser:
		DurakMatch.OPPONENT:
			# Gegner ist Durak: Gold, neues Deck, neuer Gegner – direkt weiter
			Profile.on_opponent_defeated(endless_opponent)
			_pay_win(endless_opponent)
			endless_decks += 1
			endless_opponent = _next_endless_opponent()
			changed.emit()
			goto(SCENE_MATCH)
		DurakMatch.PLAYER:
			# selbst Durak: ein Leben weg; ist noch eins übrig, geht es zum Händler
			lives -= 1
			if lives <= 0:
				_end_run(true)
			else:
				endless_opponent = _next_endless_opponent()
				last_gold_reward = 0
				last_interest = 0
				open_shop()
		_:
			endless_opponent = _next_endless_opponent()
			changed.emit()
			goto(SCENE_MATCH)


## Zufälliger Gegner (auch Bosse), nicht derselbe wie gerade eben.
func _next_endless_opponent() -> OpponentData:
	var pool: Array[OpponentData] = []
	for res in _load_all(OPPONENT_DIR):
		var o := res as OpponentData
		if o != null and o.model != null and o.portrait != null and o != endless_opponent:
			pool.append(o)
	if pool.is_empty():
		return endless_opponent
	var r := stream(["endless_opponent", endless_duels])
	return pool[r.randi_range(0, pool.size() - 1)]


## Entwicklermenü: aktuellen Gegner überspringen (zählt als gewonnen, ohne Gold).
func dev_skip_opponent() -> void:
	if endless or tutorial:
		return
	floor_index += 1
	if floor_index >= encounters.size():
		start_endless()
	else:
		changed.emit()
		goto(SCENE_MAP)


## Entwicklermenü: direkt zum Boss des aktuellen Akts.
func dev_skip_to_boss() -> void:
	if endless or tutorial:
		return
	floor_index = act_of() * FIGHTS_PER_ACT + FIGHTS_PER_ACT - 1
	changed.emit()
	goto(SCENE_MAP)


## Entwicklermenü: alle Tische überspringen und den Endlos-Modus starten.
func dev_start_endless() -> void:
	if tutorial:
		return
	floor_index = encounters.size()
	start_endless()


## Bis zu `count` zufällige Relikte, die der Spieler noch nicht hat.
func get_reward_choices(count := 2) -> Array[RelicData]:
	var pool: Array[RelicData] = []
	for r in _load_all(RELIC_DIR):
		if not has_relic(r.id):
			pool.append(r)
	_shuffle(pool, shop_rng)
	return pool.slice(0, count)


# --- Shop ---------------------------------------------------------------------

func open_shop() -> void:
	reroll_price = REROLL_BASE_PRICE
	shop_rng = stream(["shop", floor_index, endless_duels if endless else -1])
	shop_offers = make_shop_offers()
	changed.emit()
	goto(SCENE_SHOP)


## Neue Auslage: 2 Relikte, 2 verbesserte Karten, 2 Verbesserungen.
## Jedes Angebot: {kind, title, text, price, symbol, color, sold, apply: Callable}
func make_shop_offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	for r in get_reward_choices(2):
		var o := _offer("RELIKT", r.display_name, r.description, 7 + shop_rng.randi_range(0, 3),
			r.visual(), Color(0.55, 0.22, 0.42), func() -> void: add_relic(r))
		o.emoji = true # wie im Duell: freies Emoji statt Medaille
		o.relic_id = r.id # schon im Besitz (z. B. als Boss-Geschenk)? Dann nicht mehr kaufbar
		offers.append(o)
	for i in 2:
		offers.append(_card_offer())
	var item_ids: Array = ITEMS.keys()
	_shuffle(item_ids, shop_rng)
	for id: StringName in item_ids.slice(0, SHOP_ITEMS):
		var it: Dictionary = ITEMS[id]
		var io := _offer("ITEM", it.name, it.text, it.price, it.emoji, Color.BLACK, func() -> void: add_item(id))
		io.emoji = true
		offers.append(io)
	# Boni (Farb-Schliff, Trumpf-Kenner …) gibt es nicht mehr beim Händler – die bringen die Decks mit
	if boss_shop: # Händler nach dem Boss: 30 % Rabatt auf alles
		for o in offers:
			o.full_price = o.price
			o.price = maxi(1, int(roundf(o.price * (1.0 - BOSS_DISCOUNT))))
	return offers


## Geschenk des Boss-Händlers: Auswahl (1 von 3 Relikten, die man noch nicht hat).
func boss_gift_choices() -> Array[RelicData]:
	return get_reward_choices(BOSS_GIFT_CHOICES)


func take_boss_gift(relic: RelicData) -> void:
	if not boss_gift_open:
		return
	boss_gift_open = false
	if relic != null:
		add_relic(relic)


func buy(offer: Dictionary) -> bool:
	if offer.get("sold", false) or gold < offer.price or is_owned(offer):
		return false
	if offer.kind == "ITEM" and not has_item_slot():
		return false
	gold -= offer.price
	offer.sold = true
	(offer.apply as Callable).call()
	changed.emit()
	return true


## Angebot ist ein Relikt, das man schon hat (z. B. gerade als Boss-Geschenk gewählt)?
func is_owned(offer: Dictionary) -> bool:
	return offer.get("kind", "") == "RELIKT" and has_relic(offer.get("relic_id", &""))


func reroll_shop() -> bool:
	if gold < reroll_price:
		return false
	gold -= reroll_price
	reroll_price += 1
	shop_offers = make_shop_offers()
	changed.emit()
	return true


## Wendet gekaufte Kartenverbesserungen auf einen frisch gemischten Stapel an.
func apply_card_enhancements(cards: Array[Card]) -> void:
	for c in cards:
		c.enhancement = card_enhancements.get(c.key(), Card.Enhancement.NONE)


func _offer(kind: String, title: String, text: String, price: int, symbol: Variant,
		color: Color, apply: Callable) -> Dictionary:
	return {"kind": kind, "title": title, "text": text, "price": price,
		"symbol": symbol, "color": color, "sold": false, "apply": apply}


func _card_offer() -> Dictionary:
	# zufällige Karte, die noch keine Verbesserung hat
	var suit := shop_rng.randi_range(0, 3)
	var rank := shop_rng.randi_range(Card.MIN_RANK, Card.MAX_RANK)
	for attempt in 20:
		if not card_enhancements.has("%d:%d" % [suit, rank]):
			break
		suit = shop_rng.randi_range(0, 3)
		rank = shop_rng.randi_range(Card.MIN_RANK, Card.MAX_RANK)
	var enh := shop_rng.randi_range(1, Card.ENHANCEMENT_NAMES.size() - 1)
	var label := "%s%s" % [Card.RANK_NAMES[rank], Card.SUIT_SYMBOLS[suit]]
	var colors := [Color.WHITE, Color(0.78, 0.58, 0.1), Color(0.25, 0.55, 0.8), Color(0.2, 0.6, 0.3)]
	var key := "%d:%d" % [suit, rank]
	var prices := [0, 6, 5, 5] # Gold (+3 Gold), Glas (doppelte Chips), Glück (1 zu 3: +5 Mult)
	var offer := _offer("KARTE", "%s %s" % [Card.ENHANCEMENT_NAMES[enh], label], Card.ENHANCEMENT_TEXT[enh],
		prices[enh], label, colors[enh], func() -> void: card_enhancements[key] = enh)
	# für die Anzeige im Shop (echtes Kartenbild)
	offer.suit = suit
	offer.rank = rank
	offer.enhancement = enh
	return offer


## Alle Relikte (für den Index).
func all_relics() -> Array[RelicData]:
	var list: Array[RelicData] = []
	for r in _load_all(RELIC_DIR):
		list.append(r as RelicData)
	return list


func has_relic(id: StringName) -> bool:
	return relics.any(func(r: RelicData) -> bool: return r.id == id)


## Matrjoschka: eine zufällige noch normale Karte des Decks bekommt eine Verbesserung.
## Gibt den Text zurück („10♥ wird Gold“) oder "" wenn alle schon verbessert sind.
func enhance_random_card(r: RandomNumberGenerator = null) -> String:
	if r == null:
		r = duel_stream(&"matrjoschka")
	var free: Array = []
	for suit in 4:
		for rank in range(Card.MIN_RANK, Card.MAX_RANK + 1):
			var key := "%d:%d" % [suit, rank]
			if not card_enhancements.has(key):
				free.append([suit, rank, key])
	if free.is_empty():
		return ""
	var pick: Array = free[r.randi_range(0, free.size() - 1)]
	var enh: int = [Card.Enhancement.GOLD, Card.Enhancement.GLASS, Card.Enhancement.LUCKY][r.randi_range(0, 2)]
	card_enhancements[pick[2]] = enh
	changed.emit()
	return "%s wird %s" % [Card.new(pick[0], pick[1]), Card.ENHANCEMENT_NAMES[enh]]


func has_item_slot() -> bool:
	return items.size() < ITEM_SLOTS


func add_item(id: StringName) -> void:
	if has_item_slot():
		items.append(id)
		changed.emit()


## Item an Platz `i` verbrauchen.
func use_item(i: int) -> void:
	if i >= 0 and i < items.size():
		items.remove_at(i)
		if not tutorial:
			Profile.add_stat("items_used")
		changed.emit()


func add_relic(relic: RelicData) -> void:
	relics.append(relic)
	lives += relic.extra_lives
	if relics.size() >= 5:
		Profile.unlock_achievement(&"relics5")
	changed.emit()


func add_gold(amount: int) -> void:
	gold += amount
	changed.emit()


func goto(scene_path: String) -> void:
	Fade.change_scene(scene_path)


## Läuft gerade ein echter Run, der noch nicht gewertet ist? (nicht Tutorial)
func run_active() -> bool:
	return not encounters.is_empty() and not tutorial and not tutorial_shop and not finished


## Run vorzeitig beenden. Zählt als verloren (Seelen für besiegte Tische gibt es trotzdem) –
## außer im Endlos-Modus: da sind alle drei Bosse schon besiegt, der Run ist gewonnen.
func abandon() -> void:
	if not run_active():
		return
	_end_run(endless)


func _end_run(won: bool) -> void:
	if finished:
		return # schon gewertet (z. B. doppelt gedrückt)
	finished = true
	won_run = won
	Profile.max_stat("best_run_points", run_points)
	if daily and daily_counts:
		Profile.daily_finish(daily_date, daily_attempt, run_points, mini(floor_index, encounters.size()), endless_score)
	if endless:
		last_endless_place = Profile.record_endless(endless_score, endless_decks, deck_name())
	# Abzeichen und Tisch-Belohnung nur für eigene Decks (das Deck des Tages kann fremd sein)
	var deck_id: StringName = deck.id if deck != null else Profile.DEFAULT_DECK
	if not Profile.is_unlocked(deck_id):
		deck_id = &""
	last_souls = Profile.on_run_finished(won, mini(floor_index, encounters.size()), souls_factor(),
		deck_id, difficulty)
	changed.emit()
	goto(SCENE_RUN_END)


func _build_encounters() -> Array[OpponentData]:
	var normal: Array[OpponentData] = []
	var bosses: Array[OpponentData] = []
	for res in _load_all(OPPONENT_DIR):
		var o := res as OpponentData
		# unvollständige Gegner (z. B. alte Dateien ohne Figur/Porträt) nicht einsetzen
		if o == null or o.model == null or o.portrait == null:
			push_warning("Gegner ohne Figur oder Porträt wird übersprungen: %s" % res.resource_path)
			continue
		if o.is_boss:
			bosses.append(o)
		else:
			normal.append(o)
	if normal.is_empty():
		return []
	# 3 Akte: je 3 normale Gegner (leichtere zuerst) und ein Boss. Gibt es zu wenige Gegner,
	# kommen sie mehrfach dran (darum gibt es vorerst Platzhalter-Gegner).
	_shuffle(normal)
	var picks: Array[OpponentData] = []
	while picks.size() < NORMAL_FIGHTS * ACTS:
		picks.append(normal[picks.size() % normal.size()])
	picks.sort_custom(func(a: OpponentData, b: OpponentData) -> bool:
		return a.mistake_chance > b.mistake_chance)
	_shuffle(bosses)
	var result: Array[OpponentData] = []
	for act in ACTS:
		result.append_array(picks.slice(act * NORMAL_FIGHTS, (act + 1) * NORMAL_FIGHTS))
		if not bosses.is_empty():
			result.append(bosses[act % bosses.size()])
	return result


## Lädt alle Ressourcen eines Ordners (funktioniert auch in exportierten Builds).
func _load_all(dir: String) -> Array[Resource]:
	var result: Array[Resource] = []
	var files := ResourceLoader.list_directory(dir)
	files.sort()
	for file in files:
		if file.ends_with(".tres") or file.ends_with(".res"):
			result.append(load(dir + file))
	return result


func _shuffle(arr: Array, r: RandomNumberGenerator = null) -> void:
	if r == null:
		r = rng
	for i in range(arr.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
