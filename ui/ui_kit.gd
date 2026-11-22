class_name UIKit
extends RefCounted
## Gemeinsame Farben, Stile und kleine Animationen für alle Bildschirme.
## Alles statisch: UIKit.hover(button), UIKit.pop(label), UIKit.glass() …

# --- Farben (Papier & Tinte, Raum bleibt Lila-Nacht) -------------------------------
## Tinte auf Papier
const INK := Color(0.12, 0.094, 0.12)
const INK_RED := Color(0.62, 0.14, 0.125)
const INK_BLUE := Color(0.16, 0.27, 0.55)
const INK_SOFT := Color(0.12, 0.094, 0.12, 0.72)
## Text direkt auf dem dunklen Raum
const CREAM := Color(0.93, 0.89, 0.8)
const MUTED := Color(0.74, 0.7, 0.66)
const LILAC := Color(0.64, 0.55, 1.0)
const LINE := Color(0.6, 0.5, 1.0, 0.28)
const GOLD := Color(1, 0.82, 0.4)
const RED := Color(1, 0.38, 0.42)
const CHIPS := Color(0.36, 0.62, 1.0)
const MULT := Color(1, 0.36, 0.4)
const SUIT_COLORS := [Color(1, 0.42, 0.45), Color(1, 0.55, 0.4), Color(0.75, 0.9, 1.0), Color(0.82, 0.78, 1.0)]

const BRUSH := preload("res://assets/fonts/RuslanDisplay-Regular.ttf")
const STAMP_SHADER := preload("res://ui/ink_stamp.gdshader")
const GRAIN := preload("res://assets/ui/ink_grain.png")
const PAPER := preload("res://assets/ui/paper.png")
const PAPER_WARM := preload("res://assets/ui/paper_warm.png")
const PAPER_DARK := preload("res://assets/ui/paper_dark.png")
const STAMP_FRAME := preload("res://assets/ui/stamp_frame.png")


# --- Stile --------------------------------------------------------------------------

## Papierzettel mit gerissenen Kanten.
static func paper(margin := Vector4(20, 16, 20, 16), warm := false) -> StyleBoxTexture:
	return _tex(PAPER_WARM if warm else PAPER, 30, margin)


## Dunkler Papierstreifen (für Text direkt über der Szene).
static func dark(margin := Vector4(16, 10, 16, 10)) -> StyleBoxTexture:
	return _tex(PAPER_DARK, 20, margin)


## Stempelrahmen in Farbe `color`.
static func stamp(color: Color, margin := Vector4(18, 8, 18, 8)) -> StyleBoxTexture:
	var st := _tex(STAMP_FRAME, 18, margin)
	st.modulate_color = color
	return st


## Material für gestempelte Schrift (ungleichmäßige Tinte).
static func stamp_material(amount := 0.45) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = STAMP_SHADER
	m.set_shader_parameter("grain", GRAIN)
	m.set_shader_parameter("amount", amount)
	return m


static func _tex(tex: Texture2D, edge: float, margin: Vector4) -> StyleBoxTexture:
	var st := StyleBoxTexture.new()
	st.texture = tex
	st.texture_margin_left = edge
	st.texture_margin_top = edge
	st.texture_margin_right = edge
	st.texture_margin_bottom = edge
	st.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	st.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	st.content_margin_left = margin.x
	st.content_margin_top = margin.y
	st.content_margin_right = margin.z
	st.content_margin_bottom = margin.w
	return st


## Leicht schief hinlegen (wie ein Zettel auf dem Tisch).
static func tilt(node: Control, degrees: float) -> void:
	node.pivot_offset = node.size * 0.5
	node.rotation_degrees = degrees
	node.resized.connect(func() -> void: node.pivot_offset = node.size * 0.5)

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


# --- Meldungen ----------------------------------------------------------------------

## Zeigt frisch freigeschaltete Decks als Zettel mit Rückseite (rechts unten, nacheinander).
static func show_unlocks(owner: Control) -> void:
	var list := Profile.take_pending_unlocks()
	for i in list.size():
		var d: DeckData = list[i]
		var note := PanelContainer.new()
		note.add_theme_stylebox_override("panel", paper(Vector4(18, 14, 22, 16), true))
		note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		note.add_child(row)
		var pic := TextureRect.new()
		pic.texture = d.back
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(54, 76)
		row.add_child(pic)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(col)
		var h := Label.new()
		h.theme_type_variation = &"InkHeader"
		h.text = "NEUES DECK"
		col.add_child(h)
		var n := Label.new()
		n.theme_type_variation = &"InkTitle"
		n.add_theme_font_size_override("font_size", 22)
		n.text = d.display_name
		col.add_child(n)
		var t := Label.new()
		t.theme_type_variation = &"InkType"
		t.add_theme_font_size_override("font_size", 14)
		t.text = d.effect_text
		col.add_child(t)
		owner.add_child(note)
		note.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		note.position = Vector2(owner.size.x - 400, 140 + i * 120)
		note.rotation_degrees = -1.5
		note.modulate.a = 0.0
		var tw := note.create_tween()
		tw.tween_interval(0.6 + i * 0.5)
		tw.tween_property(note, "modulate:a", 1.0, 0.3)
		tw.parallel().tween_property(note, "position:x", owner.size.x - 420, 0.4).from(owner.size.x - 300).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(4.5)
		tw.tween_property(note, "modulate:a", 0.0, 0.6)
		tw.tween_callback(note.queue_free)


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
