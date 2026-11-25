extends CanvasLayer
## Autoload „Pause“: Esc öffnet im Spiel ein Pausenmenü (Weiter, Optionen, Hauptmenü).
## Im Hauptmenü selbst ist es aus – dort gibt es den Optionen-Knopf direkt.

var _root: Control
var _options: OptionsMenu
var _confirm := false


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS


var _dev: DevMenu


func _unhandled_input(event: InputEvent) -> void:
	# F8: Entwicklermenü überall (Hauptmenü, Weg, Händler). Im Duell öffnet es match.gd selbst.
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_F8:
		if _dev == null and not is_open():
			get_viewport().set_input_as_handled()
			_dev = DevMenu.new()
			_dev.match_node = get_tree().current_scene
			add_child(_dev)
			_dev.closed.connect(func() -> void: _dev = null)
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _options != null:
		return # das Optionen-Fenster schließt sich selbst
	if is_open():
		close()
	elif _can_open():
		open()
	else:
		return
	get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _root != null


func _can_open() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.scene_file_path != Run.SCENE_MENU


func open() -> void:
	if is_open():
		return
	get_tree().paused = true
	_confirm = false
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.paper(Vector4(40, 30, 40, 34), true))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := Label.new()
	title.text = "PAUSE"
	title.theme_type_variation = &"InkTitle"
	title.add_theme_font_size_override("font_size", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var sub := Label.new()
	sub.theme_type_variation = &"InkType"
	sub.text = "Die Karten bleiben liegen."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var resume := _button(box, "WEITER")
	resume.theme_type_variation = &"PrimaryButton"
	resume.pressed.connect(close)
	_button(box, "OPTIONEN").pressed.connect(_open_options)
	var quit := _button(box, "ZUM HAUPTMENÜ")
	quit.theme_type_variation = &"DangerButton"
	quit.pressed.connect(func() -> void:
		if not _confirm:
			_confirm = true
			quit.text = "WIRKLICH? RUN ENDET"
			return
		close()
		Run.goto(Run.SCENE_MENU))
	resume.grab_focus()
	UIKit.appear(panel, 0.0, Vector2(0, 20), 0.3)


func close() -> void:
	if _options != null:
		_options.queue_free()
		_options = null
	if _root != null:
		_root.queue_free()
		_root = null
	get_tree().paused = false


func _open_options() -> void:
	_options = OptionsMenu.new()
	_root.add_child(_options)
	_options.closed.connect(func() -> void: _options = null)


func _button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(300, 52)
	parent.add_child(b)
	UIKit.hover(b, 1.04)
	return b
