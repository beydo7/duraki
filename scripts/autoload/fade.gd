extends CanvasLayer
## Autoload „Fade“: weicher Übergang zwischen Szenen (abdunkeln → wechseln → aufhellen).

const TIME_OUT := 0.28
const TIME_IN := 0.42

var _rect: ColorRect
var _busy := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color(0.02, 0.012, 0.04)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.modulate.a = 0.0
	add_child(_rect)


func change_scene(path: String) -> void:
	if _busy or DisplayServer.get_name() == "headless":
		get_tree().change_scene_to_file.call_deferred(path)
		return
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_rect, "modulate:a", 1.0, TIME_OUT).set_trans(Tween.TRANS_SINE)
	await tw.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_rect, "modulate:a", 0.0, TIME_IN).set_trans(Tween.TRANS_SINE)
	await tw2.finished
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
