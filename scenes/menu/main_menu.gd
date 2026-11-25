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
var _has_tutorial := false


func _ready() -> void:
	world = TableWorld.new()
	%Viewport.add_child(world)
	var opp := load(MENU_OPPONENT) as OpponentData
	world.build_room(opp, false)
	world.sway_strength = 0.6
	Settings.apply_viewport(%Viewport)
	UIKit.fit_viewport(self, %View, %Viewport)
	get_viewport().size_changed.connect(func() -> void: UIKit.fit_viewport(self, %View, %Viewport))

	_build_cards()
	Settings.changed.connect(func() -> void:
		if _has_tutorial != bool(Settings.get_value("general/show_tutorial")):
			_build_cards())

	UIKit.poster_wedge(self, Vector2(640, 335), %TitleBlock, "BEYD & FLÖRRY")
	%Hint.visible = false # Deck- und Seelen-Anzeige unten links gibt es nicht mehr
	_build_leaderboard()
	Profile.changed.connect(_build_leaderboard)

	# Auftritt: Kamera gleitet an den Tisch, Titel und Menü blenden ein
	var seat := world.get_camera_pose()
	Music.play_main() # Hauptthema ab dem Menü (läuft im Spiel weiter)
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
	_focus(0, true)


## Menükarten fächerförmig auf dem Tisch (mit Tutorial-Karte, solange es nicht geschafft ist).
func _build_cards() -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	_actions.clear()
	_has_tutorial = bool(Settings.get_value("general/show_tutorial"))
	var specs := [
		["SPIELEN", "Neuer Run", "♠", Color("ecc87c"), _start_run],
		["DECKS", "Karten wählen", "♥", Color("f2625c"), _open_decks],
		["OPTIONEN", "Bild · Ton · Spiel", "♦", Color("f2625c"), _open_options],
		["INDEX", "Alles im Spiel", "★", Color("ecc87c"), _open_index],
		["BEENDEN", "Aufstehen und gehen", "♣", Color("ecc87c"), _quit],
	]
	if _has_tutorial:
		specs.push_front(["TUTORIAL", "Übungsrunde mit Hilfe", "?", Color("8fd18a"), _start_tutorial])
	var spread := 0.175 if specs.size() <= 5 else 0.165
	for i in specs.size():
		var s: Array = specs[i]
		var card := MenuCard3D.new().setup(s[0], s[1], s[2], s[3])
		var f := i - (specs.size() - 1) * 0.5
		var x := f * spread
		card.transform = Transform3D(Basis.from_euler(Vector3(0, -f * 0.09, 0)), Vector3(x, TableWorld.TABLE_Y + 0.002, CARD_Z + absf(f) * 0.03))
		world.add_child(card)
		card.chosen.connect(func() -> void: Sfx.play(&"card_select"))
		card.chosen.connect(s[4])
		card.hovered_changed.connect(func(c: MenuCard3D, on: bool) -> void:
			if on:
				_focus(_cards.find(c)))
		_cards.append(card)
		_actions.append(s[4])
	_sel = clampi(_sel, 0, _cards.size() - 1)
	for i in _cards.size():
		_cards[i].focused = i == _sel


func _process(delta: float) -> void:
	_t += delta
	# Titel flackert ganz leicht wie unter einer alten Glühbirne
	var flicker := 1.0 - 0.06 * maxf(0.0, sin(_t * 17.0) * sin(_t * 3.1) - 0.6) * 2.5
	%Title.self_modulate = Color(flicker, flicker, flicker)


func _focus(index: int, silent := false) -> void:
	if index < 0 or index >= _cards.size() or _leaving:
		return # nach „Spielen“ (Kamera fährt an den Tisch) keine Hover-Töne mehr
	if not silent and (index != _sel or not _cards[index].focused):
		# leicht andere Tonhöhe je Karte, wie Töne auf einer Tonleiter
		Sfx.play(&"card_hover", [0.94, 1.0, 1.06, 1.12, 1.19, 1.26][index % 6])
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
	if _leaving or _sub_open:
		return
	var menu := RunSetupMenu.new()
	add_child(menu)
	_sub_open = true
	menu.closed.connect(func() -> void: _sub_open = false)
	menu.started.connect(func() -> void:
		_sub_open = false
		_begin_run())


func _start_tutorial() -> void:
	if _leaving or _sub_open:
		return
	_begin_run(Run.start_tutorial)


func _begin_run(start: Callable = Run.start_new_run) -> void:
	if _leaving:
		return
	_leaving = true
	# Kamera beugt sich zum Tisch, dann beginnt der Run
	var from := world.get_camera_pose()
	var to := Transform3D(from.basis.rotated(from.basis.x, -0.25), from.origin + Vector3(0, -0.12, -0.32))
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: world.set_camera_pose(from.interpolate_with(to, v)),
		0.0, 1.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void: start.call())


## Bestenliste oben rechts: die besten Endlos-Ergebnisse. Vorerst nur die eigenen
## (lokal gespeichert); der Vergleich mit Freunden kommt mit einem Online-Dienst später.
var _board: Slab


func _build_leaderboard() -> void:
	if _board != null:
		_board.queue_free()
	_board = Slab.new()
	_board.color = Color(0.07, 0.055, 0.055, 0.9)
	_board.skew = -0.06
	_board.margins = Vector4(22, 14, 22, 16)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.anchor_left = 1.0
	_board.anchor_right = 1.0
	_board.offset_left = -330.0
	_board.offset_right = -40.0
	_board.offset_top = 36.0
	_board.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_board)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(col)
	var head := UIKit.poster_label("BESTENLISTE", UIKit.display_font(1), 22, UIKit.P_CREAM)
	col.add_child(head)
	col.add_child(UIKit.label("ENDLOS-MODUS · PUNKTE", 11, Color(1, 0.55, 0.5), &"HeaderLabel"))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	col.add_child(gap)
	var records := Profile.endless_records
	if records.is_empty():
		var none := UIKit.label("Noch keine Einträge –\nschaff alle drei Bosse!", 15, UIKit.MUTED, &"TypeLabel")
		col.add_child(none)
	for i in mini(records.size(), 5):
		var r: Dictionary = records[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var place := UIKit.label("%d." % (i + 1), 18, Color(1, 0.84, 0.55) if i == 0 else UIKit.MUTED, &"BrushLabel")
		place.custom_minimum_size = Vector2(26, 0)
		row.add_child(place)
		var who := UIKit.label(String(r.get("name", "Du")), 18, UIKit.CREAM, &"BrushLabel")
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.custom_minimum_size = Vector2(120, 0)
		who.clip_text = true
		row.add_child(who)
		row.add_child(UIKit.label("%d" % int(r.get("score", 0)), 18, Color(1, 0.84, 0.55) if i == 0 else UIKit.CREAM, &"BrushLabel"))
		row.tooltip_text = "%s · %d Decks · %s" % [r.get("deck", ""), int(r.get("decks", 0)), r.get("date", "")]
		col.add_child(row)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 4)
	col.add_child(gap2)
	col.add_child(UIKit.label("Freunde: online kommt bald", 12, Color(UIKit.MUTED, 0.7), &"TypeLabel"))
	UIKit.appear(_board, 1.2, Vector2(20, 0), 0.6)


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

