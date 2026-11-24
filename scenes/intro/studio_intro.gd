extends Control
## Studio-Intro beim Spielstart: Das „Hitbox Hooligans“-Spielmodul knallt ins Bild,
## eine Hitbox schnappt drumherum zu, „HIT!“ – danach geht es ins Hauptmenü.
## Dauert gut 3 Sekunden; jede Taste, jeder Klick und jeder Controller-Knopf überspringt.
## Alles wird im Code gezeichnet (keine Bilddateien), damit es in jeder Auflösung scharf bleibt.

const NEXT_SCENE := "res://scenes/menu/main_menu.tscn"

# Zeitplan in Sekunden
const T_DROP := 0.25        # Modul fällt
const T_SLAM := 0.6         # Modul schlägt auf
const T_BOX := 0.78         # Hitbox-Ecken fliegen ein
const T_HIT := 1.05         # „HIT!“-Stempel
const T_TEXT := 1.25        # „präsentiert“
const T_GLINT := 1.55       # Glanz über das Etikett
const T_END := 2.95         # weiter ins Menü

const BLACK := UIKit.P_BLACK
const RED := UIKit.P_RED
const RED_DARK := UIKit.P_RED_DARK
const CREAM := UIKit.P_CREAM
const GOLD := UIKit.P_GOLD
const SHELL := Color("55555d")
const SHELL_DARK := Color("3a3a40")

const DISPLAY := preload("res://assets/fonts/RussoOne-Regular.ttf")

const GRAIN_SHADER := """
shader_type canvas_item;
// Filmkorn + Vignette über dem Intro
float rand(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 d = UV - 0.5;
	float n = rand(FRAGCOORD.xy + fract(TIME) * 97.0);
	COLOR = vec4(vec3(n * 0.35), clamp(dot(d, d) * 1.6 + n * 0.06, 0.0, 0.85));
}
"""

var _t := 0.0
var _shake := 0.0
var _leaving := false
var _slammed := false
var _hit := false
var _body: FontVariation
var _body_bold: FontVariation


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Im Headless-Betrieb (Tests) ohne Umweg ins Menü
	if DisplayServer.get_name() == "headless":
		get_tree().change_scene_to_file.call_deferred(NEXT_SCENE)
		return
	_body = UIKit.body_font(500, 6)
	_body_bold = UIKit.body_font(700, 4)
	var grain := ColorRect.new()
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = GRAIN_SHADER
	grain.material = mat
	add_child(grain)


func _process(delta: float) -> void:
	_t += delta
	_shake = maxf(_shake - delta * 4.0, 0.0)
	if not _slammed and _t >= T_SLAM:
		_slammed = true
		_shake = 1.0
	if not _hit and _t >= T_HIT:
		_hit = true
		_shake = maxf(_shake, 0.55)
	if _t >= T_END:
		_finish()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if _t < 0.15:
		return
	var skip: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventJoypadButton and event.pressed)
	if skip:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	if _leaving:
		return
	_leaving = true
	Fade.change_scene(NEXT_SCENE)


# --- Zeichnen ---------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BLACK)
	var k := minf(size.x / 1280.0, size.y / 720.0) * 0.74
	var center := size * 0.5 + Vector2(0, -18) * k
	var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 14.0 * _shake * _shake

	# Roter Plakat-Keil hinter dem Modul, schiebt sich beim Aufprall auf
	var band := _ease_out(_phase(T_SLAM - 0.02, 0.18))
	if band > 0.0:
		_draw_band(center + jitter * 0.5, k, band)

	var base := Transform2D(0.0, Vector2.ONE * k, 0.0, center + jitter)
	_set_xf(base)

	# Modul fällt von oben (beschleunigt) und federt beim Aufprall kurz ein
	var drop := _ease_in(_phase(T_DROP, T_SLAM - T_DROP))
	var y := lerpf(-620.0, 0.0, drop)
	var squash := 1.0
	if _t > T_SLAM:
		var a := _phase(T_SLAM, 0.22)
		squash = 1.0 - 0.06 * sin(a * PI) * (1.0 - a)
	if _t >= T_DROP:
		_set_xf(Transform2D(0.0, Vector2(k * (2.0 - squash), k * squash), 0.0, center + jitter + Vector2(0, y) * k))
		_draw_cartridge()
		_set_xf(base)

	_draw_impact()
	_draw_hitbox()
	_draw_hit_stamp()
	_set_xf(Transform2D.IDENTITY)
	_draw_presents(center, k)


func _draw_band(center: Vector2, k: float, grow: float) -> void:
	var half := size.x * 0.5 + 80.0
	var w := half * grow
	var h := 150.0 * k
	var slope := 0.07
	var pts := PackedVector2Array([
		center + Vector2(-w, -h + w * slope),
		center + Vector2(w, -h - w * slope),
		center + Vector2(w, h - w * slope),
		center + Vector2(-w, h + w * slope),
	])
	draw_colored_polygon(pts, RED)
	# schwarzer Versatz-Streifen darunter
	var off := Vector2(0, h + 10.0 * k)
	var thin := PackedVector2Array([
		center + Vector2(-w, w * slope) + off,
		center + Vector2(w, -w * slope) + off,
		center + Vector2(w, -w * slope) + off + Vector2(0, 14.0 * k),
		center + Vector2(-w, w * slope) + off + Vector2(0, 14.0 * k),
	])
	draw_colored_polygon(thin, RED_DARK)


func _draw_cartridge() -> void:
	var shape := PackedVector2Array([
		Vector2(-190, -250), Vector2(190, -250), Vector2(190, 160), Vector2(160, 190),
		Vector2(160, 250), Vector2(-160, 250), Vector2(-160, 190), Vector2(-190, 160),
	])
	var shadow := PackedVector2Array()
	for p in shape:
		shadow.append(p + Vector2(16, 20))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.55))
	draw_colored_polygon(shape, SHELL)
	var outline := shape.duplicate()
	outline.append(shape[0])
	draw_polyline(outline, Color.BLACK, 7.0, true)
	# Griffrillen
	for i in 14:
		draw_rect(Rect2(-150 + i * 22, -232, 10, 44), SHELL_DARK)
	# Kontakte unten
	for i in 7:
		draw_rect(Rect2(-132 + i * 40, 215, 24, 35), Color.BLACK)
	# Etikett
	var label := Rect2(-150, -160, 300, 290)
	draw_rect(label, CREAM)
	draw_rect(Rect2(-150, -160, 300, 70), RED)
	_text(_body, "GAME STUDIO", Vector2(0, -116), 22, CREAM)
	_text(DISPLAY, "HITBOX", Vector2(0, -12), 62, BLACK)
	_text(DISPLAY, "HOOLIGANS", Vector2(0, 42), 40, RED)
	# kleiner Pixel-Pfeil + „Press Start“
	for r in [Rect2(-112, 70, 12, 12), Rect2(-100, 82, 12, 12), Rect2(-112, 94, 12, 12)]:
		draw_rect(r, BLACK)
	_text(_body_bold, "PRESS START", Vector2(8, 101), 20, BLACK)
	draw_rect(label, Color.BLACK, false, 4.0)
	_draw_glint(label)


func _draw_glint(label: Rect2) -> void:
	var a := _phase(T_GLINT, 0.5)
	if a <= 0.0 or a >= 1.0:
		return
	var x := lerpf(label.position.x - 80.0, label.end.x + 80.0, _ease_in_out(a))
	var top := label.position.y
	var bottom := label.end.y
	var lo := label.position.x
	var hi := label.end.x
	var pts := PackedVector2Array([
		Vector2(clampf(x + 40, lo, hi), top), Vector2(clampf(x + 90, lo, hi), top),
		Vector2(clampf(x + 10, lo, hi), bottom), Vector2(clampf(x - 40, lo, hi), bottom),
	])
	if pts[1].x - pts[0].x > 1.0 or pts[2].x - pts[3].x > 1.0:
		draw_colored_polygon(pts, Color(1, 1, 1, 0.35))


func _draw_impact() -> void:
	var a := _phase(T_SLAM, 0.32)
	if a <= 0.0 or a >= 1.0:
		return
	var col := Color(CREAM, 1.0 - a)
	for side in [-1.0, 1.0]:
		for i in 3:
			var base := Vector2(side * (205 + i * 4), 150 + i * 38)
			var dir := Vector2(side, 0.25 - i * 0.25).normalized()
			draw_line(base + dir * (20 + 60 * a), base + dir * (60 + 110 * a), col, 6.0)
	# Staubring am Boden
	draw_arc(Vector2(0, 262), 200 + 160 * a, PI * 1.05, PI * 1.95, 24, Color(CREAM, 0.5 * (1.0 - a)), 4.0)


func _draw_hitbox() -> void:
	var a := _ease_out_back(_phase(T_BOX, 0.22))
	if a <= 0.0:
		return
	var r := Rect2(-228, -288, 456, 576)
	var fly := (1.0 - a) * 180.0
	var arm := 54.0
	var col := CREAM
	var corners := [
		[r.position + Vector2(-fly, -fly), Vector2(1, 1)],
		[Vector2(r.end.x, r.position.y) + Vector2(fly, -fly), Vector2(-1, 1)],
		[Vector2(r.position.x, r.end.y) + Vector2(-fly, fly), Vector2(1, -1)],
		[r.end + Vector2(fly, fly), Vector2(-1, -1)],
	]
	for c in corners:
		var p: Vector2 = c[0]
		var d: Vector2 = c[1]
		draw_line(p, p + Vector2(d.x * arm, 0), col, 8.0)
		draw_line(p, p + Vector2(0, d.y * arm), col, 8.0)
	# gestrichelte Kante, sobald die Ecken sitzen
	var dash := _phase(T_BOX + 0.18, 0.2)
	if dash > 0.0:
		var dc := Color(CREAM, 0.55 * dash)
		draw_dashed_line(r.position + Vector2(arm, 0), Vector2(r.end.x - arm, r.position.y), dc, 3.0, 14.0)
		draw_dashed_line(Vector2(r.position.x + arm, r.end.y), r.end - Vector2(arm, 0), dc, 3.0, 14.0)
		draw_dashed_line(r.position + Vector2(0, arm), Vector2(r.position.x, r.end.y - arm), dc, 3.0, 14.0)
		draw_dashed_line(Vector2(r.end.x, r.position.y + arm), r.end - Vector2(0, arm), dc, 3.0, 14.0)
		# Etikett der Hitbox
		var tag := Rect2(r.position.x, r.position.y - 38, 196, 30)
		draw_rect(tag, Color(CREAM, dash))
		_text(_body_bold, "HITBOX · ХИТБОКС", tag.get_center() + Vector2(0, 8), 17, Color(BLACK, dash))


func _draw_hit_stamp() -> void:
	var a := _phase(T_HIT, 0.3)
	if a <= 0.0:
		return
	var s := lerpf(2.6, 1.0, _ease_out_back(a))
	var alpha := clampf(a * 4.0, 0.0, 1.0)
	var pos := Vector2(205, -250)
	var outer := _xf
	_set_xf(outer * Transform2D(-0.21, Vector2(s, s), 0.0, pos))
	draw_rect(Rect2(-78 + 6, -36 + 7, 156, 72), Color(0, 0, 0, 0.6 * alpha))
	draw_rect(Rect2(-78, -36, 156, 72), Color(GOLD, alpha))
	draw_rect(Rect2(-78, -36, 156, 72), Color(0, 0, 0, alpha), false, 4.0)
	_text(DISPLAY, "HIT!", Vector2(0, 17), 48, Color(BLACK, alpha))
	_set_xf(outer)


func _draw_presents(center: Vector2, k: float) -> void:
	var a := _phase(T_TEXT, 0.35)
	if a <= 0.0:
		return
	var pos := center + Vector2(0, 345 * k + (1.0 - _ease_out(a)) * 14.0)
	_text(_body, "ПРЕДСТАВЛЯЕТ  ·  PRÄSENTIERT", pos, int(round(24 * k / 0.74)), Color(CREAM, a * 0.85))


# --- Helfer -----------------------------------------------------------------------------

var _xf := Transform2D.IDENTITY

## Setzt die Zeichen-Transformation und merkt sie sich (der Stempel baut darauf auf).
func _set_xf(xf: Transform2D) -> void:
	_xf = xf
	draw_set_transform_matrix(xf)


func _text(font: Font, text: String, pos: Vector2, font_size: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, pos - Vector2(w * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _phase(start: float, length: float) -> float:
	return clampf((_t - start) / length, 0.0, 1.0)


static func _ease_in(x: float) -> float:
	return x * x * x


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func _ease_in_out(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


static func _ease_out_back(x: float) -> float:
	if x <= 0.0:
		return 0.0
	var c := 1.9
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)
