class_name Deck
extends RefCounted
## Kartenstapel. Die unterste Karte (Index 0) ist die aufgedeckte Trumpfkarte
## und wird als letzte gezogen.

var cards: Array[Card] = []


func _init() -> void:
	for s in Card.Suit.values():
		for r in range(Card.MIN_RANK, Card.MAX_RANK + 1):
			cards.append(Card.new(s, r))


## Mischt mit einem eigenen RNG, damit Runs über einen Seed reproduzierbar sind.
func shuffle(rng: RandomNumberGenerator) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cards[i]
		cards[i] = cards[j]
		cards[j] = tmp


func draw() -> Card:
	return cards.pop_back()


func size() -> int:
	return cards.size()


func is_empty() -> bool:
	return cards.is_empty()


func bottom_card() -> Card:
	return cards[0] if not cards.is_empty() else null
