extends Control
## Ende des Runs: Sieg über den Boss oder die letzte Kerze ist aus.
## Im Hintergrund sitzt der letzte Gegner – zusammengesunken oder lachend.


func _ready() -> void:
	var last: OpponentData = null
	if Run.endless and Run.endless_opponent != null:
		last = Run.endless_opponent
	elif not Run.encounters.is_empty():
		last = Run.encounters[clampi(Run.floor_index if not Run.won_run else Run.encounters.size() - 1,
			0, Run.encounters.size() - 1)]
	var bd := RoomBackdrop.new()
	bd.opponent = last
	bd.blur = 1.0
	bd.darken = 0.4
	bd.cam_from = Vector3(0.35, 1.3, 0.95)
	bd.cam_to = Vector3(0.3, 1.12, -0.4)
	add_child(bd)
	move_child(bd, 0)
	if bd.world != null and bd.world.figure != null:
		if Run.won_run:
			bd.world.figure.slump()
		else:
			bd.world.figure.laugh()

	if Run.endless:
		%Header.text = "ENDLOS-MODUS VORBEI"
		%TitleLabel.text = "%d PUNKTE" % Run.endless_score
		%AgainButton.theme_type_variation = &""
	elif Run.won_run:
		%TitleLabel.text = "RUN GEWONNEN!"
		%Header.text = "DIE NACHT GEHÖRT DIR"
		%AgainButton.theme_type_variation = &""
	else:
		%Header.text = "DIE LETZTE KERZE IST AUS"
		%TitleLabel.text = "DU BIST DER DURAK."
		%Panel.theme_type_variation = &""
		%Panel.add_theme_stylebox_override("panel", UIKit.paper(Vector4(30, 26, 30, 26), true))
		%TitleLabel.add_theme_color_override("font_color", UIKit.INK_RED)
	if Run.endless:
		_stat("Endlos-Punkte", "%d" % Run.endless_score)
		_stat("Decks geschafft", "%d" % Run.endless_decks)
		_stat("Bestenliste", "Platz %d" % Run.last_endless_place if Run.last_endless_place > 0 else "nicht unter den besten 10")
	else:
		_stat("Akt", "%d / %d" % [mini(Run.act_of() + 1, Run.ACTS), Run.ACTS])
	if Run.daily:
		_stat("Tägliche Herausforderung", ("%d Punkte" % Run.run_points) + ("" if Run.daily_counts else "  (Übung, zählt nicht)"))
	_stat("Gegner besiegt", "%d / %d" % [mini(Run.floor_index, Run.encounters.size()), Run.encounters.size()])
	_stat("Gold", "%d" % Run.gold)
	_stat("Relikte", "%d" % Run.relics.size() if Run.relics.size() > 0 else "keine")
	_stat("Deck", Run.deck_name())
	var mode: String = Settings.DIFFICULTY_NAMES[Run.difficulty] + ("" if Run.hints else " · ohne Hinweise")
	_stat("Schwierigkeit", "%s  (Seelen ×%s)" % [mode, RunSetupMenu.factor_text(Run.souls_factor())])
	_stat("Seelen erhalten", "+%d  (jetzt %d)" % [Run.last_souls, Profile.souls])
	%MenuButton.pressed.connect(func() -> void: Run.goto(Run.SCENE_MENU))
	%AgainButton.pressed.connect(func() -> void: Run.start_new_run())
	UIKit.hover(%MenuButton, 1.04)
	UIKit.hover(%AgainButton, 1.04)
	UIKit.appear(%Panel, 0.2, Vector2(-40, 0), 0.7)
	%MenuButton.grab_focus()
	UIKit.show_unlocks.call_deferred(self)


func _stat(name: String, value: String) -> void:
	var n := Label.new()
	n.theme_type_variation = &"InkType"
	n.text = name
	%Stats.add_child(n)
	var v := Label.new()
	v.theme_type_variation = &"InkTitle"
	v.add_theme_font_size_override("font_size", 22)
	v.text = value
	%Stats.add_child(v)
