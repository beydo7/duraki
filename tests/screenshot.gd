extends Node
## Rendert Screenshots der Duell-Szene (zum Prüfen des Designs).
##   godot --path . res://tests/screenshot.tscn -- out=/tmp/shots
## Ohne Bildschirm z. B. mit xvfb-run starten.

var out_dir := "user://shots"
var _bot := SimpleAI.new(RandomNumberGenerator.new(), 0.0)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out_dir = arg.substr(4)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_detach.call_deferred()


func _detach() -> void:
	var placeholder := Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	Run.start_new_run(4242)
	await get_tree().create_timer(0.5).timeout
	Run.floor_index = Run.encounters.size() - 1 if "boss" in OS.get_cmdline_user_args() else 0
	if "enh" in OS.get_cmdline_user_args():
		# ein paar verbesserte Karten zum Ansehen
		for suit in 4:
			for rank in [7, 10, 12, 14]:
				Run.card_enhancements["%d:%d" % [suit, rank]] = 1 + (suit + rank) % 3
	Run.goto(Run.SCENE_MATCH)
	await get_tree().create_timer(2.5).timeout
	var scene := get_tree().current_scene
	var duel: DurakMatch = scene.duel
	var args := OS.get_cmdline_user_args()
	if "rows" in args:
		TableWorld.hand_layout = "rows"
	if "many" in args:
		# viele Karten auf die Hand, um das Layout zu prüfen
		var extra := 20 if "huge" in args else 12
		for k in extra:
			duel.player_hand.append(duel.deck.draw())
		DurakRules.sort_hand(duel.player_hand, duel.trump_suit)
		duel.changed.emit()
		await get_tree().create_timer(2.0).timeout
		await _shot("many")
		get_tree().quit()
		return
	await _shot("1_start")
	# ein paar Züge spielen
	for step in 6:
		if duel.is_over:
			break
		if duel.current_actor() == DurakMatch.PLAYER:
			_bot.take_turn(duel, DurakMatch.PLAYER)
		await get_tree().create_timer(1.2).timeout
		await _shot("2_step%d" % step)
	get_tree().quit()


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("Screenshot: ", name)
