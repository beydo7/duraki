extends Control
## Der Händler nach einem Sieg. Im Hintergrund weichgezeichnet sein Tisch mit Kerzen und Gold;
## davor drei Stände als Plakatflächen:
##   KARTEN   – verbesserte Spielkarten (echtes Kartenbild)
##   RELIKTE  – Relikte und dauerhafte Boni als Medaillons
##   ITEMS    – Feuerzeug und Spiegel (einmal im Duell einsetzbar, höchstens 2 Plätze)

const CARD_SIZE := Vector2(108, 151)
const STALL_GAP := 20
const RELIC_W := 132.0
const CARD_W := 164.0

const ENH_COLORS := [Color.WHITE, UIKit.P_GOLD, Color(0.55, 0.82, 1.0), Color(0.42, 0.85, 0.5)]

var _gold_shown := -1
## Alle Waren der Auslage: {offer, btn, price}; wird beim Kauf direkt aktualisiert
var _wares: Array[Dictionary] = []


func _ready() -> void:
	UIKit.poster_wedge(self, Vector2(590, 178), %Head)
	if Run.encounters.is_empty():
		# Szene direkt mit F6 gestartet → Testdaten
		Run.start_new_run()
		Run.gold = 30
		Run.open_shop()
		return
	var bd := RoomBackdrop.new()
	bd.blur = 2.3
	bd.darken = 0.26
	bd.merchant = true
	# knapp über dem Händlertisch: Kerzenschein und Goldstapel unten, dahinter das Regal
	bd.cam_from = Vector3(-0.08, 0.92, 0.5)
	bd.cam_to = Vector3(0.1, 1.0, -0.35)
	add_child(bd)
	move_child(bd, 0)

	%ContinueButton.pressed.connect(func() -> void:
		if Run.tutorial_shop:
			Run.tutorial_shop = false
			Run.goto(Run.SCENE_MENU) # Tutorial zu Ende
		else:
			Run.goto(Run.SCENE_MAP))
	%RerollButton.pressed.connect(func() -> void:
		if Run.reroll_shop():
			_render(true))
	UIKit.hover(%ContinueButton, 1.04)
	UIKit.hover(%RerollButton, 1.04)
	_render(true)
	%ContinueButton.grab_focus()
	UIKit.show_unlocks.call_deferred(self)
	if Run.tutorial_shop:
		%ContinueButton.text = "TUTORIAL BEENDEN"
		_start_tutorial()


## Komplette Auslage neu aufbauen (Start und Neu-Mischen).
func _render(deal := false) -> void:
	_update_header()
	_wares.clear()
	for c in %Stalls.get_children():
		c.queue_free()
	var cards: Array[Dictionary] = []
	var relics: Array[Dictionary] = []
	var items: Array[Dictionary] = []
	for o in Run.shop_offers:
		if o.kind == "KARTE":
			cards.append(o)
		elif o.kind == "ITEM":
			items.append(o)
		else:
			relics.append(o)

	var card_row := _stall("KARTEN", "für dein Deck", cards.size() * (CARD_W + 14) + 22, deal, 0)
	for i in cards.size():
		card_row.add_child(_card_offer(cards[i], deal, 0.25 + i * 0.07))
	var relic_row := _stall("RELIKTE", "dauerhafte Vorteile", relics.size() * (RELIC_W + 14) + 26, deal, 1)
	for i in relics.size():
		relic_row.add_child(_relic_offer(relics[i], deal, 0.35 + i * 0.06))
	var item_row := _stall("ITEMS", "einmal im Duell einsetzbar",
		maxi(items.size(), 1) * (RELIC_W + 14) + 26, deal, 2)
	for i in items.size():
		item_row.add_child(_relic_offer(items[i], deal, 0.45 + i * 0.06))
	_render_owned()


## Gold, Zinsen und Neu-Mischen-Knopf aktualisieren.
func _update_header() -> void:
	if _gold_shown >= 0 and Run.gold != _gold_shown:
		UIKit.count(%GoldLabel, _gold_shown, Run.gold, 0.5)
		UIKit.pop(%GoldBox, 1.08)
	else:
		%GoldLabel.text = str(Run.gold)
	_gold_shown = Run.gold
	%EarnedLabel.text = "Sieg: +%d Gold   ·   Zinsen: +%d Gold" % [Run.last_gold_reward, Run.last_interest]
	%RerollButton.text = "NEU MISCHEN · %d G" % Run.reroll_price
	%RerollButton.disabled = Run.gold < Run.reroll_price


## Nach einem Kauf: nichts neu aufbauen, nur Zustände, Preise und Besitz anpassen.
func _bought(btn: Button) -> void:
	_update_header()
	for w in _wares:
		_apply_state(w)
	Sfx.play(&"coins")
	_render_owned()


func _render_owned() -> void:
	for c in %Owned.get_children():
		c.queue_free()
	var cap := UIKit.label("DEIN BESITZ", 10, UIKit.MUTED, &"HeaderLabel")
	cap.custom_minimum_size = Vector2(0, 26)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	%Owned.add_child(cap)
	# Relikte und Items nur als kleine Symbole (Name beim Drüberfahren), damit nichts verdeckt wird
	for r in Run.relics:
		%Owned.add_child(_mini_icon(r.visual(), "%s – %s" % [r.display_name, r.description]))
	for id in Run.items:
		%Owned.add_child(_mini_icon(Run.ITEMS[id].emoji, "%s – %s" % [Run.ITEMS[id].name, Run.ITEMS[id].text]))
	var owned := _owned_items()
	if owned.is_empty() and Run.relics.is_empty() and Run.items.is_empty():
		%Owned.add_child(UIKit.label("noch nichts", 12, Color(UIKit.MUTED, 0.7), &"TypeLabel"))
	for item: Array in owned:
		%Owned.add_child(_chip(item[0], item[1]))


func _mini_icon(icon: Variant, tip: String) -> Control:
	var c := UIKit.relic_icon(icon, 26, 18)
	c.tooltip_text = tip
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c


# --- Stände -----------------------------------------------------------------------------

## Ein Stand: dunkle Plakatfläche mit rotem Schild oben. Liefert die Reihe für die Waren.
func _stall(title: String, sub: String, width: float, _deal: bool, _index: int) -> HBoxContainer:
	var panel := Slab.new()
	panel.color = Color(0.07, 0.055, 0.055, 0.78)
	panel.points = PackedVector2Array([Vector2(0, 0.015), Vector2(1, 0), Vector2(0.99, 1), Vector2(0.008, 0.99)])
	panel.shadow_offset = Vector2(7, 9)
	panel.margins = Vector4(0, 0, 0, 14)
	panel.custom_minimum_size = Vector2(width, 0)
	%Stalls.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)

	var head := Slab.new()
	head.color = UIKit.P_RED
	head.points = PackedVector2Array([Vector2(0, 0.06), Vector2(1, 0), Vector2(0.985, 0.86), Vector2(0, 1)])
	head.extra = [PackedVector2Array([Vector2(0, 0.86), Vector2(0.985, 0.74), Vector2(0.985, 0.86), Vector2(0, 1)])]
	head.extra_colors = PackedColorArray([UIKit.P_RED_DARK])
	head.shadow_offset = Vector2.ZERO
	head.margins = Vector4(18, 6, 18, 10)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var head_row := HBoxContainer.new()
	head_row.add_theme_constant_override("separation", 10)
	head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(head_row)
	var t := UIKit.poster_label(title, UIKit.display_font(2), 24, UIKit.P_CREAM)
	head_row.add_child(t)
	var s := UIKit.poster_label(sub.to_upper(), UIKit.body_font(600, 3), 11, Color(1, 0.8, 0.76))
	s.size_flags_vertical = Control.SIZE_SHRINK_END
	s.custom_minimum_size.y = 22
	head_row.add_child(s)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	return row


## Gemeinsamer Rahmen einer Ware: schwebender, fokussierbarer Knopf ohne eigenen Hintergrund.
func _ware(offer: Dictionary, w: float, h: float, _deal: bool, _delay: float) -> Array:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(w, h)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var btn := Button.new()
	btn.flat = true
	for st in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = UIKit.P_GOLD
	focus.set_border_width_all(2)
	focus.set_expand_margin_all(4)
	btn.add_theme_stylebox_override("focus", focus)
	btn.focus_mode = Control.FOCUS_ALL
	btn.size = Vector2(w, h)
	holder.add_child(btn)
	btn.pressed.connect(func() -> void:
		if Run.buy(offer):
			_bought(btn))
	# nur beim Drüberfahren etwas größer (wie im Index), sonst keine Animation
	btn.mouse_entered.connect(func() -> void: _lift(btn, true))
	btn.mouse_exited.connect(func() -> void: _lift(btn, false))
	btn.focus_entered.connect(func() -> void: _lift(btn, true))
	btn.focus_exited.connect(func() -> void: _lift(btn, false))

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(box)
	var entry := {"offer": offer, "btn": btn, "price": null}
	_wares.append(entry)
	return [holder, btn, box, entry]


func _card_offer(offer: Dictionary, deal: bool, delay: float) -> Control:
	var parts := _ware(offer, CARD_W, 290, deal, delay)
	var box: VBoxContainer = parts[2]
	var enh: int = offer.get("enhancement", 0)

	# echtes Kartenbild, bei Glas die Glasversion
	var pic_holder := Control.new()
	pic_holder.custom_minimum_size = CARD_SIZE + Vector2(0, 6)
	pic_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pic_holder)
	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.55)
	shadow.position = Vector2((CARD_W - CARD_SIZE.x) * 0.5 + 6, 7)
	shadow.size = CARD_SIZE
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic_holder.add_child(shadow)
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.position = Vector2((CARD_W - CARD_SIZE.x) * 0.5, 0)
	pic.size = CARD_SIZE
	pic.rotation_degrees = -3.0
	pic.pivot_offset = CARD_SIZE * 0.5
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if enh == Card.Enhancement.GLASS:
		var under := ColorRect.new() # Glas auf dunklem Grund, wie im Spiel
		under.color = Color(0.1, 0.16, 0.14)
		under.position = pic.position + Vector2(4, 4)
		under.size = CARD_SIZE - Vector2(8, 8)
		under.rotation_degrees = -3.0
		under.pivot_offset = under.size * 0.5
		under.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic_holder.add_child(under)
	if offer.has("suit"):
		var shown := Card.new(offer.suit, offer.rank)
		shown.enhancement = enh
		pic.texture = Card3D.face_texture(shown)
	pic_holder.add_child(pic)
	# kein Schriftzug auf der Karte (Regel: die Verbesserung erkennt man am Bild)

	box.add_child(_spacer(4))
	var title := _label(offer.title, 17, UIKit.P_CREAM, true)
	box.add_child(title)
	var text := _label(offer.text, 13, Color(UIKit.P_CREAM, 0.72), false)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	_finish_ware(parts)
	return parts[0]


func _relic_offer(offer: Dictionary, deal: bool, delay: float) -> Control:
	var parts := _ware(offer, RELIC_W, 290, deal, delay)
	var box: VBoxContainer = parts[2]
	var is_relic: bool = offer.kind == "RELIKT"

	var medal_holder := CenterContainer.new()
	medal_holder.custom_minimum_size = Vector2(RELIC_W, 84)
	medal_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(medal_holder)
	if offer.get("emoji", false):
		var icon := UIKit.relic_icon(offer.symbol, 76, 52)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		medal_holder.add_child(icon)
		return _relic_texts(parts, offer, is_relic)
	var medal := Roundel.new()
	medal.color = offer.color
	medal.ring_color = UIKit.P_GOLD if is_relic else UIKit.P_CREAM
	medal.custom_minimum_size = Vector2(76, 76)
	medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	medal_holder.add_child(medal)
	var sym := UIKit.poster_label(offer.symbol, UIKit.SYMBOL_FONT, 30, UIKit.P_CREAM)
	sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sym.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sym.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	medal.add_child(sym)
	return _relic_texts(parts, offer, is_relic)


func _relic_texts(parts: Array, offer: Dictionary, is_relic: bool) -> Control:
	var box: VBoxContainer = parts[2]
	if offer.kind == "BONUS":
		var kind := _label("BONUS", 10, Color(1, 0.8, 0.76), false)
		kind.add_theme_font_override("font", UIKit.body_font(700, 3))
		box.add_child(kind)
	var title := _label(offer.title, 14, UIKit.P_CREAM, true)
	title.custom_minimum_size.x = RELIC_W - 8
	box.add_child(title)
	var text := _label(offer.text, 12, Color(UIKit.P_CREAM, 0.72), false)
	text.custom_minimum_size.x = RELIC_W - 8 # fest umbrechen, nie in den Nachbarn ragen
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	_finish_ware(parts)
	return parts[0]


## Preisschild anhängen und Zustand (kaufbar / zu teuer / verkauft) setzen.
func _finish_ware(parts: Array) -> void:
	var price := CenterContainer.new()
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parts[2] as VBoxContainer).add_child(price)
	var entry: Dictionary = parts[3]
	entry.price = price
	_apply_state(entry)


func _apply_state(entry: Dictionary) -> void:
	var offer: Dictionary = entry.offer
	var btn: Button = entry.btn
	var sold: bool = offer.sold
	var affordable: bool = Run.gold >= offer.price
	var full: bool = offer.kind == "ITEM" and not Run.has_item_slot()
	btn.disabled = sold or not affordable or full
	btn.modulate = Color(1, 1, 1, 0.38) if sold else (Color.WHITE if affordable else Color(0.75, 0.72, 0.72, 0.85))
	btn.tooltip_text = "Zu wenig Gold" if not affordable and not sold else ""
	if full and not sold:
		btn.tooltip_text = "Keine freien Item-Plätze"
		btn.modulate = Color(0.75, 0.72, 0.72, 0.85)
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE if sold else Control.MOUSE_FILTER_STOP
	var center: CenterContainer = entry.price
	for c in center.get_children():
		c.queue_free()
	center.add_child(_price(offer))


func _lift(btn: Control, up: bool) -> void:
	if up and btn is BaseButton and (btn as BaseButton).disabled:
		return
	if up:
		Sfx.play(&"index_hover", randf_range(0.96, 1.08))
	btn.pivot_offset = btn.size * 0.5
	btn.z_index = 1 if up else 0
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", Vector2.ONE * (1.1 if up else 1.0), 0.12).set_trans(Tween.TRANS_QUAD)


func _price(offer: Dictionary) -> Control:
	var sold: bool = offer.sold
	var affordable: bool = Run.gold >= offer.price
	var tag := Slab.new()
	tag.skew = 0.1
	tag.shadow_offset = Vector2(3, 4)
	tag.margins = Vector4(16, 3, 16, 4)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := "%d G" % offer.price
	var col := UIKit.P_BLACK
	if sold:
		tag.color = UIKit.P_BLACK
		text = "VERKAUFT"
		col = UIKit.P_RED
	elif affordable:
		tag.color = UIKit.P_GOLD
	else:
		tag.color = UIKit.P_RED_DARK
		col = UIKit.P_CREAM
	tag.add_child(UIKit.poster_label(text, UIKit.display_font(1), 18, col))
	return tag


# --- Tutorial: Händler erklären ---------------------------------------------------------

const TUTORIAL_STEPS := [
	["DER HÄNDLER", "Nach jedem gewonnenen Tisch kommst du hierher. Mit deinem Gold kaufst du Karten, Relikte und Items. Fürs Tutorial hast du %d Gold bekommen – kauf ruhig etwas."],
	["KARTEN", "Links: verbesserte Karten für dein Deck (Gold, Glas, Glück). Sie ersetzen die normale Karte gleichen Rangs und gleicher Farbe."],
	["RELIKTE", "In der Mitte: Relikte wirken dauerhaft, den ganzen Run lang. Im Duell stehen sie oben rechts als Symbole – Maus drüber zeigt die Wirkung."],
	["ITEMS", "Rechts: Items setzt du im Duell einmal ein, du kannst höchstens 2 tragen. Im Duell sind sie oben rechts in den runden Plätzen – anklicken zum Einsetzen."],
	["WEITER", "Neu mischen legt für etwas Gold neue Waren aus. Unten links siehst du deinen Besitz. Mit dem roten Knopf geht es zum nächsten Tisch – hier beendest du damit das Tutorial."],
]
var tutorial_step := -1
var _tut_panel: PanelContainer
var _tut_title: Label
var _tut_text: Label
var _tut_button: Button


func _start_tutorial() -> void:
	_tut_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UIKit.P_BLACK, 0.96)
	box.border_color = UIKit.P_RED
	box.border_width_left = 8
	box.content_margin_left = 22
	box.content_margin_right = 20
	box.content_margin_top = 12
	box.content_margin_bottom = 14
	_tut_panel.add_theme_stylebox_override("panel", box)
	_tut_panel.anchor_left = 0.5
	_tut_panel.anchor_right = 0.5
	_tut_panel.offset_left = -40
	_tut_panel.offset_right = 400
	_tut_panel.offset_top = 14
	add_child(_tut_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_tut_panel.add_child(col)
	var step := UIKit.poster_label("TUTORIAL · HÄNDLER", UIKit.body_font(700, 4), 12, UIKit.P_GOLD)
	col.add_child(step)
	_tut_title = UIKit.poster_label("", UIKit.display_font(2), 22, UIKit.P_CREAM)
	col.add_child(_tut_title)
	_tut_text = UIKit.poster_label("", UIKit.body_font(400), 15, UIKit.P_CREAM)
	_tut_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tut_text.custom_minimum_size = Vector2(390, 0)
	col.add_child(_tut_text)
	_tut_button = Button.new()
	_tut_button.custom_minimum_size = Vector2(0, 36)
	_tut_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_tut_button.pressed.connect(tutorial_next)
	col.add_child(_tut_button)
	tutorial_next()


## Nächster Erklärschritt (nach dem letzten verschwindet die Tafel).
func tutorial_next() -> void:
	tutorial_step += 1
	if tutorial_step >= TUTORIAL_STEPS.size():
		_tut_panel.queue_free()
		_tut_panel = null
		%ContinueButton.grab_focus()
		return
	if tutorial_step > 0:
		Sfx.play(&"button")
	var st: Array = TUTORIAL_STEPS[tutorial_step]
	_tut_title.text = st[0]
	_tut_text.text = st[1] % Run.TUTORIAL_SHOP_GOLD if "%d" in st[1] else st[1]
	_tut_button.text = "VERSTANDEN" if tutorial_step == TUTORIAL_STEPS.size() - 1 else "WEITER"
	_tut_panel.reset_size.call_deferred()
	_tut_panel.modulate.a = 0.0
	_tut_panel.create_tween().tween_property(_tut_panel, "modulate:a", 1.0, 0.2)


# --- Besitz -----------------------------------------------------------------------------

func _owned_items() -> Array:
	var items := []
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


func _chip(text: String, tip: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.paper(Vector4(8, 3, 10, 3)))
	p.tooltip_text = tip
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override("font_size", 12)
	l.text = text
	p.add_child(l)
	return p


# --- Helfer -----------------------------------------------------------------------------

func _label(text: String, size: int, color: Color, display: bool) -> Label:
	var l := UIKit.poster_label(text, UIKit.display_font() if display else UIKit.body_font(500), size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
