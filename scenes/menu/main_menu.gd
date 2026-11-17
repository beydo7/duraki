extends Control


func _ready() -> void:
	%NewRunButton.pressed.connect(func() -> void: Run.start_new_run())
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())
	%NewRunButton.grab_focus()
