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
		var world: TableWorld = scene.world
		if Time.get_ticks_msec() / 1000.0 < world.busy_until():
			continue # es wird noch ausgeteilt
		# Die Karten im Fächer überlappen: zielen, warten, bis die Maus-Abfrage (Physik) gelaufen ist,
		# und nur klicken, wenn die Karte unter der Maus spielbar ist.
		var target: Card = null
		var screen := Vector2.ZERO
		var shrink: float = scene.get_node("%View").stretch_shrink
		for c: Card in options:
			var node: Card3D = world._cards[c]
			# über die Karte wandern, bis sie selbst (nicht die Nachbarkarte) unter der Maus liegt
			for fx: float in [0.35, 0.2, 0.0, -0.2, -0.35]:
				screen = world.camera.unproject_position(node.global_transform * Vector3(Card3D.WIDTH * fx, 0, -Card3D.HEIGHT * 0.3)) * shrink
				_mouse(screen, false)
				for k in 3:
					await get_tree().physics_frame
				if node.hovered:
					target = c
					break
			if target != null:
				break
		if target == null:
			print("Versuch %d: keine spielbare Karte unter der Maus" % attempt)
			continue
		var before := duel.hand(DurakMatch.PLAYER).size()
		# sehr schneller Klick: Drücken und Loslassen im selben Bild (wie Tippen aufs Touchpad)
		_mouse(screen, true)
		_mouse(screen, true, false)
		await get_tree().create_timer(0.3).timeout
		var after := duel.hand(DurakMatch.PLAYER).size()
		# Passt die Karte auf mehrere Angriffskarten (oder geht Schieben), fragt das Spiel erst nach:
		# dann ist der Klick auch angekommen.
		var asked: bool = scene.hud._choice != null and is_instance_valid(scene.hud._choice)
		print("Klick auf %s bei %s: Handkarten %d -> %d%s" % [target, screen, before, after, " (Auswahl offen)" if asked else ""])
		ok = after < before or asked
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
