class_name OpponentData
extends Resource
## Ein Gegner im Run. Neue Gegner: im Editor unter data/opponents/ eine neue
## Ressource vom Typ OpponentData anlegen.

@export var display_name := "Gegner"
@export_multiline var taunt := ""
@export var hand_size := 6
@export_range(0.0, 1.0, 0.05) var mistake_chance := 0.3
@export var gold_reward := 10
@export var is_boss := false
## Eigenes Punkteziel; 0 = Standardziel der Etage (Run.SCORE_TARGETS).
@export var score_target := 0
