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
const INTEREST_MAX := 5
const REROLL_BASE_PRICE := 2
## Punkteziel pro Etage (wie die Blinds bei Balatro). Letzter Eintrag = Boss.
## Gibt es mehr Etagen als Einträge, wird der letzte Wert weiter gesteigert.
const SCORE_TARGETS: Array[int] = [300, 380, 450, 550]
const SCORE_TARGET_GROWTH := 1.25

var rng := RandomNumberGenerator.new()
var seed_value := 0
var lives := 0
var gold := 0
var floor_index := 0
var encounters: Array[OpponentData] = []
var relics: Array[RelicData] = []
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

## Aktuelle Shop-Auslage (siehe make_shop_offers) und Preis fürs Neu-Mischen.
var shop_offers: Array[Dictionary] = []
var reroll_price := REROLL_BASE_PRICE


func start_new_run(p_seed := 0) -> void:
	seed_value = p_seed if p_seed != 0 else randi()
	rng.seed = seed_value
	lives = START_LIVES
	gold = 0
	floor_index = 0
	relics.clear()
	won_run = false
	card_enhancements.clear()
	suit_chip_bonus.clear()
	trump_mult_bonus = 0
	extra_hand = 0
	interest_max_bonus = 0
	shop_offers.clear()
	encounters = _build_encounters()
	changed.emit()
	goto(SCENE_MAP)


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
	var opponent := encounters[floor_i] if floor_i < encounters.size() else null
	if opponent != null and opponent.score_target > 0:
		return opponent.score_target
	var idx := SCORE_TARGETS.size() - 1 if opponent != null and opponent.is_boss else floor_i
	if idx < SCORE_TARGETS.size():
		return SCORE_TARGETS[idx]
	var extra := idx - SCORE_TARGETS.size() + 1
	return int(SCORE_TARGETS[-1] * pow(SCORE_TARGET_GROWTH, extra))


## Start-Mult pro Runde (1 + Boni aus Relikten).
func base_mult() -> int:
	var m := 1
	for r in relics:
		m += r.bonus_mult
	return m


## Wird von der Match-Szene aufgerufen, sobald ein Duell vorbei ist.
## `loser` ist OPPONENT, wenn das Punkteziel erreicht wurde, sonst PLAYER.
func on_match_finished(loser: int) -> void:
	match loser:
		DurakMatch.OPPONENT:
			var opponent := current_opponent()
			last_gold_reward = opponent.gold_reward
			for r in relics:
				last_gold_reward += r.bonus_gold_per_win
			last_interest = mini(gold / INTEREST_PER, INTEREST_MAX + interest_max_bonus)
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
		offers.append(_offer("RELIKT", r.display_name, r.description, 7 + rng.randi_range(0, 3),
			"★", Color(0.55, 0.22, 0.42), func() -> void: add_relic(r)))
	for i in 2:
		offers.append(_card_offer())
	var upgrades := _upgrade_pool()
	_shuffle(upgrades)
	for u in upgrades.slice(0, 2):
		offers.append(u)
	return offers


func buy(offer: Dictionary) -> bool:
	if offer.get("sold", false) or gold < offer.price:
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


func _offer(kind: String, title: String, text: String, price: int, symbol: String,
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
	return _offer("KARTE", "%s %s" % [Card.ENHANCEMENT_NAMES[enh], label], Card.ENHANCEMENT_TEXT[enh],
		4 + enh, label, colors[enh], func() -> void: card_enhancements[key] = enh)


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


func add_relic(relic: RelicData) -> void:
	relics.append(relic)
	lives += relic.extra_lives
	changed.emit()


func add_gold(amount: int) -> void:
	gold += amount
	changed.emit()


func goto(scene_path: String) -> void:
	get_tree().change_scene_to_file.call_deferred(scene_path)


func _end_run(won: bool) -> void:
	won_run = won
	changed.emit()
	goto(SCENE_RUN_END)


func _build_encounters() -> Array[OpponentData]:
	var normal: Array[OpponentData] = []
	var bosses: Array[OpponentData] = []
	for res in _load_all(OPPONENT_DIR):
		var o := res as OpponentData
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
