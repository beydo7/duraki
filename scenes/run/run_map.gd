extends Control
## Übersicht über den Run: Gegnerfolge, Leben, Gold, Relikte.


func _ready() -> void:
	if Run.encounters.is_empty():
		# Szene direkt mit F6 gestartet → einfach einen neuen Run beginnen.
		Run.start_new_run()
		return
	%FightButton.pressed.connect(func() -> void: Run.goto(Run.SCENE_MATCH))
	%AbandonButton.pressed.connect(func() -> void: Run.goto(Run.SCENE_MENU))
	_render()
	%FightButton.grab_focus()


func _render() -> void:
	%StatsLabel.text = "Leben: %d   ·   Gold: %d   ·   Handgröße: %d" % [
		Run.lives, Run.gold, Run.player_hand_size()]

	for c in %EncounterList.get_children():
		c.queue_free()
	for i in Run.encounters.size():
		var o := Run.encounters[i]
		var label := Label.new()
		var marker := "✓" if i < Run.floor_index else ("►" if i == Run.floor_index else "·")
		label.text = "%s  %s%s" % [marker, o.display_name, "  (Boss)" if o.is_boss else ""]
		if i < Run.floor_index:
			label.modulate = Color(1, 1, 1, 0.5)
		%EncounterList.add_child(label)

	if Run.relics.is_empty():
		%RelicLabel.text = "Noch keine Relikte."
	else:
		var names := PackedStringArray()
		for r in Run.relics:
			names.append(r.display_name)
		%RelicLabel.text = "Relikte: " + ", ".join(names)

	var next := Run.current_opponent()
	%FightButton.text = "Kämpfen gegen %s" % next.display_name if next else "Kämpfen"
