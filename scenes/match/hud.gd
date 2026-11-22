class_name MatchHUD
extends Control
## HUD des Duells. Aufbau (siehe match.tscn):
##   oben links   Gegner-Plakette (Porträt, Name, Tisch x/y, Kartenzahl, „überlegt …“) + Sprechblase
##   oben Mitte   Zug-Anzeige: wer ist dran, was kann man tun
##   oben rechts  Punkte (Chips × Mult, Fortschritt zum Ziel)
##   rechts       Trumpf, Stapel, Angriffskarten dieser Runde, „Schieben möglich“
##   unten links  Leben, Gold, Relikte (im Raum zusätzlich als Kerzen und Münzen)
##   unten rechts Aktionen mit Tastenkürzeln
## Die Spiellogik ruft nur die öffentlichen Funktionen auf (siehe match.gd).

enum Turn { ATTACK, DEFEND, WAIT, THROW_IN, OVER }

const TOAST_TIME := 4.5
const TOAST_MAX := 4
const COLOR_GOLD := UIKit.GOLD
const COLOR_TEXT := UIKit.CREAM
const COLOR_MUTED := UIKit.MUTED
const TURN_STYLE := {
	Turn.ATTACK: ["⚔", UIKit.GOLD],
	Turn.DEFEND: ["⛨", UIKit.RED],
	Turn.WAIT: ["⌛", UIKit.LILAC],
	Turn.THROW_IN: ["✚", UIKit.GOLD],
	Turn.OVER: ["✦", UIKit.CREAM],
}
const RELIC_SYMBOLS := {&"ace_up_sleeve": "A", &"lucky_coin": "●", &"samovar": "♨", &"vodka": "✶"}

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
var _turn_style: StyleBoxFlat
var _glow_target := 0.0
var _glow := 0.0
var _choice: Control
var _deck := -1
var _lives := -1
var _gold := -1


func _ready() -> void:
	_turn_style = (%TurnPill.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	%TurnPill.add_theme_stylebox_override("panel", _turn_style)
	for b: Button in [%TakeButton, %PassButton, %ContinueButton]:
		UIKit.hover(b, 1.04)
	%TakeButton.visible = false
	%PassButton.visible = false
	%KeyHint.visible = false


func _process(delta: float) -> void:
	_t += delta
	if _thinking:
		var dots := int(_t * 3.0) % 4
		%ThinkLabel.text = %ThinkLabel.get_meta("base", "überlegt") + ".".repeat(dots)
	# Zug-Anzeige atmet, wenn du dran bist
	var mine := _turn in [Turn.ATTACK, Turn.DEFEND, Turn.THROW_IN]
	var pulse := (sin(_t * 3.6) * 0.5 + 0.5) if mine else 0.0
	var col: Color = TURN_STYLE.get(_turn, TURN_STYLE[Turn.WAIT])[1]
	_turn_style.border_color = Color(col, 0.35 + 0.5 * pulse)
	_turn_style.shadow_color = Color(col, 0.08 + 0.22 * pulse)
	%Portrait.intensity = move_toward(%Portrait.intensity, 1.0 if _thinking else 0.0, delta * 2.0)
	_glow = move_toward(_glow, _glow_target, delta * 0.8)
	(%EdgeGlow.material as ShaderMaterial).set_shader_parameter("strength", _glow)


# --- Öffentliche Schnittstelle ---------------------------------------------------

func setup(opponent: OpponentData, target: int, floor_i := 0, floor_count := 1) -> void:
	%OpponentLabel.text = opponent.display_name
	%Portrait.mask_color = opponent.mask_color
	%Portrait.eye_color = opponent.eye_color
	%Portrait.portrait = opponent.portrait
	%FloorLabel.text = ("BOSS · TISCH %d VON %d" if opponent.is_boss else "TISCH %d VON %d") % [floor_i + 1, floor_count]
	if opponent.is_boss:
		%FloorLabel.add_theme_color_override("font_color", UIKit.RED)
	_target = maxi(1, target)
	%TargetLabel.text = "ZIEL %d" % target
	UIKit.appear(%OpponentPlate, 0.05, Vector2(-30, 0))
	UIKit.appear(%ScorePanel, 0.12, Vector2(30, 0))
	UIKit.appear(%TurnPill, 0.2, Vector2(0, -20))
	UIKit.appear(%TablePanel, 0.28, Vector2(30, 0))
	UIKit.appear(%RunBar, 0.34, Vector2(0, 20))


## Wer ist dran und was kann man tun?
func set_turn(mode: int, title: String, hint: String) -> void:
	if title != _turn_title or mode != _turn:
		var style: Array = TURN_STYLE[mode]
		%TurnIcon.text = style[0]
		%TurnIcon.add_theme_color_override("font_color", style[1])
		%TurnTitle.add_theme_color_override("font_color", style[1])
		%TurnTitle.text = title
		if mode != _turn:
			UIKit.pop(%TurnPill, 1.08, 0.45)
		_turn = mode
		_turn_title = title
	%TurnHint.text = hint
	# roter Rand, wenn du dich verteidigen musst (stärker bei vielen offenen Karten)
	_glow_target = 0.0
	if mode == Turn.DEFEND:
		_glow_target = 0.12
	(%EdgeGlow.material as ShaderMaterial).set_shader_parameter("glow_color", UIKit.RED)


func set_danger(strength: float) -> void:
	_glow_target = maxf(_glow_target, strength)


func set_opponent_cards(count: int) -> void:
	if count == _opp_cards:
		return
	var grew := count > _opp_cards and _opp_cards >= 0
	_opp_cards = count
	for c in %OpponentCards.get_children():
		c.queue_free()
	for i in mini(count, 12):
		var card := Panel.new()
		card.custom_minimum_size = Vector2(10, 15)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.36, 0.26, 0.7)
		st.border_color = Color(0.96, 0.91, 0.8, 0.9)
		st.set_border_width_all(1)
		st.set_corner_radius_all(2)
		card.add_theme_stylebox_override("panel", st)
		%OpponentCards.add_child(card)
	var label := UIKit.label("  %d %s" % [count, "Karte" if count == 1 else "Karten"], 13, COLOR_MUTED)
	%OpponentCards.add_child(label)
	if grew:
		UIKit.pop(%OpponentCards, 1.12)


func set_thinking(thinking: bool, text: String = "") -> void:
	_thinking = thinking
	if thinking:
		%ThinkLabel.set_meta("base", text)
	var tw := %ThinkLabel.create_tween()
	tw.tween_property(%ThinkLabel, "modulate:a", 1.0 if thinking else 0.0, 0.25)


## Sprechblase unter der Plakette (Sticheleien des Gegners).
func say(text: String, time := 4.0) -> void:
	%SpeechLabel.text = "„%s“" % text
	%Speech.reset_size()
	var tw := %Speech.create_tween()
	%Speech.modulate.a = 0.0
	%Speech.position.y = 104
	tw.tween_property(%Speech, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(%Speech, "position:y", 114.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(time)
	tw.tween_property(%Speech, "modulate:a", 0.0, 0.5)


func set_run_info(lives: int, gold: int, deck: int, trump_suit: int) -> void:
	if lives != _lives:
		%LivesLabel.text = "♥".repeat(maxi(0, lives)) if lives <= 6 else "♥ %d" % lives
		if _lives >= 0:
			UIKit.pop(%LivesLabel, 1.3)
		_lives = lives
	if gold != _gold:
		if _gold >= 0 and gold > _gold:
			UIKit.count(%GoldLabel, _gold, gold, 0.6, "● %d")
			UIKit.pop(%GoldLabel, 1.25)
		else:
			%GoldLabel.text = "● %d" % gold
		_gold = gold
	if deck != _deck:
		%DeckLabel.text = "Stapel %d" % deck if deck > 0 else "Stapel leer"
		%DeckLabel.add_theme_color_override("font_color", UIKit.RED if deck == 0 else COLOR_TEXT)
		_deck = deck
	%TrumpSymbol.text = Card.SUIT_SYMBOLS[trump_suit]
	%TrumpSymbol.add_theme_color_override("font_color", UIKit.SUIT_COLORS[trump_suit])
	%TrumpName.text = Card.SUIT_NAMES[trump_suit]


## Angriffskarten dieser Runde (x von höchstens y) und ob Schieben gerade geht.
func set_bout(attack_count: int, limit: int, can_transfer: bool) -> void:
	%BoutInfo.text = "Angriff %d / %d" % [attack_count, limit] if attack_count > 0 else "Tisch leer"
	if %TransferHint.visible != can_transfer:
		%TransferHint.visible = can_transfer
		if can_transfer:
			UIKit.pop(%TransferHint, 1.3)


func set_relics(relics: Array) -> void:
	for c in %Relics.get_children():
		c.queue_free()
	for r: RelicData in relics:
		var chip := PanelContainer.new()
		var st := UIKit.tile(UIKit.LILAC, 7)
		st.content_margin_left = 6
		st.content_margin_right = 6
		chip.add_theme_stylebox_override("panel", st)
		chip.tooltip_text = "%s – %s" % [r.display_name, r.description]
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		var l := UIKit.label(RELIC_SYMBOLS.get(r.id, r.display_name.left(1)), 15, UIKit.CREAM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(16, 0)
		chip.add_child(l)
		%Relics.add_child(chip)


func set_score(total: int, target: int, chips: int, mult: int, sub_text: String) -> void:
	_target = maxi(1, target)
	%TargetLabel.text = "ZIEL %d" % target
	if total != _score:
		var from := _shown_score
		_score = total
		var tw := %ScoreLabel.create_tween()
		tw.tween_method(_show_score, from, float(total), 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		UIKit.pop(%ScoreLabel, 1.25)
	else:
		_show_score(total)
	if chips != _chips:
		if chips > _chips:
			UIKit.pop(%ChipsBox, 1.18)
		_chips = chips
	if mult != _mult:
		if mult > _mult:
			UIKit.pop(%MultBox, 1.18)
		_mult = mult
	%ChipsLabel.text = str(chips)
	%MultLabel.text = str(mult)
	%BoutLabel.text = sub_text
	if total >= target:
		%ScoreLabel.add_theme_color_override("font_color", COLOR_GOLD)


## Eine Runde wurde gewertet: Punkte fliegen von Chips × Mult zur Punktzahl.
func bout_scored(points: int, text: String) -> void:
	toast(text, COLOR_GOLD if points > 0 else COLOR_MUTED)
	if points <= 0:
		return
	var big := text.begins_with("Volltreffer") or text.begins_with("Durak")
	var start: Vector2 = %ChipsBox.get_global_rect().get_center().lerp(%MultBox.get_global_rect().get_center(), 0.5)
	var end_pos: Vector2 = %ScoreLabel.get_global_rect().get_center()
	var label := UIKit.label("+%d" % points, 56 if big else 40, COLOR_GOLD, &"BrushLabel")
	label.add_theme_color_override("font_outline_color", Color(0.12, 0.06, 0.25))
	label.add_theme_constant_override("outline_size", 12)
	%FloatLayer.add_child(label)
	label.reset_size()
	label.pivot_offset = label.size * 0.5
	label.global_position = start - label.size * 0.5 + Vector2(-60, 70)
	label.scale = Vector2(0.3, 0.3)
	var tw := label.create_tween()
	tw.tween_property(label, "scale", Vector2.ONE * (1.3 if big else 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.35)
	tw.tween_property(label, "global_position", end_pos - label.size * 0.5, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(label, "scale", Vector2(0.5, 0.5), 0.45)
	tw.parallel().tween_property(label, "modulate:a", 0.0, 0.45).set_delay(0.2)
	tw.tween_callback(label.queue_free)
	if big:
		UIKit.shake(%ScorePanel, 7.0)
		(%EdgeGlow.material as ShaderMaterial).set_shader_parameter("glow_color", COLOR_GOLD)
		_glow = 0.6
		_glow_target = 0.0


## Kurze Meldung links (Spielprotokoll), blendet nach ein paar Sekunden aus.
func toast(text: String, color: Color = COLOR_TEXT) -> void:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.04, 0.03, 0.08, 0.7)
	st.set_corner_radius_all(8)
	st.content_margin_left = 12
	st.content_margin_right = 12
	st.content_margin_top = 4
	st.content_margin_bottom = 5
	st.border_width_left = 3
	st.border_color = Color(color, 0.8)
	pill.add_theme_stylebox_override("panel", st)
	var label := UIKit.label(text, 14, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = _text_width(label, text, 320)
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


## Großes Banner in der Bildmitte („DEIN ANGRIFF“ …) mit Tintenbalken.
func show_banner(text: String, color: Color = Color(1, 0.86, 0.5)) -> void:
	%BannerLabel.text = text
	%BannerLabel.add_theme_color_override("font_color", color)
	%BannerLabel.pivot_offset = %BannerLabel.size * 0.5
	%BannerBar.pivot_offset = %BannerBar.size * 0.5
	var tw := _tween_key(%Banner, "banner")
	%Banner.modulate.a = 0.0
	%BannerBar.scale = Vector2(0.0, 1.0)
	%BannerLabel.scale = Vector2(0.75, 0.75)
	tw.tween_property(%Banner, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(%BannerBar, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(%BannerLabel, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.75)
	tw.tween_property(%Banner, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(%BannerBar, "scale", Vector2(1.15, 0.6), 0.3)


func set_actions(take_visible: bool, pass_visible: bool, pass_enabled: bool, pass_text := "BITO") -> void:
	_set_button(%TakeButton, take_visible)
	_set_button(%PassButton, pass_visible)
	%PassButton.disabled = not pass_enabled
	%PassButton.text = pass_text
	var hints := PackedStringArray()
	if pass_visible:
		hints.append("Leertaste: %s" % pass_text.capitalize())
	if take_visible:
		hints.append("E: Nehmen")
	%KeyHint.text = " · ".join(hints)
	%KeyHint.visible = not hints.is_empty()


## Kleine Auswahl rechts bei den Aktionen (z. B. „Schlagen oder Schieben?“).
## `callback` bekommt den Index der gewählten Option; Abbrechen ruft nichts auf.
func ask_choice(title: String, options: Array[String], callback: Callable) -> void:
	close_choice()
	var panel := PanelContainer.new()
	_choice = panel
	panel.add_theme_stylebox_override("panel", UIKit.glass(12, Vector4(14, 12, 14, 12), 0.94))
	%Actions.add_child(panel)
	%Actions.move_child(panel, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var label := UIKit.label(title, 15, COLOR_GOLD)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 46)
		if i == options.size() - 1:
			b.theme_type_variation = &"PrimaryButton"
		UIKit.hover(b, 1.04)
		var index := i
		b.pressed.connect(func() -> void:
			close_choice()
			callback.call(index))
		box.add_child(b)
	var cancel := Button.new()
	cancel.text = "ABBRECHEN"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.custom_minimum_size = Vector2(0, 36)
	cancel.add_theme_font_size_override("font_size", 13)
	cancel.pressed.connect(close_choice)
	box.add_child(cancel)
	UIKit.appear(panel, 0.0, Vector2(20, 0), 0.25)


func close_choice() -> void:
	if _choice != null and is_instance_valid(_choice):
		_choice.queue_free()
	_choice = null


func show_result(won: bool, title: String, text: String, score_text: String) -> void:
	set_actions(false, false, false)
	close_choice()
	_glow_target = 0.0
	%ResultHeader.text = "DUELL GEWONNEN" if won else "DUELL VERLOREN"
	%ResultTitle.text = title
	%ResultTitle.add_theme_color_override("font_color", COLOR_GOLD if won else Color(1, 0.5, 0.5))
	%ResultText.text = text
	%ResultScore.text = score_text
	%Result.visible = true
	%Dim.modulate.a = 0.0
	%ResultPanel.pivot_offset = %ResultPanel.size * 0.5
	%ResultPanel.scale = Vector2(0.7, 0.7)
	%ResultPanel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(%Dim, "modulate:a", 1.0, 0.4)
	tw.parallel().tween_property(%ResultPanel, "modulate:a", 1.0, 0.3).set_delay(0.15)
	tw.parallel().tween_property(%ResultPanel, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.15)
	tw.tween_callback(func() -> void: %ContinueButton.grab_focus())


func is_result_open() -> bool:
	return %Result.visible


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


func _tween_key(node: Node, key: String) -> Tween:
	if node.has_meta("_tw_" + key):
		var old: Variant = node.get_meta("_tw_" + key)
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tw := node.create_tween()
	node.set_meta("_tw_" + key, tw)
	return tw


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
