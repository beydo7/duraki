extends Control
## Ende des Runs: Sieg über den Boss oder die letzte Kerze ist aus.
## Im Hintergrund sitzt der letzte Gegner – zusammengesunken oder lachend.


func _ready() -> void:
	var last: OpponentData = null
	if not Run.encounters.is_empty():
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

	if Run.won_run:
		%Header.text = "DIE NACHT GEHÖRT DIR"
		%TitleLabel.text = "RUN GEWONNEN!"
		%TitleLabel.add_theme_color_override("font_color", UIKit.INK_BLUE)
	else:
		%Header.text = "DIE LETZTE KERZE IST AUS"
		%TitleLabel.text = "DU BIST DER DURAK."
	_stat("Gegner besiegt", "%d / %d" % [mini(Run.floor_index, Run.encounters.size()), Run.encounters.size()])
	_stat("Gold", "%d" % Run.gold)
	_stat("Relikte", "%d" % Run.relics.size() if Run.relics.size() > 0 else "keine")
	_stat("Deck", Run.deck_name())
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
