class_name RelicData
extends Resource
## Ein Relikt (passiver Bonus für den Run). Neue Relikte: im Editor unter
## data/relics/ eine neue Ressource vom Typ RelicData anlegen.

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""

@export_group("Effekte")
@export var hand_size_bonus := 0
@export var bonus_gold_per_win := 0
@export var extra_lives := 0
