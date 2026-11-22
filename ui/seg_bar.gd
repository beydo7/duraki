@tool
class_name SegBar
extends Control
## Fortschritt als schräge Plakat-Segmente (z. B. Punkte bis zum Ziel).

@export var segments := 10:
	set(v): segments = maxi(1, v); queue_redraw()
@export_range(0.0, 1.0) var value := 0.0:
	set(v): value = clampf(v, 0.0, 1.0); queue_redraw()
@export var fill_color := Color(0.94, 0.89, 0.8)
@export var empty_color := Color(0.42, 0.05, 0.07)
@export var gap := 5.0
@export var slant := 0.3


func _draw() -> void:
	var w := (size.x - gap * (segments - 1)) / segments
	var h := size.y
	var filled := value * segments
	for i in segments:
		var x := i * (w + gap)
		var pts := PackedVector2Array([
			Vector2(x + h * slant, 0), Vector2(x + w, 0), Vector2(x + w - h * slant, h), Vector2(x, h)])
		draw_colored_polygon(pts, empty_color)
		var part := clampf(filled - i, 0.0, 1.0)
		if part > 0.0:
			var fw := w * part
			var fp := PackedVector2Array([
				Vector2(x + h * slant, 0), Vector2(x + h * slant + fw - h * slant * part, 0),
				Vector2(x + fw - h * slant * part, h), Vector2(x, h)])
			if part >= 1.0:
				fp = pts
			draw_colored_polygon(fp, fill_color)
