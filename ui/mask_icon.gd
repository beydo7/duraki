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
## 0 = keine, 1 = Teufelshörner, 2 = Widderhörner
@export var horns := 0
## 0 = zugenäht, 1 = Reißzahn-Grinsen
@export var mouth := 1

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
	# Hörner hinter dem Schädel
	var bob := sin(_t * 1.4) * r * 0.03
	var fc := c + Vector2(0, r * 0.08 + bob)
	var fw := r * 0.46
	var fh := r * 0.64
	var horn_col := Color(0.22, 0.17, 0.14)
	for side in [-1.0, 1.0]:
		if horns == 1:
			draw_colored_polygon(PackedVector2Array([fc + Vector2(side * fw * 0.35, -fh * 0.75),
				fc + Vector2(side * fw * 0.85, -fh * 0.5), fc + Vector2(side * fw * 1.05, -fh * 1.35)]), horn_col)
		elif horns == 2:
			draw_arc(fc + Vector2(side * fw * 0.95, -fh * 0.45), fw * 0.42, 0, TAU * 0.8, 20, horn_col, fw * 0.22)
	# Schädel: oben breit, Kinn spitz
	var pts := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		var x := cos(a) * fw
		var y := sin(a) * fh
		if y > 0:
			x *= 1.0 - 0.35 * (y / fh)
		pts.append(fc + Vector2(x, y))
	draw_colored_polygon(pts, mask_color)
	# schräge, tiefe Augenhöhlen mit glühender Pupille
	var glow := 0.65 + sin(_t * 2.3) * 0.25 + intensity * 0.35
	for side in [-1.0, 1.0]:
		var e := fc + Vector2(side * fw * 0.4, -fh * 0.08)
		var eye := PackedVector2Array()
		for i in 20:
			var a := TAU * i / 20.0
			var p := Vector2(cos(a) * fw * 0.3, sin(a) * fh * 0.17)
			eye.append(e + p.rotated(side * -0.35))
		draw_colored_polygon(eye, INK)
		draw_circle(e, fw * 0.11 * (1.0 + intensity * 0.3), Color(eye_color, clampf(glow, 0, 1)))
		draw_circle(e, fw * 0.05, Color(1, 0.9, 0.7, clampf(glow, 0, 1)))
	# Nasenlöcher
	for side in [-1.0, 1.0]:
		draw_circle(fc + Vector2(side * fw * 0.08, fh * 0.2), fw * 0.05, INK)
	var m := fc + Vector2(0, fh * 0.48)
	if mouth == 1:
		# breites Grinsen (Mundwinkel hoch) mit spitzen Zähnen
		var w := fw * 0.62
		var grin := PackedVector2Array()
		for i in 17:
			var x := lerpf(-w, w, i / 16.0)
			grin.append(m + Vector2(x, _grin_top(x, w, fh)))
		for i in range(15, 0, -1):
			var x := lerpf(-w, w, i / 16.0)
			grin.append(m + Vector2(x, _grin_bottom(x, w, fh)))
		draw_colored_polygon(grin, INK)
		var tooth := mask_color.darkened(0.1)
		for i in 6:
			var x := lerpf(-w * 0.75, w * 0.75, i / 5.0)
			var tw := w * 0.1
			var top := _grin_top(x, w, fh)
			draw_colored_polygon(PackedVector2Array([m + Vector2(x - tw, top), m + Vector2(x + tw, top),
				m + Vector2(x, top + fh * 0.09)]), tooth)
			var bx := x + w * 0.12
			if absf(bx) < w * 0.8:
				var bot := _grin_bottom(bx, w, fh)
				draw_colored_polygon(PackedVector2Array([m + Vector2(bx - tw, bot), m + Vector2(bx + tw, bot),
					m + Vector2(bx, bot - fh * 0.07)]), tooth)
	else:
		draw_line(m - Vector2(fw * 0.4, 0), m + Vector2(fw * 0.4, 0), INK, 2.0)
		for i in 4:
			var x := -fw * 0.3 + i * fw * 0.2
			draw_line(m + Vector2(x, -fh * 0.08), m + Vector2(x, fh * 0.08), INK, 1.6)


func _grin_top(x: float, w: float, fh: float) -> float:
	return -fh * 0.16 * pow(x / w, 2.0)


func _grin_bottom(x: float, w: float, fh: float) -> float:
	var k := pow(x / w, 2.0)
	return -fh * 0.16 * k + fh * 0.2 * (1.0 - k)


func _ellipse(center: Vector2, radius: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_colored_polygon(pts, col)
