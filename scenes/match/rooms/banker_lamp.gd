class_name BankerLamp
extends Node3D
## Grüne Bankerlampe (Schreibtischlampe mit grünem Glasschirm, Messingfuß und Zugkette).
## Steht im Casino dort, wo im Hinterzimmer die Kerzen stehen, und zeigt die Leben:
## auf dem Messingfuß leuchtet pro Leben ein kleines rotes Lämpchen. Verlierst du ein
## Leben, flackert die Lampe und ein Lämpchen geht aus; beim letzten geht die Lampe aus.
## Ganz in Code gebaut (kein Blender). Maße in echten Metern, am Ende verkleinert.

const SIZE := 0.75 # Verkleinerung gegenüber einer echten Lampe (passt zu den Karten)
const SHADE_LEN := 0.26
const SHADE_R := 0.072
const SHADE_Y := 0.33

var _root: Node3D
var _jewels: Array[MeshInstance3D] = []
var _jewel_on: StandardMaterial3D
var _jewel_off: StandardMaterial3D
var _inner: StandardMaterial3D
var _bulb: StandardMaterial3D
var _glass: StandardMaterial3D
var _spot: SpotLight3D
var _glow: OmniLight3D
var _lives := 0
## 1 = an, 0 = aus (Flackern beim Lebensverlust)
var _power := 1.0
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
	_spot.light_energy = 4.0 * _power * hum
	_glow.light_energy = 0.6 * _power * hum
	_inner.emission_energy_multiplier = 1.6 * _power
	_bulb.emission_energy_multiplier = 4.0 * _power
	_glass.emission_energy_multiplier = 0.55 * _power


## Lämpchen für die Leben setzen (einmal beim Aufbau).
func set_lives(count: int) -> void:
	for j in _jewels:
		j.queue_free()
	_jewels.clear()
	_lives = count
	var step := minf(0.026, 0.15 / maxf(count - 1, 1))
	var m := SphereMesh.new()
	m.radius = 0.0085
	m.height = 0.012
	for i in count:
		var j := MeshInstance3D.new()
		j.mesh = m
		j.material_override = _jewel_on
		j.position = Vector3((i - (count - 1) * 0.5) * step, 0.036, 0.05)
		_root.add_child(j)
		_jewels.append(j)


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

	# Fuß: zwei ovale Stufen und ein kleiner Kegel
	_cyl(0.11, 0.115, 0.02, Vector3(0, 0.01, 0), brass, 0.62)
	_cyl(0.085, 0.095, 0.016, Vector3(0, 0.028, 0), brass, 0.6)
	_cyl(0.022, 0.045, 0.03, Vector3(0, 0.05, -0.02), brass)
	# Säule mit Zierknauf und Ring
	_cyl(0.009, 0.009, 0.24, Vector3(0, 0.18, -0.02), brass)
	var knob := MeshInstance3D.new()
	var km := SphereMesh.new()
	km.radius = 0.02
	km.height = 0.032
	knob.mesh = km
	knob.material_override = brass
	knob.position = Vector3(0, 0.1, -0.02)
	_root.add_child(knob)
	_cyl(0.016, 0.016, 0.008, Vector3(0, 0.22, -0.02), brass)
	# Halter zum Schirm (kurzer Bogen nach vorn)
	_cyl(0.007, 0.007, 0.045, Vector3(0, SHADE_Y - 0.01, -0.0), brass).rotation.x = PI * 0.5
	# Schirm: halbe Röhre, Öffnung unten, leicht zum Spieler gekippt
	var shade := Node3D.new()
	shade.position = Vector3(0, SHADE_Y, 0.02)
	shade.rotation.x = 0.28
	_root.add_child(shade)
	var outer := MeshInstance3D.new()
	outer.mesh = _half_tube(SHADE_R, SHADE_LEN, true)
	outer.material_override = _glass
	shade.add_child(outer)
	var inner := MeshInstance3D.new()
	inner.mesh = _half_tube(SHADE_R * 0.96, SHADE_LEN * 0.99, false)
	inner.material_override = _inner
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shade.add_child(inner)
	# Messingkappen an den Enden und Leiste unten
	for sx in [-1.0, 1.0]:
		var cap := MeshInstance3D.new()
		var cm := TorusMesh.new()
		cm.inner_radius = SHADE_R - 0.004
		cm.outer_radius = SHADE_R + 0.004
		cm.rings = 32
		cm.ring_segments = 6
		cap.mesh = cm
		cap.material_override = brass
		cap.rotation.z = PI * 0.5
		cap.scale = Vector3(1, 0.5, 1)
		cap.position.x = sx * SHADE_LEN * 0.5
		shade.add_child(cap)
	# Glühbirne unter dem Schirm
	var bulb := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.022
	bm.height = 0.05
	bulb.mesh = bm
	bulb.material_override = _bulb
	bulb.position = Vector3(0, -0.01, 0)
	bulb.rotation.z = PI * 0.5
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shade.add_child(bulb)
	# Zugkette rechts am Schirm (Kügelchen mit Messinggriff)
	var bead := SphereMesh.new()
	bead.radius = 0.0035
	bead.height = 0.007
	for k in 12:
		var b := MeshInstance3D.new()
		b.mesh = bead
		b.material_override = brass
		b.position = Vector3(SHADE_LEN * 0.36, -0.012 - k * 0.0085, SHADE_R * 0.55)
		shade.add_child(b)
	var grip := MeshInstance3D.new()
	var gm := CylinderMesh.new()
	gm.top_radius = 0.004
	gm.bottom_radius = 0.008
	gm.height = 0.022
	grip.mesh = gm
	grip.material_override = brass
	grip.position = Vector3(SHADE_LEN * 0.36, -0.12, SHADE_R * 0.55)
	shade.add_child(grip)
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


## Halbe Röhre entlang x (obere Hälfte), Öffnung zeigt nach unten.
## Mit Halbkreis-Deckeln an beiden Enden (nur außen).
static func _half_tube(r: float, length: float, caps: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 28
	var hx := length * 0.5
	for i in seg:
		var a0 := PI * i / seg
		var a1 := PI * (i + 1) / seg
		var n0 := Vector3(0, sin(a0), cos(a0))
		var n1 := Vector3(0, sin(a1), cos(a1))
		var p00 := Vector3(-hx, 0, 0) + n0 * r
		var p10 := Vector3(hx, 0, 0) + n0 * r
		var p01 := Vector3(-hx, 0, 0) + n1 * r
		var p11 := Vector3(hx, 0, 0) + n1 * r
		for v in [[p00, n0], [p10, n0], [p11, n1], [p00, n0], [p11, n1], [p01, n1]]:
			st.set_normal(v[1])
			st.add_vertex(v[0])
		if caps:
			for sx in [-1.0, 1.0]:
				var c := Vector3(sx * hx, 0, 0)
				var n := Vector3(sx, 0, 0)
				for v in [c, c + Vector3(0, 0, 0) + n0 * r, c + n1 * r]:
					st.set_normal(n)
					st.add_vertex(Vector3(sx * hx, v.y, v.z))
	return st.commit()


func _cyl(top: float, bottom: float, h: float, pos: Vector3, m: Material, squash := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 32
	mi.mesh = c
	mi.material_override = m
	mi.position = pos
	mi.scale.z = squash
	_root.add_child(mi)
	return mi
