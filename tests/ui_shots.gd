extends Node
## Screenshots aller 2D-Bildschirme (Menü, Weg, Belohnung, Ende).
##   xvfb-run godot --path . --rendering-driver opengl3 res://tests/ui_shots.tscn -- out=/tmp/ui

var out_dir := "user://ui_shots"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out_dir = arg.substr(4)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var placeholder := Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	Run.goto(Run.SCENE_MENU)
	await get_tree().create_timer(2.5).timeout
	await _wait_shot("1_menu")
	var options := OptionsMenu.new()
	get_tree().current_scene.add_child(options)
	await _wait_shot("1b_options_grafik")
	options._tab_buttons[1].pressed.emit()
	await _wait_shot("1c_options_audio")
	options._tab_buttons[2].pressed.emit()
	await _wait_shot("1d_options_allgemein")
	options.close()
	Run.start_new_run(4242)
	await get_tree().create_timer(0.2).timeout
	Run.floor_index = 1
	Run.relics.append(load("res://data/relics/lucky_coin.tres"))
	Run.goto(Run.SCENE_MAP)
	await _wait_shot("2_map")
	Pause.open()
	await _wait_shot("2b_pause")
	Pause.close()
	Run.last_gold_reward = 8
	Run.last_interest = 2
	Run.gold = 14
	Run.open_shop()
	await _wait_shot("3_shop")
	Run.won_run = false
	Run.goto(Run.SCENE_RUN_END)
	await _wait_shot("4_end")
	get_tree().quit()


func _wait_shot(name: String) -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("Screenshot: ", name)
