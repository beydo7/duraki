class_name LedLives
extends Node3D
## LED-Anzeige an der Wand des Bahnhofswartesaals – zeigt die Leben.
## Pro Leben eine rote Leuchte in einem Blechkasten. Verlierst du ein Leben, blinkt die
## letzte leuchtende LED kurz und geht dann aus. Der Kasten wächst mit der Anzahl.

const SND_CLICK := preload("res://assets/rooms/station/neon_tick.wav")
const STEP := 0.12 # Abstand der LEDs
const LED_R := 0.034
const HEIGHT := 0.2

var _leds: Array[Dictionary] = []
var _box: MeshInstance3D
var _face: MeshInstance3D
var _on: StandardMaterial3D
var _off: StandardMaterial3D
var _frame: StandardMaterial3D
var _black: StandardMaterial3D


func _init() -> void:
	_frame = StandardMaterial3D.new()
	_frame.albedo_color = Color(0.3, 0.32, 0.31)
	_frame.metallic = 0.6
	_frame.roughness = 0.45
	_black = StandardMaterial3D.new()
	_black.albedo_color = Color(0.03, 0.03, 0.035)
	_black.roughness = 0.7
	_on = StandardMaterial3D.new()
	_on.albedo_color = Color(1.0, 0.15, 0.1)
	_on.emission_enabled = true
	_on.emission = Color(1.0, 0.12, 0.06)
	_on.emission_energy_multiplier = 3.5
	_on.roughness = 0.2
	_off = StandardMaterial3D.new()
	_off.albedo_color = Color(0.22, 0.04, 0.04)
	_off.roughness = 0.25
	_box = MeshInstance3D.new()
	_box.material_override = _frame
	add_child(_box)
	_face = MeshInstance3D.new()
	_face.material_override = _black
	add_child(_face)
	set_lives(3)


## Eine LED pro Leben (Kasten passt sich an).
func set_lives(count: int) -> void:
	for l in _leds:
		(l.root as Node3D).queue_free()
	_leds.clear()
	count = maxi(count, 1)
	var w := count * STEP + 0.06
	var bm := BoxMesh.new()
	bm.size = Vector3(w, HEIGHT, 0.06)
	_box.mesh = bm
	_box.position.z = 0.03
	var fm := BoxMesh.new()
	fm.size = Vector3(w - 0.03, HEIGHT - 0.03, 0.01)
	_face.mesh = fm
	_face.position.z = 0.061
	for i in count:
		var root := Node3D.new()
		root.position = Vector3((i - (count - 1) * 0.5) * STEP, 0, 0.066)
		add_child(root)
		# Fassung (Metallring) und die LED als halbe Kugel
		var ring := MeshInstance3D.new()
		var rm := TorusMesh.new()
		rm.inner_radius = LED_R
		rm.outer_radius = LED_R + 0.01
		rm.rings = 24
		rm.ring_segments = 8
		ring.mesh = rm
		ring.material_override = _frame
		ring.rotation.x = PI * 0.5
		root.add_child(ring)
		var led := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = LED_R
		sm.height = LED_R * 2.0
		sm.is_hemisphere = true
		led.mesh = sm
		led.material_override = _on
		led.rotation.x = PI * 0.5 # Wölbung zeigt nach vorn
		root.add_child(led)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.2, 0.12)
		light.light_energy = 0.35
		light.omni_range = 0.45
		light.position.z = 0.06
		root.add_child(light)
		_leds.append({"root": root, "led": led, "light": light, "on": true})


## Ein Leben weg: die letzte leuchtende LED blinkt dreimal und geht aus.
func lose_life() -> void:
	for i in range(_leds.size() - 1, -1, -1):
		var l: Dictionary = _leds[i]
		if l.on:
			l.on = false
			var led: MeshInstance3D = l.led
			var light: OmniLight3D = l.light
			var tw := create_tween()
			for k in 3:
				tw.tween_callback(func() -> void:
					led.material_override = _off
					light.visible = false)
				tw.tween_interval(0.12)
				tw.tween_callback(func() -> void:
					led.material_override = _on
					light.visible = true)
				tw.tween_interval(0.12)
			tw.tween_callback(func() -> void:
				led.material_override = _off
				light.visible = false
				_click())
			return


func _click() -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX"
	p.stream = SND_CLICK
	p.volume_db = -14.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
