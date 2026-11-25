extends Node
## Spielt das Tutorial automatisch durch (Hinweise wegklicken, Bot spielt) und prüft,
## dass danach die Tutorial-Karte ausgeblendet ist.
##   godot --headless --path . res://tests/tutorial_test.tscn
var _bot := SimpleAI.new(RandomNumberGenerator.new(), 0.0)
var _tips := 0
func _ready() -> void:
	Profile.reset_for_tests()
	Engine.time_scale = 10.0
	Settings._values["general/show_tutorial"] = true
	_go.call_deferred()
func _go() -> void:
	var ph := Node.new(); get_tree().root.add_child(ph); get_tree().current_scene = ph
	Run.start_tutorial()
	for i in 3000:
		await get_tree().create_timer(0.05).timeout
		var sc = get_tree().current_scene
		if sc == null: continue
		if sc.name == "MainMenu" or sc.scene_file_path == Run.SCENE_MENU:
			var hidden := not bool(Settings.get_value("general/show_tutorial"))
			print("Zurück im Menü. Hinweise: %d, Karte ausgeblendet: %s" % [_tips, hidden])
			print("Tutorial-Test: %s" % ("OK" if _tips >= 10 and hidden else "FEHLER (Tutorial verloren?)"))
			Settings.set_value("general/show_tutorial", true) # echte Einstellung nicht verstellen
			get_tree().quit(); return
		if sc.scene_file_path == Run.SCENE_SHOP:
			# Tutorial-Händler: Erklärungen durchklicken, dann beenden
			if sc.tutorial_step >= 0 and sc.tutorial_step < sc.TUTORIAL_STEPS.size():
				_tips += 1
				sc.tutorial_next()
			else:
				sc.get_node("%ContinueButton").pressed.emit()
			continue
		if sc.scene_file_path != Run.SCENE_MATCH: continue
		var duel: DurakMatch = sc.duel
		if sc.coach != null and sc.coach._open_key != "":
			_tips += 1
			sc.coach._dismiss()
			continue
		if duel.is_over:
			sc.hud.continue_button.pressed.emit()
		elif duel.current_actor() == DurakMatch.PLAYER:
			_bot.take_turn(duel, DurakMatch.PLAYER)
	print("TIMEOUT"); get_tree().quit()
