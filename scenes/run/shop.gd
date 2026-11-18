extends Control
## Shop nach einem Sieg: Relikte, verbesserte Karten und Verbesserungen kaufen.


func _ready() -> void:
	if Run.encounters.is_empty():
		# Szene direkt mit F6 gestartet → Testdaten
		Run.start_new_run()
		Run.gold = 30
		Run.open_shop()
		return
	%ContinueButton.pressed.connect(func() -> void: Run.goto(Run.SCENE_MAP))
	%RerollButton.pressed.connect(func() -> void:
		if Run.reroll_shop():
			_render())
	_render()
	%ContinueButton.grab_focus()


func _render() -> void:
	%GoldLabel.text = "%d Gold" % Run.gold
	%EarnedLabel.text = "Sieg: +%d Gold   ·   Zinsen: +%d Gold" % [Run.last_gold_reward, Run.last_interest]
	%RerollButton.text = "NEU MISCHEN · %d G" % Run.reroll_price
	%RerollButton.disabled = Run.gold < Run.reroll_price

	for c in %Offers.get_children():
		c.queue_free()
	for offer in Run.shop_offers:
		%Offers.add_child(_offer_card(offer))

	var owned := PackedStringArray()
	for r in Run.relics:
		owned.append(r.display_name)
	for key in Run.card_enhancements:
		var parts: PackedStringArray = key.split(":")
		var enh: int = Run.card_enhancements[key]
		owned.append("%s %s%s" % [Card.ENHANCEMENT_TAGS[enh].capitalize(),
			Card.RANK_NAMES[int(parts[1])], Card.SUIT_SYMBOLS[int(parts[0])]])
	for suit in Run.suit_chip_bonus:
		owned.append("%s +%d Chips" % [Card.SUIT_SYMBOLS[suit], Run.suit_chip_bonus[suit]])
	if Run.trump_mult_bonus > 0:
		owned.append("Trumpf +%d Mult" % Run.trump_mult_bonus)
	if Run.interest_max_bonus > 0:
		owned.append("Zinsen +%d" % Run.interest_max_bonus)
	%OwnedLabel.text = "Dein Besitz: " + ("  ·  ".join(owned) if not owned.is_empty() else "noch nichts")


func _offer_card(offer: Dictionary) -> Control:
	var btn := Button.new()
	btn.theme_type_variation = &"CardButton"
	btn.custom_minimum_size = Vector2(160, 250)
	var sold: bool = offer.sold
	var affordable: bool = Run.gold >= offer.price
	btn.disabled = sold or not affordable
	if sold:
		btn.modulate = Color(1, 1, 1, 0.35)
	elif not affordable:
		btn.modulate = Color(0.75, 0.72, 0.8, 0.85)
	btn.pressed.connect(func() -> void:
		if Run.buy(offer):
			_render())

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	box.add_theme_constant_override("separation", 6)
	btn.add_child(box)

	var kind_l := _label(offer.kind, &"HeaderLabel", 12)
	kind_l.add_theme_color_override("font_color", Color(0.45, 0.32, 0.8))
	box.add_child(kind_l)

	var sym := _label(offer.symbol, &"", 40 if offer.symbol.length() <= 1 else 32)
	sym.add_theme_color_override("font_color", offer.color)
	sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sym)

	var title_l := _label(offer.title, &"CardTitle", 20)
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_l)

	var text_l := _label(offer.text, &"CardText", 14)
	text_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text_l)

	var price := _label("VERKAUFT" if sold else "%d G" % offer.price, &"CardTitle", 22)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.add_theme_color_override("font_color",
		Color(0.45, 0.32, 0.8) if sold else (Color(0.62, 0.42, 0.05) if affordable else Color(0.6, 0.2, 0.2)))
	box.add_child(price)
	return btn


func _label(text: String, variation: StringName, size: int) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
