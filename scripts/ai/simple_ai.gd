class_name SimpleAI
extends RefCounted
## Einfache Gegner-KI: spielt möglichst billige Karten, schont Trümpfe.
## `mistake_chance` macht schwächere Gegner unberechenbarer.

var rng: RandomNumberGenerator
var mistake_chance := 0.0


func _init(p_rng: RandomNumberGenerator, p_mistake_chance := 0.0) -> void:
	rng = p_rng
	mistake_chance = p_mistake_chance


## Führt genau eine Aktion aus, wenn `me` am Zug ist.
func take_turn(duel: DurakMatch, me: int) -> void:
	if duel.current_actor() != me:
		return
	if me == duel.defender():
		_defend(duel)
	else:
		_attack(duel)


func _defend(duel: DurakMatch) -> void:
	var options := _sorted(duel.legal_defenses(), duel)
	if _should_transfer(duel, options):
		return
	if options.is_empty():
		duel.take()
		return
	duel.defend(_pick(options))


## Weiterschieben, wenn es billiger ist als Schlagen (oder Schlagen nicht geht).
## Gibt true zurück, wenn geschoben wurde.
func _should_transfer(duel: DurakMatch, defenses: Array[Card]) -> bool:
	var transfers := _sorted(duel.legal_transfers(), duel)
	if transfers.is_empty() or rng.randf() < mistake_chance * 0.5:
		return false
	var t := transfers[0]
	var t_value := DurakRules.card_value(t, duel.trump_suit)
	var cheap := t.suit != duel.trump_suit or duel.deck.is_empty()
	if defenses.is_empty():
		return cheap and duel.transfer(t)
	var defend_value := DurakRules.card_value(defenses[0], duel.trump_suit)
	if cheap and (defend_value > t_value + 2 or rng.randf() < 0.4):
		return duel.transfer(t)
	return false


func _attack(duel: DurakMatch) -> void:
	var options := _sorted(duel.legal_attacks(), duel)
	if duel.taking:
		# Der Gegner nimmt: billige Karten hinterherwerfen, Trümpfe behalten.
		if not options.is_empty():
			var c := options[0]
			if c.suit != duel.trump_suit and (c.rank <= 11 or duel.deck.is_empty()):
				duel.attack(c)
				return
		duel.finish_take()
		return
	if options.is_empty():
		duel.pass_bout()
		return
	if duel.attack_cards.is_empty():
		duel.attack(_pick(options))
		return
	# Nachlegen nur mit billigen Karten (oder wenn der Stapel leer ist).
	var cheapest := options[0]
	var cheap := cheapest.suit != duel.trump_suit and cheapest.rank <= 10
	if cheap or duel.deck.is_empty():
		duel.attack(cheapest)
	else:
		duel.pass_bout()


func _pick(options: Array[Card]) -> Card:
	if rng.randf() < mistake_chance:
		return options[rng.randi_range(0, options.size() - 1)]
	return options[0]


func _sorted(cards: Array[Card], duel: DurakMatch) -> Array[Card]:
	var result := cards.duplicate()
	result.sort_custom(func(a: Card, b: Card) -> bool:
		return DurakRules.card_value(a, duel.trump_suit) < DurakRules.card_value(b, duel.trump_suit))
	return result


## Möchte die KI direkt noch eine Karte gleichen Rangs dazuwerfen?
## Gibt die Karte zurück oder null. Nur billige Karten, keine Trümpfe.
func extra_attack(duel: DurakMatch, me: int, chance := 0.6) -> Card:
	if duel.attacker != me or duel.attack_cards.is_empty() or duel.taking or rng.randf() > chance:
		return null
	var last: Card = duel.attack_cards[-1]
	for c in _sorted(duel.legal_attacks(), duel):
		if c.rank == last.rank and c.suit != duel.trump_suit and (c.rank <= 11 or duel.deck.is_empty()):
			return c
	return null
