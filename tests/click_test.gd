extends Node
## Prüft, ob man Handkarten in der 3D-Szene per Mausklick spielen kann.
##   xvfb-run godot --path . --rendering-driver opengl3 res://tests/click_test.tscn

func _ready() -> void:
	Profile.reset_for_tests()
	_run.call_deferred()


func _run() -> void:
	var placeholder := Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	Run.start_new_run(4242)
	await get_tree().create_timer(0.3).timeout
	Run.goto(Run.SCENE_MATCH)
	var ok := false
	for attempt in 40:
		await get_tree().create_timer(0.5).timeout
		var scene := get_tree().current_scene
		if scene == null or scene.name != "Match":
			continue
		var duel: DurakMatch = scene.duel
		if duel.current_actor() != DurakMatch.PLAYER:
			continue
		var defending := duel.defender() == DurakMatch.PLAYER
		var options := duel.legal_defenses() if defending else duel.legal_attacks()
		if options.is_empty():
			continue
		var target: Card = options[0]
		var world: TableWorld = scene.world
		var node: Card3D = world._cards[target]
		var shrink: float = scene.get_node("%View").stretch_shrink
		var screen := world.camera.unproject_position(node.global_transform * Vector3(0, 0, -Card3D.HEIGHT * 0.3)) * shrink
		var before := duel.hand(DurakMatch.PLAYER).size()
		_mouse(screen, false)
		await get_tree().create_timer(0.2).timeout
		_mouse(screen, true)
		await get_tree().process_frame
		_mouse(screen, false, false)
		await get_tree().create_timer(0.3).timeout
		var after := duel.hand(DurakMatch.PLAYER).size()
		print("Klick auf %s bei %s: Handkarten %d -> %d" % [target, screen, before, after])
		ok = after < before
		break
	print("KLICKTEST: ", "OK" if ok else "FEHLGESCHLAGEN")
	get_tree().quit(0 if ok else 1)


func _mouse(pos: Vector2, button: bool, pressed := true) -> void:
	if button:
		var e := InputEventMouseButton.new()
		e.position = pos
		e.global_position = pos
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		Input.parse_input_event(e)
	else:
		var m := InputEventMouseMotion.new()
		m.position = pos
		m.global_position = pos
		Input.parse_input_event(m)
		if not pressed:
			var e := InputEventMouseButton.new()
			e.position = pos
			e.global_position = pos
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = false
			Input.parse_input_event(e)
