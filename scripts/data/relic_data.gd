class_name RelicData
extends Resource
## Ein Relikt (passiver Bonus für den Run). Neue Relikte: im Editor unter
## data/relics/ eine neue Ressource vom Typ RelicData anlegen.

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
## Symbol (Emoji) für HUD, Händler, Index und Karte
@export var emoji := ""

@export_group("Effekte")
@export var hand_size_bonus := 0
@export var bonus_gold_per_win := 0
@export var extra_lives := 0
## Start-Mult jeder Runde (wie ein Joker bei Balatro).
@export var bonus_mult := 0


## Emoji oder notfalls der Anfangsbuchstabe.
func icon() -> String:
	return emoji if not emoji.is_empty() else display_name.left(1)
