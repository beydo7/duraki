extends Control
## Startszene: Testaufbau, der ein Deck mischt und eine Hand austeilt.
## Leertaste / "Neu geben" mischt neu.

@onready var info_label: Label = %InfoLabel
@onready var hand_label: Label = %HandLabel

var deck: Deck
var hand: Array[Card] = []


func _ready() -> void:
	%DealButton.pressed.connect(_deal)
	_deal()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_deal()


func _deal() -> void:
	deck = Deck.new()
	hand.clear()
	deck.refill_hand(hand)
	hand.sort_custom(func(a: Card, b: Card) -> bool:
		if a.suit != b.suit:
			return a.suit < b.suit
		return a.rank < b.rank)

	info_label.text = "Trumpf: %s   |   Karten im Stapel: %d" % [deck.trump_card, deck.remaining()]
	hand_label.text = "  ".join(hand.map(func(c: Card) -> String: return str(c)))
