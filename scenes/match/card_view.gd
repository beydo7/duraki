class_name CardView
extends Button
## Darstellung einer Karte. Platzhalter-Optik ohne Grafiken –
## später durch Sprites/Texturen ersetzen.

signal card_pressed(card: Card)

const CARD_SIZE := Vector2(84, 120)
const COLOR_FACE := Color("fbf8f0")
const COLOR_BACK := Color("2c3e72")
const COLOR_RED := Color("c0392b")
const COLOR_BLACK := Color("1f1f1f")
const COLOR_TRUMP_BORDER := Color("d4a017")

var card: Card
var face_down := false
var is_trump := false
var interactive := false


func setup(p_card: Card, p_face_down := false, p_is_trump := false, p_interactive := false) -> CardView:
	card = p_card
	face_down = p_face_down
	is_trump = p_is_trump
	interactive = p_interactive
	if is_inside_tree():
		_refresh()
	return self


func set_playable(playable: bool) -> void:
	disabled = not playable
	modulate = Color.WHITE if playable else Color(1, 1, 1, 0.55)


func _ready() -> void:
	custom_minimum_size = CARD_SIZE
	focus_mode = Control.FOCUS_NONE
	pressed.connect(func() -> void:
		if card != null:
			card_pressed.emit(card))
	_refresh()


func _refresh() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 28)
	var showing_face := card != null and not face_down
	text = card.get_label() if showing_face else ""
	var font_color := COLOR_RED if showing_face and card.is_red() else COLOR_BLACK
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		add_theme_color_override(state, font_color)

	var bg := COLOR_FACE if showing_face else COLOR_BACK
	var border := COLOR_TRUMP_BORDER if showing_face and is_trump else Color(0, 0, 0, 0.35)
	add_theme_stylebox_override("normal", _make_style(bg, border, 2))
	add_theme_stylebox_override("disabled", _make_style(bg, border, 2))
	add_theme_stylebox_override("hover", _make_style(bg.lightened(0.05), Color("f1c40f"), 3))
	add_theme_stylebox_override("pressed", _make_style(bg.darkened(0.1), Color("f1c40f"), 3))


func _make_style(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(8)
	return s
