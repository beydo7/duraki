class_name IndexMenu
extends Control
## Index (Hauptmenü): alles, was es im Spiel gibt – sofort sichtbar, auch wenn man es noch
## nie gesehen hat. Gedacht zum Kontrollieren und Testen beim Entwickeln.
##   KARTEN   alle 36 Karten, umschaltbar Normal / Gold / Glas / Glück (mit Effekt und Preis)
##   RELIKTE  alle Relikte aus data/relics/ mit Effekt
##   ITEMS    Feuerzeug, Spiegel …
##     var menu := IndexMenu.new(); add_child(menu); menu.closed.connect(...)

signal closed

const TABS := ["KARTEN", "RELIKTE", "ITEMS"] # Boni stehen bei den Decks
const CARD_SIZE := Vector2(80, 112)
const ENH_COLORS := [UIKit.P_CREAM, UIKit.P_GOLD, Color(0.55, 0.82, 1.0), Color(0.42, 0.85, 0.5)]
const ENH_LABELS := ["NORMAL", "GOLD", "GLAS", "GLÜCK"]
## Preise im Shop (siehe RunState._card_offer)
const ENH_PRICES := [0, 6, 5, 5]

var _tab_buttons: Array[Button] = []
var _content: Control
var _enh := 0
var _panel: Slab


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.012, 0.04, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = Slab.new()
	_panel.color = Color(0.07, 0.055, 0.055, 0.97)
	_panel.points = PackedVector2Array([Vector2(0, 0.01), Vector2(1, 0), Vector2(0.995, 1), Vector2(0.004, 0.993)])
	_panel.shadow_offset = Vector2(8, 10)
	_panel.margins = Vector4(0, 0, 0, 18)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.offset_left = 48
	_panel.offset_right = -48
	_panel.offset_top = 32
	_panel.offset_bottom = -32
	add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	_panel.add_child(root)

	# Kopf: roter Streifen mit Titel und Reitern
	var head := Slab.new()
	head.color = UIKit.P_RED
	head.points = PackedVector2Array([Vector2(0, 0.06), Vector2(1, 0), Vector2(0.995, 0.86), Vector2(0, 1)])
	head.extra = [PackedVector2Array([Vector2(0, 0.86), Vector2(0.995, 0.76), Vector2(0.995, 0.86), Vector2(0, 1)])]
	head.extra_colors = PackedColorArray([UIKit.P_RED_DARK])
	head.shadow_offset = Vector2.ZERO
	head.margins = Vector4(26, 8, 22, 14)
	root.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	head.add_child(row)
	var title := UIKit.poster_label("INDEX", UIKit.display_font(2), 34, UIKit.P_CREAM, 3)
	row.add_child(title)
	var sub := UIKit.poster_label("ALLES IM SPIEL · ZUM TESTEN", UIKit.body_font(600, 3), 12, Color(1, 0.8, 0.76))
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	sub.custom_minimum_size.y = 30
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sub)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(128, 44)
		var index := i
		b.pressed.connect(func() -> void: _show_tab(index)) # Klickton kommt von UIKit.hover
		UIKit.hover(b, 1.04)
		row.add_child(b)
		_tab_buttons.append(b)
	var back := Button.new()
	back.text = "ZURÜCK"
	back.theme_type_variation = &"PrimaryButton"
	back.custom_minimum_size = Vector2(130, 44)
	back.pressed.connect(close)
	UIKit.hover(back, 1.04)
	row.add_child(back)

	_content = MarginContainer.new()
	_content.add_theme_constant_override("margin_left", 26)
	_content.add_theme_constant_override("margin_right", 26)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_content)

	_show_tab(0)
	_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_panel, "modulate:a", 1.0, 0.25)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	closed.emit()
	queue_free()


func _show_tab(index: int) -> void:
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == index
	for c in _content.get_children():
		c.queue_free()
	match index:
		0: _content.add_child(_cards_tab())
		1: _content.add_child(_relics_tab())
		2: _content.add_child(_items_tab())
	_tab_buttons[index].grab_focus()


# --- KARTEN -------------------------------------------------------------------------------

func _cards_tab() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	box.add_child(bar)
	for e in ENH_LABELS.size():
		var b := Button.new()
		b.text = ENH_LABELS[e]
		b.toggle_mode = true
		b.button_pressed = e == _enh
		b.custom_minimum_size = Vector2(110, 38)
		b.add_theme_color_override("font_color", ENH_COLORS[e])
		b.add_theme_color_override("font_pressed_color", UIKit.P_BLACK if e != 0 else UIKit.P_RED)
		var en := e
		b.pressed.connect(func() -> void:
			Sfx.play(&"ui_click", 1.0 + en * 0.06)
			_enh = en
			_show_tab(0))
		bar.add_child(b)
	var info := "Normale Karten: Chips = Kartenwert (6–10, Bildkarten 10, Ass 11)."
	if _enh != 0:
		info = "%s – %s   Preis beim Händler: %d G" % [Card.ENHANCEMENT_NAMES[_enh], Card.ENHANCEMENT_TEXT[_enh], ENH_PRICES[_enh]]
	var info_l := UIKit.poster_label(info, UIKit.body_font(500), 16, ENH_COLORS[_enh])
	info_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(info_l)

	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 10)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(grid)
	box.add_child(center)
	for suit in 4:
		for rank in range(Card.MIN_RANK, Card.MAX_RANK + 1):
			var c := Card.new(suit, rank)
			c.enhancement = _enh
			grid.add_child(_card_pic(c))
	return box


func _card_pic(c: Card) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = CARD_SIZE
	holder.tooltip_text = "%s %s%s\nChips: %d" % [
		Card.ENHANCEMENT_NAMES[c.enhancement] if c.enhancement != 0 else "Karte",
		Card.RANK_NAMES[c.rank], Card.SUIT_SYMBOLS[c.suit], ScoreTracker.chip_value(c)]
	if c.enhancement == Card.Enhancement.GLASS:
		var felt := ColorRect.new() # Glas liegt auf dunklem Grund (wie im Spiel)
		felt.color = Color(0.1, 0.16, 0.14)
		felt.size = CARD_SIZE
		felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(felt)
	var pic := TextureRect.new()
	pic.texture = Card3D.face_texture(c)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size = CARD_SIZE
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pic)
	holder.mouse_entered.connect(func() -> void: _lift(holder, true))
	holder.mouse_exited.connect(func() -> void: _lift(holder, false))
	return holder


func _lift(node: Control, up: bool) -> void:
	if up:
		Sfx.play(&"index_hover", randf_range(0.96, 1.08))
	node.pivot_offset = node.size * 0.5
	node.z_index = 1 if up else 0
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector2.ONE * (1.6 if up else 1.0), 0.12).set_trans(Tween.TRANS_QUAD)


# --- RELIKTE / BONI -----------------------------------------------------------------------

func _relics_tab() -> Control:
	var entries := []
	var colors := MatchHUD.RELIC_COLORS
	var relics := Run.all_relics()
	for i in relics.size():
		var r: RelicData = relics[i]
		entries.append([r.icon(), colors[i % colors.size()], UIKit.P_GOLD,
			r.display_name, r.description, _relic_details(r)])
	return _medal_grid(entries, "Relikte gibt es beim Händler (7–10 G). Sie wirken den ganzen Run. Neue Relikte: data/relics/")


func _relic_details(r: RelicData) -> String:
	var parts := PackedStringArray()
	if r.hand_size_bonus != 0:
		parts.append("Handkarten %+d" % r.hand_size_bonus)
	if r.bonus_gold_per_win != 0:
		parts.append("Gold pro Sieg %+d" % r.bonus_gold_per_win)
	if r.extra_lives != 0:
		parts.append("Leben %+d" % r.extra_lives)
	if r.bonus_mult != 0:
		parts.append("Start-Mult %+d" % r.bonus_mult)
	return " · ".join(parts)


## Raster aus Medaillons: [Symbol, Farbe, Ringfarbe, Name, Text, Zusatz]
func _medal_grid(entries: Array, note: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	var n := UIKit.poster_label(note, UIKit.body_font(500), 15, Color(UIKit.P_CREAM, 0.7))
	box.add_child(n)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 18)
	box.add_child(grid)
	for e: Array in entries:
		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2(260, 96)
		cell.add_theme_constant_override("separation", 12)
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		cell.mouse_entered.connect(func() -> void: Sfx.play(&"index_hover", randf_range(0.9, 1.0)))
		var is_emoji := String(e[0]).unicode_at(0) >= 0x1F000
		if is_emoji:
			# Relikte und Items wie im Spiel: freies Emoji mit Schatten
			var icon := UIKit.relic_icon(e[0], 72, 46)
			icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(icon)
			# Maus drüber: Symbol wird größer (wie im Duell)
			cell.mouse_entered.connect(func() -> void:
				icon.create_tween().tween_property(icon, "scale", Vector2.ONE * 1.25, 0.12).set_trans(Tween.TRANS_BACK))
			cell.mouse_exited.connect(func() -> void:
				icon.create_tween().tween_property(icon, "scale", Vector2.ONE, 0.12))
		else:
			var medal := Roundel.new()
			medal.color = e[1]
			medal.ring_color = e[2]
			medal.custom_minimum_size = Vector2(72, 72)
			medal.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			var sym := UIKit.poster_label(e[0], UIKit.SYMBOL_FONT, 28, UIKit.P_CREAM)
			sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sym.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			sym.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			medal.add_child(sym)
			cell.add_child(medal)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(col)
		col.add_child(UIKit.poster_label(e[3], UIKit.display_font(), 18, UIKit.P_CREAM))
		var t := UIKit.poster_label(e[4], UIKit.body_font(500), 14, Color(UIKit.P_CREAM, 0.78))
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size.x = 170
		col.add_child(t)
		if e[5] != "":
			col.add_child(UIKit.poster_label(e[5], UIKit.body_font(600, 1), 13, UIKit.P_GOLD))
		grid.add_child(cell)
	return box


# --- ITEMS --------------------------------------------------------------------------------

func _items_tab() -> Control:
	var entries := []
	for id: StringName in Run.ITEMS:
		var it: Dictionary = Run.ITEMS[id]
		entries.append([it.emoji, Color.BLACK, Color.BLACK, it.name, it.text, "Preis: %d G · einmal einsetzbar" % it.price])
	return _medal_grid(entries, "Items kauft man beim Händler (höchstens %d gleichzeitig) und setzt sie im Duell oben rechts ein." % Run.ITEM_SLOTS)
