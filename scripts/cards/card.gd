class_name Card
extends Resource
## Eine einzelne Spielkarte im Durak-Deck (36 Karten: 6 bis Ass).

enum Suit { HEARTS, DIAMONDS, CLUBS, SPADES }

const SUIT_SYMBOLS := {
	Suit.HEARTS: "♥",
	Suit.DIAMONDS: "♦",
	Suit.CLUBS: "♣",
	Suit.SPADES: "♠",
}

## Rang 6..14 (11 = Bube, 12 = Dame, 13 = König, 14 = Ass)
const RANK_NAMES := {
	6: "6", 7: "7", 8: "8", 9: "9", 10: "10",
	11: "B", 12: "D", 13: "K", 14: "A",
}

@export var suit: Suit = Suit.HEARTS
@export_range(6, 14) var rank: int = 6


static func create(p_suit: Suit, p_rank: int) -> Card:
	var card := Card.new()
	card.suit = p_suit
	card.rank = p_rank
	return card


## Durak-Regel: Kann diese Karte (Verteidigung) die angreifende Karte schlagen?
## - gleiche Farbe und höherer Rang, oder
## - Trumpf gegen Nicht-Trumpf.
func beats(attacking: Card, trump_suit: Suit) -> bool:
	if suit == attacking.suit:
		return rank > attacking.rank
	return suit == trump_suit


func is_red() -> bool:
	return suit == Suit.HEARTS or suit == Suit.DIAMONDS


func _to_string() -> String:
	return "%s%s" % [RANK_NAMES[rank], SUIT_SYMBOLS[suit]]
