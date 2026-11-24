extends Control
## Hauptmenü in 3D: Du sitzt schon am Tisch im Hinterzimmer, gegenüber wartet eine
## Gestalt im Dunkeln. Die Menüpunkte liegen als Karten auf dem Tisch: anklicken
## oder mit Pfeiltasten/Controller wählen und mit Enter/A bestätigen.

const MENU_OPPONENT := "res://data/opponents/crow.tres"
var CAM_START := Transform3D(Basis.from_euler(Vector3(-0.18, 0, 0)), Vector3(0, 1.62, 1.75))
const CARD_Z := 0.08

var world: TableWorld
var _cards: Array[MenuCard3D] = []
var _actions: Array[Callable] = []
var _sel := 0
var _sub_open := false
var _leaving := false
var _t := 0.0


func _ready() -> void:
	world = TableWorld.new()
	%Viewport.add_child(world)
	var opp := load(MENU_OPPONENT) as OpponentData
	world.build_room(opp, false)
	world.sway_strength = 0.6
	Settings.apply_viewport(%Viewport)
	UIKit.fit_viewport(self, %View, %Viewport)
	get_viewport().size_changed.connect(func() -> void: UIKit.fit_viewport(self, %View, %Viewport))

	# Menükarten fächerförmig auf dem Tisch
	var specs := [
		["SPIELEN", "Neuer Run", "♠", Color("ecc87c"), _start_run],
		["DECKS", "Karten wählen", "♥", Color("f2625c"), _open_decks],
		["OPTIONEN", "Bild · Ton · Spiel", "♦", Color("f2625c"), _open_options],
		["INDEX", "Alles im Spiel", "★", Color("ecc87c"), _open_index],
		["BEENDEN", "Aufstehen und gehen", "♣", Color("ecc87c"), _quit],
	]
	for i in specs.size():
		var s: Array = specs[i]
		var card := MenuCard3D.new().setup(s[0], s[1], s[2], s[3])
		var f := i - (specs.size() - 1) * 0.5
		var x := f * 0.175
		card.transform = Transform3D(Basis.from_euler(Vector3(0, -f * 0.09, 0)), Vector3(x, TableWorld.TABLE_Y + 0.002, CARD_Z + absf(f) * 0.03))
		world.add_child(card)
		card.chosen.connect(func() -> void: Sfx.play(&"card_select"))
		card.chosen.connect(s[4])
		card.hovered_changed.connect(func(c: MenuCard3D, on: bool) -> void:
			if on:
				_focus(_cards.find(c)))
		_cards.append(card)
		_actions.append(s[4])

	UIKit.poster_wedge(self, Vector2(640, 335), %TitleBlock, "BEYD & FLÖRRY")
	_update_info()
	Profile.changed.connect(_update_info)

	# Auftritt: Kamera gleitet an den Tisch, Titel und Menü blenden ein
	var seat := world.get_camera_pose()
	# Easter Egg: Schnapsglas oft genug anklicken → austrinken
	var egg := ShotGlassEgg.new()
	world.add_child(egg)
	egg.setup(world, func() -> Transform3D: return seat)
	world.set_camera_pose(CAM_START)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		world.set_camera_pose(CAM_START.interpolate_with(seat, v)),
		0.0, 1.0, 2.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	UIKit.appear(%TitleBlock, 0.5, Vector2(-30, 0), 0.8)
	UIKit.appear(%Hint, 1.4, Vector2(0, 8), 0.6)
	_focus(0, true)


func _process(delta: float) -> void:
	_t += delta
	# Titel flackert ganz leicht wie unter einer alten Glühbirne
	var flicker := 1.0 - 0.06 * maxf(0.0, sin(_t * 17.0) * sin(_t * 3.1) - 0.6) * 2.5
	%Title.self_modulate = Color(flicker, flicker, flicker)


func _focus(index: int, silent := false) -> void:
	if index < 0 or index >= _cards.size():
		return
	if not silent and (index != _sel or not _cards[index].focused):
		# leicht andere Tonhöhe je Karte, wie Töne auf einer Tonleiter
		Sfx.play(&"card_hover", [0.94, 1.0, 1.06, 1.12, 1.19][index % 5], -3.0)
	_sel = index
	for i in _cards.size():
		_cards[i].focused = i == index


## Tastatur/Controller: links/rechts (oder hoch/runter) wechselt die Karte, Bestätigen wählt sie.
func _unhandled_input(event: InputEvent) -> void:
	if _leaving or _sub_open:
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_focus(wrapi(_sel - 1, 0, _cards.size()))
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_focus(wrapi(_sel + 1, 0, _cards.size()))
	elif event.is_action_pressed("ui_accept"):
		Sfx.play(&"card_select")
		_actions[_sel].call()
	else:
		return
	get_viewport().set_input_as_handled()


func _start_run() -> void:
	if _leaving:
		return
	_leaving = true
	# Kamera beugt sich zum Tisch, dann beginnt der Run
	var from := world.get_camera_pose()
	var to := Transform3D(from.basis.rotated(from.basis.x, -0.25), from.origin + Vector3(0, -0.12, -0.32))
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: world.set_camera_pose(from.interpolate_with(to, v)),
		0.0, 1.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: Run.start_new_run())


func _update_info() -> void:
	var d := Profile.selected_deck()
	%Hint.text = "Deck: %s   ·   %d Seelen" % [d.display_name if d else "–", Profile.souls]


func _open_decks() -> void:
	var menu := DeckMenu.new()
	add_child(menu)
	_sub_open = true
	menu.closed.connect(func() -> void: _sub_open = false)


func _open_options() -> void:
	var menu := OptionsMenu.new()
	add_child(menu)
	_sub_open = true
	menu.closed.connect(func() -> void: _sub_open = false)


func _open_index() -> void:
	var menu := IndexMenu.new()
	add_child(menu)
	_sub_open = true
	menu.closed.connect(func() -> void: _sub_open = false)


func _quit() -> void:
	get_tree().quit()

