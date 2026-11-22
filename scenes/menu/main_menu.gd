extends Control


func _ready() -> void:
	%NewRunButton.pressed.connect(func() -> void: Run.start_new_run())
	%OptionsButton.pressed.connect(_open_options)
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())
	%NewRunButton.grab_focus()


func _open_options() -> void:
	var menu := OptionsMenu.new()
	add_child(menu)
	menu.closed.connect(func() -> void: %OptionsButton.grab_focus())
