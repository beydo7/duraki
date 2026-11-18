@tool
class_name Backdrop
extends Control
## Gemeinsamer Hintergrund für alle 2D-Bildschirme (Menü, Weg, Belohnung, Ende).
## Einfach als erstes Kind in eine Szene legen.

const SHADER := preload("res://ui/backdrop.gdshader")
const BRUSH := preload("res://assets/fonts/PermanentMarker-Regular.ttf")
const SYMBOLS := preload("res://assets/fonts/DejaVuSans.ttf")

## Großer, blasser Schriftzug hinter dem Inhalt (leer = keiner).
@export var wordmark := "":
	set(v):
		wordmark = v
		queue_redraw()
@export var show_suits := true:
	set(v):
		show_suits = v
		queue_redraw()

var _rect: ColorRect
var _t := 0.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(PRESET_FULL_RECT)
	_rect = ColorRect.new()
	_rect.mouse_filter = MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(PRESET_FULL_RECT)
	_rect.show_behind_parent = true
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	_rect.material = mat
	add_child(_rect)
	resized.connect(_on_resized)
	_on_resized()


func _on_resized() -> void:
	if _rect and size.y > 0:
		(_rect.material as ShaderMaterial).set_shader_parameter("aspect", size.x / size.y)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var h := size.y
	var c := size * 0.5
	if show_suits:
		var bob := sin(_t * 0.8) * 6.0
		_symbol("♣", Vector2(c.x - h * 0.47, c.y + h * 0.04 + bob), h * 0.2)
		_symbol("♠", Vector2(c.x + h * 0.47, c.y + h * 0.04 - bob), h * 0.2)
	if not wordmark.is_empty():
		var fs := int(h * 0.2)
		var w := BRUSH.get_string_size(wordmark, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(c.x - w * 0.5, c.y + fs * 0.42)
		draw_string(BRUSH, pos + Vector2(8, 8), wordmark, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.02, 0.01, 0.06, 0.55))
		draw_string(BRUSH, pos, wordmark, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.45, 0.36, 0.78, 0.55))


func _symbol(sym: String, center: Vector2, fs: float) -> void:
	var s := SYMBOLS.get_string_size(sym, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs))
	draw_string(SYMBOLS, center - Vector2(s.x * 0.5, -fs * 0.35), sym, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), Color(0.6, 0.55, 0.75, 0.13))
