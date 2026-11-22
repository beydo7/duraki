@tool
class_name Roundel
extends Control
## Runde Plakette (Leben, Gold, Stapel) mit Innenring, Beschriftung oben und Wert in der Mitte.

@export var color := Color(0.81, 0.15, 0.16):
	set(v): color = v; queue_redraw()
@export var ring_color := Color(0.94, 0.89, 0.8):
	set(v): ring_color = v; queue_redraw()
## Fünfzackiger Stern statt Kreis (Trumpf)
@export var star := false:
	set(v): star = v; queue_redraw()
@export var shadow_offset := Vector2(3, 4)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	if star:
		var pts := _star(c, r)
		draw_colored_polygon(_star(c + shadow_offset, r), Color(0, 0, 0, 0.75))
		draw_colored_polygon(pts, color)
		pts.append(pts[0])
		draw_polyline(pts, color, 1.2, true)
		return
	draw_circle(c + shadow_offset, r, Color(0, 0, 0, 0.75), true, -1.0, true)
	draw_circle(c, r, color, true, -1.0, true)
	draw_arc(c, r - 5.0, 0, TAU, 64, ring_color, 1.6, true)


func _star(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.42
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts
