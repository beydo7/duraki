@tool
class_name Slab
extends Container
## Plakat-Fläche: ein oder mehrere Vielecke (Koordinaten 0..1 relativ zur Größe),
## mit hartem Versatz-Schatten wie bei gedruckten Plakaten.
## Als Container passt sie ihre Kinder in die Fläche minus `margins` ein.

## Standardform: Parallelogramm, oben um `skew` nach rechts versetzt.
@export var color := Color(0.07, 0.055, 0.055, 0.96):
	set(v): color = v; queue_redraw()
@export_range(-0.5, 0.5) var skew := 0.0:
	set(v): skew = v; queue_redraw()
## Eigene Form (überschreibt `skew`), Punkte 0..1.
@export var points := PackedVector2Array():
	set(v): points = v; queue_redraw()
## Zusätzliche Flächen darüber (z. B. dunkler Streifen), je mit Farbe aus `extra_colors`.
var extra: Array = []
var extra_colors := PackedColorArray()
@export var shadow_offset := Vector2(4, 5):
	set(v): shadow_offset = v; queue_redraw()
@export var shadow_color := Color(0, 0, 0, 0.75):
	set(v): shadow_color = v; queue_redraw()
@export var outline_color := Color(0, 0, 0, 0):
	set(v): outline_color = v; queue_redraw()
@export var outline_width := 2.0
## false: Kinder werden frei positioniert (Slab ist dann nur Hintergrund)
@export var fit_children := true:
	set(v): fit_children = v; queue_sort(); update_minimum_size()
## links, oben, rechts, unten
@export var margins := Vector4(14, 8, 14, 8):
	set(v): margins = v; queue_sort(); update_minimum_size()


func _shape() -> PackedVector2Array:
	if not points.is_empty():
		return points
	var s := absf(skew)
	if skew >= 0.0:
		return PackedVector2Array([Vector2(s, 0), Vector2(1, 0), Vector2(1 - s, 1), Vector2(0, 1)])
	return PackedVector2Array([Vector2(0, 0), Vector2(1 - s, 0), Vector2(1, 1), Vector2(s, 1)])


func _to_px(pts: PackedVector2Array, off := Vector2.ZERO) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p * size + off)
	return out


func _fill(pts: PackedVector2Array, c: Color) -> void:
	if c.a <= 0.0 or pts.size() < 3:
		return
	draw_colored_polygon(pts, c)
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, c, 1.2, true)  # weiche Kante


func _draw() -> void:
	var shape := _shape()
	if shadow_color.a > 0.0 and shadow_offset != Vector2.ZERO:
		_fill(_to_px(shape, shadow_offset), shadow_color)
	_fill(_to_px(shape), color)
	for i in extra.size():
		_fill(_to_px(extra[i]), extra_colors[i] if i < extra_colors.size() else color.darkened(0.3))
	if outline_color.a > 0.0:
		var loop := _to_px(shape)
		loop.append(loop[0])
		draw_polyline(loop, outline_color, outline_width, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN and fit_children:
		var r := Rect2(Vector2(margins.x, margins.y), size - Vector2(margins.x + margins.z, margins.y + margins.w))
		for c in get_children():
			if c is Control and (c as Control).visible and not (c as Control).top_level:
				fit_child_in_rect(c, r)
	elif what == NOTIFICATION_RESIZED:
		queue_redraw()


func _get_minimum_size() -> Vector2:
	if not fit_children:
		return Vector2.ZERO
	var m := Vector2.ZERO
	for c in get_children():
		if c is Control and (c as Control).visible and not (c as Control).top_level:
			m = m.max((c as Control).get_combined_minimum_size())
	return m + Vector2(margins.x + margins.z, margins.y + margins.w)
