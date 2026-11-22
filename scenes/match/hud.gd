class_name MatchHUD
extends Control
## HUD des Duells im Stil „Papier & Tinte“ (siehe match.tscn):
##   links oben   Zettel mit Foto des Gegners, darunter der Zug als Stempel + Hinweis,
##                darunter seine Sprüche und das Spielprotokoll
##   rechts oben  Notizblock mit Punkten, Pokerchips für Chips × Mult
##   rechts       Trumpfzettel (Trumpf, Stapel, Angriff), „Schieben möglich“
##   unten links  Leben, Gold, Relikte (im Raum zusätzlich als Kerzen und Münzen)
##   unten rechts Aktionen als Etiketten mit Tastenkürzeln
## Die Spiellogik ruft nur die öffentlichen Funktionen auf (siehe match.gd).

enum Turn { ATTACK, DEFEND, WAIT, THROW_IN, OVER }

const TOAST_TIME := 4.5
const TOAST_MAX := 4
const COLOR_GOLD := UIKit.GOLD
const COLOR_TEXT := UIKit.CREAM
const COLOR_MUTED := UIKit.MUTED
## Stempelfarbe je Zug
const TURN_INK := {
	Turn.ATTACK: UIKit.INK_BLUE,
	Turn.DEFEND: UIKit.INK_RED,
	Turn.WAIT: Color(0.35, 0.32, 0.36),
	Turn.THROW_IN: UIKit.INK_BLUE,
	Turn.OVER: UIKit.INK_RED,
}
const TYPE_FONT := preload("res://assets/fonts/SpecialElite-Regular.ttf")
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
var _stamp_style: StyleBoxTexture
var _glow_target := 0.0
var _glow := 0.0
var _choice: Control
var _deck := -1
var _lives := -1
var _gold := -1


func _ready() -> void:
	_stamp_style = (%StampBox.get_theme_stylebox("panel") as StyleBoxTexture).duplicate() as StyleBoxTexture
	%StampBox.add_theme_stylebox_override("panel", _stamp_style)
	%TurnTitle.material = UIKit.stamp_material(0.4)
	%ResultTitle.material = UIKit.stamp_material(0.35)
	for b: Button in [%TakeButton, %PassButton, %ContinueButton]:
		UIKit.hover(b, 1.04)
	# Zettel liegen leicht schief
	UIKit.tilt.call_deferred(%OpponentNote, -1.2)
	UIKit.tilt.call_deferred(%TurnNote, 0.9)
	UIKit.tilt.call_deferred(%ScorePanel, 1.0)
	UIKit.tilt.call_deferred(%TablePanel, -1.6)
	UIKit.tilt.call_deferred(%RunBar, 0.8)
	UIKit.tilt.call_deferred(%Photo, 3.0)
	UIKit.tilt.call_deferred(%StampBox, -2.0)
	%TakeButton.visible = false
	%PassButton.visible = false
	%KeyHint.visible = false


func _process(delta: float) -> void:
	_t += delta
	if _thinking:
		var dots := int(_t * 3.0) % 4
		%ThinkLabel.text = %ThinkLabel.get_meta("base", "überlegt") + ".".repeat(dots)
	# Der Zettel „atmet“ leicht, wenn du dran bist
	var mine := _turn in [Turn.ATTACK, Turn.DEFEND, Turn.THROW_IN]
	var pulse := (sin(_t * 3.2) * 0.5 + 0.5) if mine else 0.0
	%TurnNote.self_modulate = Color(1, 1, 1).lerp(Color(1.08, 1.02, 0.92), pulse)
	_glow = move_toward(_glow, _glow_target, delta * 0.8)
	(%EdgeGlow.material as ShaderMaterial).set_shader_parameter("strength", _glow)


# --- Öffentliche Schnittstelle ---------------------------------------------------

func setup(opponent: OpponentData, target: int, floor_i := 0, floor_count := 1) -> void:
	%OpponentLabel.text = opponent.display_name
	%Portrait.texture = opponent.portrait
	%FloorLabel.text = ("BOSS · TISCH %d VON %d" if opponent.is_boss else "TISCH %d VON %d") % [floor_i + 1, floor_count]
	_target = maxi(1, target)
	%TargetLabel.text = "Ziel %d" % target
	UIKit.appear(%OpponentNote, 0.05, Vector2(-40, 0))
	UIKit.appear(%TurnNote, 0.15, Vector2(-40, 0))
	UIKit.appear(%ScorePanel, 0.1, Vector2(40, 0))
	UIKit.appear(%TablePanel, 0.22, Vector2(40, 0))
	UIKit.appear(%RunBar, 0.3, Vector2(0, 30))


## Wer ist dran und was kann man tun?
func set_turn(mode: int, title: String, hint: String) -> void:
	if title != _turn_title or mode != _turn:
		var ink: Color = TURN_INK[mode]
		%TurnTitle.add_theme_color_override("font_color", ink)
		_stamp_style.modulate_color = ink
		%TurnTitle.text = title
		_stamp_slam()
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
		card.custom_minimum_size = Vector2(9, 14)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0.3, 0.12, 0.14)
		st.border_color = UIKit.INK
		st.set_border_width_all(1)
		card.add_theme_stylebox_override("panel", st)
		%OpponentCards.add_child(card)
	var label := Label.new()
	label.theme_type_variation = &"InkType"
	label.add_theme_font_size_override("font_size", 13)
	label.text = "  %d %s" % [count, "Karte" if count == 1 else "Karten"]
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
	var tw := _tween_key(%Speech, "say")
	%Speech.modulate.a = 0.0
	%Speech.position.y = 208
	tw.tween_property(%Speech, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(%Speech, "position:y", 218.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
			UIKit.count(%GoldLabel, _gold, gold, 0.6, "%d Gold")
			UIKit.pop(%GoldLabel, 1.25)
		else:
			%GoldLabel.text = "%d Gold" % gold
		_gold = gold
	if deck != _deck:
		%DeckLabel.text = "Stapel %d" % deck if deck > 0 else "Stapel leer"
		%DeckLabel.add_theme_color_override("font_color", UIKit.INK_RED if deck == 0 else UIKit.INK_SOFT)
		_deck = deck
	%TrumpSymbol.text = Card.SUIT_SYMBOLS[trump_suit]
	%TrumpSymbol.add_theme_color_override("font_color", UIKit.INK_RED if trump_suit <= 1 else UIKit.INK)
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
		var l := Label.new()
		l.theme_type_variation = &"InkLabel"
		l.add_theme_font_size_override("font_size", 18)
		l.text = RELIC_SYMBOLS.get(r.id, r.display_name.left(1))
		l.tooltip_text = "%s – %s" % [r.display_name, r.description]
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		%Relics.add_child(l)


func set_score(total: int, target: int, chips: int, mult: int, sub_text: String) -> void:
	_target = maxi(1, target)
	%TargetLabel.text = "Ziel %d" % target
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
		%ScoreLabel.add_theme_color_override("font_color", UIKit.INK_RED)


## Eine Runde wurde gewertet: Punkte fliegen von Chips × Mult zur Punktzahl.
func bout_scored(points: int, text: String) -> void:
	toast(text, COLOR_GOLD if points > 0 else COLOR_MUTED)
	if points <= 0:
		return
	var big := text.begins_with("Volltreffer") or text.begins_with("Durak")
	var start: Vector2 = %ChipsBox.get_global_rect().get_center().lerp(%MultBox.get_global_rect().get_center(), 0.5)
	var end_pos: Vector2 = %ScoreLabel.get_global_rect().get_center()
	var label := UIKit.label("+%d" % points, 56 if big else 42, Color(1, 0.86, 0.55), &"BrushLabel")
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.08))
	label.add_theme_constant_override("outline_size", 10)
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
	pill.add_theme_stylebox_override("panel", UIKit.dark(Vector4(12, 5, 12, 6)))
	var label := UIKit.label(text, 14, color, &"TypeLabel")
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
	panel.add_theme_stylebox_override("panel", UIKit.paper(Vector4(18, 16, 18, 16), true))
	%Actions.add_child(panel)
	%Actions.move_child(panel, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var label := Label.new()
	label.theme_type_variation = &"InkLabel"
	label.add_theme_font_size_override("font_size", 16)
	label.text = title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	for i in options.size():
		var b := Button.new()
		b.text = options[i]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 50)
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
	cancel.custom_minimum_size = Vector2(0, 42)
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
	var ink := UIKit.INK_BLUE if won else UIKit.INK_RED
	%ResultTitle.add_theme_color_override("font_color", ink)
	var st := (%StampBox2.get_theme_stylebox("panel") as StyleBoxTexture).duplicate() as StyleBoxTexture
	st.modulate_color = ink
	%StampBox2.add_theme_stylebox_override("panel", st)
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
	tw.tween_callback(func() -> void:
		%ContinueButton.grab_focus()
		%StampBox2.pivot_offset = %StampBox2.size * 0.5
		%StampBox2.rotation_degrees = -4.0
		%StampBox2.scale = Vector2(1.6, 1.6)
		var t2 := %StampBox2.create_tween()
		t2.tween_property(%StampBox2, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t2.tween_callback(func() -> void: UIKit.shake(%ResultPanel, 5.0)))


func is_result_open() -> bool:
	return %Result.visible


# --- Hilfen -----------------------------------------------------------------------

## Breite für ein umbrechendes Label: so breit wie der Text, höchstens max_width.
func _text_width(label: Label, text: String, max_width: float) -> float:
	var fs := label.get_theme_font_size("font_size")
	if label.has_theme_font_size_override("font_size"):
		fs = label.get_theme_font_size("font_size")
	return minf(max_width, TYPE_FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8)


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


## Stempel „knallt“ auf den Zettel.
func _stamp_slam() -> void:
	var box: Control = %StampBox
	box.pivot_offset = box.size * 0.5
	var tw := _tween_key(box, "slam")
	box.scale = Vector2(1.45, 1.45)
	box.modulate.a = 0.0
	box.rotation_degrees = randf_range(-3.5, 1.0)
	tw.tween_property(box, "modulate:a", 1.0, 0.08)
	tw.parallel().tween_property(box, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: UIKit.shake(%TurnNote, 3.0))


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
