class_name OptionsMenu
extends Control
## Optionen-Fenster (Grafik, Audio, Allgemein). Wird als Overlay über jede Szene
## gelegt (Hauptmenü, Pause-Menü) und schreibt direkt in das Autoload „Settings“.
##     var menu := OptionsMenu.new(); add_child(menu); menu.closed.connect(...)

signal closed

const SECTIONS := [["GRAFIK", "graphics"], ["AUDIO", "audio"], ["ALLGEMEIN", "general"]]
const COLOR_GOLD := UIKit.INK_RED
const COLOR_MUTED := UIKit.INK_SOFT
const LABEL_WIDTH := 300.0

var _page: VBoxContainer
var _tab_buttons: Array[Button] = []
var _section := 0
var _resolution_option: OptionButton
var _panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(820, 600)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "OPTIONEN"
	title.theme_type_variation = &"InkTitle"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	box.add_child(tabs)
	var group := ButtonGroup.new()
	for i in SECTIONS.size():
		var b := Button.new()
		b.text = SECTIONS[i][0]
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(180, 46)
		var index := i
		b.pressed.connect(func() -> void: _show_section(index))
		tabs.add_child(b)
		_tab_buttons.append(b)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 22)
	scroll.add_child(margin)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 10)
	margin.add_child(_page)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	box.add_child(bottom)
	var reset := Button.new()
	reset.text = "STANDARD"
	reset.custom_minimum_size = Vector2(180, 48)
	reset.pressed.connect(func() -> void:
		Settings.reset_section(SECTIONS[_section][1])
		_show_section(_section))
	bottom.add_child(reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var back := Button.new()
	back.theme_type_variation = &"PrimaryButton"
	back.text = "ZURÜCK"
	back.custom_minimum_size = Vector2(180, 48)
	back.pressed.connect(close)
	bottom.add_child(back)

	_tab_buttons[0].button_pressed = true
	_show_section(0)
	_tab_buttons[0].grab_focus()

	_panel.pivot_offset = _panel.custom_minimum_size * 0.5
	_panel.scale = Vector2(0.92, 0.92)
	modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	closed.emit()
	queue_free()


# --- Seiten ---------------------------------------------------------------------

func _show_section(index: int) -> void:
	_section = index
	_tab_buttons[index].button_pressed = true
	if is_inside_tree():
		_tab_buttons[index].grab_focus()
	for i in _tab_buttons.size():
		if i == index:
			_tab_buttons[i].add_theme_color_override("font_color", COLOR_GOLD)
			_tab_buttons[i].add_theme_color_override("font_pressed_color", COLOR_GOLD)
			_tab_buttons[i].add_theme_color_override("font_focus_color", COLOR_GOLD)
		else:
			_tab_buttons[i].remove_theme_color_override("font_color")
			_tab_buttons[i].remove_theme_color_override("font_pressed_color")
			_tab_buttons[i].remove_theme_color_override("font_focus_color")
	for c in _page.get_children():
		c.queue_free()
	match SECTIONS[index][1]:
		"graphics":
			_build_graphics()
		"audio":
			_build_audio()
		"general":
			_build_general()


func _build_graphics() -> void:
	_heading("Anzeige")
	_option("Anzeigemodus", "graphics/window_mode", Settings.WINDOW_MODE_NAMES)
	var res_names: Array = []
	for r in Settings.RESOLUTIONS:
		res_names.append("%d × %d" % [r.x, r.y])
	_resolution_option = _option("Fenstergröße", "graphics/resolution", res_names)
	_update_resolution_enabled()
	_toggle("VSync", "graphics/vsync")
	var fps_names: Array = []
	for f in Settings.FPS_LIMITS:
		fps_names.append("Unbegrenzt" if f == 0 else "%d FPS" % f)
	_option("Bildrate begrenzen", "graphics/fps_limit", fps_names)
	_heading("Qualität")
	_option("Kantenglättung", "graphics/msaa", Settings.MSAA_NAMES)
	_slider("Renderauflösung", "graphics/render_scale", 0.5, 1.0, 0.05, _percent)
	_option("Schatten", "graphics/shadows", Settings.QUALITY_NAMES)
	_toggle("Leuchteffekte (Glow)", "graphics/glow")
	_slider("Helligkeit", "graphics/brightness", 0.6, 1.4, 0.05, _percent)


func _build_audio() -> void:
	_heading("Lautstärke")
	_slider("Gesamt", "audio/master", 0.0, 1.0, 0.05, _percent)
	_slider("Musik", "audio/music", 0.0, 1.0, 0.05, _percent)
	_slider("Effekte", "audio/sfx", 0.0, 1.0, 0.05, _percent)
	_heading("Sonstiges")
	_toggle("Im Hintergrund stumm", "audio/mute_unfocused")
	_note("Die Musik startet bewusst leise (20 %). Alle Regler wirken sofort.")


func _build_general() -> void:
	_heading("Spiel")
	_option("Bedenkzeit der Gegner", "general/ai_speed", Settings.SPEED_NAMES)
	_option("Kartenanimationen", "general/anim_speed", Settings.SPEED_NAMES)
	_toggle("Spielmeldungen einblenden", "general/messages")
	_toggle("Kamera schwenkt mit der Maus", "general/camera_sway")
	_heading("Run")
	_option("Schwierigkeit", "general/difficulty", Settings.DIFFICULTY_NAMES)
	_toggle("Hinweise (spielbare Karten leuchten)", "general/hints")
	_toggle("Tutorial im Hauptmenü anzeigen", "general/show_tutorial")
	_note("Schwierigkeit und Hinweise gelten ab dem nächsten Run. Ohne Hinweise gibt es ×1,5 Seelen.")
	_heading("Oberfläche")
	_slider("Größe der Oberfläche", "general/ui_scale", 0.8, 1.3, 0.05, _percent)
	var lang := _option("Sprache", "", ["Deutsch"])
	lang.disabled = true
	_note("Weitere Sprachen folgen.")


# --- Bausteine ------------------------------------------------------------------

func _heading(text: String) -> void:
	var l := Label.new()
	l.text = text.to_upper()
	l.theme_type_variation = &"InkHeader"
	if _page.get_child_count() > 0:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 6)
		_page.add_child(gap)
	_page.add_child(l)


func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.theme_type_variation = &"InkType"
	l.add_theme_font_size_override("font_size", 14)
	_page.add_child(l)


func _row(text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override("font_size", 17)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	_page.add_child(row)


func _option(text: String, key: String, names: Array) -> OptionButton:
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(0, 40)
	for n in names:
		opt.add_item(str(n))
	opt.get_popup().add_theme_font_size_override("font_size", 16)
	if not key.is_empty():
		opt.select(clampi(int(Settings.get_value(key)), 0, names.size() - 1))
		opt.item_selected.connect(func(i: int) -> void:
			Settings.set_value(key, i)
			if key == "graphics/window_mode":
				_update_resolution_enabled())
	_row(text, opt)
	return opt


func _toggle(text: String, key: String) -> CheckButton:
	var cb := CheckButton.new()
	cb.button_pressed = Settings.get_value(key)
	cb.text = "An" if cb.button_pressed else "Aus"
	cb.custom_minimum_size = Vector2(0, 40)
	cb.toggled.connect(func(on: bool) -> void:
		cb.text = "An" if on else "Aus"
		Settings.set_value(key, on))
	_row(text, cb)
	return cb


func _slider(text: String, key: String, lo: float, hi: float, step: float, fmt: Callable) -> HSlider:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = Settings.get_value(key)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 28)
	_style_slider(s)
	var val := Label.new()
	val.custom_minimum_size = Vector2(64, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.theme_type_variation = &"InkLabel"
	val.add_theme_color_override("font_color", COLOR_GOLD)
	val.text = fmt.call(s.value)
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt.call(v)
		Settings.set_value(key, v))
	hb.add_child(s)
	hb.add_child(val)
	_row(text, hb)
	return s


func _percent(v: float) -> String:
	return "%d %%" % roundi(v * 100.0)


func _update_resolution_enabled() -> void:
	if _resolution_option != null and is_instance_valid(_resolution_option):
		_resolution_option.disabled = Settings.get_value("graphics/window_mode") != Settings.WindowMode.WINDOWED
		_resolution_option.tooltip_text = "Nur im Fenstermodus" if _resolution_option.disabled else ""


# --- Stil -----------------------------------------------------------------------

func _panel_style(margin := 30) -> StyleBox:
	return UIKit.paper(Vector4(margin + 6, margin, margin + 6, margin), true)


func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.12, 0.094, 0.12, 0.18)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = UIKit.INK_RED
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
