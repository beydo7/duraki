class_name DailyMenu
extends Control
## Tägliche Herausforderung: Erklärung, heutiges Ergebnis und Start.
## Alle spielen am selben Tag denselben Run (gleiche Gegner, Räume, Händler-Angebote),
## mit dem Standard-Deck auf Normal. Nur der erste Versuch des Tages zählt.
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
	root.add_child(_l("Heute spielen alle denselben Run: gleiche Gegner, gleiche Räume, gleiche Waren beim Händler. "
		+ "Standard-Deck, Schwierigkeit Normal. Gewertet werden alle Punkte des Runs – auch im Endlos-Modus. "
		+ "Nur dein erster Versuch des Tages zählt.", &"InkType", 16, true))

	var entry := Profile.daily_entry(date)
	var status := ""
	if entry.is_empty():
		status = "Heute noch nicht gespielt."
	elif bool(entry.get("done", false)):
		status = "Dein Ergebnis heute: %d Punkte · %d von %d Tischen%s" % [int(entry.points), int(entry.tables),
			Run.ACTS * Run.FIGHTS_PER_ACT, (" · Endlos %d" % int(entry.endless)) if int(entry.endless) > 0 else ""]
	else:
		status = "Dein Versuch heute wurde nicht beendet – er zählt mit 0 Punkten."
	var st := _l(status, &"InkLabel", 18, true)
	st.add_theme_color_override("font_color", UIKit.INK_RED if not entry.is_empty() else UIKit.INK)
	root.add_child(st)
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
	go.text = "LOS GEHT'S" if entry.is_empty() else "ÜBEN (ZÄHLT NICHT)"
	go.theme_type_variation = &"PrimaryButton"
	go.custom_minimum_size = Vector2(300, 54)
	go.pressed.connect(_start)
	UIKit.hover(go, 1.04)
	buttons.add_child(go)
	go.grab_focus.call_deferred()
	UIKit.appear(panel, 0.0, Vector2(0, 30), 0.35)


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
