class_name ScoreTracker
extends RefCounted
## Punktewertung wie bei Balatro: Chips × Mult.
##
## Jede Runde (Angriff bis Bito/Nehmen) sammelt Chips und Mult für den Spieler:
## - Jede eigene Karte (Angriff oder Verteidigung) bringt ihren Chip-Wert.
## - Jede Verteidigung: +1 Mult.
## - Jede nachgelegte Angriffskarte (ab der zweiten): +1 Mult.
## - Jeder gespielte Trumpf: +1 Mult.
## Am Rundenende wird gewertet:
## - Du verteidigst alles (Bito)       → Chips × Mult
## - Dein Angriff wird abgewehrt       → Chips × Mult
## - Gegner muss aufnehmen             → Chips × Mult × 2 („Volltreffer“)
## - Du musst aufnehmen                → 0 Punkte, die Runde verfällt
## Endet das Duell regulär und der Gegner ist der Durak, gibt es einen Bonus
## pro Karte, die er noch auf der Hand hat.
## Wer das Punkteziel erreicht, gewinnt den Tisch sofort.

signal changed
signal bout_scored(points: int, text: String)
signal target_reached
## Eine Goldkarte wurde gespielt.
signal gold_found(amount: int, source: String)
## Eine Glückskarte hat getroffen (Zufall): zusätzliches Mult für diese Runde.
signal lucky_hit(extra_mult: int)
## Ein Relikt hat gewirkt (für das Aufblitzen im HUD)
signal relic_triggered(id: StringName)

const CHIP_VALUES := {
	6: 6, 7: 7, 8: 8, 9: 9, 10: 10,
	11: 10, 12: 10, 13: 10, # Bube (J), Dame, König
	14: 11, # Ass
}
const HIT_MULTIPLIER := 2
const DURAK_BONUS_PER_CARD := 15
## Glückskarte: Chance und Bonus
const LUCKY_CHANCE := 1.0 / 3.0
const LUCKY_MULT := 5

var target := 0
var total := 0
var base_mult := 1
var chips := 0
var mult := 1
var last_text := ""
## Zusätzliche Chips pro Farbe (Card.Suit → int), aus Shop-Verbesserungen.
var suit_chip_bonus := {}
## Zusätzliches Mult für jeden gespielten Trumpf.
var trump_mult_bonus := 0
## Zufall für Glückskarten (Tests setzen lucky_chance auf 0 oder 1)
var rng := RandomNumberGenerator.new()
var lucky_chance := LUCKY_CHANCE
## Relikte/Items (setzt match.gd):
## Wolfszahn – Chips für jede eigene Verteidigung mit Trumpf
var trump_defense_chips := 0
## Wirbel – Mult beim ersten eigenen Schieben im Duell
var first_transfer_mult := 0
## Hufeisen – Gold bei jedem Glücks-Treffer
var lucky_gold := 0
## Maske – Faktor für die nächste gewertete Runde (danach wieder 1)
var next_bout_factor := 1
var _transfer_bonus_used := false

var _duel: DurakMatch
var _me := DurakMatch.PLAYER
var _bout_attacker := -1
var _target_announced := false


func _init(p_target: int, p_base_mult := 1) -> void:
	target = p_target
	base_mult = maxi(1, p_base_mult)
	mult = base_mult
	rng.randomize()


func attach(duel: DurakMatch, me := DurakMatch.PLAYER) -> void:
	_duel = duel
	_me = me
	duel.card_played.connect(_on_card_played)
	duel.transferred.connect(_on_transferred)
	duel.bout_ended.connect(_on_bout_ended)
	duel.finished.connect(_on_finished)


static func chip_value(card: Card) -> int:
	return CHIP_VALUES.get(card.rank, card.rank)


## Chips einer Karte inkl. Farb-Bonus und Glaskarte.
func card_chips(card: Card) -> int:
	var c: int = chip_value(card) + int(suit_chip_bonus.get(card.suit, 0))
	if card.enhancement == Card.Enhancement.GLASS:
		c *= 2
	return c


func reached_target() -> bool:
	return total >= target


func remaining() -> int:
	return maxi(0, target - total)


# --- Signale vom Duell --------------------------------------------------------

func _on_card_played(who: int, card: Card, as_attack: bool) -> void:
	if _bout_attacker == -1:
		_bout_attacker = _duel.attacker
	if who != _me:
		return
	chips += card_chips(card)
	match card.enhancement:
		Card.Enhancement.GOLD:
			gold_found.emit(3, "Goldkarte")
		Card.Enhancement.LUCKY:
			if rng.randf() < lucky_chance:
				mult += LUCKY_MULT
				lucky_hit.emit(LUCKY_MULT)
				if lucky_chance > LUCKY_CHANCE:
					relic_triggered.emit(&"loaded_dice")
				if lucky_gold > 0:
					gold_found.emit(lucky_gold, "Hufeisen")
					relic_triggered.emit(&"horseshoe")
	if as_attack:
		if _duel.attack_cards.size() > 1:
			mult += 1 # Nachlegen
	else:
		mult += 1 # Verteidigung
	if card.suit == _duel.trump_suit:
		mult += 1 + trump_mult_bonus
		if not as_attack and trump_defense_chips > 0:
			chips += trump_defense_chips
			relic_triggered.emit(&"wolf_tooth")
	changed.emit()


## Nach dem Schieben zählt der Schiebende als Angreifer dieser Runde.
## (Methode statt Lambda: ein Lambda hielte die Wertung fest, die Wertung hält das Duell –
## dann würden beide nie freigegeben.)
func _on_transferred(who: int, _card: Card) -> void:
	_bout_attacker = who
	if who == _me and first_transfer_mult > 0 and not _transfer_bonus_used:
		_transfer_bonus_used = true
		mult += first_transfer_mult
		relic_triggered.emit(&"whirl")
		changed.emit()


func _on_bout_ended(defended: bool) -> void:
	var i_attacked := _bout_attacker == _me
	var points := 0
	var text := ""
	if chips > 0:
		if i_attacked and not defended:
			points = chips * mult * HIT_MULTIPLIER
			text = "Volltreffer! %d × %d × %d = %d" % [chips, mult, HIT_MULTIPLIER, points]
		elif not i_attacked and not defended:
			text = "Aufgenommen – %d × %d verfallen." % [chips, mult]
		else:
			points = chips * mult
			text = "%d × %d = %d" % [chips, mult, points]
		if points > 0 and next_bout_factor > 1:
			points *= next_bout_factor
			text += "  · Maske ×%d = %d" % [next_bout_factor, points]
			next_bout_factor = 1
	_add_points(points, text)
	chips = 0
	mult = base_mult
	_bout_attacker = -1
	changed.emit()


func _on_finished(loser: int) -> void:
	# Bonus nur bei regulärem Ende (nicht, wenn das Ziel schon erreicht war).
	if _target_announced or loser != 1 - _me:
		return
	var cards_left := _duel.hand(loser).size()
	if cards_left > 0:
		var bonus := cards_left * DURAK_BONUS_PER_CARD
		_add_points(bonus, "Durak-Bonus: %d Karten × %d = %d" % [cards_left, DURAK_BONUS_PER_CARD, bonus])
	changed.emit()


## Punkte direkt gutschreiben (z. B. Item Bestechung).
func add_bonus(points: int, text: String) -> void:
	_add_points(points, text)
	changed.emit()


func _add_points(points: int, text: String) -> void:
	total += points
	if not text.is_empty():
		last_text = text
		bout_scored.emit(points, text)
	if not _target_announced and reached_target():
		_target_announced = true
		target_reached.emit()
