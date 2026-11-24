class_name ShotGlassEgg
extends Node3D
## Easter Egg im Hauptmenü:
##   Schnapsglas voll:  jeder Klick lässt es wackeln und klirren (immer etwas höher);
##                      nach CLICKS Klicks nimmst du es und trinkst es aus (Kopf in den
##                      Nacken, danach schwankt der Raum, die Gestalt lacht).
##   Schnapsglas leer:  Klicks aufs Glas klirren nur noch gleich hoch. Nach CLICKS Klicks
##                      auf die Whiskeyflasche schenkt sie nach – dann geht alles von vorn,
##                      bis die Flasche leer ist (dann klingt sie nur noch hohl).
##     var egg := ShotGlassEgg.new(); world.add_child(egg); egg.setup(world, func() -> Transform3D: return seat)

const CLICKS := 5
const GLASS_POS := Vector3(0.57, 0.8, 0.14) # Mitte unten des Glases (siehe build_models.py)
const GLASS_TOP := 0.055

var _world: TableWorld
var _seat: Callable
var _pivot: Node3D
var _liq_pivot: Node3D
var _clicks := 0
var _bottle_clicks := 0
var _busy := false
var _empty := false
var _tipsy := 0.0
var _t := 0.0
var _stream: MeshInstance3D


func setup(world: TableWorld, seat_pose: Callable) -> void:
	_world = world
	_seat = seat_pose
	var glass := world.find_child("Schnapsglas", true, false) as MeshInstance3D
	var liquor := world.find_child("Schnaps", true, false) as MeshInstance3D
	if glass == null:
		return
	# Glas und Schnaps an Drehpunkte hängen (die Modelle liegen in Weltkoordinaten)
	_pivot = Node3D.new()
	_pivot.position = GLASS_POS
	add_child(_pivot)
	_liq_pivot = Node3D.new()
	_pivot.add_child(_liq_pivot)
	glass.get_parent().remove_child(glass)
	_pivot.add_child(glass)
	glass.position = -GLASS_POS
	if liquor != null:
		liquor.get_parent().remove_child(liquor)
		_liq_pivot.add_child(liquor)
		liquor.position = -GLASS_POS
	var area := Area3D.new()
	area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.04
	cyl.height = 0.08
	shape.shape = cyl
	shape.position = Vector3(0, 0.035, 0)
	area.add_child(shape)
	_pivot.add_child(area)
	area.input_event.connect(_on_glass_input)
	if world.whiskey != null:
		world.whiskey.clicked.connect(_on_bottle)


func _process(delta: float) -> void:
	_t += delta
	if _tipsy <= 0.0 or _world == null or _busy:
		return
	_tipsy = maxf(_tipsy - delta * 0.22, 0.0)
	var k := _tipsy * _tipsy
	var wobble := Transform3D(Basis.from_euler(Vector3(sin(_t * 1.3) * 0.05, sin(_t * 0.9) * 0.07, sin(_t * 1.1) * 0.09) * k),
		Vector3(sin(_t * 0.8) * 0.04, sin(_t * 1.7) * 0.015, 0) * k)
	_world.set_camera_pose(_seat.call() * wobble)


func _on_glass_input(_cam: Node, event: InputEvent, _p: Vector3, _n: Vector3, _i: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _busy:
		return
	if _empty:
		_jiggle(1.0) # leer: immer gleicher Ton
		return
	_clicks += 1
	if _clicks < CLICKS:
		_jiggle(0.9 + _clicks * 0.06)
	else:
		_drink()


func _on_bottle() -> void:
	if _busy:
		return
	var bottle := _world.whiskey
	Sfx.play(&"bottle_knock", 1.0 if bottle.can_pour() else 1.25) # leer klingt hohler
	_wobble(bottle, 0.05)
	if not _empty or not bottle.can_pour():
		return
	_bottle_clicks += 1
	if _bottle_clicks >= CLICKS:
		_pour()


func _jiggle(pitch: float) -> void:
	Sfx.play(&"clink", pitch)
	_wobble(_pivot, 0.12)


func _wobble(node: Node3D, amount: float) -> void:
	var tw := create_tween()
	tw.tween_property(node, "rotation:z", amount, 0.05)
	tw.tween_property(node, "rotation:z", -amount * 0.6, 0.07)
	tw.tween_property(node, "rotation:z", 0.0, 0.1)


func _drink() -> void:
	_busy = true
	var cam := _world.camera
	var start := _pivot.transform
	# Vor den Mund: etwas unter der Bildmitte, nah an der Kamera
	var cam_xf := cam.global_transform
	var mouth := cam_xf.origin - cam_xf.basis.z * 0.2 - cam_xf.basis.y * 0.07
	var to_mouth := Transform3D(Basis.looking_at(cam_xf.origin - mouth, Vector3.UP), mouth)
	var tilted := Transform3D(to_mouth.basis.rotated(cam_xf.basis.x, -1.6), mouth + cam_xf.basis.y * 0.03)
	var seat: Transform3D = _seat.call()
	var head_back := seat * Transform3D(Basis.from_euler(Vector3(0.35, 0, 0)), Vector3(0, 0.02, 0.02))

	var tw := create_tween()
	tw.tween_property(_pivot, "transform", to_mouth, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void: Sfx.play(&"gulp"))
	# Glas kippen und Kopf in den Nacken – beides aus derselben Bewegung, damit sie zusammenpassen
	tw.tween_method(func(v: float) -> void:
		_pivot.transform = to_mouth.interpolate_with(tilted, v)
		_world.set_camera_pose(seat.interpolate_with(head_back, v))
		_liq_pivot.scale = Vector3(1, clampf(1.0 - (v - 0.45) / 0.45, 0.001, 1.0), 1),
		0.0, 1.0, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(0.2)
	tw.tween_method(func(v: float) -> void:
		_pivot.transform = tilted.interpolate_with(start, v)
		_world.set_camera_pose(head_back.interpolate_with(seat, v)),
		0.0, 1.0, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		Sfx.play(&"clink", 0.8)
		_empty = true
		_clicks = 0
		_bottle_clicks = 0
		_busy = false
		_tipsy = 1.0
		if _world.figure != null:
			_world.figure.laugh())


## Flasche hebt sich, kippt über dem Glas, Whiskey läuft hinein, Flasche zurück.
func _pour() -> void:
	_busy = true
	var bottle := _world.whiskey
	var start := bottle.transform
	var parent_inv := bottle.get_parent_node_3d().global_transform.affine_inverse()
	var glass_top := _pivot.global_position + Vector3(0, GLASS_TOP + 0.04, 0)
	var d := (bottle.global_position - _pivot.global_position) * Vector3(1, 0, 1)
	d = d.normalized()
	var a := deg_to_rad(42.0)
	var neck_dir := (-d * cos(a) + Vector3.DOWN * sin(a)).normalized()
	var axis := Vector3.UP.cross(neck_dir).normalized()
	var basis := Basis(axis, Vector3.UP.angle_to(neck_dir)) * Basis(Vector3.UP, start.basis.get_euler().y)
	var origin := glass_top + d * 0.012 - basis * Vector3(0, WhiskeyBottle.NECK_TOP, 0)
	var pour_xf := parent_inv * Transform3D(basis, origin)
	var lifted := start.translated(Vector3(0, 0.08, 0))

	var tw := create_tween()
	tw.tween_property(bottle, "transform", lifted, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(bottle, "transform", pour_xf, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(0.12) # erst wenn die Flasche ganz gekippt ist, läuft der Whiskey
	tw.tween_callback(func() -> void:
		Sfx.play(&"pour")
		_show_stream(bottle.spout(), _pivot.global_position + Vector3(0, 0.012, 0)))
	tw.tween_method(func(v: float) -> void: _set_stream(v, 1.0), 0.0, 1.0, 0.14)
	tw.tween_property(_liq_pivot, "scale", Vector3.ONE, 1.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(bottle, "fill", bottle.fill - WhiskeyBottle.POUR, 1.0)
	# Strahl reißt von oben ab
	tw.tween_method(func(v: float) -> void: _set_stream(1.0, 1.0 - v), 0.0, 1.0, 0.12)
	tw.tween_callback(func() -> void:
		if _stream != null:
			_stream.queue_free())
	tw.tween_property(bottle, "transform", lifted, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(bottle, "transform", start, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		Sfx.play(&"bottle_knock", 0.8, -4.0)
		_empty = false
		_clicks = 0
		_bottle_clicks = 0
		_busy = false)


## Dünner Whiskeystrahl von der Flaschenöffnung ins Glas (anfangs unsichtbar, siehe _set_stream).
var _stream_from := Vector3.ZERO
var _stream_to := Vector3.ZERO


func _show_stream(from: Vector3, to: Vector3) -> void:
	_stream_from = from
	_stream_to = to
	var c := CylinderMesh.new()
	c.top_radius = 0.0025
	c.bottom_radius = 0.0018
	c.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.35, 0.08, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.15, 0.03)
	mat.roughness = 0.1
	_stream = MeshInstance3D.new()
	_stream.mesh = c
	_stream.material_override = mat
	_stream.top_level = true
	add_child(_stream)
	_set_stream(0.0, 1.0)


## Strahl von der Öffnung aus: `reach` = wie weit nach unten (0..1), `top` = wie viel oben noch hängt.
func _set_stream(reach: float, top: float) -> void:
	if _stream == null:
		return
	var a := _stream_from.lerp(_stream_to, 1.0 - top)
	var b := _stream_from.lerp(_stream_to, maxf(reach, 0.001))
	var len := maxf(a.distance_to(b), 0.0005)
	var up := (_stream_from - _stream_to).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	_stream.global_transform = Transform3D(Basis(side, up * len, side.cross(up)), (a + b) * 0.5)
	_stream.visible = reach > 0.01 and top > 0.01
