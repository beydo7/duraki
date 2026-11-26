class_name BankerLamp
extends Node3D
## Grüne Bankerlampe (Schreibtischlampe mit grünem Glasschirm, Messingfuß und Zugkette).
## Steht im Casino dort, wo im Hinterzimmer die Kerzen stehen, und zeigt die Leben:
## auf dem Messingfuß leuchtet pro Leben ein kleines rotes Lämpchen. Verlierst du ein
## Leben, flackert die Lampe und ein Lämpchen geht aus; beim letzten geht die Lampe aus.
## Zugkette: anklicken (wenn `interactive`) → die Kette wird ein Stück heruntergezogen
## und schnellt zurück, mit Klick-Geräusch geht die Lampe an bzw. aus.
## Die Form kommt aus Blender (banker_lamp.glb, gebaut mit art/blender/casino.py); Materialien,
## Licht, Zugkette und Lämpchen steuert der Code. Maße in echten Metern, am Ende verkleinert.

const MODEL := preload("res://assets/rooms/casino/banker_lamp.glb")
const SND_CHAIN := preload("res://assets/rooms/casino/lamp_chain.wav")

const SIZE := 0.75 # Verkleinerung gegenüber einer echten Lampe (passt zu den Karten)
const SHADE_LEN := 0.26
const SHADE_R := 0.072
const SHADE_Y := 0.33

var _root: Node3D
var _jewels: Array[MeshInstance3D] = []
var _jewel_on: StandardMaterial3D
var _jewel_off: StandardMaterial3D
var _jewel_mesh: Mesh # geschliffenes Lämpchen und seine Messingfassung (Vorlagen aus dem Modell)
var _bezel_mesh: Mesh
var _brass: StandardMaterial3D
var _inner: StandardMaterial3D
var _bulb: StandardMaterial3D
var _glass: StandardMaterial3D
var _spot: SpotLight3D
var _glow: OmniLight3D
var _lives := 0
## 1 = an, 0 = aus (Flackern beim Lebensverlust)
var _power := 1.0
## Schalter der Zugkette: 1 = an, 0 = aus (weich überblendet)
var _switch := 1.0
var _on := true
var _chain: Node3D
var _pulling := false
## Kette anklickbar (nur im Duell)
var interactive := false:
	set(v):
		interactive = v
		if _chain_area != null:
			_chain_area.input_ray_pickable = v
var _chain_area: Area3D
var _t := 0.0


func _init() -> void:
	_root = Node3D.new()
	_root.scale = Vector3.ONE * SIZE
	add_child(_root)
	_build()


func _process(delta: float) -> void:
	_t += delta
	# ganz leichtes Netzbrummen im Licht, sonst ruhig (keine Kerze)
	var hum := 1.0 + 0.015 * sin(_t * 31.0)
	var p := _power * _switch
	_spot.light_energy = 4.0 * p * hum
	_glow.light_energy = 0.6 * p * hum
	_inner.emission_energy_multiplier = 1.6 * p
	_bulb.emission_energy_multiplier = 4.0 * p
	_glass.emission_energy_multiplier = 0.55 * p


## An der Zugkette ziehen: Kette runter und zurück, Lampe an/aus.
func pull_chain() -> void:
	if _pulling:
		return
	_pulling = true
	_on = not _on
	_play_chain()
	var tw := create_tween()
	tw.tween_property(_chain, "position:y", -0.028, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		var sw := create_tween()
		sw.tween_property(self, "_switch", 1.0 if _on else 0.0, 0.06))
	tw.tween_property(_chain, "position:y", 0.0, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _pulling = false)


func _play_chain() -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var pl := AudioStreamPlayer.new()
	pl.bus = &"SFX"
	pl.stream = SND_CHAIN
	pl.volume_db = -10.0
	add_child(pl)
	pl.play()
	pl.finished.connect(pl.queue_free)


func _on_chain_input(_cam: Node, event: InputEvent, _p: Vector3, _n: Vector3, _i: int) -> void:
	if interactive and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		pull_chain()


## Lämpchen für die Leben setzen (einmal beim Aufbau).
func set_lives(count: int) -> void:
	for j in _jewels:
		j.queue_free()
	_jewels.clear()
	_lives = count
	var step := minf(0.026, 0.15 / maxf(count - 1, 1))
	for i in count:
		var j := MeshInstance3D.new()
		j.mesh = _jewel_mesh
		j.material_override = _jewel_on
		j.position = Vector3((i - (count - 1) * 0.5) * step, 0.036, 0.05)
		_root.add_child(j)
		_jewels.append(j)
		var bezel := MeshInstance3D.new()
		bezel.mesh = _bezel_mesh
		bezel.material_override = _brass
		j.add_child(bezel)


## Ein Leben weg: Lampe flackert, das letzte leuchtende Lämpchen erlischt.
func lose_life() -> void:
	if _lives <= 0:
		return
	_lives -= 1
	var j := _jewels[_lives]
	var last := _lives == 0
	var tw := create_tween()
	for k in 4: # kurzes Flackern
		tw.tween_property(self, "_power", 0.25, 0.05)
		tw.tween_property(self, "_power", 1.0, 0.07 + k * 0.03)
	tw.tween_callback(func() -> void: j.material_override = _jewel_off)
	if last: # letzte Kerze → Lampe geht aus
		tw.tween_property(self, "_power", 0.0, 0.5).set_trans(Tween.TRANS_SINE)


# --- Aufbau --------------------------------------------------------------------------

func _build() -> void:
	var brass := StandardMaterial3D.new()
	_brass = brass
	brass.albedo_color = Color(0.86, 0.64, 0.3)
	brass.metallic = 1.0
	brass.roughness = 0.22
	_glass = StandardMaterial3D.new()
	_glass.albedo_color = Color(0.01, 0.2, 0.07)
	_glass.roughness = 0.06
	_glass.metallic_specular = 0.9
	_glass.clearcoat_enabled = true
	_glass.emission_enabled = true
	_glass.emission = Color(0.03, 0.3, 0.1) # Glas schimmert grün durch
	_glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	_inner = StandardMaterial3D.new()
	_inner.albedo_color = Color(0.98, 0.94, 0.82)
	_inner.emission_enabled = true
	_inner.emission = Color(1.0, 0.86, 0.6)
	_inner.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bulb = StandardMaterial3D.new()
	_bulb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bulb.albedo_color = Color(1.0, 0.9, 0.7)
	_bulb.emission_enabled = true
	_bulb.emission = Color(1.0, 0.82, 0.55)
	_jewel_on = StandardMaterial3D.new()
	_jewel_on.albedo_color = Color(0.9, 0.08, 0.06)
	_jewel_on.roughness = 0.15
	_jewel_on.emission_enabled = true
	_jewel_on.emission = Color(1.0, 0.12, 0.08)
	_jewel_on.emission_energy_multiplier = 2.2
	_jewel_off = StandardMaterial3D.new()
	_jewel_off.albedo_color = Color(0.2, 0.03, 0.03)
	_jewel_off.roughness = 0.25

	# Fuß, Säule, Schirm, Birnen und Zugkette aus Blender; „Schirm“ ist leicht zum Spieler gekippt
	var model := RoomKit.model(_root, MODEL, {
		"Lampenmessing": brass, "Glas_Gruen": _glass, "Schirm_Innen": _inner, "Gluehbirne": _bulb,
	})
	var shade := model.find_child("Schirm", true, false) as Node3D
	for part in ["Schirm_Innen", "Schirm_Birnen"]:
		(shade.find_child(part, true, false) as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Zugkette rechts am Schirm (Knoten „Kette“), beweglich und anklickbar
	_chain = shade.find_child("Kette", true, false) as Node3D
	# Vorlagen für die Lämpchen herausnehmen (set_lives setzt je Leben eines auf den Fuß)
	for part in ["Juwel", "Juwel_Fassung"]:
		var tpl := model.find_child(part, true, false) as MeshInstance3D
		if part == "Juwel":
			_jewel_mesh = tpl.mesh
		else:
			_bezel_mesh = tpl.mesh
		tpl.get_parent().remove_child(tpl)
		tpl.free()
	# großzügige Klickfläche um Kette und Griff (dünne Kette wäre schwer zu treffen)
	_chain_area = Area3D.new()
	_chain_area.input_ray_pickable = interactive
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.06, 0.15, 0.06)
	shape.shape = box
	shape.position = Vector3(SHADE_LEN * 0.36, -0.07, SHADE_R * 0.55)
	_chain_area.add_child(shape)
	_chain_area.input_event.connect(_on_chain_input)
	_chain.add_child(_chain_area)
	# Licht: warmer Kegel nach unten auf den Tisch, dazu ein schwaches grünliches Leuchten
	_spot = SpotLight3D.new()
	_spot.light_color = Color(1.0, 0.84, 0.6)
	_spot.spot_range = 1.0
	_spot.spot_angle = 70.0
	_spot.spot_attenuation = 0.8
	_spot.position = Vector3(0, -0.02, 0)
	_spot.rotation.x = -PI * 0.5
	shade.add_child(_spot)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(0.45, 0.95, 0.55)
	_glow.omni_range = 0.45
	_glow.position = Vector3(0, 0.09, 0)
	shade.add_child(_glow)
