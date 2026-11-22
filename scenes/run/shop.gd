extends Control
## Der Händler nach einem Sieg: Relikte, verbesserte Karten und Verbesserungen kaufen.
## Angebote liegen als Karten aus (schweben leicht, heben sich beim Hover).

var _gold_shown := -1


func _ready() -> void:
	if Run.encounters.is_empty():
		# Szene direkt mit F6 gestartet → Testdaten
		Run.start_new_run()
		Run.gold = 30
		Run.open_shop()
		return
	var bd := RoomBackdrop.new()
	bd.blur = 2.6
	bd.darken = 0.55
	bd.cam_from = Vector3(0.7, 1.4, 0.75)
	bd.cam_to = Vector3(-0.2, 0.85, -0.2)
	add_child(bd)
	move_child(bd, 0)

	%ContinueButton.pressed.connect(func() -> void: Run.goto(Run.SCENE_MAP))
	%RerollButton.pressed.connect(func() -> void:
		if Run.reroll_shop():
			_render(true))
	UIKit.hover(%ContinueButton, 1.04)
	UIKit.hover(%RerollButton, 1.04)
	_render(true)
	UIKit.appear(%Head, 0.05, Vector2(-30, 0), 0.6)
	UIKit.appear(%GoldBox, 0.15, Vector2(30, 0), 0.6)
	%ContinueButton.grab_focus()


func _render(deal := false) -> void:
	if _gold_shown >= 0 and Run.gold != _gold_shown:
		UIKit.count(%GoldLabel, _gold_shown, Run.gold, 0.5)
		UIKit.pop(%GoldBox, 1.08)
	else:
		%GoldLabel.text = str(Run.gold)
	_gold_shown = Run.gold
	%EarnedLabel.text = "Sieg: +%d Gold   ·   Zinsen: +%d Gold" % [Run.last_gold_reward, Run.last_interest]
	%RerollButton.text = "NEU MISCHEN · %d G" % Run.reroll_price
	%RerollButton.disabled = Run.gold < Run.reroll_price

	for c in %Offers.get_children():
		c.queue_free()
	for i in Run.shop_offers.size():
		var card := _offer_card(Run.shop_offers[i])
		%Offers.add_child(card)
		if deal:
			UIKit.appear(card, 0.15 + i * 0.07, Vector2(0, 40), 0.45)

	for c in %Owned.get_children():
		c.queue_free()
	var cap := UIKit.label("DEIN BESITZ", 11, UIKit.MUTED, &"HeaderLabel")
	cap.custom_minimum_size = Vector2(0, 30)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	%Owned.add_child(cap)
	var owned := _owned_items()
	if owned.is_empty():
		%Owned.add_child(UIKit.label("noch nichts", 14, Color(UIKit.MUTED, 0.6)))
	for item: Array in owned:
		%Owned.add_child(_chip(item[0], item[1]))


func _owned_items() -> Array:
	var items := []
	for r in Run.relics:
		items.append(["%s %s" % [MatchHUD.RELIC_SYMBOLS.get(r.id, "★"), r.display_name], r.description])
	for key in Run.card_enhancements:
		var parts: PackedStringArray = key.split(":")
		var enh: int = Run.card_enhancements[key]
		items.append(["%s %s%s" % [Card.ENHANCEMENT_TAGS[enh].capitalize(), Card.RANK_NAMES[int(parts[1])],
			Card.SUIT_SYMBOLS[int(parts[0])]], Card.ENHANCEMENT_TEXT[enh]])
	for suit in Run.suit_chip_bonus:
		items.append(["%s +%d Chips" % [Card.SUIT_SYMBOLS[suit], Run.suit_chip_bonus[suit]], "Farb-Schliff"])
	if Run.trump_mult_bonus > 0:
		items.append(["Trumpf +%d Mult" % Run.trump_mult_bonus, "Trumpf-Kenner"])
	if Run.interest_max_bonus > 0:
		items.append(["Zinsen +%d" % Run.interest_max_bonus, "Sparschwein"])
	return items


func _offer_card(offer: Dictionary) -> Control:
	# Halter, damit Schweben/Hover die Reihe nicht verschieben
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(168, 260)
	var btn := Button.new()
	btn.theme_type_variation = &"CardButton"
	btn.size = Vector2(168, 252)
	btn.focus_mode = Control.FOCUS_ALL
	holder.add_child(btn)
	var sold: bool = offer.sold
	var affordable: bool = Run.gold >= offer.price
	btn.disabled = sold or not affordable
	if sold:
		btn.modulate = Color(1, 1, 1, 0.4)
	elif not affordable:
		btn.modulate = Color(0.72, 0.7, 0.78, 0.9)
	btn.tooltip_text = "Zu wenig Gold" if not affordable and not sold else ""
	btn.pressed.connect(func() -> void:
		if Run.buy(offer):
			_render())
	if not btn.disabled:
		UIKit.hover(btn, 1.06)
	UIKit.float_idle(btn, 3.0, 3.0 + randf(), randf() * 1.5)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)

	var kind_l := _label(offer.kind, &"HeaderLabel", 11)
	kind_l.add_theme_color_override("font_color", Color(0.42, 0.3, 0.78))
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
	var price := _label("%d G" % offer.price, &"CardTitle", 24)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.add_theme_color_override("font_color", Color(0.62, 0.42, 0.05) if affordable else Color(0.65, 0.2, 0.22))
	box.add_child(price)
	if sold:
		var stamp := _label("VERKAUFT", &"BrushLabel", 30)
		stamp.add_theme_color_override("font_color", Color(0.75, 0.15, 0.2))
		stamp.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		stamp.rotation = -0.35
		stamp.position = Vector2(14, 110)
		btn.add_child(stamp)
	return holder


func _chip(text: String, tip: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.glass(14, Vector4(12, 5, 12, 5), 0.82))
	p.tooltip_text = tip
	p.add_child(UIKit.label(text, 14, UIKit.CREAM))
	return p


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
