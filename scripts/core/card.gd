class_name Card
extends RefCounted
## Eine einzelne Spielkarte (36er-Blatt: 6 bis Ass).

enum Suit { HEARTS, DIAMONDS, CLUBS, SPADES }

const MIN_RANK := 6
const MAX_RANK := 14 # Ass
const RANK_NAMES := {
	6: "6", 7: "7", 8: "8", 9: "9", 10: "10",
	11: "B", 12: "D", 13: "K", 14: "A",
}
const SUIT_SYMBOLS := ["♥", "♦", "♣", "♠"]
const SUIT_NAMES := ["Herz", "Karo", "Kreuz", "Pik"]

var suit: Suit
var rank: int


func _init(p_suit: Suit = Suit.HEARTS, p_rank: int = MIN_RANK) -> void:
	suit = p_suit
	rank = p_rank


func is_red() -> bool:
	return suit == Suit.HEARTS or suit == Suit.DIAMONDS


func get_label() -> String:
	return RANK_NAMES[rank] + SUIT_SYMBOLS[suit]


func _to_string() -> String:
	return get_label()
