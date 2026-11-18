extends Control
## Belohnung nach einem Sieg: ein Relikt wählen oder Gold nehmen.
## Jede Wahl ist als Spielkarte dargestellt.


func _ready() -> void:
	%GoldLabel.text = "+%d Gold  ·  jetzt %d" % [Run.last_gold_reward, Run.gold]

	for relic in Run.get_reward_choices():
		_add_card("RELIKT", relic.display_name, relic.description, func() -> void:
			Run.add_relic(relic)
			Run.goto(Run.SCENE_MAP))

	_add_card("GOLD", "Säckchen Gold", "+%d Gold" % Run.GOLD_REWARD_OPTION, func() -> void:
		Run.add_gold(Run.GOLD_REWARD_OPTION)
		Run.goto(Run.SCENE_MAP))

	if %Choices.get_child_count() > 0:
		(%Choices.get_child(0) as Control).grab_focus()


func _add_card(kind: String, title: String, text: String, on_pick: Callable) -> void:
	var btn := Button.new()
	btn.theme_type_variation = &"CardButton"
	btn.custom_minimum_size = Vector2(190, 260)
	btn.pressed.connect(on_pick)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 10)
	btn.add_child(box)

	var kind_l := Label.new()
	kind_l.theme_type_variation = &"HeaderLabel"
	kind_l.add_theme_color_override("font_color", Color(0.45, 0.32, 0.8))
	kind_l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	kind_l.text = kind
	box.add_child(kind_l)

	var sym := Label.new()
	sym.text = "★" if kind == "RELIKT" else "◆"
	sym.add_theme_font_size_override("font_size", 46)
	sym.add_theme_color_override("font_color", Color(0.55, 0.22, 0.42))
	sym.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sym)

	var title_l := Label.new()
	title_l.theme_type_variation = &"CardTitle"
	title_l.text = title
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title_l)

	var text_l := Label.new()
	text_l.theme_type_variation = &"CardText"
	text_l.text = text
	text_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text_l)

	for c in box.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	%Choices.add_child(btn)
