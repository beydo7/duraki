class_name DeckMenu
extends Control
## Deck-Auswahl (Hauptmenü): alle Decks mit Rückseite, Effekt und wie man sie freischaltet.
## Freie Decks lassen sich wählen, kaufbare mit Seelen kaufen.
##     var menu := DeckMenu.new(); add_child(menu); menu.closed.connect(...)

signal closed

const CARD_SIZE := Vector2(112, 156)

var _grid: GridContainer
var _souls: Label
var _detail_name: Label
var _detail_text: Label
var _detail_unlock: Label
var _action: Button
var _current: DeckData
var _panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.012, 0.04, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UIKit.paper(Vector4(40, 28, 40, 30), true))
	_panel.custom_minimum_size = Vector2(1080, 0)
	center.add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	_panel.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := _l("DECKS", &"InkTitle", 40)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_souls = _l("", &"InkTitle", 24)
	_souls.add_theme_color_override("font_color", UIKit.INK_RED)
	_souls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_souls.tooltip_text = "Seelen bekommst du am Ende jedes Runs: %d pro besiegtem Tisch, %d für einen Sieg." % [
		Profile.SOULS_PER_TABLE, Profile.SOULS_RUN_WIN]
	_souls.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(_souls)
	root.add_child(_l("Jedes Deck hat eine eigene Rückseite und einen kleinen Vorteil. Besiege Gegner, um ihr Deck zu bekommen – oder kaufe Decks mit Seelen.", &"InkType", 15, true))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 26)
	root.add_child(body)
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 6)
	body.add_child(_grid)

	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(250, 0)
	detail.add_theme_constant_override("separation", 8)
	body.add_child(detail)
	_detail_name = _l("", &"InkTitle", 26, true)
	detail.add_child(_detail_name)
	_detail_text = _l("", &"InkLabel", 17, true)
	detail.add_child(_detail_text)
	_detail_unlock = _l("", &"InkType", 15, true)
	detail.add_child(_detail_unlock)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(spacer)
	_action = Button.new()
	_action.custom_minimum_size = Vector2(0, 54)
	_action.pressed.connect(_on_action)
	UIKit.hover(_action, 1.04)
	detail.add_child(_action)
	var back := Button.new()
	back.text = "ZURÜCK"
	back.custom_minimum_size = Vector2(0, 50)
	back.pressed.connect(close)
	UIKit.hover(back, 1.04)
	detail.add_child(back)

	_render()
	_show(Profile.selected_deck())
	_panel.pivot_offset = _panel.size * 0.5
	UIKit.appear(_panel, 0.0, Vector2(0, 30), 0.35)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	closed.emit()
	queue_free()


func _render() -> void:
	_souls.text = "%d Seelen" % Profile.souls
	for c in _grid.get_children():
		c.queue_free()
	for d in Profile.decks():
		_grid.add_child(_deck_card(d))


func _deck_card(d: DeckData) -> Control:
	var unlocked := Profile.is_unlocked(d.id)
	var selected := Profile.selected == d.id and unlocked
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var btn := TextureButton.new()
	btn.texture_normal = d.back
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.custom_minimum_size = CARD_SIZE
	btn.tooltip_text = d.display_name
	if not unlocked:
		btn.modulate = Color(0.32, 0.3, 0.32) if not Profile.can_buy(d.id) else Color(0.6, 0.56, 0.52)
	btn.pressed.connect(func() -> void: _show(d))
	btn.mouse_entered.connect(func() -> void: _show(d))
	UIKit.hover(btn, 1.06)
	box.add_child(btn)
	var name := _l(d.display_name, &"InkLabel", 13)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.custom_minimum_size = Vector2(CARD_SIZE.x, 0)
	name.clip_text = true
	if selected:
		name.add_theme_color_override("font_color", UIKit.INK_RED)
		name.text = "✓ " + d.display_name
	elif not unlocked:
		name.add_theme_color_override("font_color", UIKit.INK_SOFT)
	box.add_child(name)
	if not unlocked:
		var how := _l("%d Seelen" % d.price_souls if d.price_souls > 0 else "gesperrt", &"InkType", 12)
		how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		how.add_theme_color_override("font_color", UIKit.INK_RED if Profile.can_buy(d.id) else UIKit.INK_SOFT)
		box.add_child(how)
	return box


func _show(d: DeckData) -> void:
	if d == null:
		return
	_current = d
	var unlocked := Profile.is_unlocked(d.id)
	_detail_name.text = d.display_name
	_detail_text.text = d.effect_text if not d.effect_text.is_empty() else "Keine Besonderheiten."
	_detail_unlock.text = "Freigeschaltet" if unlocked else "Freischalten: " + d.unlock_text()
	_detail_unlock.add_theme_color_override("font_color", UIKit.INK_SOFT if unlocked else UIKit.INK_RED)
	_action.disabled = false
	_action.theme_type_variation = &"PrimaryButton"
	if unlocked and Profile.selected == d.id:
		_action.text = "GEWÄHLT"
		_action.disabled = true
	elif unlocked:
		_action.text = "DIESES DECK SPIELEN"
	elif d.price_souls > 0:
		_action.text = "KAUFEN · %d SEELEN" % d.price_souls
		_action.disabled = not Profile.can_buy(d.id)
	else:
		_action.text = "GESPERRT"
		_action.disabled = true


func _on_action() -> void:
	if _current == null:
		return
	if Profile.is_unlocked(_current.id):
		Profile.select(_current.id)
	elif Profile.buy(_current.id):
		Profile.select(_current.id)
		UIKit.pop(_souls, 1.3)
	_render()
	_show(_current)


func _l(text: String, variation: StringName, size: int, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(240, 0)
	return l
