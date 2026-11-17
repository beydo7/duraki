class_name DurakMatch
extends RefCounted
## Ein Durak-Duell (1 gegen 1) als reine Spiellogik ohne UI.
##
## Ablauf vereinfacht und rundenbasiert:
## - Der Angreifer legt eine Karte, der Verteidiger schlägt sie oder nimmt alles.
## - Ist alles geschlagen, darf der Angreifer Karten mit Rängen vom Tisch
##   nachlegen oder die Runde beenden („Bito“).
## - Danach wird auf die Handgröße aufgefüllt (Angreifer zuerst).
## - Wer bei leerem Stapel als Letzter Karten hält, ist der Durak.

signal changed
signal message(text: String)
signal bout_ended(defended: bool)
## Wird für jede gespielte Karte gesendet (für Wertung, Joker, Effekte).
signal card_played(who: int, card: Card, as_attack: bool)
signal finished(loser: int)

const PLAYER := 0
const OPPONENT := 1
const NO_LOSER := -1 # Unentschieden
const MAX_ATTACK_CARDS := 6

var deck: Deck
var trump_card: Card
var trump_suit: Card.Suit
var player_hand: Array[Card] = []
var opponent_hand: Array[Card] = []
var hand_sizes: Array[int] = [6, 6]

var attack_cards: Array[Card] = []
var defense_cards: Array[Card] = [] # gleiche Länge wie attack_cards, null = ungeschlagen
var discard_pile: Array[Card] = []

var attacker := PLAYER
var bout_limit := MAX_ATTACK_CARDS
var is_over := false
var loser := NO_LOSER


func start(rng: RandomNumberGenerator, player_hand_size := 6, opponent_hand_size := 6) -> void:
	deck = Deck.new()
	deck.shuffle(rng)
	trump_card = deck.bottom_card()
	trump_suit = trump_card.suit
	hand_sizes = [player_hand_size, opponent_hand_size]
	_refill(PLAYER)
	_refill(OPPONENT)
	attacker = _lowest_trump_holder()
	message.emit("Trumpf ist %s. %s beginnt." % [Card.SUIT_NAMES[trump_suit], name_of(attacker)])
	changed.emit()


# --- Abfragen -----------------------------------------------------------------

func hand(p: int) -> Array[Card]:
	return player_hand if p == PLAYER else opponent_hand


func defender() -> int:
	return 1 - attacker


func name_of(p: int) -> String:
	return "Du" if p == PLAYER else "Gegner"


func table_cards() -> Array[Card]:
	var result: Array[Card] = []
	result.append_array(attack_cards)
	for c in defense_cards:
		if c != null:
			result.append(c)
	return result


func unbeaten_index() -> int:
	for i in defense_cards.size():
		if defense_cards[i] == null:
			return i
	return -1


## Wer ist gerade am Zug? (NO_LOSER, wenn das Spiel vorbei ist)
func current_actor() -> int:
	if is_over:
		return NO_LOSER
	return defender() if unbeaten_index() != -1 else attacker


func can_attack_with(card: Card) -> bool:
	if is_over or current_actor() != attacker or not hand(attacker).has(card):
		return false
	if attack_cards.is_empty():
		return true
	if attack_cards.size() >= bout_limit or hand(defender()).is_empty():
		return false
	return DurakRules.ranks_on_table(table_cards()).has(card.rank)


func legal_attacks() -> Array[Card]:
	return hand(attacker).filter(can_attack_with)


func can_defend_with(card: Card) -> bool:
	var idx := unbeaten_index()
	if is_over or idx == -1 or not hand(defender()).has(card):
		return false
	return DurakRules.can_beat(attack_cards[idx], card, trump_suit)


func legal_defenses() -> Array[Card]:
	return hand(defender()).filter(can_defend_with)


func can_take() -> bool:
	return not is_over and unbeaten_index() != -1


func can_pass() -> bool:
	return not is_over and not attack_cards.is_empty() and unbeaten_index() == -1


# --- Aktionen -----------------------------------------------------------------

func attack(card: Card) -> bool:
	if not can_attack_with(card):
		return false
	if attack_cards.is_empty():
		bout_limit = mini(MAX_ATTACK_CARDS, hand(defender()).size())
	hand(attacker).erase(card)
	attack_cards.append(card)
	defense_cards.append(null)
	card_played.emit(attacker, card, true)
	message.emit("%s %s %s." % [name_of(attacker), "legst" if attacker == PLAYER else "legt", card])
	changed.emit()
	return true


func defend(card: Card) -> bool:
	if not can_defend_with(card):
		return false
	var idx := unbeaten_index()
	hand(defender()).erase(card)
	defense_cards[idx] = card
	card_played.emit(defender(), card, false)
	message.emit("%s %s %s mit %s." % [
		name_of(defender()), "schlägst" if defender() == PLAYER else "schlägt", attack_cards[idx], card])
	_auto_pass_if_stuck()
	changed.emit()
	return true


## Verteidiger nimmt alle Karten vom Tisch. Der Angreifer bleibt Angreifer.
func take() -> bool:
	if not can_take():
		return false
	message.emit("%s %s die Karten." % [name_of(defender()), "nimmst" if defender() == PLAYER else "nimmt"])
	hand(defender()).append_array(table_cards())
	_end_bout(false)
	return true


## Angreifer beendet die Runde („Bito“). Karten wandern auf den Ablagestapel.
func pass_bout() -> bool:
	if not can_pass():
		return false
	message.emit("Bito – die Karten gehen weg.")
	discard_pile.append_array(table_cards())
	_end_bout(true)
	return true


## Beendet das Duell sofort (z. B. wenn das Punkteziel erreicht ist).
func force_finish(p_loser: int, text := "") -> void:
	if is_over:
		return
	is_over = true
	loser = p_loser
	if not text.is_empty():
		message.emit(text)
	finished.emit(loser)
	changed.emit()


# --- Intern -------------------------------------------------------------------

func _auto_pass_if_stuck() -> void:
	if unbeaten_index() == -1 and legal_attacks().is_empty():
		pass_bout()


func _end_bout(defended: bool) -> void:
	attack_cards.clear()
	defense_cards.clear()
	var old_attacker := attacker
	_refill(old_attacker)
	_refill(1 - old_attacker)
	if defended:
		attacker = 1 - old_attacker
	bout_ended.emit(defended)
	_check_end()
	changed.emit()


func _refill(p: int) -> void:
	var h := hand(p)
	while h.size() < hand_sizes[p] and not deck.is_empty():
		h.append(deck.draw())
	DurakRules.sort_hand(h, trump_suit)


func _check_end() -> void:
	if is_over or not deck.is_empty():
		return
	var player_out := player_hand.is_empty()
	var opponent_out := opponent_hand.is_empty()
	if not player_out and not opponent_out:
		return
	is_over = true
	if player_out and opponent_out:
		loser = NO_LOSER
		message.emit("Unentschieden!")
	else:
		loser = OPPONENT if player_out else PLAYER
		message.emit("%s %s der Durak!" % [name_of(loser), "bist" if loser == PLAYER else "ist"])
	finished.emit(loser)


func _lowest_trump_holder() -> int:
	var best_player := PLAYER
	var best_rank := 99
	for p in [PLAYER, OPPONENT]:
		for c in hand(p):
			if c.suit == trump_suit and c.rank < best_rank:
				best_rank = c.rank
				best_player = p
	return best_player
