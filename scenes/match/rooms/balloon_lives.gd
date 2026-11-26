class_name BalloonLives
extends Node3D
## Luftballons an der Tischkante im Zirkuswagen – zeigen die Leben.
## Pro Leben ein bunter Ballon an einer Schnur, die Ballons schaukeln leicht.
## Verlierst du ein Leben, zittert der rechte Ballon kurz und platzt mit Konfetti.

const SND_POP := preload("res://assets/rooms/circus/pop.wav")
const MODEL := preload("res://assets/rooms/circus/balloon.glb") # Vorlagen, gebaut mit art/blender/circus.py
const COLORS := [Color(0.85, 0.12, 0.12), Color(0.95, 0.75, 0.15), Color(0.15, 0.4, 0.85),
	Color(0.2, 0.7, 0.35), Color(0.8, 0.3, 0.7)]
const STEP := 0.1
const R := 0.052
const STRING_LEN := 0.36

var _balloons: Array[Dictionary] = []
var _ball_mesh: Mesh # Tropfenform und Knoten aus dem Modell
var _knot_mesh: Mesh
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	for b in _balloons:
		if not b.alive:
			continue
		var root: Node3D = b.root
		root.rotation.z = sin(_t * 1.1 + b.phase) * 0.06 + float(b.shake) * sin(_t * 60.0) * 0.08
		root.rotation.x = sin(_t * 0.8 + b.phase * 2.0) * 0.04


func set_lives(count: int) -> void:
	for b in _balloons:
		(b.root as Node3D).queue_free()
	_balloons.clear()
	if _ball_mesh == null:
		var src := MODEL.instantiate()
		_ball_mesh = (src.find_child("Ballon", true, false) as MeshInstance3D).mesh
		_knot_mesh = (src.find_child("Ballonknoten", true, false) as MeshInstance3D).mesh
		src.free()
	for i in maxi(count, 0):
		var root := Node3D.new() # dreht sich um den Knoten an der Tischkante
		root.position = Vector3((i - (count - 1) * 0.5) * STEP, 0, 0)
		add_child(root)
		var string := RoomKit.mat(Color(0.9, 0.9, 0.85), 0.8)
		var s := RoomKit.cyl(root, 0.0015, 0.0015, STRING_LEN, Vector3(0, STRING_LEN * 0.5, 0), string, 4)
		s.rotation.z = (i - (count - 1) * 0.5) * -0.06
		var m := RoomKit.mat(COLORS[i % COLORS.size()], 0.25)
		m.metallic_specular = 0.8
		var top := Vector3(-sin(s.rotation.z) * STRING_LEN, STRING_LEN, 0)
		var ball := MeshInstance3D.new()
		ball.mesh = _ball_mesh
		ball.material_override = m
		ball.position = top + Vector3(0, R * 1.1, 0)
		ball.scale = Vector3(1.0, 1.2, 1.0)
		root.add_child(ball)
		var knot := MeshInstance3D.new() # Knoten
		knot.mesh = _knot_mesh
		knot.material_override = m
		knot.position = top + Vector3(0, 0.005, 0)
		root.add_child(knot)
		RoomKit.sphere(ball, 0.008, Vector3(-0.02, 0.025, 0.042), RoomKit.glow(Color(1, 1, 1), 0.4)) # Glanz
		_balloons.append({"root": root, "ball": ball, "alive": true, "phase": randf() * TAU, "shake": 0.0,
			"color": COLORS[i % COLORS.size()]})


func lose_life() -> void:
	for i in range(_balloons.size() - 1, -1, -1):
		var b: Dictionary = _balloons[i]
		if b.alive:
			b.alive = false
			b.shake = 1.0
			_pop(b)
			return


func _pop(b: Dictionary) -> void:
	var root: Node3D = b.root
	var ball: MeshInstance3D = b.ball
	var tw := create_tween()
	tw.tween_property(ball, "scale", Vector3(1.15, 1.35, 1.15), 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		RoomKit.play(self, SND_POP, -8.0)
		var conf := CPUParticles3D.new()
		conf.position = ball.position
		conf.one_shot = true
		conf.amount = 40
		conf.lifetime = 1.6
		conf.explosiveness = 1.0
		conf.direction = Vector3.UP
		conf.spread = 180.0
		conf.initial_velocity_min = 0.4
		conf.initial_velocity_max = 0.9
		conf.gravity = Vector3(0, -0.9, 0)
		conf.damping_min = 0.6
		conf.damping_max = 1.2
		conf.angular_velocity_min = -400.0
		conf.angular_velocity_max = 400.0
		var q := QuadMesh.new()
		q.size = Vector2(0.012, 0.008)
		var qm := StandardMaterial3D.new()
		qm.vertex_color_use_as_albedo = true
		qm.cull_mode = BaseMaterial3D.CULL_DISABLED
		q.material = qm
		conf.mesh = q
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
		g.colors = PackedColorArray([b.color, Color(0.95, 0.85, 0.2), Color(0.2, 0.5, 0.95), Color(0.9, 0.2, 0.6)])
		conf.color_initial_ramp = g
		root.add_child(conf)
		conf.emitting = true
		ball.visible = false
		# geplatzte Fetzen am Knoten
		RoomKit.sphere(root, 0.014, ball.position - Vector3(0, R * 1.0, 0),
			ball.material_override, Vector3(1.0, 0.6, 1.0))
		b.shake = 0.0
		get_tree().create_timer(2.0).timeout.connect(conf.queue_free))
