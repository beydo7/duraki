class_name MatchHUD
extends Control
## HUD des Duells: Gegner-Plakette, Punkte-Panel (Chips × Mult), Meldungen,
## Zug-Banner, schwebende Punkte und das Ergebnis-Fenster – alles animiert.
## Die Spiellogik ruft nur die öffentlichen Funktionen auf (siehe match.gd).

const TOAST_TIME := 5.5
const TOAST_MAX := 5
const COLOR_GOLD := Color(1, 0.82, 0.4)
const COLOR_TEXT := Color(0.93, 0.88, 0.8)
const COLOR_MUTED := Color(0.75, 0.68, 0.95)
const SUIT_COLORS := [Color(1, 0.42, 0.45), Color(1, 0.55, 0.4), Color(0.75, 0.9, 1.0), Color(0.82, 0.78, 1.0)]

var _shown_score := 0.0
var _score := 0
var _target := 1
var _chips := 0
var _mult := 1
var _opp_cards := -1
var _thinking := false
var _my_turn := false
var _t := 0.0
var _status_style: StyleBoxFlat
var _tweens := {}
var _choice: Control


func _ready() -> void:
	# eigene Kopie des Status-Stils, damit nur er pulsiert
	_status_style = (%StatusPill.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	%StatusPill.add_theme_stylebox_override("panel", _status_style)
	for b: Button in [%TakeButton, %PassButton, %ContinueButton]:
		_make_bouncy(b)
	%Banner.pivot_offset = Vector2(%Banner.size.x * 0.5, 40)


func _process(delta: float) -> void:
	_t += delta
	# „überlegt …“ mit wandernden Punkten
	if _thinking:
		var dots := int(_t * 3.0) % 4
		%ThinkLabel.text = %ThinkLabel.get_meta("base", "überlegt") + ".".repeat(dots)
	# Status pulsiert, wenn du am Zug bist
	var pulse := (sin(_t * 4.0) * 0.5 + 0.5) if _my_turn else 0.0
	_status_style.border_color = Color(0.45, 0.36, 0.82, 0.55).lerp(COLOR_GOLD, pulse * 0.85)
	_status_style.shadow_color = Color(0, 0, 0, 0.35).lerp(Color(1, 0.75, 0.3, 0.35), pulse)
	%Portrait.intensity = move_toward(%Portrait.intensity, 1.0 if _thinking else 0.0, delta * 2.0)


# --- Öffentliche Schnittstelle ---------------------------------------------------

func setup(opponent: OpponentData, target: int) -> void:
	%OpponentLabel.text = opponent.display_name
	%Portrait.mask_color = opponent.mask_color
	%Portrait.eye_color = opponent.eye_color
	%Portrait.portrait = opponent.portrait
	_target = maxi(1, target)
	%TargetLabel.text = " / %d" % target
	_slide_in(%OpponentPanel, Vector2(-40, 0), 0.0)
	_slide_in(%ScorePanel, Vector2(40, 0), 0.05)


func set_status(text: String, my_turn: bool) -> void:
	if %StatusLabel.text != text:
		%StatusLabel.text = text
		%StatusLabel.custom_minimum_size.x = _text_width(%StatusLabel, text, 360)
	_my_turn = my_turn


func set_opponent_cards(count: int) -> void:
	if count == _opp_cards:
		return
	var grew := count > _opp_cards and _opp_cards >= 0
	_opp_cards = count
	for c in %OpponentCards.get_children():
		c.queue_free()
	var shown := mini(count, 12)
	for i in shown:
		var card := Panel.new()
		card.custom_minimum_size = Vector2(11, 16)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.3, 0.2, 0.6)
		st.border_color = Color(0.95, 0.88, 0.75)
		st.set_border_width_all(1)
		st.set_corner_radius_all(2)
		card.add_theme_stylebox_override("panel", st)
		%OpponentCards.add_child(card)
	var label := Label.new()
	label.text = "  %d Karten" % count if count != 1 else "  1 Karte"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", COLOR_MUTED)
	%OpponentCards.add_child(label)
	if grew:
		_pop(%OpponentCards, 1.12)


func set_thinking(thinking: bool, text: String = "") -> void:
	_thinking = thinking
	if thinking:
		%ThinkLabel.set_meta("base", text)
	_fade(%ThinkLabel, 1.0 if thinking else 0.0, 0.25)


func set_run_info(lives: int, gold: int, deck: int, trump_suit: int) -> void:
	%LivesLabel.text = "♥".repeat(maxi(0, lives)) if lives <= 5 else "♥ %d" % lives
	%GoldLabel.text = "● %d" % gold
	%DeckLabel.text = "▮ %d" % deck
	%TrumpLabel.text = "Trumpf %s" % Card.SUIT_SYMBOLS[trump_suit]
	%TrumpLabel.add_theme_color_override("font_color", SUIT_COLORS[trump_suit])


func set_score(total: int, target: int, chips: int, mult: int, sub_text: String) -> void:
	_target = maxi(1, target)
	%TargetLabel.text = " / %d" % target
	if total != _score:
		var from := _shown_score
		_score = total
		_tween_key("score").tween_method(_show_score, from, float(total), 0.7) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_pop(%ScoreLabel, 1.25)
	else:
		_show_score(total)
	if chips != _chips:
		if chips > _chips:
			_pop(%ChipsBox, 1.18)
		_chips = chips
	if mult != _mult:
		if mult > _mult:
			_pop(%MultBox, 1.18)
		_mult = mult
	%ChipsLabel.text = str(chips)
	%MultLabel.text = str(mult)
	%BoutLabel.text = sub_text


## Eine Runde wurde gewertet: Punkte fliegen von Chips × Mult zur Punktzahl.
func bout_scored(points: int, text: String) -> void:
	toast(text, COLOR_GOLD if points > 0 else COLOR_MUTED)
	if points <= 0:
		return
	var big := text.begins_with("Volltreffer") or text.begins_with("Durak")
	var start: Vector2 = %ChipsBox.get_global_rect().get_center().lerp(%MultBox.get_global_rect().get_center(), 0.5)
	var end_pos: Vector2 = %ScoreLabel.get_global_rect().get_center()
	var label := Label.new()
	label.text = "+%d" % points
	label.theme_type_variation = &"BrushLabel"
	label.add_theme_font_size_override("font_size", 54 if big else 40)
	label.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.25))
	label.add_theme_constant_override("outline_size", 12)
	%FloatLayer.add_child(label)
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	label.global_position = start - label.size * 0.5 + Vector2(0, 50)
	label.scale = Vector2(0.3, 0.3)
	var tw := create_tween()
	tw.tween_property(label, "scale", Vector2.ONE * (1.3 if big else 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.35)
	tw.tween_property(label, "global_position", end_pos - label.size * 0.5, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(label, "scale", Vector2(0.5, 0.5), 0.45)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.45).set_delay(0.2)
	tw.tween_callback(label.queue_free)
	if big:
		_shake(%ScorePanel)


## Kurze Meldung, die links einblendet und nach ein paar Sekunden verschwindet.
func toast(text: String, color: Color = COLOR_TEXT) -> void:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.035, 0.09, 0.72)
	st.set_corner_radius_all(10)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	st.set_border_width_all(1)
	st.border_color = Color(color, 0.35)
	pill.add_theme_stylebox_override("panel", st)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = _text_width(label, text, 340)
	pill.add_child(label)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	%Toasts.add_child(pill)
	while %Toasts.get_child_count() > TOAST_MAX:
		var old: Node = %Toasts.get_child(0)
		%Toasts.remove_child(old)
		old.queue_free()
	pill.modulate.a = 0.0
	var tw := pill.create_tween()
	tw.tween_property(pill, "modulate:a", 1.0, 0.2)
	tw.tween_interval(TOAST_TIME)
	tw.tween_property(pill, "modulate:a", 0.0, 0.6)
	tw.tween_callback(pill.queue_free)


## Großes Banner in der Bildmitte („DEIN ANGRIFF“ …).
func show_banner(text: String) -> void:
	%Banner.text = text
	%Banner.pivot_offset = Vector2(%Banner.size.x * 0.5, %Banner.size.y * 0.5)
	var tw := _tween_key("banner")
	%Banner.scale = Vector2(0.7, 0.7)
	%Banner.modulate.a = 0.0
	tw.tween_property(%Banner, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(%Banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.7)
	tw.tween_property(%Banner, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(%Banner, "scale", Vector2(1.08, 1.08), 0.35)


func set_actions(take_visible: bool, pass_visible: bool, pass_enabled: bool, pass_text := "BITO") -> void:
	_set_button(%TakeButton, take_visible)
	_set_button(%PassButton, pass_visible)
	%PassButton.disabled = not pass_enabled
	%PassButton.text = pass_text


## Kleine Auswahl über der Hand (z. B. „Schlagen oder Schieben?“).
## `callback` bekommt den Index der gewählten Option; Abbrechen ruft nichts auf.
func ask_choice(title: String, options: Array[String], callback: Callable) -> void:
	close_choice()
	var panel := PanelContainer.new()
	_choice = panel
	%Actions.add_child(panel)
	var style := (%OpponentPanel.get_theme_stylebox("panel") as StyleBox).duplicate() as StyleBox
	if style is StyleBoxFlat:
		(style as StyleBoxFlat).content_margin_left = 14
		(style as StyleBoxFlat).content_margin_right = 14
		(style as StyleBoxFlat).content_margin_top = 14
		(style as StyleBoxFlat).content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var label := Label.new()
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", COLOR_GOLD)
	box.add_child(label)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	for i in options.size():
		var b := _action_button(options[i])
		var index := i
		b.pressed.connect(func() -> void:
			close_choice()
			callback.call(index))
		row.add_child(b)
	var cancel := _action_button("ABBRECHEN")
	cancel.custom_minimum_size = Vector2(140, 40)
	cancel.add_theme_font_size_override("font_size", 14)
	cancel.pressed.connect(close_choice)
	box.add_child(cancel)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.pivot_offset = Vector2(118, 60)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.85, 0.85)
	var tw := _tween_key("choice")
	tw.tween_property(panel, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close_choice() -> void:
	if _choice != null and is_instance_valid(_choice):
		_choice.queue_free()
	_choice = null


func _action_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 50)
	b.add_theme_font_size_override("font_size", 18)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(st, %TakeButton.get_theme_stylebox(st))
	_make_bouncy(b)
	return b


func show_result(won: bool, title: String, text: String, score_text: String) -> void:
	set_actions(false, false, false)
	close_choice()
	%ResultTitle.text = title
	%ResultTitle.add_theme_color_override("font_color", COLOR_GOLD if won else Color(1, 0.5, 0.5))
	%ResultText.text = text
	%ResultScore.text = score_text
	%Result.visible = true
	%Dim.modulate.a = 0.0
	%ResultPanel.pivot_offset = %ResultPanel.size * 0.5
	%ResultPanel.scale = Vector2(0.6, 0.6)
	%ResultPanel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(%Dim, "modulate:a", 1.0, 0.4)
	tw.parallel().tween_property(%ResultPanel, "modulate:a", 1.0, 0.3).set_delay(0.15)
	tw.parallel().tween_property(%ResultPanel, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.15)
	tw.tween_callback(func() -> void: %ContinueButton.grab_focus())


# --- Hilfen -----------------------------------------------------------------------

## Breite für ein umbrechendes Label: so breit wie der Text, höchstens max_width.
func _text_width(label: Label, text: String, max_width: float) -> float:
	var font := label.get_theme_font("font")
	var fs := label.get_theme_font_size("font_size")
	return minf(max_width, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6)


func _show_score(value: float) -> void:
	_shown_score = value
	%ScoreLabel.text = str(int(round(value)))
	%ScoreBar.value = clampf(value / float(_target), 0.0, 1.0)


func _tween_key(key: String) -> Tween:
	var old: Tween = _tweens.get(key)
	if old != null and old.is_valid():
		old.kill()
	var tw := create_tween()
	_tweens[key] = tw
	return tw


func _pop(node: Control, amount: float) -> void:
	node.pivot_offset = node.size * 0.5
	var tw := _tween_key("pop_%d" % node.get_instance_id())
	node.scale = Vector2.ONE * amount
	tw.tween_property(node, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _shake(node: Control) -> void:
	var base := node.position
	var tw := _tween_key("shake_%d" % node.get_instance_id())
	for i in 6:
		tw.tween_property(node, "position", base + Vector2(randf_range(-6, 6), randf_range(-4, 4)), 0.04)
	tw.tween_property(node, "position", base, 0.05)


func _fade(node: CanvasItem, alpha: float, time: float) -> void:
	_tween_key("fade_%d" % node.get_instance_id()).tween_property(node, "modulate:a", alpha, time)


func _slide_in(node: Control, offset: Vector2, delay: float) -> void:
	node.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(delay + 0.05)
	tw.tween_callback(func() -> void:
		var target := node.position
		node.position = target + offset
		var t2 := create_tween()
		t2.tween_property(node, "position", target, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t2.parallel().tween_property(node, "modulate:a", 1.0, 0.35))


func _set_button(b: Button, show: bool) -> void:
	if b.visible == show:
		return
	b.visible = show
	if show:
		b.pivot_offset = Vector2(b.size.x * 0.5, b.size.y * 0.5)
		b.modulate.a = 0.0
		b.scale = Vector2(0.85, 0.85)
		var tw := _tween_key("btn_%d" % b.get_instance_id())
		tw.tween_property(b, "modulate:a", 1.0, 0.2)
		tw.parallel().tween_property(b, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _make_bouncy(b: Button) -> void:
	b.mouse_entered.connect(func() -> void:
		b.pivot_offset = b.size * 0.5
		_tween_key("hover_%d" % b.get_instance_id()).tween_property(b, "scale", Vector2(1.06, 1.06), 0.12))
	b.mouse_exited.connect(func() -> void:
		_tween_key("hover_%d" % b.get_instance_id()).tween_property(b, "scale", Vector2.ONE, 0.15))
	b.button_down.connect(func() -> void:
		b.pivot_offset = b.size * 0.5
		_tween_key("hover_%d" % b.get_instance_id()).tween_property(b, "scale", Vector2(0.95, 0.95), 0.06))
