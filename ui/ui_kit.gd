class_name UIKit
extends RefCounted
## Gemeinsame Farben, Stile und kleine Animationen für alle Bildschirme.
## Alles statisch: UIKit.hover(button), UIKit.pop(label), UIKit.glass() …

# --- Farben (Plakat: Rot / Schwarz / Creme, Raum bleibt Lila-Nacht) ----------------
## Plakatfarben
const P_RED := Color(0.81, 0.15, 0.16)
const P_RED_DARK := Color(0.55, 0.08, 0.1)
const P_BLACK := Color(0.07, 0.055, 0.055)
const P_CREAM := Color(0.94, 0.89, 0.8)
const P_GOLD := Color(0.91, 0.71, 0.27)
## Text auf Plakatflächen (früher „Tinte auf Papier“)
const INK := Color(0.94, 0.89, 0.8)
const INK_RED := Color(0.96, 0.34, 0.3)
const INK_BLUE := Color(0.45, 0.7, 1.0)
const INK_SOFT := Color(0.94, 0.89, 0.8, 0.72)
## Text direkt auf dem dunklen Raum
const CREAM := Color(0.94, 0.89, 0.8)
const MUTED := Color(0.67, 0.63, 0.59)
const LILAC := Color(0.64, 0.55, 1.0)
const LINE := Color(0.81, 0.15, 0.16, 0.5)
const GOLD := Color(0.95, 0.74, 0.3)
const RED := Color(0.96, 0.34, 0.3)
const CHIPS := Color(0.67, 0.57, 1.0) # Lila wie das Nachtlicht (nicht Balatro-Blau)
const MULT := Color(0.91, 0.71, 0.27) # Gold (nicht Balatro-Rot)
const SUIT_COLORS := [Color(1, 0.42, 0.45), Color(1, 0.55, 0.4), Color(0.75, 0.9, 1.0), Color(0.82, 0.78, 1.0)]

const DISPLAY_FONT := preload("res://assets/fonts/RussoOne-Regular.ttf")
const BODY_FONT := preload("res://assets/fonts/Oswald-Variable.ttf")
const BRUSH := DISPLAY_FONT


const SYMBOL_FONT := preload("res://assets/fonts/DejaVuSans-Bold.ttf")
static var _fonts := {}


## Oswald in Stärke `weight` (200–700), optional mit Zeichenabstand.
static func body_font(weight := 400, spacing := 0) -> FontVariation:
	var key := "b%d_%d" % [weight, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var f := FontVariation.new()
	f.base_font = BODY_FONT
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	f.spacing_glyph = spacing
	f.fallbacks = [SYMBOL_FONT]
	_fonts[key] = f
	return f


## Russo One (Plakatschrift), optional mit Zeichenabstand.
static var _emoji: Font


## Farbige Emojis aus der Systemschrift (Windows: Segoe UI Emoji), sonst Textschrift.
static func emoji_font() -> Font:
	if _emoji == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Segoe UI Emoji", "Apple Color Emoji", "Noto Color Emoji"])
		f.fallbacks = [BODY_FONT]
		_emoji = f
	return _emoji


## Relikt/Item-Symbol wie in Slay the Spire: Emoji frei stehend mit dunklem Schatten.
static func relic_icon(emoji: String, box: float, font_size: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(box, box)
	c.pivot_offset = Vector2(box, box) * 0.5
	var shadow := poster_label(emoji, emoji_font(), font_size, P_CREAM)
	shadow.modulate = Color(0, 0, 0, 0.6) # Emoji als dunkle Silhouette = Schatten
	var icon := poster_label(emoji, emoji_font(), font_size, P_CREAM)
	for l: Label in [shadow, icon]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.size = Vector2(box, box)
		c.add_child(l)
	# immer mittig im Platz, auch wenn ein Container ihn größer macht
	var fit := func() -> void:
		var sz := c.size if c.size.x > 0.0 else Vector2(box, box)
		icon.position = Vector2.ZERO
		icon.size = sz
		shadow.size = sz
		shadow.position = Vector2(box, box) * 0.05
		c.pivot_offset = sz * 0.5
	c.resized.connect(fit)
	fit.call()
	return c


static func display_font(spacing := 0) -> FontVariation:
	var key := "d_%d" % spacing
	if _fonts.has(key):
		return _fonts[key]
	var f := FontVariation.new()
	f.base_font = DISPLAY_FONT
	f.spacing_glyph = spacing
	f.fallbacks = [SYMBOL_FONT]
	_fonts[key] = f
	return f


## Label mit Plakatschrift: `font` aus body_font()/display_font(), harter Schatten optional.
static func poster_label(text: String, font: Font, size: int, color := P_CREAM, hard_shadow := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if hard_shadow > 0:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("shadow_offset_x", hard_shadow)
		l.add_theme_constant_override("shadow_offset_y", hard_shadow)
	else:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# --- Stile --------------------------------------------------------------------------

static func _box(bg: Color, margin: Vector4, skew := 0.0) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.skew = Vector2(skew, 0)
	st.content_margin_left = margin.x
	st.content_margin_top = margin.y
	st.content_margin_right = margin.z
	st.content_margin_bottom = margin.w
	st.anti_aliasing_size = 0.8
	return st


## Schwarze Plakatfläche mit rotem Balken oben (Standard-Panel).
static func paper(margin := Vector4(20, 16, 20, 16), warm := false) -> StyleBoxFlat:
	var st := _box(Color(P_BLACK, 0.96), margin)
	st.border_width_top = 8 if warm else 5
	st.border_color = P_RED
	st.shadow_color = Color(0, 0, 0, 0.7)
	st.shadow_size = 1
	st.shadow_offset = Vector2(5, 6)
	return st


## Dunkler, leicht schräger Streifen (Text direkt über der Szene).
static func dark(margin := Vector4(16, 10, 16, 10)) -> StyleBoxFlat:
	return _box(Color(0.05, 0.04, 0.04, 0.88), margin, 0.12)


## Farbige, schräge Plakette (früher Stempelrahmen) in `color`.
static func stamp(color: Color, margin := Vector4(18, 8, 18, 8)) -> StyleBoxFlat:
	var st := _box(color, margin, 0.18)
	st.shadow_color = Color(0, 0, 0, 0.75)
	st.shadow_size = 1
	st.shadow_offset = Vector2(4, 4)
	return st


## Früher: Tintenkorn für Stempelschrift. Im Plakatstil nicht mehr nötig.
static func stamp_material(_amount := 0.45) -> Material:
	return null


## Leicht schief hinlegen (wie ein Zettel auf dem Tisch).
static func tilt(node: Control, degrees: float) -> void:
	node.pivot_offset = node.size * 0.5
	node.rotation_degrees = degrees
	node.resized.connect(func() -> void: node.pivot_offset = node.size * 0.5)

## Dunkles Panel (Altname, für ältere Stellen).
static func glass(_radius := 14, margin := Vector4(18, 14, 18, 14), alpha := 0.9) -> StyleBoxFlat:
	return _box(Color(P_BLACK, alpha), margin)


## Farbige Kachel (z. B. Chips/Mult).
static func tile(color: Color, _radius := 10) -> StyleBoxFlat:
	var st := _box(color, Vector4(10, 2, 10, 2), 0.15)
	st.shadow_color = Color(0, 0, 0, 0.75)
	st.shadow_size = 1
	st.shadow_offset = Vector2(3, 4)
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


## Roter Plakat-Keil oben links hinter einem Titel (Menü, Weg, Händler),
## optional mit kleiner Zeile im dunklen Streifen (z. B. Credits im Hauptmenü).
static func poster_wedge(owner: Control, size: Vector2, behind: Control, subline := "") -> Slab:
	var wedge := Slab.new()
	wedge.color = P_RED
	wedge.points = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0.84, 0.8), Vector2(0, 1)])
	wedge.extra = [PackedVector2Array([Vector2(0, 0.83), Vector2(0.86, 0.69), Vector2(0.84, 0.8), Vector2(0, 0.97)])]
	wedge.extra_colors = PackedColorArray([P_RED_DARK])
	wedge.shadow_offset = Vector2(6, 8)
	wedge.fit_children = false
	wedge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wedge.position = Vector2.ZERO
	wedge.size = size
	owner.add_child(wedge)
	owner.move_child(wedge, behind.get_index())
	if subline != "":
		var ru := poster_label(subline, body_font(600, 4), 12, Color(1, 0.8, 0.76))
		var y0 := size.y * 0.89
		ru.position = Vector2(64, y0 - 14)
		ru.rotation = atan2(-(0.14 * size.y), 0.86 * size.x)
		wedge.add_child(ru)
	return wedge


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
	# Retro-Look: nur die 3D-Welt wird grob gepixelt (kleiner rendern, scharf hochskalieren) –
	# Texte und Oberfläche bleiben lesbar
	var retro: bool = Settings.get_value("graphics/retro")
	if retro:
		scale *= 0.4
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if retro else CanvasItem.TEXTURE_FILTER_PARENT_NODE
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
		(node as BaseButton).pressed.connect(func() -> void: Sfx.play(&"button", randf_range(0.95, 1.05)))
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
