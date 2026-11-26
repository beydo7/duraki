class_name DailyMenu
extends Control
## Tägliche Herausforderung: Erklärung, heutiges Ergebnis und Start.
## Alle spielen am selben Tag denselben Run (gleiche Gegner, Räume, Händler-Angebote),
## mit dem Deck des Tages auf Normal. 3 Versuche pro Tag, der beste zählt.
##     var m := DailyMenu.new(); add_child(m); m.started.connect(...); m.closed.connect(...)

signal started
signal closed

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
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.paper(Vector4(40, 28, 40, 30), true))
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	var date := Profile.today()
	root.add_child(_l("TÄGLICHE HERAUSFORDERUNG", &"InkTitle", 36))
	root.add_child(_l(_pretty(date), &"InkLabel", 20))
	root.add_child(_l("Jeden Tag ein neuer Run – und heute spielen ihn alle gleich: dieselben Gegner, Räume, "
		+ "Waren beim Händler und dasselbe Deck (auch eins, das du noch nicht freigeschaltet hast). "
		+ "Schwierigkeit Normal. Gewertet werden alle Punkte des Runs – auch im Endlos-Modus. "
		+ "Du hast 3 Versuche am Tag, dein bester zählt. Ein abgebrochener Versuch ist verbraucht.", &"InkType", 16, true))
	var d := Run.daily_deck(date)
	if d != null:
		var deck_row := HBoxContainer.new()
		deck_row.add_theme_constant_override("separation", 14)
		root.add_child(deck_row)
		if d.back != null:
			var back_pic := TextureRect.new()
			back_pic.texture = d.back
			back_pic.custom_minimum_size = Vector2(46, 64)
			back_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			back_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			deck_row.add_child(back_pic)
		var dcol := VBoxContainer.new()
		dcol.add_theme_constant_override("separation", 0)
		dcol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		deck_row.add_child(dcol)
		dcol.add_child(_l("Deck des Tages: %s" % d.display_name, &"InkLabel", 18))
		dcol.add_child(_l(d.effect_text if d.effect_text != "" else "Keine Besonderheiten.", &"InkType", 15))

	var entry := Profile.daily_entry(date)
	var tries: Array = entry.get("tries", [])
	var left := Profile.DAILY_TRIES - tries.size()
	# Versuche als Punkte: ● verbraucht, ○ frei – darunter die Ergebnisse
	var dots := ""
	for i in Profile.DAILY_TRIES:
		dots += ("●" if i < tries.size() else "○") + " "
	var tr := _l("Versuche: %s  %s" % [dots.strip_edges(),
		("noch %d übrig" % left) if left > 0 else "alle verbraucht"], &"InkLabel", 20)
	tr.add_theme_color_override("font_color", UIKit.INK_RED if left == 0 else UIKit.INK)
	root.add_child(tr)
	if not tries.is_empty():
		var parts := PackedStringArray()
		for i in tries.size():
			parts.append("%d. Versuch: %d" % [i + 1, int(tries[i])])
		root.add_child(_l("   ·   ".join(parts) + "      →  Bestwert heute: %d Punkte" % int(entry.get("points", 0)),
			&"InkType", 16, true))
	else:
		root.add_child(_l("Heute noch nicht gespielt. Du hast %d Versuche – der beste zählt." % Profile.DAILY_TRIES,
			&"InkType", 16, true))
	var streak := Profile.daily_streak()
	root.add_child(_l("Serie: %d %s in Folge   ·   Bester Tag: %d Punkte" % [streak, "Tag" if streak == 1 else "Tage",
		Profile.daily_best()], &"InkType", 15))

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
	go.text = ("VERSUCH %d VON %d" % [tries.size() + 1, Profile.DAILY_TRIES]) if left > 0 else "ÜBEN (ZÄHLT NICHT)"
	go.theme_type_variation = &"PrimaryButton"
	go.custom_minimum_size = Vector2(300, 54)
	go.pressed.connect(_start)
	UIKit.hover(go, 1.04)
	buttons.add_child(go)
	go.grab_focus.call_deferred()
	# nur einblenden (Position macht der CenterContainer – kein Verschieben, sonst landet die
	# Tafel oben links, wenn das Layout noch nicht steht)
	panel.modulate.a = 0.0
	panel.create_tween().tween_property(panel, "modulate:a", 1.0, 0.3)


## „2026-11-26“ → „Donnerstag, 26.11.2026“
static func _pretty(date: String) -> String:
	const DAYS := ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
	var d := Time.get_datetime_dict_from_datetime_string(date + "T12:00:00", true)
	if d.is_empty():
		return date
	return "%s, %02d.%02d.%d" % [DAYS[int(d.weekday)], int(d.day), int(d.month), int(d.year)]


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
		l.custom_minimum_size = Vector2(680, 0)
	return l
