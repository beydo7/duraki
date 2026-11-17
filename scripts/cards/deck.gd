class_name Deck
extends RefCounted
## Das Durak-Deck: 36 Karten, die unterste Karte bestimmt den Trumpf.

var cards: Array[Card] = []
var trump_card: Card
var trump_suit: Card.Suit


func _init() -> void:
	reset()


## Baut ein frisches, gemischtes Deck und legt den Trumpf fest.
func reset() -> void:
	cards.clear()
	for suit in Card.Suit.values():
		for rank in range(6, 15):
			cards.append(Card.create(suit, rank))
	cards.shuffle()
	# Die unterste Karte (Index 0) liegt offen und bestimmt den Trumpf.
	# Sie wird als letzte gezogen.
	trump_card = cards[0]
	trump_suit = trump_card.suit


## Zieht die oberste Karte. Gibt null zurück, wenn das Deck leer ist.
func draw() -> Card:
	if cards.is_empty():
		return null
	return cards.pop_back()


## Füllt eine Hand bis zur gewünschten Größe auf (Standard in Durak: 6).
func refill_hand(hand: Array[Card], target_size: int = 6) -> void:
	while hand.size() < target_size and not cards.is_empty():
		hand.append(draw())


func remaining() -> int:
	return cards.size()
