class_name DurakMatch
extends RefCounted
## Ein Durak-Duell (1 gegen 1) als reine Spiellogik ohne UI.
##
## Regeln (Schiebe-Durak / Perevodnoy, 1 gegen 1):
## - Der Angreifer legt eine Karte (oder mehrere gleichen Rangs), der Verteidiger
##   schlägt sie, schiebt weiter oder nimmt alles.
## - Schieben: Solange noch nichts geschlagen ist und alle Angriffskarten denselben
##   Rang haben, darf der Verteidiger eine Karte dieses Rangs dazulegen. Dann tauschen
##   die Rollen und der bisherige Angreifer muss sich gegen alle Karten verteidigen
##   (nur wenn er genug Karten auf der Hand hat).
## - Der Angreifer darf Karten mit Rängen vom Tisch nachlegen oder die Runde
##   beenden („Bito“).
## - Nimmt der Verteidiger auf, darf der Angreifer noch passende Karten
##   hinterherwerfen (nachwerfen), die ebenfalls aufgenommen werden.
## - Danach wird auf die Handgröße aufgefüllt (Angreifer zuerst).
## - Wer bei leerem Stapel als Letzter Karten hält, ist der Durak.

signal changed
signal message(text: String)
signal bout_ended(defended: bool)
## Wird für jede gespielte Karte gesendet (für Wertung, Joker, Effekte).
signal card_played(who: int, card: Card, as_attack: bool)
## Jemand hat Karten vom Stapel gezogen.
signal cards_drawn(who: int, count: int)
## Der Verteidiger nimmt die Tischkarten auf.
signal cards_taken(who: int, count: int)
## Bito: die Tischkarten gehen auf den Ablagestapel.
signal cards_discarded(count: int)
## Der Verteidiger hat weitergeschoben und ist jetzt Angreifer.
signal transferred(who: int, card: Card)
## Der Verteidiger hat „nehmen“ angesagt; der Angreifer darf noch nachwerfen.
signal take_declared(who: int)
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
## Verteidiger hat „nehmen“ angesagt, Angreifer darf noch nachwerfen.
var taking := false
var is_over := false
var loser := NO_LOSER


## `deck_setup` (optional) bekommt die Karten des frisch gemischten Stapels,
## z. B. um gekaufte Verbesserungen anzuwenden.
func start(rng: RandomNumberGenerator, player_hand_size := 6, opponent_hand_size := 6,
		deck_setup := Callable()) -> void:
	deck = Deck.new()
	deck.shuffle(rng)
	if deck_setup.is_valid():
		deck_setup.call(deck.cards)
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
	if taking:
		return attacker
	return defender() if unbeaten_index() != -1 else attacker


## Der Angreifer darf jederzeit passende Ränge dazulegen – auch mehrere auf
## einmal, ohne auf die Verteidigung zu warten. Grenze: nie mehr ungeschlagene
## Karten, als der Verteidiger noch auf der Hand hat.
func can_attack_with(card: Card) -> bool:
	if is_over or not hand(attacker).has(card):
		return false
	if attack_cards.is_empty():
		return current_actor() == attacker
	if attack_cards.size() >= bout_limit or hand(defender()).is_empty():
		return false
	if unbeaten_count() >= hand(defender()).size():
		return false
	return DurakRules.ranks_on_table(table_cards()).has(card.rank)


func unbeaten_count() -> int:
	return defense_cards.count(null)


func legal_attacks() -> Array[Card]:
	return hand(attacker).filter(can_attack_with)


func can_defend_with(card: Card) -> bool:
	var idx := unbeaten_index()
	if is_over or taking or idx == -1 or not hand(defender()).has(card):
		return false
	return DurakRules.can_beat(attack_cards[idx], card, trump_suit)


## Darf der Verteidiger mit `card` weiterschieben?
func can_transfer_with(card: Card) -> bool:
	if is_over or taking or attack_cards.is_empty() or not hand(defender()).has(card):
		return false
	for d in defense_cards:
		if d != null:
			return false # es wurde schon geschlagen
	for a in attack_cards:
		if a.rank != card.rank:
			return false
	var count := attack_cards.size() + 1
	# der neue Verteidiger (bisheriger Angreifer) muss alle Karten schlagen können
	return count <= MAX_ATTACK_CARDS and hand(attacker).size() >= count


func legal_transfers() -> Array[Card]:
	return hand(defender()).filter(can_transfer_with)


func legal_defenses() -> Array[Card]:
	return hand(defender()).filter(can_defend_with)


func can_take() -> bool:
	return not is_over and not taking and unbeaten_index() != -1


func can_pass() -> bool:
	return not is_over and not taking and not attack_cards.is_empty() and unbeaten_index() == -1


## Angreifer ist mit dem Nachwerfen fertig (nur während `taking`).
func can_finish_take() -> bool:
	return not is_over and taking


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
	message.emit("%s %s %s%s." % [name_of(attacker), "legst" if attacker == PLAYER else "legt", card,
		" nach" if taking else ""])
	if taking and legal_attacks().is_empty():
		finish_take() # nichts mehr nachzuwerfen
		return true
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


## Verteidiger schiebt weiter: legt eine Karte gleichen Rangs dazu und wird Angreifer.
func transfer(card: Card) -> bool:
	if not can_transfer_with(card):
		return false
	var who := defender()
	hand(who).erase(card)
	attack_cards.append(card)
	defense_cards.append(null)
	attacker = who
	bout_limit = mini(MAX_ATTACK_CARDS, hand(defender()).size())
	transferred.emit(who, card)
	card_played.emit(who, card, true)
	message.emit("%s %s mit %s weiter!" % [name_of(who), "schiebst" if who == PLAYER else "schiebt", card])
	changed.emit()
	return true


## Verteidiger sagt „nehmen“ an. Der Angreifer darf noch passende Karten
## nachwerfen und beendet dann mit finish_take(). Kann er nichts mehr legen,
## werden die Karten sofort aufgenommen.
func take() -> bool:
	if not can_take():
		return false
	taking = true
	message.emit("%s %s die Karten." % [name_of(defender()), "nimmst" if defender() == PLAYER else "nimmt"])
	take_declared.emit(defender())
	if legal_attacks().is_empty():
		finish_take()
	else:
		changed.emit()
	return true


## Nachwerfen beendet: der Verteidiger nimmt alle Tischkarten auf.
## Der Angreifer bleibt Angreifer.
func finish_take() -> bool:
	if not can_finish_take():
		return false
	taking = false
	var taken := table_cards()
	hand(defender()).append_array(taken)
	cards_taken.emit(defender(), taken.size())
	_end_bout(false)
	return true


## Angreifer beendet die Runde („Bito“). Karten wandern auf den Ablagestapel.
func pass_bout() -> bool:
	if not can_pass():
		return false
	message.emit("Fertig – die Karten gehen weg.")
	var cleared := table_cards()
	discard_pile.append_array(cleared)
	cards_discarded.emit(cleared.size())
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
	if not taking and unbeaten_index() == -1 and legal_attacks().is_empty():
		pass_bout()


func _end_bout(defended: bool) -> void:
	taking = false
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
	var drawn := 0
	while h.size() < hand_sizes[p] and not deck.is_empty():
		h.append(deck.draw())
		drawn += 1
	if drawn > 0:
		cards_drawn.emit(p, drawn)
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
