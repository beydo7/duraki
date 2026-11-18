extends Control


func _ready() -> void:
	if Run.won_run:
		%Header.text = "DIE NACHT GEHÖRT DIR"
		%TitleLabel.text = "RUN GEWONNEN!"
		%Card.caption = "DER SIEGER"
		%Card.corner = "K"
		%Card.eye_color = Color(0.95, 0.8, 0.3)
	else:
		%Header.text = "AM ENDE BLEIBT EINER ÜBRIG"
		%TitleLabel.text = "DU BIST DER DURAK."
	%SummaryLabel.text = "Gegner besiegt: %d / %d   ·   Gold: %d   ·   Seed: %d" % [
		Run.floor_index, Run.encounters.size(), Run.gold, Run.seed_value]
	%MenuButton.pressed.connect(func() -> void: Run.goto(Run.SCENE_MENU))
	%MenuButton.grab_focus()
