class_name RunSetupMenu
extends Control
## Vor dem Run: Schwierigkeit wählen (Leicht/Normal/Schwer) und Hinweise an/aus.
## Die Wahl wird in den Einstellungen gemerkt (general/difficulty, general/hints).
##     var m := RunSetupMenu.new(); add_child(m); m.started.connect(...); m.closed.connect(...)

signal started
signal closed

const LEVELS := [
	["LEICHT", "Niedrigere Punkteziele, Gegner machen mehr Fehler. +1 Leben.", "Seelen ×0,75"],
	["NORMAL", "Die gedachte Erfahrung: Gegner spielen ordentlich, Ziele sind fordernd.", "Seelen ×1"],
	["SCHWER", "Hohe Punkteziele, Gegner spielen fast fehlerfrei. −1 Leben.", "Seelen ×1,25"],
]

var _tiles: Array[Button] = []
var _hints: CheckButton
var _bonus: Label
var _panel: PanelContainer
var _done := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.012, 0.04, 0.74)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UIKit.paper(Vector4(40, 28, 40, 30), true))
	_panel.custom_minimum_size = Vector2(900, 0)
	center.add_child(_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	_panel.add_child(root)
	root.add_child(_l("NEUER RUN", &"InkTitle", 40))
	var d := Profile.selected_deck()
	root.add_child(_l("Deck: %s  ·  Wie hart soll es werden?" % (d.display_name if d else "–"), &"InkType", 16))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	root.add_child(row)
	var group := ButtonGroup.new()
	for i in LEVELS.size():
		var tile := _level_tile(i, group)
		row.add_child(tile)
		_tiles.append(tile)

	var hint_row := HBoxContainer.new()
	hint_row.add_theme_constant_override("separation", 16)
	root.add_child(hint_row)
	var hl := _l("Hinweise (spielbare Karten leuchten)", &"InkLabel", 18)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_row.add_child(hl)
	_hints = CheckButton.new()
	_hints.button_pressed = bool(Settings.get_value("general/hints"))
	_hints.custom_minimum_size = Vector2(110, 40)
	_hints.toggled.connect(func(on: bool) -> void:
		Sfx.play(&"ui_click")
		Settings.set_value("general/hints", on)
		_update())
	hint_row.add_child(_hints)
	_bonus = _l("", &"InkType", 15, true)
	root.add_child(_bonus)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(buttons)
	var back := Button.new()
	back.text = "ZURÜCK"
	back.custom_minimum_size = Vector2(200, 54)
	back.pressed.connect(close)
	UIKit.hover(back, 1.04)
	buttons.add_child(back)
	var go := Button.new()
	go.text = "LOS GEHT'S"
	go.theme_type_variation = &"PrimaryButton"
	go.custom_minimum_size = Vector2(260, 54)
	go.pressed.connect(_start)
	UIKit.hover(go, 1.04)
	buttons.add_child(go)

	_tiles[clampi(int(Settings.get_value("general/difficulty")), 0, 2)].button_pressed = true
	_update()
	go.grab_focus.call_deferred()
	UIKit.appear(_panel, 0.0, Vector2(0, 30), 0.35)


func _level_tile(i: int, group: ButtonGroup) -> Button:
	var spec: Array = LEVELS[i]
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.custom_minimum_size = Vector2(0, 170)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16
	box.offset_right = -16
	box.offset_top = 14
	box.offset_bottom = -12
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	b.add_child(box)
	var title := UIKit.poster_label(spec[0], UIKit.display_font(3), 30, UIKit.P_CREAM)
	box.add_child(title)
	var text := _l(spec[1], &"InkType", 15, true)
	text.custom_minimum_size = Vector2(220, 0)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(text)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	var souls := _l(spec[2], &"InkLabel", 15)
	souls.add_theme_color_override("font_color", UIKit.P_GOLD)
	souls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(souls)
	b.set_meta("title", title)
	b.toggled.connect(func(on: bool) -> void:
		if on:
			Settings.set_value("general/difficulty", i)
			Sfx.play(&"ui_click")
		_update())
	UIKit.hover(b, 1.03)
	return b


func _update() -> void:
	for i in _tiles.size():
		var on := _tiles[i].button_pressed
		(_tiles[i].get_meta("title") as Label).add_theme_color_override("font_color", UIKit.P_CREAM if on else UIKit.MUTED)
		_tiles[i].self_modulate = Color(1.15, 1.08, 1.0) if on else Color(0.8, 0.78, 0.78)
	_hints.text = "An" if _hints.button_pressed else "Aus"
	var level := clampi(int(Settings.get_value("general/difficulty")), 0, 2)
	var factor: float = Run.DIFF_SOULS[level] * (1.0 if _hints.button_pressed else Run.NO_HINTS_SOULS)
	var f := RunSetupMenu.factor_text(factor)
	var tip := "Schalte die Hinweise aus für ×1,5 Seelen – dann musst du selbst sehen, was passt." \
		if _hints.button_pressed else "Ohne Hinweise: ×1,5 Seelen."
	_bonus.text = "%s   Seelen in diesem Run: ×%s" % [tip, f]
	_bonus.add_theme_color_override("font_color", UIKit.INK_SOFT if _hints.button_pressed else UIKit.P_GOLD)


## 1.875 → „1,88“, 1.0 → „1“
static func factor_text(f: float) -> String:
	var t := "%.2f" % f
	t = t.rstrip("0").rstrip(".")
	return t.replace(".", ",")


func _start() -> void:
	if _done:
		return
	_done = true
	started.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if _done:
		return
	_done = true
	closed.emit()
	queue_free()


func _l(text: String, variation: StringName, size: int, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(240, 0)
	return l
