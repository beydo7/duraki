class_name DeckData
extends Resource
## Ein Kartendeck (Skin + kleiner Effekt). Neue Decks: unter data/decks/ eine
## Ressource vom Typ DeckData anlegen und mit tools/generate_cards.py eine Rückseite
## unter assets/cards/backs/<id>.png erzeugen.

@export var id: StringName
@export var display_name := ""
## Kurzer Text, was das Deck bewirkt (leer = nur Optik).
@export_multiline var effect_text := ""
@export var back: Texture2D
## Reihenfolge in der Auswahl
@export var sort_order := 0

@export_group("Freischalten")
## Von Anfang an verfügbar
@export var starter := false
## Wird frei, sobald dieser Gegner (Dateiname ohne .tres) besiegt wurde.
@export var unlock_opponent: StringName
## Wird frei, sobald ein Run gewonnen wurde.
@export var unlock_run_win := false
## Kaufpreis in Seelen (0 = nicht kaufbar).
@export var price_souls := 0

@export_group("Effekte")
@export var start_gold := 0
@export var extra_lives := 0
@export var extra_hand := 0
## Start-Mult jeder Runde
@export var bonus_mult := 0
@export var trump_mult_bonus := 0
@export var interest_max_bonus := 0
## Farbe (Card.Suit, -1 = keine), deren Karten mehr Chips bringen
@export var suit_bonus_suit := -1
@export var suit_bonus_chips := 0
## Zufällig verbesserte Karten zu Beginn des Runs
@export var start_gold_cards := 0
@export var start_glass_cards := 0
@export var start_lucky_cards := 0


func unlock_text() -> String:
	if starter:
		return "Von Anfang an"
	var parts := PackedStringArray()
	if unlock_opponent != &"":
		var opp := load("res://data/opponents/%s.tres" % unlock_opponent) as OpponentData
		parts.append("Besiege %s" % (opp.display_name if opp != null else String(unlock_opponent)))
	if unlock_run_win:
		parts.append("Gewinne einen Run")
	if price_souls > 0:
		parts.append("%d Seelen" % price_souls)
	return " oder ".join(parts)
