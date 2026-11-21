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

@export_group("Aussehen")
## 3D-Modell aus art/blender/opponents (exportiert nach assets/models/opponents)
@export var model: PackedScene
## Gerendertes Porträt fürs HUD und die Run-Übersicht (assets/portraits)
@export var portrait: Texture2D
@export var eye_color := Color("c4271b")
@export_range(0.7, 1.5, 0.05) var figure_scale := 1.0
## Nur für die gezeichnete Ersatz-Maske, wenn kein Porträt da ist
@export var mask_color := Color("d8cfb8")
