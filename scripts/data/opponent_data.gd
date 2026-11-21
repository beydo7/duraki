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
@export var mask_color := Color("d8cfb8")
@export var body_color := Color("1b1716")
@export var eye_color := Color("c4271b")
@export_range(0.7, 1.5, 0.05) var figure_scale := 1.0
@export var wears_hat := false
## Monster-Merkmale (Teile kommen aus art/blender/figure.blend)
@export_enum("Keine", "Teufelshörner", "Widderhörner") var horns := 0
@export_enum("Zugenäht", "Grinsen mit Zähnen") var mouth := 1
@export var extra_eyes := false
