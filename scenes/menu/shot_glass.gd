class_name ShotGlassEgg
extends Node3D
## Easter Egg im Hauptmenü: Das Schnapsglas auf dem Tisch lässt sich anklicken.
## Jeder Klick: Glas wackelt und klirrt. Nach CLICKS_TO_DRINK Klicks nimmst du es,
## kippst den Schnaps (Glas zur Kamera, Kopf in den Nacken) und stellst es leer zurück –
## danach schwankt die Kamera ein paar Sekunden, und die Gestalt gegenüber lacht.
##     var egg := ShotGlassEgg.new(); world.add_child(egg); egg.setup(world, func() -> Transform3D: return seat)

const CLICKS_TO_DRINK := 5
const GLASS_POS := Vector3(0.57, 0.8, 0.14) # Mitte unten des Glases (siehe build_models.py)

var _world: TableWorld
var _seat: Callable
var _pivot: Node3D
var _liquor: MeshInstance3D
var _clicks := 0
var _busy := false
var _empty := false
var _tipsy := 0.0
var _t := 0.0


func setup(world: TableWorld, seat_pose: Callable) -> void:
	_world = world
	_seat = seat_pose
	var glass := world.find_child("Schnapsglas", true, false) as MeshInstance3D
	_liquor = world.find_child("Schnaps", true, false) as MeshInstance3D
	if glass == null:
		return
	# Glas und Schnaps an einen Drehpunkt hängen (die Modelle liegen in Weltkoordinaten)
	_pivot = Node3D.new()
	_pivot.position = GLASS_POS
	add_child(_pivot)
	for mesh in [glass, _liquor]:
		if mesh == null:
			continue
		mesh.get_parent().remove_child(mesh)
		_pivot.add_child(mesh)
		mesh.position = -GLASS_POS
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
	area.input_event.connect(_on_input)


func _process(delta: float) -> void:
	_t += delta
	if _tipsy <= 0.0 or _world == null or _busy:
		return
	_tipsy = maxf(_tipsy - delta * 0.22, 0.0)
	var k := _tipsy * _tipsy
	var wobble := Transform3D(Basis.from_euler(Vector3(sin(_t * 1.3) * 0.05, sin(_t * 0.9) * 0.07, sin(_t * 1.1) * 0.09) * k),
		Vector3(sin(_t * 0.8) * 0.04, sin(_t * 1.7) * 0.015, 0) * k)
	_world.set_camera_pose(_seat.call() * wobble)


func _on_input(_cam: Node, event: InputEvent, _p: Vector3, _n: Vector3, _i: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _busy:
		return
	_clicks += 1
	if _empty or _clicks < CLICKS_TO_DRINK:
		_jiggle()
	else:
		_drink()


## Kurz anstupsen: Glas wackelt, klirrt etwas höher bei jedem Klick.
func _jiggle() -> void:
	Sfx.play(&"clink", 0.9 + _clicks * 0.06, -6.0)
	var tw := create_tween()
	tw.tween_property(_pivot, "rotation:z", 0.12, 0.05)
	tw.tween_property(_pivot, "rotation:z", -0.08, 0.07)
	tw.tween_property(_pivot, "rotation:z", 0.0, 0.1)


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
	# Kopf in den Nacken und Glas kippen
	tw.tween_property(_pivot, "transform", tilted, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(func(v: float) -> void: _world.set_camera_pose(seat.interpolate_with(head_back, v)),
		0.0, 1.0, 0.45).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func() -> void:
		if _liquor != null:
			_liquor.visible = false)
	tw.tween_interval(0.25)
	tw.tween_method(func(v: float) -> void: _world.set_camera_pose(head_back.interpolate_with(seat, v)),
		0.0, 1.0, 0.5).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(_pivot, "transform", start, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		Sfx.play(&"clink", 0.8, -4.0)
		_empty = true
		_busy = false
		_tipsy = 1.0
		if _world.figure != null:
			_world.figure.laugh())
