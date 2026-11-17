extends Control


func _ready() -> void:
	%TitleLabel.text = "Run gewonnen!" if Run.won_run else "Du bist der Durak."
	%SummaryLabel.text = "Gegner besiegt: %d / %d   ·   Gold: %d   ·   Seed: %d" % [
		Run.floor_index, Run.encounters.size(), Run.gold, Run.seed_value]
	%MenuButton.pressed.connect(func() -> void: Run.goto(Run.SCENE_MENU))
	%MenuButton.grab_focus()
