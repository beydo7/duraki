class_name DevMenu
extends Control
## Entwicklermenü (F8 im Duell und überall sonst, auch im Hauptmenü): beliebige Karte (Farbe, Rang, Verbesserung) auf die Hand
## nehmen, Items und Relikte holen, Gold dazu, alles freischalten. Zum Testen.
##     var m := DevMenu.new(); m.match_node = self; add_child(m)

signal closed

var match_node: Node # match.gd

var _suit := Card.Suit.SPADES
var _rank := 14
var _enh := Card.Enhancement.NONE
var _status: Label
var _groups := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UIKit.P_BLACK, 0.97)
	box.border_color = UIKit.P_GOLD
	box.set_border_width_all(2)
	box.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", box)
	panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(panel)
	# bei vielen Relikten/Items wird es hoch: Inhalt scrollbar, Fenster passt immer auf den Bildschirm
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(856, minf(620.0, get_viewport_rect().size.y - 90.0))
	panel.add_child(scroll)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	var title := UIKit.poster_label("ENTWICKLERMENÜ", UIKit.display_font(2), 28, UIKit.P_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UIKit.poster_label("F8 / Esc schließt", UIKit.body_font(500), 14, UIKit.MUTED))

	root.add_child(_head("KARTE AUF DIE HAND"))
	root.add_child(_choice_row("suit", Card.SUIT_SYMBOLS, [0, 1, 2, 3], func(v: int) -> void: _suit = v, _suit))
	var ranks: Array = []
	var rank_names: Array = []
	for r in range(Card.MIN_RANK, Card.MAX_RANK + 1):
		ranks.append(r)
		rank_names.append(Card.RANK_NAMES[r])
	root.add_child(_choice_row("rank", rank_names, ranks, func(v: int) -> void: _rank = v, _rank))
	root.add_child(_choice_row("enh", ["Normal", "Gold", "Glas", "Glück"], [0, 1, 2, 3], func(v: int) -> void: _enh = v, _enh))
	var give := _button("KARTE NEHMEN", _give_card, true)
	root.add_child(give)

	root.add_child(_head("ITEMS"))
	var items := HFlowContainer.new()
	items.add_theme_constant_override("h_separation", 8)
	items.add_theme_constant_override("v_separation", 8)
	root.add_child(items)
	for id: StringName in Run.ITEMS:
		var it: Dictionary = Run.ITEMS[id]
		items.add_child(_button(("%s %s" % [it.emoji, it.name]) if it.emoji is String else String(it.name), func() -> void: _give_item(id)))
	items.add_child(_button("Items leeren", func() -> void:
		Run.items.clear()
		_refresh("Items geleert.")))

	root.add_child(_head("RELIKTE & GOLD"))
	var relics := HFlowContainer.new()
	relics.add_theme_constant_override("h_separation", 8)
	relics.add_theme_constant_override("v_separation", 8)
	root.add_child(relics)
	for r in Run.all_relics():
		relics.add_child(_button("%s %s" % [r.icon(), r.display_name], func() -> void:
			if Run.relics.any(func(o: RelicData) -> bool: return o.id == r.id):
				_refresh("%s hast du schon." % r.display_name)
				return
			Run.add_relic(r)
			_refresh("%s erhalten." % r.display_name)))
	relics.add_child(_button("+10 Gold", func() -> void:
		Run.add_gold(10)
		_refresh("+10 Gold.")))

	root.add_child(_head("RUN ÜBERSPRINGEN (zum Testen)"))
	var skip := HFlowContainer.new()
	skip.add_theme_constant_override("h_separation", 8)
	skip.add_theme_constant_override("v_separation", 8)
	root.add_child(skip)
	skip.add_child(_button("GEGNER ÜBERSPRINGEN", func() -> void: _skip(Run.dev_skip_opponent)))
	skip.add_child(_button("ZUM BOSS DES AKTS", func() -> void: _skip(Run.dev_skip_to_boss)))
	skip.add_child(_button("BOSS-HÄNDLER", func() -> void:
		_skip(func() -> void:
			Run.boss_shop = true
			Run.boss_gift_open = true
			Run.last_gold_reward = 0
			Run.last_interest = 0
			Run.open_shop())))
	skip.add_child(_button("ENDLOS-MODUS STARTEN", func() -> void: _skip(Run.dev_start_endless)))

	root.add_child(_head("RAUM (für alle Tische, bis zum Neustart)"))
	var rooms := HBoxContainer.new()
	rooms.add_theme_constant_override("separation", 8)
	root.add_child(rooms)
	rooms.add_child(_button("ZUFÄLLIG", func() -> void: _set_room(&"")))
	for id: StringName in Rooms.NAMES:
		rooms.add_child(_button(String(Rooms.NAMES[id]).to_upper(), func() -> void: _set_room(id)))

	root.add_child(_head("PROFIL"))
	root.add_child(_button("ALLES FREISCHALTEN – alle Decks und alle Abzeichen", func() -> void:
		Profile.unlock_all()
		_refresh("Alle Decks freigeschaltet, alle Abzeichen vergeben.")))

	_status = UIKit.poster_label("", UIKit.body_font(500), 15, UIKit.P_CREAM)
	root.add_child(_status)
	root.add_child(_button("SCHLIESSEN", close))
	# Profil-Knopf und Rückmeldung nach oben holen, damit man sie ohne Scrollen sieht
	root.move_child(_status, 1)
	UIKit.appear(panel, 0.0, Vector2(0, 20), 0.25)


## Sprung im Run (nur während eines Runs, nicht im Tutorial).
func _skip(action: Callable) -> void:
	if Run.encounters.is_empty() or Run.tutorial:
		_refresh("Geht nur während eines Runs.")
		return
	close()
	action.call()


## Raum erzwingen; im Duell wird der Tisch dafür neu aufgebaut.
func _set_room(id: StringName) -> void:
	Rooms.forced = id
	var name := "normal (je nach Tisch)" if id == &"" else String(Rooms.NAMES[id])
	if match_node != null and "duel" in match_node and match_node.duel != null:
		close()
		Run.goto(Run.SCENE_MATCH)
		return
	_refresh("Raum: %s – gilt ab dem nächsten Tisch." % name)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	closed.emit()
	queue_free()


## Gewählte Karte auf die Hand: aus Stapel/Ablage/Gegnerhand holen, sonst neu erzeugen.
func _give_card() -> void:
	if match_node == null or not ("duel" in match_node):
		_refresh("Karten gibt es nur im Duell.")
		return
	var duel: DurakMatch = match_node.duel
	if duel == null or duel.is_over:
		_refresh("Kein laufendes Duell.")
		return
	var card: Card = null
	for list: Array in [duel.deck.cards, duel.discard_pile, duel.opponent_hand]:
		for c: Card in list:
			if c.suit == _suit and c.rank == _rank:
				card = c
				list.erase(c)
				break
		if card != null:
			break
	if card == null:
		for c: Card in duel.player_hand:
			if c.suit == _suit and c.rank == _rank:
				card = c
		if card != null:
			card.enhancement = _enh
			duel.changed.emit()
			_refresh("%s hast du schon – Verbesserung gesetzt." % card)
			return
		card = Card.new(_suit, _rank) # liegt auf dem Tisch: Kopie
	card.enhancement = _enh
	duel.player_hand.append(card)
	DurakRules.sort_hand(duel.player_hand, duel.trump_suit)
	duel.changed.emit()
	_refresh("%s auf die Hand genommen." % card)


func _give_item(id: StringName) -> void:
	if not Run.has_item_slot():
		Run.items.remove_at(0) # ältestes ersetzen
	Run.add_item(id)
	_refresh("%s erhalten." % Run.ITEMS[id].name)


func _refresh(text: String) -> void:
	_status.text = text
	if match_node != null and match_node.has_method("refresh_after_dev"):
		match_node.refresh_after_dev()


# --- Bausteine -----------------------------------------------------------------------

func _head(text: String) -> Label:
	return UIKit.poster_label(text, UIKit.body_font(700, 3), 13, UIKit.P_GOLD)


func _choice_row(key: String, names: Array, values: Array, on_pick: Callable, current: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	_groups[key] = group
	for i in names.size():
		var b := Button.new()
		b.text = str(names[i])
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(52, 40)
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = values[i] == current
		var v: int = values[i]
		b.pressed.connect(func() -> void: on_pick.call(v))
		row.add_child(b)
	return row


func _button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.focus_mode = Control.FOCUS_NONE
	if primary:
		b.theme_type_variation = &"PrimaryButton"
	b.pressed.connect(cb)
	return b
