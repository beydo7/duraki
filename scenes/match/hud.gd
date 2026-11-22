class_name MatchHUD
extends Control
## HUD des Duells im Plakat-Stil (Rot / Schwarz / Creme, russische Plakate).
## Alles wird hier im Code gebaut (Basisgröße 1280×720, an den Rändern verankert):
##   links oben    roter Keil mit Punkten, Ziel und Segment-Fortschritt,
##                 darunter schwarze Plakette Chips × Mult und das Spielprotokoll
##   links         runde Plaketten: Leben, Gold, Stapel, Trumpf-Stern
##   rechts oben   schwarzer Balken mit Gegner (Foto, Name kyrillisch + deutsch, Tisch, Handkarten),
##                 darunter Relikte als Briefmarken
##   rechts unten  Zug-Plakette (wer ist dran, was geht) und die Aktionen
##   Mitte         kurz eingeblendete Schrägbanner („ЗАЩИТА – VERTEIDIGE DICH“)
## Die Spiellogik ruft nur die öffentlichen Funktionen auf (siehe match.gd).

enum Turn { ATTACK, DEFEND, WAIT, THROW_IN, OVER }

const TOAST_TIME := 4.5
const TOAST_MAX := 4
const COLOR_GOLD := UIKit.GOLD
const COLOR_TEXT := UIKit.CREAM
const COLOR_MUTED := UIKit.MUTED
const RED := UIKit.P_RED
const RED_DARK := UIKit.P_RED_DARK
const BLACK := UIKit.P_BLACK
const CREAM := UIKit.P_CREAM
const PGOLD := UIKit.P_GOLD
const EDGE_SHADER := preload("res://scenes/match/edge_glow.gdshader")
const RELIC_SYMBOLS := {&"ace_up_sleeve": "A", &"lucky_coin": "₽", &"samovar": "♨", &"vodka": "✶"}
const RELIC_COLORS := [Color(0.47, 0.24, 0.59), Color(0.16, 0.43, 0.27), Color(0.67, 0.43, 0.12), Color(0.2, 0.32, 0.55)]
## Gegnernamen auf Russisch (nach Dateiname der Gegner-Ressource)
const CYRILLIC := {
	"bandit": "БАНДИТ", "swamp_man": "БОЛОТНИК", "crow": "ВОРОНА", "wolf": "ВОЛЧИЦА",
	"jester": "ШУТ", "bone_man": "КОСТЛЯВЫЙ", "witch": "ВЕДЬМА", "giant": "ВЕЛИКАН",
}
const BANNER_RU := {
	"DEIN ANGRIFF": "АТАКА", "VERTEIDIGE DICH": "ЗАЩИТА", "GESCHOBEN!": "ПЕРЕВОД",
	"WEITERGESCHOBEN": "ПЕРЕВОД",
}
## Zug-Plakette: [Hintergrund, Titelfarbe, Hinweisfarbe]
const TURN_LOOK := {
	Turn.ATTACK: [CREAM, BLACK, Color(0.2, 0.16, 0.16)],
	Turn.DEFEND: [RED, CREAM, Color(1, 0.86, 0.8)],
	Turn.WAIT: [BLACK, Color(0.82, 0.78, 0.72), Color(0.67, 0.63, 0.59)],
	Turn.THROW_IN: [PGOLD, BLACK, Color(0.2, 0.14, 0.08)],
	Turn.OVER: [BLACK, CREAM, Color(0.67, 0.63, 0.59)],
}

## Für match.gd und Tests
var take_button: Button
var pass_button: Button
var continue_button: Button

var _shown_score := 0.0
var _score := 0
var _target := 1
var _chips := 0
var _mult := 1
var _opp_cards := -1
var _thinking := false
var _turn := -1
var _turn_title := ""
var _t := 0.0
var _glow_target := 0.0
var _glow := 0.0
var _choice: Control
var _deck := -1
var _lives := -1
var _gold := -1

# Knoten
var _edge: ColorRect
var _wedge: Slab
var _score_label: Label
var _target_label: Label
var _seg: SegBar
var _chips_plate: Slab
var _chips_label: Label
var _mult_label: Label
var _sub_label: Label
var _toasts: VBoxContainer
var _opp_bar: Slab
var _portrait: TextureRect
var _cyr_label: Label
var _opp_label: Label
var _floor_label: Label
var _opp_cards_draw: Control
var _opp_count: Label
var _think_label: Label
var _relics: HBoxContainer
var _speech: Slab
var _speech_label: Label
var _lives_label: Label
var _gold_label: Label
var _deck_label: Label
var _deck_roundel: Roundel
var _trump_symbol: Label
var _trump_caption: Label
var _bout_label: Label
var _turn_plate: Slab
var _turn_title_label: Label
var _turn_hint: Label
var _transfer_tag: Slab
var _actions: VBoxContainer
var _banner: Slab
var _banner_label: Label
var _banner_sub: Label
var _float_layer: Control
var _result: Control
var _dim: ColorRect
var _result_panel: Slab
var _result_header: Label
var _result_title: Label
var _result_score: Label
var _result_text: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_build()
	take_button.visible = false
	pass_button.visible = false


func _process(delta: float) -> void:
	_t += delta
	if _thinking:
		var dots := int(_t * 3.0) % 4
		_think_label.text = String(_think_label.get_meta("base", "überlegt")) + ".".repeat(dots)
	# Die Zug-Plakette pulsiert leicht, wenn du dran bist
	var mine := _turn in [Turn.ATTACK, Turn.DEFEND, Turn.THROW_IN]
	var pulse := (sin(_t * 3.2) * 0.5 + 0.5) if mine else 0.0
	_turn_plate.self_modulate = Color(1, 1, 1).lerp(Color(1.12, 1.08, 1.04), pulse)
	_glow = move_toward(_glow, _glow_target, delta * 0.8)
	(_edge.material as ShaderMaterial).set_shader_parameter("strength", _glow)


# --- Aufbau ---------------------------------------------------------------------------

func _build() -> void:
	_edge = ColorRect.new()
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	mat.shader = EDGE_SHADER
	mat.set_shader_parameter("glow_color", Color(1, 0.25, 0.3))
	mat.set_shader_parameter("strength", 0.0)
	mat.set_shader_parameter("width", 0.22)
	_edge.material = mat
	add_child(_edge)
	_build_score()
	_build_opponent()
	_build_left()
	_build_turn_and_actions()
	_build_banner()
	_float_layer = Control.new()
	_float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_float_layer)
	_build_result()


## Control an einer Ecke verankern: `corner` 0..1 je Achse, `pos` relativ zur Ecke.
func _anchor(c: Control, corner: Vector2, pos: Vector2, sz: Vector2) -> void:
	c.anchor_left = corner.x
	c.anchor_right = corner.x
	c.anchor_top = corner.y
	c.anchor_bottom = corner.y
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + sz.x
	c.offset_bottom = pos.y + sz.y
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if corner.x >= 1.0 else Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if corner.y >= 1.0 else Control.GROW_DIRECTION_END


func _slab(color: Color, pts: Array = [], skew := 0.0, margins := Vector4.ZERO) -> Slab:
	var s := Slab.new()
	s.color = color
	s.skew = skew
	if not pts.is_empty():
		s.points = PackedVector2Array(pts)
	s.margins = margins
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _at(parent: Control, c: Control, pos: Vector2, sz := Vector2.ZERO) -> Control:
	parent.add_child(c)
	c.position = pos
	if sz != Vector2.ZERO:
		c.size = sz
	return c


func _build_score() -> void:
	_wedge = _slab(RED, [Vector2(0, 0), Vector2(1, 0), Vector2(0.875, 0.83), Vector2(0, 1)])
	_wedge.extra = [PackedVector2Array([Vector2(0, 0.763), Vector2(0.9375, 0.593), Vector2(0.9125, 0.788), Vector2(0, 0.975)])]
	_wedge.extra_colors = PackedColorArray([Color(0.55, 0.07, 0.09)])
	_wedge.shadow_offset = Vector2(5, 7)
	_wedge.fit_children = false
	_anchor(_wedge, Vector2.ZERO, Vector2(0, 0), Vector2(430, 160))
	add_child(_wedge)
	var head := UIKit.poster_label("ОЧКИ · PUNKTE", UIKit.body_font(600, 3), 14, CREAM)
	_at(_wedge, head, Vector2(26, 10))
	_score_label = UIKit.poster_label("0", UIKit.display_font(), 72, CREAM, 4)
	_at(_wedge, _score_label, Vector2(20, 18))
	_target_label = UIKit.poster_label("/0", UIKit.body_font(600), 28, Color(1, 0.8, 0.76))
	_at(_wedge, _target_label, Vector2(200, 58))
	_score_label.resized.connect(_place_target)
	_seg = SegBar.new()
	_seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_seg.segments = 10
	_seg.empty_color = Color(0.36, 0.03, 0.05)
	_at(_wedge, _seg, Vector2(28, 126), Vector2(270, 13))
	_seg.rotation_degrees = -3.6

	_chips_plate = _slab(BLACK, [Vector2(0.03, 0.18), Vector2(1, 0), Vector2(0.97, 0.84), Vector2(0, 1)], 0.0, Vector4(20, 9, 18, 9))
	_anchor(_chips_plate, Vector2.ZERO, Vector2(10, 166), Vector2(300, 56))
	add_child(_chips_plate)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips_plate.add_child(row)
	_chips_label = UIKit.poster_label("0", UIKit.display_font(), 30, UIKit.CHIPS)
	_chips_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_chips_label)
	var times := UIKit.poster_label("×", UIKit.body_font(700), 26, CREAM)
	times.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(times)
	_mult_label = UIKit.poster_label("1", UIKit.display_font(), 30, UIKit.MULT)
	_mult_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_mult_label)
	var gap := Control.new()
	gap.custom_minimum_size.x = 8
	row.add_child(gap)
	_sub_label = UIKit.poster_label("", UIKit.body_font(500), 13, Color(0.78, 0.74, 0.69))
	_sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub_label.custom_minimum_size.x = 120
	row.add_child(_sub_label)

	_toasts = VBoxContainer.new()
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_theme_constant_override("separation", 6)
	_anchor(_toasts, Vector2.ZERO, Vector2(12, 240), Vector2(340, 10))
	add_child(_toasts)


func _place_target() -> void:
	var w := _score_label.get_theme_font("font").get_string_size(_score_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 72).x
	_target_label.position = Vector2(_score_label.position.x + w + 10, 58)


func _build_opponent() -> void:
	_opp_bar = _slab(BLACK, [Vector2(0.031, 0.222), Vector2(1, 0), Vector2(1, 0.815), Vector2(0, 0.948)])
	_opp_bar.extra = [PackedVector2Array([Vector2(0.003, 0.889), Vector2(1, 0.756), Vector2(1, 0.859), Vector2(0, 0.993)])]
	_opp_bar.extra_colors = PackedColorArray([RED])
	_opp_bar.shadow_offset = Vector2(5, 7)
	_opp_bar.fit_children = false
	_anchor(_opp_bar, Vector2(1, 0), Vector2(-434, 0), Vector2(434, 92))
	add_child(_opp_bar)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_at(_opp_bar, _portrait, Vector2(22, 16), Vector2(60, 60))
	var frame := _slab(Color(0, 0, 0, 0), [Vector2(0.04, 0.02), Vector2(1, 0), Vector2(0.97, 1), Vector2(0, 0.98)])
	frame.shadow_offset = Vector2.ZERO
	frame.outline_color = RED
	frame.outline_width = 2.5
	_at(_opp_bar, frame, Vector2(18, 13), Vector2(68, 66))
	_cyr_label = UIKit.poster_label("", UIKit.body_font(600, 5), 14, UIKit.INK_RED)
	_at(_opp_bar, _cyr_label, Vector2(98, 16))
	_opp_label = UIKit.poster_label("", UIKit.display_font(), 26, CREAM)
	_at(_opp_bar, _opp_label, Vector2(96, 34))
	_floor_label = UIKit.poster_label("", UIKit.body_font(600, 2), 13, UIKit.MUTED)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_at(_opp_bar, _floor_label, Vector2(250, 8), Vector2(168, 20))
	_opp_cards_draw = Control.new()
	_opp_cards_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_opp_cards_draw.draw.connect(_draw_opp_cards)
	_at(_opp_bar, _opp_cards_draw, Vector2(250, 32), Vector2(168, 15))
	_opp_count = UIKit.poster_label("", UIKit.body_font(500, 2), 12, UIKit.MUTED)
	_opp_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_at(_opp_bar, _opp_count, Vector2(250, 49), Vector2(168, 18))

	_relics = HBoxContainer.new()
	_relics.alignment = BoxContainer.ALIGNMENT_END
	_relics.add_theme_constant_override("separation", 10)
	_relics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(_relics, Vector2(1, 0), Vector2(-420, 102), Vector2(404, 58))
	add_child(_relics)

	_think_label = UIKit.poster_label("", UIKit.body_font(500), 16, CREAM, 2)
	_think_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_think_label.modulate.a = 0.0
	_anchor(_think_label, Vector2(1, 0), Vector2(-420, 168), Vector2(404, 24))
	add_child(_think_label)

	_speech = _slab(CREAM, [], 0.05, Vector4(22, 9, 22, 11))
	_speech.shadow_offset = Vector2(4, 5)
	_speech.fit_children = false
	_speech_label = UIKit.poster_label("", UIKit.body_font(500), 18, BLACK)
	_speech_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech.add_child(_speech_label)
	_speech.modulate.a = 0.0
	_anchor(_speech, Vector2(0.5, 0), Vector2(70, 128), Vector2(10, 10))
	add_child(_speech)


func _draw_opp_cards() -> void:
	var n := mini(maxi(_opp_cards, 0), 12)
	var w := 9.0
	var gap := 4.0
	var h := _opp_cards_draw.size.y
	var x := _opp_cards_draw.size.x - n * (w + gap) + gap
	for i in n:
		var pts := PackedVector2Array([Vector2(x + 2.5, 0), Vector2(x + w + 2.5, 0), Vector2(x + w, h), Vector2(x, h)])
		_opp_cards_draw.draw_colored_polygon(pts, RED)
		x += w + gap


func _roundel(center: Vector2, radius: float, color: Color, ring: Color, caption: String, text_color: Color) -> Label:
	var r := Roundel.new()
	r.color = color
	r.ring_color = ring
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(r, Vector2.ZERO, center - Vector2(radius, radius), Vector2(radius, radius) * 2)
	add_child(r)
	var cap := UIKit.poster_label(caption, UIKit.body_font(600, 2), 10, text_color)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_at(r, cap, Vector2(0, radius * 0.38), Vector2(radius * 2, 14))
	var val := UIKit.poster_label("", UIKit.display_font(), 26, text_color)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_at(r, val, Vector2(0, radius * 0.62), Vector2(radius * 2, 34))
	r.set_meta("value", val)
	return val


func _build_left() -> void:
	_lives_label = _roundel(Vector2(56, 410), 36, RED, CREAM, "LEBEN", CREAM)
	_gold_label = _roundel(Vector2(56, 496), 36, PGOLD, BLACK, "GOLD", BLACK)
	_deck_label = _roundel(Vector2(56, 582), 36, BLACK, CREAM, "STAPEL", CREAM)
	_deck_roundel = _deck_label.get_parent() as Roundel
	var star := Roundel.new()
	star.star = true
	star.color = RED
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(star, Vector2.ZERO, Vector2(56 - 26, 650 - 26), Vector2(52, 52))
	add_child(star)
	_trump_symbol = UIKit.poster_label("♥", UIKit.SYMBOL_FONT, 20, CREAM)
	_trump_symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_at(star, _trump_symbol, Vector2(0, 13), Vector2(52, 26))
	_trump_caption = UIKit.poster_label("TRUMPF", UIKit.body_font(600, 2), 11, CREAM, 2)
	_trump_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_trump_caption, Vector2.ZERO, Vector2(6, 680), Vector2(100, 16))
	add_child(_trump_caption)
	_bout_label = UIKit.poster_label("", UIKit.body_font(600, 2), 13, CREAM, 2)
	_anchor(_bout_label, Vector2.ZERO, Vector2(98, 640), Vector2(160, 20))
	add_child(_bout_label)


func _build_turn_and_actions() -> void:
	_turn_plate = _slab(BLACK, [], 0.06, Vector4(26, 10, 22, 13))
	_turn_plate.shadow_offset = Vector2(5, 6)
	_anchor(_turn_plate, Vector2(1, 1), Vector2(-14 - 360, -178 - 80), Vector2(360, 80))
	add_child(_turn_plate)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_plate.add_child(col)
	_turn_title_label = UIKit.poster_label("", UIKit.display_font(), 25, CREAM)
	_turn_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(_turn_title_label)
	_turn_hint = UIKit.poster_label("", UIKit.body_font(500), 14, CREAM)
	_turn_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_turn_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_turn_hint.custom_minimum_size.x = 312
	col.add_child(_turn_hint)
	_transfer_tag = _slab(PGOLD, [], 0.2, Vector4(18, 3, 24, 4))
	_transfer_tag.shadow_offset = Vector2(3, 3)
	_transfer_tag.size_flags_horizontal = Control.SIZE_SHRINK_END
	var tl := UIKit.poster_label("↻  SCHIEBEN MÖGLICH", UIKit.body_font(700, 2), 13, BLACK)
	_transfer_tag.add_child(tl)
	_transfer_tag.visible = false
	var tag_gap := Control.new()
	tag_gap.custom_minimum_size.y = 4
	col.add_child(tag_gap)
	col.add_child(_transfer_tag)
	tag_gap.visible = false
	_transfer_tag.set_meta("gap", tag_gap)

	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 12)
	_actions.alignment = BoxContainer.ALIGNMENT_END
	_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor(_actions, Vector2(1, 1), Vector2(-14 - 250, -18 - 112), Vector2(250, 112))
	add_child(_actions)
	take_button = _action_button("NEHMEN", "E", &"PrimaryButton")
	pass_button = _action_button("BITO", "LEER", &"")
	_actions.add_child(take_button)
	_actions.add_child(pass_button)
	_refresh_padding(take_button)
	_refresh_padding(pass_button)


func _action_button(text: String, key: String, variation: StringName) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(250, 50)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_constant_override("h_separation", 0)
	if variation != &"":
		b.theme_type_variation = variation
	var k := UIKit.poster_label("[%s]" % key, UIKit.body_font(600, 2), 13, CREAM)
	k.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	k.offset_left = -80
	k.offset_right = -26
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	k.modulate.a = 0.75
	b.add_child(k)
	b.set_meta("key", k)
	UIKit.hover(b, 1.04)
	return b


func _build_banner() -> void:
	_banner = _slab(RED, [Vector2(0.02, 0.06), Vector2(1, 0), Vector2(0.98, 0.94), Vector2(0, 1)], 0.0, Vector4(60, 8, 60, 10))
	_banner.shadow_offset = Vector2(6, 8)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(col)
	_banner_label = UIKit.poster_label("", UIKit.display_font(), 40, CREAM, 3)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_banner_label)
	_banner_sub = UIKit.poster_label("", UIKit.body_font(600, 10), 14, Color(1, 0.8, 0.76))
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_banner_sub)
	_banner.modulate.a = 0.0
	_anchor(_banner, Vector2(0.5, 0), Vector2(-200, 380), Vector2(400, 70))
	add_child(_banner)


func _build_result() -> void:
	_result = Control.new()
	_result.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.visible = false
	add_child(_result)
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.01, 0.02, 0.72)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.add_child(center)
	_result_panel = _slab(RED, [Vector2(0.03, 0), Vector2(1, 0.02), Vector2(0.97, 1), Vector2(0, 0.97)], 0.0, Vector4(56, 30, 56, 34))
	_result_panel.shadow_offset = Vector2(9, 11)
	_result_panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(_result_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_panel.add_child(col)
	_result_header = UIKit.poster_label("", UIKit.body_font(600, 4), 15, CREAM)
	_result_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_result_header)
	_result_title = UIKit.poster_label("", UIKit.display_font(), 86, CREAM, 6)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_result_title)
	_result_score = UIKit.poster_label("", UIKit.display_font(), 26, PGOLD)
	_result_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_result_score)
	_result_text = UIKit.poster_label("", UIKit.body_font(400), 17, CREAM)
	_result_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_text.custom_minimum_size.x = 420
	col.add_child(_result_text)
	var gap := Control.new()
	gap.custom_minimum_size.y = 12
	col.add_child(gap)
	continue_button = Button.new()
	continue_button.text = "WEITER"
	continue_button.custom_minimum_size = Vector2(260, 54)
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_button.add_theme_font_size_override("font_size", 24)
	UIKit.hover(continue_button, 1.05)
	col.add_child(continue_button)


# --- Öffentliche Schnittstelle ---------------------------------------------------

func setup(opponent: OpponentData, target: int, floor_i := 0, floor_count := 1) -> void:
	_opp_label.text = opponent.display_name.to_upper()
	_portrait.texture = opponent.portrait
	var id := opponent.resource_path.get_file().get_basename()
	_cyr_label.text = CYRILLIC.get(id, "ПРОТИВНИК")
	_floor_label.text = ("BOSS · TISCH %d/%d" if opponent.is_boss else "TISCH %d/%d") % [floor_i + 1, floor_count]
	_target = maxi(1, target)
	_target_label.text = "/%d" % target
	_intro.call_deferred()


## Einflug der Plakatflächen, erst wenn das Layout steht.
func _intro() -> void:
	for n: CanvasItem in [_wedge, _chips_plate, _opp_bar, _turn_plate, _actions]:
		n.modulate.a = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	UIKit.appear(_wedge, 0.05, Vector2(-60, -20))
	UIKit.appear(_chips_plate, 0.15, Vector2(-60, 0))
	UIKit.appear(_opp_bar, 0.1, Vector2(60, -20))
	UIKit.appear(_turn_plate, 0.25, Vector2.ZERO)
	UIKit.appear(_actions, 0.3, Vector2.ZERO)


## Wer ist dran und was kann man tun?
func set_turn(mode: int, title: String, hint: String) -> void:
	if title != _turn_title or mode != _turn:
		var look: Array = TURN_LOOK[mode]
		_turn_plate.color = look[0]
		_turn_title_label.add_theme_color_override("font_color", look[1])
		_turn_hint.add_theme_color_override("font_color", look[2])
		_turn_title_label.text = title
		_turn = mode
		_turn_title = title
		_plate_slam()
		_fit_plate.call_deferred()
	if _turn_hint.text != hint:
		_turn_hint.text = hint
		_fit_plate.call_deferred()
	_glow_target = 0.0
	if mode == Turn.DEFEND:
		_glow_target = 0.12
	(_edge.material as ShaderMaterial).set_shader_parameter("glow_color", UIKit.RED)


func set_danger(strength: float) -> void:
	_glow_target = maxf(_glow_target, strength)


func set_opponent_cards(count: int) -> void:
	if count == _opp_cards:
		return
	var grew := count > _opp_cards and _opp_cards >= 0
	_opp_cards = count
	_opp_count.text = "%d %s" % [count, "KARTE" if count == 1 else "KARTEN"]
	_opp_cards_draw.queue_redraw()
	if grew:
		UIKit.pop(_opp_count, 1.2)


func set_thinking(thinking: bool, text: String = "") -> void:
	_thinking = thinking
	if thinking:
		_think_label.set_meta("base", text)
	var tw := _think_label.create_tween()
	tw.tween_property(_think_label, "modulate:a", 1.0 if thinking else 0.0, 0.25)


## Sprechblase neben dem Gegner (Sticheleien).
func say(text: String, time := 4.0) -> void:
	_speech_label.text = "„%s“" % text
	var font := _speech_label.get_theme_font("font")
	var w := minf(font.get_string_size(_speech_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 4, 300)
	var h := font.get_multiline_string_size(_speech_label.text, HORIZONTAL_ALIGNMENT_LEFT, w, 18).y
	var m := _speech.margins
	_speech.size = Vector2(w + m.x + m.z, h + m.y + m.w)
	_speech_label.position = Vector2(m.x, m.y)
	_speech_label.size = Vector2(w, h)
	var tw := _tween_key(_speech, "say")
	_speech.modulate.a = 0.0
	_speech.rotation_degrees = -1.5
	_speech.pivot_offset = Vector2(0, _speech.size.y)
	_speech.scale = Vector2(0.85, 0.85)
	tw.tween_property(_speech, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(_speech, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(time)
	tw.tween_property(_speech, "modulate:a", 0.0, 0.4)


func set_run_info(lives: int, gold: int, deck: int, trump_suit: int) -> void:
	if lives != _lives:
		_lives_label.text = str(maxi(lives, 0))
		if _lives >= 0:
			UIKit.pop(_lives_label.get_parent() as Control, 1.25)
		_lives = lives
	if gold != _gold:
		if _gold >= 0 and gold > _gold:
			UIKit.count(_gold_label, _gold, gold, 0.6, "%d")
			UIKit.pop(_gold_label.get_parent() as Control, 1.2)
		else:
			_gold_label.text = str(gold)
		_gold = gold
	if deck != _deck:
		_deck_label.text = str(deck) if deck > 0 else "–"
		_deck_roundel.color = RED_DARK if deck == 0 else BLACK
		_deck = deck
	_trump_symbol.text = Card.SUIT_SYMBOLS[trump_suit]
	_trump_caption.text = "TRUMPF · %s" % String(Card.SUIT_NAMES[trump_suit]).to_upper()


## Angriffskarten dieser Runde (x von höchstens y) und ob Schieben gerade geht.
func set_bout(attack_count: int, limit: int, can_transfer: bool) -> void:
	_bout_label.text = "ANGRIFF %d/%d" % [attack_count, limit] if attack_count > 0 else ""
	if _transfer_tag.visible != can_transfer:
		_transfer_tag.visible = can_transfer
		(_transfer_tag.get_meta("gap") as Control).visible = can_transfer
		_fit_plate.call_deferred()
		if can_transfer:
			UIKit.pop(_transfer_tag, 1.3)


func set_relics(relics: Array) -> void:
	for c in _relics.get_children():
		c.queue_free()
	for i in relics.size():
		var r: RelicData = relics[i]
		var stamp := _slab(CREAM, [], 0.0, Vector4(5, 5, 5, 5))
		stamp.custom_minimum_size = Vector2(46, 56)
		stamp.shadow_offset = Vector2(3, 4)
		stamp.mouse_filter = Control.MOUSE_FILTER_PASS
		stamp.tooltip_text = "%s – %s" % [r.display_name, r.description]
		var inner := _slab(RELIC_COLORS[i % RELIC_COLORS.size()], [], 0.0)
		inner.shadow_offset = Vector2.ZERO
		stamp.add_child(inner)
		var sym := UIKit.poster_label(RELIC_SYMBOLS.get(r.id, r.display_name.left(1)), UIKit.display_font(), 22, CREAM, 2)
		sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sym.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		stamp.add_child(sym)
		stamp.rotation_degrees = [-3.0, 2.0, -1.0, 3.0][i % 4]
		_relics.add_child(stamp)


func set_score(total: int, target: int, chips: int, mult: int, sub_text: String) -> void:
	_target = maxi(1, target)
	_target_label.text = "/%d" % target
	if total != _score:
		var from := _shown_score
		_score = total
		var tw := _score_label.create_tween()
		tw.tween_method(_show_score, from, float(total), 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		UIKit.pop(_score_label, 1.18)
	else:
		_show_score(total)
	if chips != _chips:
		if chips > _chips:
			UIKit.pop(_chips_label, 1.3)
		_chips = chips
	if mult != _mult:
		if mult > _mult:
			UIKit.pop(_mult_label, 1.3)
		_mult = mult
	_chips_label.text = str(chips)
	_mult_label.text = str(mult)
	_sub_label.text = sub_text
	var done := total >= target
	_score_label.add_theme_color_override("font_color", Color(1, 0.86, 0.45) if done else CREAM)
	_seg.fill_color = Color(1, 0.84, 0.4) if done else CREAM
	_seg.queue_redraw()


## Eine Runde wurde gewertet: Punkte fliegen von Chips × Mult zur Punktzahl.
func bout_scored(points: int, text: String) -> void:
	toast(text, COLOR_GOLD if points > 0 else COLOR_MUTED)
	if points <= 0:
		return
	var big := text.begins_with("Volltreffer") or text.begins_with("Durak")
	var start: Vector2 = _chips_plate.get_global_rect().get_center()
	var end_pos: Vector2 = _score_label.get_global_rect().get_center()
	var label := UIKit.poster_label("+%d" % points, UIKit.display_font(), 54 if big else 40, Color(1, 0.86, 0.45))
	label.add_theme_color_override("font_outline_color", BLACK)
	label.add_theme_constant_override("outline_size", 12)
	_float_layer.add_child(label)
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	label.global_position = start - label.size * 0.5 + Vector2(40, 60)
	label.scale = Vector2(0.3, 0.3)
	label.rotation_degrees = -4.0
	var tw := label.create_tween()
	tw.tween_property(label, "scale", Vector2.ONE * (1.3 if big else 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.35)
	tw.tween_property(label, "global_position", end_pos - label.size * 0.5, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(label, "scale", Vector2(0.5, 0.5), 0.45)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.45).set_delay(0.2)
	tw.tween_callback(label.queue_free)
	if big:
		UIKit.shake(_wedge, 8.0)
		(_edge.material as ShaderMaterial).set_shader_parameter("glow_color", COLOR_GOLD)
		_glow = 0.6
		_glow_target = 0.0


## Kurze Meldung links (Spielprotokoll), blendet nach ein paar Sekunden aus.
func toast(text: String, color: Color = COLOR_TEXT) -> void:
	var pill := _slab(Color(0.05, 0.04, 0.04, 0.9), [], 0.04, Vector4(14, 5, 16, 6))
	pill.shadow_offset = Vector2(3, 3)
	var label := UIKit.poster_label(text, UIKit.body_font(500), 15, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var w := label.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 6
	label.custom_minimum_size.x = minf(w, 300)
	pill.add_child(label)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_toasts.add_child(pill)
	while _toasts.get_child_count() > TOAST_MAX:
		var old: Node = _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	pill.modulate.a = 0.0
	var tw := pill.create_tween()
	tw.tween_property(pill, "modulate:a", 1.0, 0.2)
	tw.tween_interval(TOAST_TIME)
	tw.tween_property(pill, "modulate:a", 0.0, 0.6)
	tw.tween_callback(pill.queue_free)


## Großes Schrägbanner in der Bildmitte („DEIN ANGRIFF“ …), mit russischer Unterzeile.
func show_banner(text: String, color: Color = Color(1, 0.86, 0.5)) -> void:
	_banner_label.text = text
	_banner_sub.text = BANNER_RU.get(text, "")
	_banner_sub.visible = _banner_sub.text != ""
	# Rötliche Farben → rotes Banner, sonst schwarzes Banner mit rotem Balken
	var reddish := color.r > 0.8 and color.g < 0.7
	_banner.color = RED if reddish else BLACK
	_banner.extra = [] if reddish else [PackedVector2Array([Vector2(0.0, 0.88), Vector2(1, 0.82), Vector2(0.995, 0.92), Vector2(0, 1.0)])]
	_banner.extra_colors = PackedColorArray([RED])
	_banner_sub.add_theme_color_override("font_color", Color(1, 0.8, 0.76) if reddish else UIKit.INK_RED)
	_banner.size = Vector2.ZERO
	_banner.reset_size()
	_banner.offset_left = -_banner.size.x * 0.5
	_banner.offset_right = _banner.size.x * 0.5
	_banner.pivot_offset = _banner.size * 0.5
	_banner.queue_redraw()
	var tw := _tween_key(_banner, "banner")
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(0.2, 1.0)
	_banner.rotation_degrees = -2.5
	tw.tween_property(_banner, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.8)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(_banner, "scale", Vector2(1.12, 0.8), 0.3)


func set_actions(take_visible: bool, pass_visible: bool, pass_enabled: bool, pass_text := "BITO") -> void:
	_set_button(take_button, take_visible)
	_set_button(pass_button, pass_visible)
	pass_button.disabled = not pass_enabled
	pass_button.text = pass_text
	(pass_button.get_meta("key") as Label).modulate.a = 0.75 if pass_enabled else 0.3
	var variation := &"PrimaryButton" if pass_enabled and not take_visible else &""
	if pass_button.theme_type_variation != variation:
		pass_button.theme_type_variation = variation
		_refresh_padding(pass_button)


## Kleine Auswahl über den Aktionen (z. B. „Schlagen oder Schieben?“).
## `callback` bekommt den Index der gewählten Option; Abbrechen ruft nichts auf.
func ask_choice(title: String, options: Array[String], callback: Callable) -> void:
	close_choice()
	var panel := _slab(BLACK, [], 0.03, Vector4(22, 14, 22, 16))
	panel.extra = [PackedVector2Array([Vector2(0.03, 0), Vector2(1, 0), Vector2(0.999, 0.03), Vector2(0.029, 0.03)])]
	panel.extra_colors = PackedColorArray([RED])
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_choice = panel
	_actions.add_child(panel)
	_actions.move_child(panel, 0)
	_turn_plate.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var label := UIKit.poster_label(title, UIKit.body_font(600), 16, CREAM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 200
	box.add_child(label)
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_font_size_override("font_size", 21)
		b.theme_type_variation = &"PrimaryButton" if i == options.size() - 1 else &""
		UIKit.hover(b, 1.04)
		var index := i
		b.pressed.connect(func() -> void:
			close_choice()
			callback.call(index))
		box.add_child(b)
	var cancel := Button.new()
	cancel.text = "ABBRECHEN"
	cancel.flat = true
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(0, 34)
	cancel.add_theme_font_override("font", UIKit.body_font(600, 3))
	cancel.add_theme_font_size_override("font_size", 13)
	cancel.add_theme_color_override("font_color", UIKit.MUTED)
	cancel.pressed.connect(close_choice)
	box.add_child(cancel)
	UIKit.appear(panel, 0.0, Vector2(30, 0), 0.25)


func close_choice() -> void:
	if _choice != null and is_instance_valid(_choice):
		_choice.queue_free()
	_choice = null
	if _turn_plate != null:
		_turn_plate.visible = true


func show_result(won: bool, title: String, text: String, score_text: String) -> void:
	set_actions(false, false, false)
	close_choice()
	_glow_target = 0.0
	_result_header.text = "ПОБЕДА · DUELL GEWONNEN" if won else "ПОРАЖЕНИЕ · DUELL VERLOREN"
	_result_title.text = title
	_result_panel.color = RED if won else BLACK
	_result_panel.extra = [] if won else [PackedVector2Array([Vector2(0.03, 0), Vector2(1, 0.02), Vector2(0.999, 0.045), Vector2(0.029, 0.025)])]
	_result_panel.extra_colors = PackedColorArray([RED])
	_result_title.add_theme_color_override("font_color", CREAM if won else UIKit.INK_RED)
	_result_header.add_theme_color_override("font_color", Color(1, 0.84, 0.8) if won else UIKit.MUTED)
	continue_button.theme_type_variation = &"" if won else &"PrimaryButton"
	_result_text.text = text
	_result_score.text = score_text
	_result.visible = true
	_dim.modulate.a = 0.0
	_result_panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_dim, "modulate:a", 1.0, 0.4)
	tw.parallel().tween_property(_result_panel, "modulate:a", 1.0, 0.2).set_delay(0.15)
	tw.tween_callback(func() -> void:
		_result_panel.pivot_offset = _result_panel.size * 0.5
		_result_panel.rotation_degrees = -2.0
		_result_title.pivot_offset = _result_title.size * 0.5
		_result_title.scale = Vector2(1.7, 1.7)
		var t2 := _result_title.create_tween()
		t2.tween_property(_result_title, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t2.tween_callback(func() -> void: UIKit.shake(_result_panel, 6.0))
		continue_button.grab_focus())


## Rote Tempo-Streifen quer durchs Bild (Schieben). `up` = Richtung Gegner.
func speed_lines(up: bool) -> void:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_layer.add_child(c)
	var rng := RandomNumberGenerator.new()
	var lines: Array = []
	for i in 16:
		lines.append([rng.randf_range(0.2, 0.8), rng.randf_range(0.0, 0.5), rng.randf_range(0.18, 0.4), rng.randf_range(2.0, 6.0), i % 3 == 0])
	var state := {"t": 0.0}
	c.draw.connect(func() -> void:
		var sz := c.size
		var t: float = state["t"]
		for l: Array in lines:
			var x: float = l[0] * sz.x
			var start: float = l[1]
			var length: float = l[2]
			var p := clampf((t - start * 0.4) / 0.6, 0.0, 1.0)
			if p <= 0.0 or p >= 1.0:
				continue
			# von unten nach oben (oder umgekehrt), leicht schräg wie auf einem Plakat
			var y_head := lerpf(1.15, -0.15, p) if up else lerpf(-0.15, 1.15, p)
			var y_tail := y_head + (length if up else -length)
			var a := Vector2(x + (y_head - 0.5) * 120.0, y_head * sz.y)
			var b := Vector2(x + (y_tail - 0.5) * 120.0, y_tail * sz.y)
			var col := CREAM if l[4] else RED
			col.a = 0.55 * sin(p * PI)
			c.draw_line(a, b, col, l[3], true))
	var tw := c.create_tween()
	tw.tween_method(func(v: float) -> void:
		state["t"] = v
		c.queue_redraw(), 0.0, 1.0, 0.55 * Settings.anim_time_factor())
	tw.tween_callback(c.queue_free)


## Roter Stempel über dem Spielfeld (z. B. „БИТО“ beim Abwerfen).
func stamp(text: String, sub := "") -> void:
	var s := _slab(Color(0, 0, 0, 0), [Vector2(0, 0.04), Vector2(1, 0), Vector2(0.99, 1), Vector2(0.01, 0.96)], 0.0, Vector4(26, 6, 26, 8))
	s.outline_color = RED
	s.outline_width = 5.0
	s.shadow_offset = Vector2.ZERO
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(col)
	var l := UIKit.poster_label(text, UIKit.display_font(4), 46, RED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	if sub != "":
		var l2 := UIKit.poster_label(sub, UIKit.body_font(700, 6), 13, RED)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l2)
	_float_layer.add_child(s)
	s.reset_size()
	# mitten auf dem Spielfeld, knapp unter dem Bereich der Schrägbanner
	s.position = Vector2(size.x * 0.5 - s.size.x * 0.5, size.y * 0.655)
	s.pivot_offset = s.size * 0.5
	s.rotation_degrees = -9.0
	s.scale = Vector2(2.2, 2.2)
	s.modulate.a = 0.0
	var f := Settings.anim_time_factor()
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 1.0, 0.08 * f)
	tw.parallel().tween_property(s, "scale", Vector2.ONE, 0.16 * f).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(0.7 * f)
	tw.tween_property(s, "modulate:a", 0.0, 0.35 * f)
	tw.tween_callback(s.queue_free)


func is_result_open() -> bool:
	return _result.visible


# --- Hilfen -----------------------------------------------------------------------

func _show_score(value: float) -> void:
	_shown_score = value
	_score_label.text = str(int(round(value)))
	_seg.value = clampf(value / float(_target), 0.0, 1.0)
	_place_target()


func _tween_key(node: Node, key: String) -> Tween:
	if node.has_meta("_tw_" + key):
		var old: Variant = node.get_meta("_tw_" + key)
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tw := node.create_tween()
	node.set_meta("_tw_" + key, tw)
	return tw


## Zug-Plakette auf ihre Mindestgröße bringen, rechte untere Ecke bleibt stehen.
func _fit_plate() -> void:
	var m := _turn_plate.get_combined_minimum_size()
	_turn_plate.offset_left = _turn_plate.offset_right - m.x
	_turn_plate.offset_top = _turn_plate.offset_bottom - m.y


## Die Zug-Plakette „knallt“ herein.
func _plate_slam() -> void:
	var p := _turn_plate
	p.pivot_offset = p.size * Vector2(1.0, 0.5)
	var tw := _tween_key(p, "slam")
	p.scale = Vector2(1.25, 1.25)
	p.rotation_degrees = -3.0
	tw.tween_property(p, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(p, "rotation_degrees", -1.0, 0.16)


func _refresh_padding(b: Button) -> void:
	for st_name in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		b.remove_theme_stylebox_override(st_name)
	for st_name in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var st := b.get_theme_stylebox(st_name)
		if st is StyleBoxFlat:
			var c := (st as StyleBoxFlat).duplicate() as StyleBoxFlat
			c.content_margin_left = 30
			b.add_theme_stylebox_override(st_name, c)


func _set_button(b: Button, show: bool) -> void:
	if b.visible == show:
		return
	b.visible = show
	if show:
		b.pivot_offset = Vector2(b.size.x * 0.5, b.size.y * 0.5)
		b.modulate.a = 0.0
		b.scale = Vector2(0.85, 0.85)
		var tw := _tween_key(b, "btn")
		tw.tween_property(b, "modulate:a", 1.0, 0.2)
		tw.parallel().tween_property(b, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
