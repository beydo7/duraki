class_name Card
extends RefCounted
## Eine einzelne Spielkarte (36er-Blatt: 6 bis Ass).

enum Suit { HEARTS, DIAMONDS, CLUBS, SPADES }

const MIN_RANK := 6
const MAX_RANK := 14 # Ass
const RANK_NAMES := {
	6: "6", 7: "7", 8: "8", 9: "9", 10: "10",
	11: "J", 12: "D", 13: "K", 14: "A",
}
const SUIT_SYMBOLS := ["♥", "♦", "♣", "♠"]
const SUIT_NAMES := ["Herz", "Karo", "Kreuz", "Pik"]

## Verbesserungen, die man im Shop für einzelne Karten kaufen kann.
enum Enhancement { NONE, GOLD, GLASS, LUCKY }
const ENHANCEMENT_NAMES := ["", "Goldkarte", "Glaskarte", "Glückskarte"]
const ENHANCEMENT_TEXT := [
	"",
	"+3 Gold, wenn du sie spielst.",
	"Doppelte Chips, wenn du sie spielst.",
	"+1 Gold, wenn du sie spielst.",
]
const ENHANCEMENT_TAGS := ["", "GOLD", "GLAS", "GLÜCK"]

var suit: Suit
var rank: int
var enhancement := Enhancement.NONE


func _init(p_suit: Suit = Suit.HEARTS, p_rank: int = MIN_RANK) -> void:
	suit = p_suit
	rank = p_rank


func is_red() -> bool:
	return suit == Suit.HEARTS or suit == Suit.DIAMONDS


## Eindeutiger Schlüssel für Farbe + Rang (z. B. für gekaufte Verbesserungen).
func key() -> String:
	return "%d:%d" % [suit, rank]


func get_label() -> String:
	return RANK_NAMES[rank] + SUIT_SYMBOLS[suit]


func _to_string() -> String:
	return get_label()
