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

var rng := RandomNumberGenerator.new()
var seed_value := 0
var lives := 0
var gold := 0
var floor_index := 0
var encounters: Array[OpponentData] = []
var relics: Array[RelicData] = []
## Items im Besitz (ids aus ITEMS)
var items: Array[StringName] = []
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
## Seelen, die am Ende dieses Runs gutgeschrieben wurden
var last_souls := 0

## Aktuelle Shop-Auslage (siehe make_shop_offers) und Preis fürs Neu-Mischen.
var shop_offers: Array[Dictionary] = []
var reroll_price := REROLL_BASE_PRICE


func start_new_run(p_seed := 0) -> void:
	_reset(p_seed)
	difficulty = clampi(int(Settings.get_value("general/difficulty")), 0, 2)
	hints = bool(Settings.get_value("general/hints"))
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
	difficulty = 0
	hints = true
	lives = 1
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
	gold = 0
	floor_index = 0
	relics.clear()
	items.clear()
	won_run = false
	card_enhancements.clear()
	suit_chip_bonus.clear()
	trump_mult_bonus = 0
	extra_hand = 0
	interest_max_bonus = 0
	shop_offers.clear()
	last_souls = 0


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


func current_opponent() -> OpponentData:
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
	var idx := SCORE_TARGETS.size() - 1 if opponent != null and opponent.is_boss else floor_i
	if idx < SCORE_TARGETS.size():
		return SCORE_TARGETS[idx]
	var extra := idx - SCORE_TARGETS.size() + 1
	return int(SCORE_TARGETS[-1] * pow(SCORE_TARGET_GROWTH, extra))


## Start-Mult pro Runde (1 + Boni aus Relikten und Deck).
func base_mult() -> int:
	var m := 1 + (deck.bonus_mult if deck != null else 0)
	for r in relics:
		m += r.bonus_mult
	return m


## Wird von der Match-Szene aufgerufen, sobald ein Duell vorbei ist.
## `loser` ist OPPONENT, wenn das Punkteziel erreicht wurde, sonst PLAYER.
func on_match_finished(loser: int) -> void:
	if tutorial:
		tutorial = false
		if loser == DurakMatch.OPPONENT:
			Settings.set_value("general/show_tutorial", false) # geschafft: Karte ausblenden
		goto(SCENE_MENU)
		return
	match loser:
		DurakMatch.OPPONENT:
			var opponent := current_opponent()
			Profile.on_opponent_defeated(opponent)
			last_gold_reward = opponent.gold_reward
			for r in relics:
				last_gold_reward += r.bonus_gold_per_win
			var interest_cap := INTEREST_MAX + interest_max_bonus + (4 if has_relic(&"sock") else 0)
			last_interest = mini(gold / INTEREST_PER, interest_cap)
			gold += last_gold_reward + last_interest
			floor_index += 1
			if floor_index >= encounters.size():
				_end_run(true)
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


## Bis zu `count` zufällige Relikte, die der Spieler noch nicht hat.
func get_reward_choices(count := 2) -> Array[RelicData]:
	var pool: Array[RelicData] = []
	for r in _load_all(RELIC_DIR):
		if not relics.any(func(owned: RelicData) -> bool: return owned.id == r.id):
			pool.append(r)
	_shuffle(pool)
	return pool.slice(0, count)


# --- Shop ---------------------------------------------------------------------

func open_shop() -> void:
	reroll_price = REROLL_BASE_PRICE
	shop_offers = make_shop_offers()
	changed.emit()
	goto(SCENE_SHOP)


## Neue Auslage: 2 Relikte, 2 verbesserte Karten, 2 Verbesserungen.
## Jedes Angebot: {kind, title, text, price, symbol, color, sold, apply: Callable}
func make_shop_offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	for r in get_reward_choices(2):
		var o := _offer("RELIKT", r.display_name, r.description, 7 + rng.randi_range(0, 3),
			r.visual(), Color(0.55, 0.22, 0.42), func() -> void: add_relic(r))
		o.emoji = true # wie im Duell: freies Emoji statt Medaille
		offers.append(o)
	for i in 2:
		offers.append(_card_offer())
	var item_ids: Array = ITEMS.keys()
	_shuffle(item_ids)
	for id: StringName in item_ids.slice(0, SHOP_ITEMS):
		var it: Dictionary = ITEMS[id]
		var io := _offer("ITEM", it.name, it.text, it.price, it.emoji, Color.BLACK, func() -> void: add_item(id))
		io.emoji = true
		offers.append(io)
	# Boni (Farb-Schliff, Trumpf-Kenner …) gibt es nicht mehr beim Händler – die bringen die Decks mit
	return offers


func buy(offer: Dictionary) -> bool:
	if offer.get("sold", false) or gold < offer.price:
		return false
	if offer.kind == "ITEM" and not has_item_slot():
		return false
	gold -= offer.price
	offer.sold = true
	(offer.apply as Callable).call()
	changed.emit()
	return true


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
	var suit := rng.randi_range(0, 3)
	var rank := rng.randi_range(Card.MIN_RANK, Card.MAX_RANK)
	for attempt in 20:
		if not card_enhancements.has("%d:%d" % [suit, rank]):
			break
		suit = rng.randi_range(0, 3)
		rank = rng.randi_range(Card.MIN_RANK, Card.MAX_RANK)
	var enh := rng.randi_range(1, Card.ENHANCEMENT_NAMES.size() - 1)
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


## Alle Boni, die der Händler anbieten kann (für den Index; Kaufen wirkt hier nicht).
func upgrade_catalog() -> Array[Dictionary]:
	return _upgrade_pool()


func _upgrade_pool() -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for s in 4:
		var suit_s := s
		pool.append(_offer("VERBESSERUNG", "%s-Schliff" % Card.SUIT_NAMES[s],
			"%s-Karten bringen +3 Chips." % Card.SUIT_NAMES[s], 5, Card.SUIT_SYMBOLS[s],
			Color(0.65, 0.12, 0.12) if s < 2 else Color(0.1, 0.08, 0.15),
			func() -> void: suit_chip_bonus[suit_s] = int(suit_chip_bonus.get(suit_s, 0)) + 3))
	pool.append(_offer("VERBESSERUNG", "Trumpf-Kenner", "Jeder gespielte Trumpf: +1 Mult extra.", 6, "▲",
		Color(0.45, 0.32, 0.8), func() -> void: trump_mult_bonus += 1))
	pool.append(_offer("VERBESSERUNG", "Pflaster", "+1 Leben.", 6, "✚",
		Color(0.7, 0.15, 0.2), func() -> void: lives += 1))
	pool.append(_offer("VERBESSERUNG", "Sparschwein", "Zinsen bis zu +3 Gold mehr pro Sieg.", 5, "◆",
		Color(0.78, 0.58, 0.1), func() -> void: interest_max_bonus += 3))
	return pool


func has_relic(id: StringName) -> bool:
	return relics.any(func(r: RelicData) -> bool: return r.id == id)


## Matrjoschka: eine zufällige noch normale Karte des Decks bekommt eine Verbesserung.
## Gibt den Text zurück („10♥ wird Gold“) oder "" wenn alle schon verbessert sind.
func enhance_random_card() -> String:
	var free: Array = []
	for suit in 4:
		for rank in range(Card.MIN_RANK, Card.MAX_RANK + 1):
			var key := "%d:%d" % [suit, rank]
			if not card_enhancements.has(key):
				free.append([suit, rank, key])
	if free.is_empty():
		return ""
	var pick: Array = free[rng.randi_range(0, free.size() - 1)]
	var enh: int = [Card.Enhancement.GOLD, Card.Enhancement.GLASS, Card.Enhancement.LUCKY][rng.randi_range(0, 2)]
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
		changed.emit()


func add_relic(relic: RelicData) -> void:
	relics.append(relic)
	lives += relic.extra_lives
	changed.emit()


func add_gold(amount: int) -> void:
	gold += amount
	changed.emit()


func goto(scene_path: String) -> void:
	Fade.change_scene(scene_path)


## Run vorzeitig beenden (zählt als verloren, Seelen für besiegte Tische gibt es trotzdem).
func abandon() -> void:
	_end_run(false)


func _end_run(won: bool) -> void:
	won_run = won
	last_souls = Profile.on_run_finished(won, mini(floor_index, encounters.size()), souls_factor(),
		deck.id if deck != null else Profile.DEFAULT_DECK, difficulty)
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
	_shuffle(normal)
	var result: Array[OpponentData] = normal.slice(0, NORMAL_FIGHTS)
	# Leichtere Gegner zuerst
	result.sort_custom(func(a: OpponentData, b: OpponentData) -> bool:
		return a.mistake_chance > b.mistake_chance)
	if not bosses.is_empty():
		result.append(bosses[rng.randi_range(0, bosses.size() - 1)])
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


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
