class_name UIKit
extends RefCounted
## Gemeinsame Farben, Stile und kleine Animationen für alle Bildschirme.
## Alles statisch: UIKit.hover(button), UIKit.pop(label), UIKit.glass() …

# --- Farben (Lila-Nacht) ---------------------------------------------------------
const INK := Color(0.04, 0.028, 0.08)
const CREAM := Color(0.96, 0.91, 0.8)
const MUTED := Color(0.72, 0.66, 0.9)
const LILAC := Color(0.64, 0.55, 1.0)
const LINE := Color(0.6, 0.5, 1.0, 0.28)
const GOLD := Color(1, 0.82, 0.4)
const RED := Color(1, 0.38, 0.42)
const CHIPS := Color(0.36, 0.62, 1.0)
const MULT := Color(1, 0.36, 0.4)
const SUIT_COLORS := [Color(1, 0.42, 0.45), Color(1, 0.55, 0.4), Color(0.75, 0.9, 1.0), Color(0.82, 0.78, 1.0)]

const BRUSH := preload("res://assets/fonts/PermanentMarker-Regular.ttf")


# --- Stile --------------------------------------------------------------------------

## Dunkles Glas-Panel (Standard für HUD-Elemente).
static func glass(radius := 14, margin := Vector4(18, 14, 18, 14), alpha := 0.84) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.035, 0.1, alpha)
	st.border_color = LINE
	st.set_border_width_all(1)
	st.set_corner_radius_all(radius)
	st.content_margin_left = margin.x
	st.content_margin_top = margin.y
	st.content_margin_right = margin.z
	st.content_margin_bottom = margin.w
	st.shadow_color = Color(0, 0, 0, 0.45)
	st.shadow_size = 16
	st.shadow_offset = Vector2(0, 5)
	st.anti_aliasing_size = 1.0
	return st


## Farbige Kachel (z. B. Chips/Mult).
static func tile(color: Color, radius := 10) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = color.darkened(0.55)
	st.bg_color.a = 0.95
	st.border_color = color
	st.set_border_width_all(2)
	st.set_corner_radius_all(radius)
	st.content_margin_left = 10
	st.content_margin_right = 10
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	st.shadow_color = Color(color, 0.25)
	st.shadow_size = 10
	st.anti_aliasing_size = 1.0
	return st


static func label(text: String, size := 16, color := CREAM, variation := &"") -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# --- 3D-Ansichten -----------------------------------------------------------------

## SubViewport in echter Bildschirmauflösung rendern (statt der Basisauflösung
## hochzuskalieren). `scale` < 1 rendert absichtlich kleiner (z. B. für unscharfe Hintergründe).
static func fit_viewport(owner: Control, view: SubViewportContainer, vp: SubViewport, scale := 1.0) -> void:
	var canvas := owner.get_viewport_rect().size
	var pixels := Vector2(owner.get_tree().root.size)
	var factor := maxf(pixels.x / maxf(canvas.x, 1.0), 1.0) * scale
	view.stretch = false
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.position = Vector2.ZERO
	var px := Vector2i((canvas * factor).round())
	vp.size = px
	view.size = Vector2(px)
	view.scale = Vector2.ONE / factor


# --- Animationen ----------------------------------------------------------------------

## Kurz aufpoppen (Wert hat sich geändert).
static func pop(node: Control, amount := 1.2, time := 0.4) -> void:
	if node == null or not node.is_inside_tree():
		return
	node.pivot_offset = node.size * 0.5
	_kill(node, "pop")
	node.scale = Vector2.ONE * amount
	var tw := node.create_tween()
	node.set_meta("_tw_pop", tw)
	tw.tween_property(node, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Wackeln (z. B. großer Treffer).
static func shake(node: Control, strength := 6.0) -> void:
	if node == null or not node.is_inside_tree():
		return
	_kill(node, "shake")
	var base: Vector2 = node.get_meta("_shake_base", node.position)
	node.set_meta("_shake_base", base)
	var tw := node.create_tween()
	node.set_meta("_tw_shake", tw)
	for i in 7:
		var f := 1.0 - i / 7.0
		tw.tween_property(node, "position", base + Vector2(randf_range(-1, 1), randf_range(-0.7, 0.7)) * strength * f, 0.035)
	tw.tween_property(node, "position", base, 0.05)
	tw.tween_callback(func() -> void: node.remove_meta("_shake_base"))


## Weich einblenden und ein Stück hereinrutschen.
static func appear(node: CanvasItem, delay := 0.0, offset := Vector2(0, 16), time := 0.45) -> void:
	if node == null:
		return
	node.modulate.a = 0.0
	var ctrl := node as Control
	var tw := node.create_tween()
	if delay > 0:
		tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		var t2 := node.create_tween().set_parallel()
		if ctrl != null:
			var target := ctrl.position
			ctrl.position = target + offset
			t2.tween_property(ctrl, "position", target, time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		t2.tween_property(node, "modulate:a", 1.0, time * 0.8))


## Hover/Klick-Feedback für Knöpfe und Karten: leicht größer, beim Drücken kleiner.
static func hover(node: Control, scale := 1.05) -> void:
	node.mouse_entered.connect(func() -> void: _scale_to(node, scale, 0.14))
	node.mouse_exited.connect(func() -> void: _scale_to(node, 1.0, 0.18))
	node.focus_entered.connect(func() -> void: _scale_to(node, scale, 0.14))
	node.focus_exited.connect(func() -> void: _scale_to(node, 1.0, 0.18))
	if node is BaseButton:
		(node as BaseButton).button_down.connect(func() -> void: _scale_to(node, 0.96, 0.06))
		(node as BaseButton).button_up.connect(func() -> void: _scale_to(node, scale if node.get_global_rect().has_point(node.get_global_mouse_position()) else 1.0, 0.12))


## Sanftes Schweben (Idle-Animation), Phase pro Element verschieden.
static func float_idle(node: Control, amplitude := 4.0, period := 3.2, phase := 0.0) -> void:
	var tw := node.create_tween().set_loops()
	var base := node.position
	if phase > 0:
		tw.tween_interval(phase)
	tw.tween_property(node, "position:y", base.y - amplitude, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(node, "position:y", base.y + amplitude * 0.4, period * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Pulsierendes Leuchten über modulate (z. B. „du bist dran“).
static func pulse(node: CanvasItem, low := 0.65, period := 1.4) -> Tween:
	var tw := node.create_tween().set_loops()
	tw.tween_property(node, "modulate:a", low, period * 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "modulate:a", 1.0, period * 0.5).set_trans(Tween.TRANS_SINE)
	return tw


## Zahl hochzählen lassen.
static func count(label: Label, from: float, to: float, time := 0.6, fmt := "%d") -> Tween:
	_kill(label, "count")
	var tw := label.create_tween()
	label.set_meta("_tw_count", tw)
	tw.tween_method(func(v: float) -> void: label.text = fmt % roundi(v), from, to, time) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw


static func _scale_to(node: Control, s: float, time: float) -> void:
	if not node.is_inside_tree():
		return
	node.pivot_offset = node.size * 0.5
	_kill(node, "scale")
	var tw := node.create_tween()
	node.set_meta("_tw_scale", tw)
	tw.tween_property(node, "scale", Vector2.ONE * s, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func _kill(node: Object, key: String) -> void:
	if not node.has_meta("_tw_" + key):
		return
	var old: Variant = node.get_meta("_tw_" + key)
	if old is Tween and (old as Tween).is_valid():
		(old as Tween).kill()
