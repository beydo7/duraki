@tool
class_name MaskCard
extends Control
## Gezeichnete Spielkarte „Der Durak“ mit der Porzellanmaske der Gegner.
## Wird im Hauptmenü (und gern auch anderswo) als Illustration benutzt.

const MONO := preload("res://assets/fonts/CourierPrime-Bold.ttf")
const SYMBOLS := preload("res://assets/fonts/DejaVuSans.ttf")

const INK := Color(0.09, 0.07, 0.17)
const PAPER := Color(0.97, 0.93, 0.83)
const PAPER_SHADE := Color(0.9, 0.84, 0.95)
const ACCENT := Color(0.55, 0.22, 0.42)

@export var caption := "DER DURAK"
@export var corner := "D"
@export var eye_color := Color(0.85, 0.18, 0.12)

var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(170, 236)
	mouse_filter = MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var tilt := -0.05 + sin(_t * 0.9) * 0.012
	var lift := sin(_t * 1.3) * 3.0
	draw_set_transform(Vector2(w * 0.5, h * 0.5 + lift), tilt, Vector2.ONE)
	var r := Rect2(-w * 0.5, -h * 0.5, w, h)

	# Schatten, Rand, Papier mit leichtem Verlauf
	draw_rect(Rect2(r.position + Vector2(10, 10), r.size), Color(0.02, 0.01, 0.05, 0.9))
	draw_rect(r, INK)
	var inner := r.grow(-6)
	draw_rect(inner, PAPER)
	for i in 12:
		var a := float(i) / 12.0
		draw_rect(Rect2(inner.position + Vector2(0, inner.size.y * a), Vector2(inner.size.x, inner.size.y / 12.0 + 1)),
			Color(PAPER_SHADE, a * 0.6))

	# Ecken
	_text(corner, inner.position + Vector2(10, 26), 22, INK)
	_sym("★", inner.position + Vector2(9, 48), 18, INK)
	draw_set_transform(Vector2(w * 0.5, h * 0.5 + lift), tilt + PI, Vector2.ONE)
	_text(corner, inner.position + Vector2(10, 26), 22, INK)
	_sym("★", inner.position + Vector2(9, 48), 18, INK)
	draw_set_transform(Vector2(w * 0.5, h * 0.5 + lift), tilt, Vector2.ONE)
	_sym("✦", Vector2(w * 0.28, -h * 0.30), 16, ACCENT)
	_sym("✦", Vector2(-w * 0.30, h * 0.22), 14, ACCENT)

	# Maske
	var face_c := Vector2(0, -h * 0.04)
	var fw := w * 0.2
	var fh := w * 0.25
	_ellipse(face_c + Vector2(4, 5), Vector2(fw, fh), Color(0.6, 0.5, 0.8, 0.5))
	_ellipse(face_c, Vector2(fw, fh), Color(0.96, 0.93, 0.86))
	_ellipse_outline(face_c, Vector2(fw, fh), INK, 2.5)
	for side in [-1.0, 1.0]:
		var e := face_c + Vector2(side * fw * 0.42, -fh * 0.12)
		_ellipse(e, Vector2(fw * 0.27, fh * 0.3), INK)
		var glow := 0.75 + sin(_t * 2.2) * 0.25
		draw_circle(e + Vector2(0, fh * 0.04), fw * 0.07, Color(eye_color, glow))
	var m := face_c + Vector2(0, fh * 0.48)
	draw_line(m - Vector2(fw * 0.42, 0), m + Vector2(fw * 0.42, 0), INK, 2.5)
	for i in 5:
		var x := -fw * 0.32 + i * fw * 0.16
		draw_line(m + Vector2(x, -fh * 0.1), m + Vector2(x, fh * 0.1), INK, 2.0)

	# Beschriftung
	var fs := 15
	var tw := MONO.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + caption.length() * 2
	_text(caption, Vector2(-tw * 0.5, h * 0.36), fs, INK, 2)


func _text(t: String, pos: Vector2, fs: int, col: Color, spacing := 0) -> void:
	if spacing == 0:
		draw_string(MONO, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		return
	var x := 0.0
	for ch in t:
		draw_string(MONO, pos + Vector2(x, 0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		x += MONO.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + spacing


func _sym(t: String, pos: Vector2, fs: int, col: Color) -> void:
	draw_string(SYMBOLS, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _ellipse(c: Vector2, radius: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		pts.append(c + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_colored_polygon(pts, col)


func _ellipse_outline(c: Vector2, radius: Vector2, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 41:
		var a := TAU * i / 40.0
		pts.append(c + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	draw_polyline(pts, col, width, true)
