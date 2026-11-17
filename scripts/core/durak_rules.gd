class_name DurakRules
extends RefCounted
## Reine Regelfunktionen ohne Zustand – leicht testbar.


## Kann `defense` die Karte `attack` schlagen?
static func can_beat(attack: Card, defense: Card, trump: Card.Suit) -> bool:
	if defense.suit == attack.suit:
		return defense.rank > attack.rank
	return defense.suit == trump and attack.suit != trump


## Ränge, die bereits auf dem Tisch liegen (dürfen nachgelegt werden).
static func ranks_on_table(table: Array[Card]) -> Array[int]:
	var ranks: Array[int] = []
	for c in table:
		if not ranks.has(c.rank):
			ranks.append(c.rank)
	return ranks


## Sortiert für die Anzeige: Nicht-Trumpf zuerst, dann nach Farbe und Rang.
static func sort_hand(hand: Array[Card], trump: Card.Suit) -> void:
	hand.sort_custom(func(a: Card, b: Card) -> bool:
		var ta := a.suit == trump
		var tb := b.suit == trump
		if ta != tb:
			return tb
		if a.suit != b.suit:
			return a.suit < b.suit
		return a.rank < b.rank
	)


## Wertung einer Karte für die KI (Trümpfe sind mehr wert).
static func card_value(card: Card, trump: Card.Suit) -> int:
	return card.rank + (20 if card.suit == trump else 0)
