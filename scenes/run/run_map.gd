extends Control
## Übersicht über den Run: Gegnerfolge als Karten, Leben, Gold, Relikte.


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
	%StatsLabel.text = "LEBEN %s   ·   GOLD %d   ·   HAND %d" % [
		"♥".repeat(Run.lives) if Run.lives > 0 else "–", Run.gold, Run.player_hand_size()]

	for c in %EncounterList.get_children():
		c.queue_free()
	for i in Run.encounters.size():
		%EncounterList.add_child(_encounter_card(i))

	if Run.relics.is_empty():
		%RelicLabel.text = "Noch keine Relikte."
	else:
		var names := PackedStringArray()
		for r in Run.relics:
			names.append(r.display_name)
		%RelicLabel.text = "Relikte: " + "  ·  ".join(names)

	var next := Run.current_opponent()
	%FightButton.text = ("AN DEN TISCH: %s" % next.display_name).to_upper() if next else "AN DEN TISCH"


func _encounter_card(i: int) -> Control:
	var o := Run.encounters[i]
	var done := i < Run.floor_index
	var current := i == Run.floor_index
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(160, 190)
	if current:
		panel.theme_type_variation = &"ActivePanel"
	if done:
		panel.modulate = Color(1, 1, 1, 0.45)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var step := Label.new()
	step.theme_type_variation = &"HeaderLabel"
	step.text = "BOSS" if o.is_boss else "TISCH %d" % (i + 1)
	step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if o.is_boss:
		step.add_theme_color_override("font_color", Color(1, 0.45, 0.4))
	box.add_child(step)

	# Porträt des Gegners (oder kleine Maske als Ersatz)
	if o.portrait != null:
		var pic := TextureRect.new()
		pic.texture = o.portrait
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(0, 72)
		if done:
			pic.modulate = Color(0.55, 0.55, 0.6)
		box.add_child(pic)
	else:
		var mask := _MaskDot.new()
		mask.mask_color = o.mask_color
		mask.eye_color = o.eye_color
		mask.custom_minimum_size = Vector2(0, 54)
		box.add_child(mask)

	var name_l := Label.new()
	name_l.text = o.display_name
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size = Vector2(130, 0)
	box.add_child(name_l)

	var target := Label.new()
	target.theme_type_variation = &"BrushLabel"
	target.add_theme_font_size_override("font_size", 22)
	target.text = "✓ besiegt" if done else "%d Pkt." % Run.score_target(i)
	target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(target)
	return panel


## Kleines Maskengesicht als Gegner-Symbol.
class _MaskDot extends Control:
	var mask_color := Color.WHITE
	var eye_color := Color.RED

	func _draw() -> void:
		var c := size * 0.5
		var r := Vector2(19, 24)
		var pts := PackedVector2Array()
		for k in 32:
			var a := TAU * k / 32.0
			pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
		draw_colored_polygon(pts, mask_color)
		for side in [-1.0, 1.0]:
			var e := c + Vector2(side * 7.5, -4)
			draw_circle(e, 5.0, Color(0.05, 0.03, 0.08))
			draw_circle(e + Vector2(0, 1), 1.6, eye_color)
		draw_line(c + Vector2(-7, 11), c + Vector2(7, 11), Color(0.05, 0.03, 0.08), 1.5)
