class_name IndexMenu
extends Control
## Index (Hauptmenü): alles, was es im Spiel gibt – sofort sichtbar, auch wenn man es noch
## nie gesehen hat. Gedacht zum Kontrollieren und Testen beim Entwickeln.
##   KARTEN   alle 36 Karten, umschaltbar Normal / Gold / Glas / Glück (mit Effekt und Preis)
##   RELIKTE  alle Relikte aus data/relics/ mit Effekt
##   ITEMS    Feuerzeug, Spiegel …
##   ERFOLGE  erreichte und offene Erfolge; geheime zeigen ihre Aufgabe erst, wenn erreicht
##   STATISTIK  Zahlen über alle Runs, Gegner (Lieblings- und Angstgegner), Tägliche Herausforderung
##     var menu := IndexMenu.new(); add_child(menu); menu.closed.connect(...)

signal closed

const TABS := ["KARTEN", "RELIKTE", "ITEMS", "ERFOLGE", "AUSSEHEN", "STATISTIK"] # Boni stehen bei den Decks
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
	sub.clip_text = true # bei vielen Reitern lieber abschneiden als überlaufen
	sub.custom_minimum_size.x = 20
	row.add_child(sub)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(104, 44)
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
		3: _content.add_child(_achievements_tab())
		4: _content.add_child(_looks_tab())
		5: _content.add_child(_stats_tab())
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
		entries.append([r.visual(), colors[i % colors.size()], UIKit.P_GOLD,
			r.display_name, r.description, _relic_details(r)])
	return _medal_grid(entries, "Relikte gibt es beim Händler (7–10 G). Sie wirken den ganzen Run.")


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
		var is_emoji: bool = e[0] is Texture2D or String(e[0]).unicode_at(0) >= 0x1F000
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


# --- ERFOLGE ------------------------------------------------------------------------------

func _achievements_tab() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	var done := Profile.achievements.size()
	var total := Profile.ACHIEVEMENTS.size()
	box.add_child(UIKit.poster_label("%d von %d erreicht. Geheime Erfolge verraten ihre Aufgabe erst, wenn du sie geschafft hast." % [done, total],
		UIKit.body_font(500), 15, Color(UIKit.P_CREAM, 0.7)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	for id: StringName in Profile.ACHIEVEMENTS:
		var a: Array = Profile.ACHIEVEMENTS[id]
		var got := Profile.has_achievement(id)
		var secret: bool = a[3] and not got
		var cell := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color(1, 1, 1, 0.05) if got else Color(0, 0, 0, 0.25)
		st.border_color = UIKit.P_GOLD if got else Color(UIKit.P_CREAM, 0.15)
		st.set_border_width_all(2)
		st.border_width_left = 6
		st.set_content_margin_all(12)
		cell.add_theme_stylebox_override("panel", st)
		cell.custom_minimum_size = Vector2(360, 108)
		cell.mouse_entered.connect(func() -> void: Sfx.play(&"index_hover", randf_range(0.9, 1.0)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		cell.add_child(row)
		var icon := UIKit.relic_icon("❓" if secret else a[0], 60, 38)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.modulate = Color.WHITE if got else Color(0.55, 0.52, 0.5, 0.85)
		row.add_child(icon)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 1)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		col.add_child(UIKit.poster_label(a[1], UIKit.display_font(), 19, UIKit.P_CREAM if got else Color(UIKit.P_CREAM, 0.75)))
		# geheim: Aufgabe zensiert (Balken statt Text)
		var task := UIKit.poster_label("████ ███ ██████ ?" if secret else String(a[2]), UIKit.body_font(500), 14,
			Color(UIKit.P_CREAM, 0.35 if secret else 0.78))
		task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		task.custom_minimum_size.x = 250
		col.add_child(task)
		col.add_child(UIKit.poster_label("✓ ERREICHT" if got else "Belohnung: noch offen",
			UIKit.body_font(600, 1), 13, UIKit.P_GOLD if got else Color(UIKit.P_CREAM, 0.45)))
		grid.add_child(cell)
	return box


# --- AUSSEHEN (Deck-Belohnungen) ---------------------------------------------------------

func _looks_tab() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var got := 0
	for id: StringName in Cosmetics.ITEMS:
		if Cosmetics.is_unlocked(id):
			got += 1
	box.add_child(UIKit.poster_label("%d von %d freigeschaltet. Jedes Deck hat drei Belohnungen: gewinne einen Run auf Leicht, Normal und Schwer. Anklicken = anlegen." % [got, Cosmetics.ITEMS.size()],
		UIKit.body_font(500), 15, Color(UIKit.P_CREAM, 0.7)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for slot: StringName in Cosmetics.SLOTS:
		list.add_child(_stat_head(String(Cosmetics.SLOTS[slot][0])))
		var flow := GridContainer.new() # feste Spalten: alle Kacheln gleich breit und bündig
		flow.columns = 4
		flow.add_theme_constant_override("h_separation", 12)
		flow.add_theme_constant_override("v_separation", 12)
		list.add_child(flow)
		flow.add_child(_look_tile(slot, &""))
		for id in Cosmetics.items_for(slot):
			flow.add_child(_look_tile(slot, id))
	return box


func _look_tile(slot: StringName, id: StringName) -> Control:
	var it: Dictionary = {} if id == &"" else Cosmetics.ITEMS[id]
	var open := id == &"" or Cosmetics.is_unlocked(id)
	var on := Cosmetics.selected(slot) == id
	var cell := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1, 1, 1, 0.07) if on else (Color(1, 1, 1, 0.03) if open else Color(0, 0, 0, 0.3))
	st.border_color = UIKit.P_GOLD if on else Color(UIKit.P_CREAM, 0.15 if open else 0.07)
	st.set_border_width_all(2)
	st.border_width_left = 6
	st.set_content_margin_all(10)
	cell.add_theme_stylebox_override("panel", st)
	cell.custom_minimum_size = Vector2(250, 84)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.tooltip_text = "Standard des Raums" if id == &"" else Cosmetics.how_to(id)
	cell.mouse_entered.connect(func() -> void: Sfx.play(&"index_hover", randf_range(0.9, 1.0)))
	if open:
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		cell.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				Sfx.play(&"card_select")
				Profile.select_cosmetic(slot, id)
				_show_tab(TABS.find("AUSSEHEN")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(row)
	var pic := _look_swatch(it)
	pic.modulate = Color.WHITE if open else Color(0.35, 0.33, 0.33)
	row.add_child(pic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var name := "Standard" if id == &"" else String(it.name)
	var title := UIKit.poster_label(name, UIKit.display_font(), 17, UIKit.P_CREAM if open else Color(UIKit.P_CREAM, 0.5))
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS # lange Namen sprengen die Kachel nicht
	title.custom_minimum_size.x = 10
	col.add_child(title)
	var sub := ""
	if id == &"":
		sub = "wie der Raum es vorsieht"
	else:
		var d := Profile.deck(it.deck)
		sub = "%s · %s" % [d.display_name if d != null else String(it.deck), Settings.DIFFICULTY_NAMES[it.level]]
	var subl := UIKit.poster_label(sub, UIKit.body_font(500), 13, Color(UIKit.P_CREAM, 0.6))
	col.add_child(subl)
	var state := "✓ ANGELEGT" if on else ("" if open else "🔒 Run auf %s gewinnen" % Settings.DIFFICULTY_NAMES[it.level])
	if state != "":
		col.add_child(UIKit.poster_label(state, UIKit.body_font(600, 1), 12, UIKit.P_GOLD if on else Color(UIKit.P_CREAM, 0.45)))
	return cell


## Vorschau: Textur (Filz, Rand), Farbe (Zigaretten, Münzen) oder Symbol (Ecken, Extras).
func _look_swatch(it: Dictionary) -> Control:
	var size := Vector2(58, 58)
	if it.is_empty():
		var r := UIKit.relic_icon("➖", 58, 30)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	if it.has("emoji"):
		var r := UIKit.relic_icon(it.emoji, 58, 36)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	var frame := Panel.new()
	frame.custom_minimum_size = size
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = it.get("color", it.get("pack", Color.GRAY))
	sb.border_color = Color(0, 0, 0, 0.6)
	sb.set_border_width_all(2)
	if it.slot == &"coins":
		sb.set_corner_radius_all(29)
		sb.border_color = (it.color as Color).darkened(0.4)
		sb.set_border_width_all(5)
	frame.add_theme_stylebox_override("panel", sb)
	if it.has("tex"):
		var tr := TextureRect.new()
		tr.texture = load(Cosmetics.DIR + it.tex)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = 2
		tr.offset_top = 2
		tr.offset_right = -2
		tr.offset_bottom = -2
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(tr)
	if it.slot == &"cigs": # kleine Zigarette quer über der Packungsfarbe
		var stick := ColorRect.new()
		stick.color = it.paper
		stick.position = Vector2(8, 25)
		stick.size = Vector2(32, 8)
		stick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(stick)
		var filt := ColorRect.new()
		filt.color = Color(0.82, 0.55, 0.28)
		filt.position = Vector2(40, 25)
		filt.size = Vector2(11, 8)
		filt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(filt)
	return frame


# --- STATISTIK ----------------------------------------------------------------------------

func _stats_tab() -> Control:
	var st := Profile.stats
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 34)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols)

	# links: Zahlen-Kacheln
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	cols.add_child(left)
	left.add_child(_stat_head("ALLGEMEIN"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	left.add_child(grid)
	var played := Profile.runs_played
	var won := int(st.get("duels_won", 0))
	var lost := int(st.get("duels_lost", 0))
	var tiles := [
		["%d" % played, "Runs gespielt"],
		["%d" % Profile.runs_won, "Runs gewonnen" + (" (%d %%)" % roundi(100.0 * Profile.runs_won / played) if played > 0 else "")],
		["%d" % int(st.get("best_act", 0)), "Akte geschafft (bester Run, von %d)" % Run.ACTS],
		["%d" % won, "Duelle gewonnen"],
		["%d" % lost, "Duelle verloren"],
		["%d" % int(st.get("bosses", 0)), "Bosse besiegt"],
		[_num(int(st.get("points", 0))), "Punkte insgesamt"],
		[_num(int(st.get("best_bout", 0))), "Beste Runde"],
		[_num(int(st.get("best_run_points", 0))), "Bester Run (Punkte)"],
		[_num(Profile.endless_best()), "Endlos-Rekord"],
		["%d" % int(st.get("transfers", 0)), "Mal geschoben"],
		["%d" % int(st.get("items_used", 0)), "Items eingesetzt"],
		[_num(int(st.get("gold_won", 0))), "Gold gewonnen"],
		["%d" % Profile.cigarettes_smoked, "Zigaretten geraucht"],
		[_time(float(st.get("play_seconds", 0.0))), "Spielzeit"],
		["%d / %d" % [Profile.achievements.size(), Profile.ACHIEVEMENTS.size()], "Erfolge"],
	]
	for t in tiles:
		grid.add_child(_stat_tile(t[0], t[1]))

	# rechts: Gegner und Tägliche Herausforderung
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(_stat_head("GEGNER"))
	var fav := Profile.top_opponent(true)
	var fear := Profile.top_opponent(false)
	right.add_child(_line("Lieblingsgegner", "%s (%d Siege)" % [_opp_name(fav[0]), fav[1]] if not fav.is_empty() else "–"))
	right.add_child(_line("Angstgegner", "%s (%d Niederlagen)" % [_opp_name(fear[0]), fear[1]] if not fear.is_empty() else "–"))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	right.add_child(list)
	var files := ResourceLoader.list_directory(Run.OPPONENT_DIR)
	files.sort()
	for f in files:
		if not f.ends_with(".tres"):
			continue
		var o := load(Run.OPPONENT_DIR + f) as OpponentData
		if o == null or o.portrait == null:
			continue
		var oid := f.get_basename()
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var pic := TextureRect.new()
		pic.texture = o.portrait
		pic.custom_minimum_size = Vector2(34, 34)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(pic)
		var n := UIKit.poster_label(o.display_name, UIKit.body_font(600), 16, UIKit.P_CREAM)
		n.custom_minimum_size.x = 190
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(n)
		var w := int(Profile.wins_vs.get(oid, 0))
		var l := int(Profile.losses_vs.get(oid, 0))
		var wl := UIKit.poster_label("%d : %d" % [w, l], UIKit.body_font(600), 16,
			UIKit.P_GOLD if w > l else (Color(1, 0.55, 0.5) if l > w else Color(UIKit.P_CREAM, 0.6)))
		wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		wl.tooltip_text = "Siege : Niederlagen"
		wl.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(wl)
		list.add_child(row)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	right.add_child(gap)
	right.add_child(_stat_head("TÄGLICHE HERAUSFORDERUNG"))
	var played_days := 0
	for d in Profile.daily_results:
		if bool(Profile.daily_results[d].get("done", false)):
			played_days += 1
	right.add_child(_line("Tage gespielt", "%d" % played_days))
	right.add_child(_line("Serie", "%d in Folge" % Profile.daily_streak()))
	right.add_child(_line("Bester Tag", "%s Punkte" % _num(Profile.daily_best())))
	var today := Profile.daily_entry()
	var used := (today.get("tries", []) as Array).size()
	right.add_child(_line("Heute", ("%s Punkte · %d/%d Versuche" % [_num(int(today.get("points", 0))), used, Profile.DAILY_TRIES])
		if used > 0 else "noch offen · %d Versuche" % Profile.DAILY_TRIES))
	return scroll


func _stat_head(text: String) -> Control:
	return UIKit.poster_label(text, UIKit.display_font(1), 20, Color(1, 0.8, 0.76))


func _stat_tile(value: String, label: String) -> Control:
	var cell := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.25)
	sb.border_color = Color(UIKit.P_CREAM, 0.15)
	sb.border_width_left = 5
	sb.border_color = UIKit.P_RED
	sb.set_content_margin_all(10)
	cell.add_theme_stylebox_override("panel", sb)
	cell.custom_minimum_size = Vector2(176, 78)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	cell.add_child(col)
	col.add_child(UIKit.poster_label(value, UIKit.display_font(1), 26, UIKit.P_CREAM))
	var l := UIKit.poster_label(label, UIKit.body_font(500), 13, Color(UIKit.P_CREAM, 0.65))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(l)
	return cell


func _line(label: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := UIKit.poster_label(label, UIKit.body_font(500), 16, Color(UIKit.P_CREAM, 0.65))
	l.custom_minimum_size.x = 160
	row.add_child(l)
	row.add_child(UIKit.poster_label(value, UIKit.body_font(600), 16, UIKit.P_CREAM))
	return row


func _opp_name(oid: String) -> String:
	var o := load(Run.OPPONENT_DIR + oid + ".tres") as OpponentData
	return o.display_name if o != null else oid


## 12345 → „12.345“
static func _num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func _time(sec: float) -> String:
	var m := int(sec) / 60
	return "%d h %02d min" % [m / 60, m % 60] if m >= 60 else "%d min" % m
