extends Control
## Hauptmenü in 3D: Du sitzt schon am Tisch im Hinterzimmer, gegenüber wartet eine
## Gestalt im Dunkeln. Die Menüpunkte liegen als Karten auf dem Tisch (anklickbar)
## und stehen zusätzlich links als Knöpfe (Tastatur/Controller).

const MENU_OPPONENT := "res://data/opponents/crow.tres"
var CAM_START := Transform3D(Basis.from_euler(Vector3(-0.18, 0, 0)), Vector3(0, 1.62, 1.75))
const CARD_Z := 0.08

var world: TableWorld
var _cards: Array[MenuCard3D] = []
var _buttons: Array[Button] = []
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
		["SPIELEN", "Neuer Run", "♠", Color("1b1426"), _start_run],
		["DECKS", "Karten wählen", "♥", Color("92201b"), _open_decks],
		["OPTIONEN", "Bild · Ton · Spiel", "♦", Color("92201b"), _open_options],
		["BEENDEN", "Aufstehen und gehen", "♣", Color("1b1426"), _quit],
	]
	for i in specs.size():
		var s: Array = specs[i]
		var card := MenuCard3D.new().setup(s[0], s[1], s[2], s[3])
		var f := i - 1.5
		var x := f * 0.19
		card.transform = Transform3D(Basis.from_euler(Vector3(0, -f * 0.09, 0)), Vector3(x, TableWorld.TABLE_Y + 0.002, CARD_Z + absf(f) * 0.03))
		world.add_child(card)
		card.chosen.connect(s[4])
		card.hovered_changed.connect(func(c: MenuCard3D, on: bool) -> void:
			if on:
				_focus(_cards.find(c)))
		_cards.append(card)

	UIKit.poster_wedge(self, Vector2(640, 335), %TitleBlock, "ДУРАКИ · НОЧЬ В ЗАДНЕЙ КОМНАТЕ")
	_buttons = [%PlayButton, %DecksButton, %OptionsButton, %QuitButton]
	_update_info()
	Profile.changed.connect(_update_info)
	for i in _buttons.size():
		var b: Button = _buttons[i]
		UIKit.hover(b, 1.04)
		b.pressed.connect(specs[i][4])
		var index := i
		b.focus_entered.connect(func() -> void: _focus(index))
		b.mouse_entered.connect(func() -> void: _focus(index))

	# Auftritt: Kamera gleitet an den Tisch, Titel und Menü blenden ein
	var seat := world.get_camera_pose()
	world.set_camera_pose(CAM_START)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		world.set_camera_pose(CAM_START.interpolate_with(seat, v)),
		0.0, 1.0, 2.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	UIKit.appear(%TitleBlock, 0.5, Vector2(-30, 0), 0.8)
	UIKit.appear(%MenuList, 1.0, Vector2(-30, 0), 0.6)
	UIKit.appear(%Hint, 1.4, Vector2(0, 8), 0.6)
	%PlayButton.grab_focus.call_deferred()


func _process(delta: float) -> void:
	_t += delta
	# Titel flackert ganz leicht wie unter einer alten Glühbirne
	var flicker := 1.0 - 0.06 * maxf(0.0, sin(_t * 17.0) * sin(_t * 3.1) - 0.6) * 2.5
	%Title.self_modulate = Color(flicker, flicker, flicker)


func _focus(index: int) -> void:
	for i in _cards.size():
		_cards[i].focused = i == index
	if index >= 0 and index < _buttons.size() and not _buttons[index].has_focus():
		_buttons[index].grab_focus()


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
	menu.closed.connect(func() -> void: %DecksButton.grab_focus())


func _open_options() -> void:
	var menu := OptionsMenu.new()
	add_child(menu)
	menu.closed.connect(func() -> void: %OptionsButton.grab_focus())


func _quit() -> void:
	get_tree().quit()

