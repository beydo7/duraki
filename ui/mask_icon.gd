@tool
class_name MaskIcon
extends Control
## Rundes Porträt der Gegnermaske fürs HUD (gezeichnet, mit glimmenden Augen).

@export var mask_color := Color("d8cfb8"):
	set(v):
		mask_color = v
		queue_redraw()
@export var eye_color := Color("c4271b"):
	set(v):
		eye_color = v
		queue_redraw()
@export var ring_color := Color(0.55, 0.45, 0.95)

## 0..1 – stärkeres Glühen, z. B. wenn der Gegner nachdenkt.
var intensity := 0.0

var _t := 0.0

const INK := Color(0.05, 0.03, 0.09)


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(64, 64)
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	# Hintergrund + Ring
	draw_circle(c, r, Color(0.1, 0.07, 0.18))
	draw_circle(c, r - 3, Color(0.16, 0.11, 0.28))
	draw_arc(c, r - 1.5, 0, TAU, 48, ring_color, 3.0, true)
	# Maske (leicht wippend)
	var bob := sin(_t * 1.4) * r * 0.03
	var fc := c + Vector2(0, r * 0.05 + bob)
	var fw := r * 0.5
	var fh := r * 0.66
	_ellipse(fc + Vector2(2, 3), Vector2(fw, fh), Color(0, 0, 0, 0.35))
	_ellipse(fc, Vector2(fw, fh), mask_color)
	# Augenhöhlen + Glut
	var glow := 0.6 + sin(_t * 2.3) * 0.25 + intensity * 0.4
	for side in [-1.0, 1.0]:
		var e := fc + Vector2(side * fw * 0.42, -fh * 0.12)
		_ellipse(e, Vector2(fw * 0.27, fh * 0.24), INK)
		draw_circle(e + Vector2(0, fh * 0.03), fw * 0.12 * (1.0 + intensity * 0.3), Color(eye_color, clampf(glow, 0, 1)))
		draw_circle(e + Vector2(0, fh * 0.03), fw * 0.06, Color(1, 0.9, 0.6, clampf(glow * 0.8, 0, 1)))
	# zugenähter Mund
	var m := fc + Vector2(0, fh * 0.5)
	draw_line(m - Vector2(fw * 0.4, 0), m + Vector2(fw * 0.4, 0), INK, 2.0)
	for i in 4:
		var x := -fw * 0.3 + i * fw * 0.2
		draw_line(m + Vector2(x, -fh * 0.08), m + Vector2(x, fh * 0.08), INK, 1.6)


func _ellipse(center: Vector2, radius: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_colored_polygon(pts, col)
