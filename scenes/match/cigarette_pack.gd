class_name CigarettePack
extends Node3D
## Zigarettenschachtel neben deinem Aschenbecher (eigene Marke „DURAKI“, rot-weiß).
##   1. Klick → Deckel klappt auf
##   2. Klick → drei Zigaretten rutschen halb heraus
##   3. Klick → eine Zigarette wandert in den Aschenbecher (dort anklicken = anzünden, rauchen)
## Ist sie aufgeraucht, holt der nächste Klick die nächste aus der Schachtel.
## Pro Run gibt es eine Schachtel mit 6 Zigaretten (zweimal 3), danach ist sie leer.

const W := 0.056 # Breite
const H := 0.086 # Höhe
const D := 0.023 # Tiefe
const LID_H := 0.026
const CIG_R := 0.0042
const CIG_LEN := 0.084

enum Step { CLOSED, OPEN, OUT }

var ashtray: Ashtray
var step := Step.CLOSED
## Zigaretten noch in der Schachtel: eine Schachtel (6 Stück) pro Run, also zweimal 3
var left: int:
	get: return maxi(Profile.PACK_SIZE - Run.cigarettes_taken, 0)
var _busy := false
var _lid: Node3D
var _brand: Label3D
var _cigs: Array[Node3D] = []


func _ready() -> void:
	_build()


func _build() -> void:
	var white := _mat(Color(0.95, 0.94, 0.9), 0.55)
	var red := Cosmetics.cig_mat(&"pack") # Deck-Belohnung: andere Farbe der Schachtel
	var inner := _mat(Color(0.82, 0.78, 0.68), 0.8) # Silberpapier/Karton innen
	var foil := _mat(Color(0.75, 0.74, 0.7), 0.3, 0.8)
	var body_h := H - LID_H
	# Modell (Maße wie die Konstanten oben): Körper mit rotem Streifen unten und rotem Dreieck vorne
	# und hinten (eigenes Design, kein Markenlogo), Innenkragen und Folie, die beim Öffnen sichtbar
	# werden, Deckel mit Scharnier an der Rückseite oben
	var lib := Ashtray.MODEL.instantiate()
	var pack := RoomKit.part(lib, "Schachtel", self,
		{"Schachtel_Weiss": white, "Schachtel_Farbe": red, "Schachtel_Innen": inner, "Schachtel_Folie": foil})
	_lid = pack.find_child("Schachtel_Deckel", true, false)
	# Beschriftung vorne (Label3D, erfundene Marke)
	_label("★", 22, Color(0.98, 0.9, 0.7), Vector3(0, body_h * 0.86, D * 0.5 + 0.0008), self)
	_brand = _label("DURAKI", 28, red.albedo_color, Vector3(0, body_h * 0.43, D * 0.5 + 0.0008), self)
	Profile.changed.connect(func() -> void: _brand.modulate = Cosmetics.cig_mat(&"pack").albedo_color)
	_label("FEINE TABAKE", 11, Color(0.35, 0.3, 0.28), Vector3(0, body_h * 0.28, D * 0.5 + 0.0008), self)
	_label("DURAKI", 22, Color(0.98, 0.95, 0.9), Vector3(0, LID_H * 0.5, D + 0.0009), _lid)
	# drei Zigaretten im Inneren (Filter oben), zunächst versteckt in der Schachtel
	for i in 3:
		var c := Node3D.new()
		c.position = Vector3((i - 1) * 0.013, body_h - CIG_LEN * 0.5 + 0.004, 0.0)
		add_child(c)
		_stick(c, lib)
		c.visible = false
		_cigs.append(c)
	lib.free()
	# Klickfläche über die ganze Schachtel
	var area := Area3D.new()
	area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(W + 0.01, H + 0.04, D + 0.02)
	shape.shape = box
	shape.position = Vector3(0, H * 0.5 + 0.01, 0)
	area.add_child(shape)
	add_child(area)
	area.input_event.connect(_on_input)


func _on_input(_cam: Node, event: InputEvent, _p: Vector3, _n: Vector3, _i: int) -> void:
	if _busy or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	get_viewport().set_input_as_handled()
	match step:
		Step.CLOSED:
			_open()
		Step.OPEN:
			_slide_out()
		Step.OUT:
			_take()


## Deckel klappt nach hinten auf.
func _open() -> void:
	_busy = true
	Sfx.play(&"card_select", 1.15)
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", -deg_to_rad(118.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		step = Step.OPEN
		_busy = false)


## 2–3 Zigaretten rutschen halb heraus.
func _slide_out() -> void:
	if left <= 0:
		Sfx.play(&"bottle_knock", 1.4, -8.0) # leer
		return
	_busy = true
	Sfx.play(&"card_hand_hover", 0.75)
	var n := mini(3, left)
	var tw := create_tween().set_parallel()
	for i in 3:
		var c := _cigs[i]
		c.visible = i < n
		if i >= n:
			continue
		var base_y := H - LID_H - CIG_LEN * 0.5 + 0.004
		c.position.y = base_y
		tw.tween_property(c, "position:y", base_y + CIG_LEN * (0.38 + 0.08 * ((i + 1) % 3)), 0.3) \
			.set_delay(i * 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(func() -> void:
		step = Step.OUT
		_busy = false)


## Die am weitesten herausstehende Zigarette wandert in den Aschenbecher.
func _take() -> void:
	if ashtray == null or not ashtray.wants_cigarette():
		# Aschenbecher noch belegt: kurz wackeln
		var tw0 := create_tween()
		tw0.tween_property(self, "rotation:z", 0.06, 0.05)
		tw0.tween_property(self, "rotation:z", 0.0, 0.1)
		return
	var pick: Node3D = null
	for c in _cigs:
		if c.visible and (pick == null or c.position.y > pick.position.y):
			pick = c
	if pick == null:
		_slide_out()
		return
	Run.cigarettes_taken += 1
	# Zigarette liegt in der Schachtel senkrecht (Filter oben); der Aschenbecher erwartet
	# „Glut bei x = 0, Filter bei +x“ – also die Lage hier entsprechend drehen
	var from := pick.global_transform * Transform3D(Basis(Vector3.FORWARD, -PI / 2.0), Vector3(0, -CIG_LEN * 0.5, 0))
	pick.visible = false
	ashtray.receive_cigarette(from)
	var still := _cigs.filter(func(c: Node3D) -> bool: return c.visible)
	if still.is_empty():
		step = Step.OPEN # nächster Klick schiebt neue heraus


# --- Bausteine ------------------------------------------------------------------------

## Zigarette in der Schachtel: steht senkrecht, Filter oben (Modell mit Papier, Filter, Tabak).
func _stick(parent: Node3D, lib: Node) -> void:
	RoomKit.part(lib, "Zigarette_Stange", parent, {
		"Zigarettenpapier": Cosmetics.cig_mat(&"paper"),
		"Zigarettenfilter": _mat(Color(0.82, 0.55, 0.28), 0.7),
		"Tabak": _mat(Color(0.35, 0.22, 0.1), 0.95)})


func _label(text: String, size: int, color: Color, pos: Vector3, parent: Node3D) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = UIKit.DISPLAY_FONT if text != "★" else UIKit.SYMBOL_FONT
	l.font_size = size
	l.pixel_size = 0.0004
	l.modulate = color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.position = pos
	parent.add_child(l)
	return l


func _mat(color: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m
