extends Node
## Rendert Screenshots der Duell-Szene (zum Prüfen des Designs).
##   godot --path . res://tests/screenshot.tscn -- out=/tmp/shots
## Ohne Bildschirm z. B. mit xvfb-run starten.

var out_dir := "user://shots"
var _bot := SimpleAI.new(RandomNumberGenerator.new(), 0.0)


func _ready() -> void:
	Profile.reset_for_tests()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out_dir = arg.substr(4)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_detach.call_deferred()


func _detach() -> void:
	var placeholder := Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	Run.start_new_run(4242)
	await get_tree().create_timer(0.5).timeout
	Run.floor_index = Run.encounters.size() - 1 if "boss" in OS.get_cmdline_user_args() else 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("opp="):
			# bestimmten Gegner zeigen, z. B. opp=crow
			Run.encounters[Run.floor_index] = load("res://data/opponents/%s.tres" % arg.substr(4))
	if "enh" in OS.get_cmdline_user_args():
		# ein paar verbesserte Karten zum Ansehen
		for suit in 4:
			for rank in [7, 10, 12, 14]:
				Run.card_enhancements["%d:%d" % [suit, rank]] = 1 + (suit + rank) % 3
	Run.goto(Run.SCENE_MATCH)
	if "film" in OS.get_cmdline_user_args():
		await _film()
		get_tree().quit()
		return
	await get_tree().create_timer(2.5).timeout
	var scene := get_tree().current_scene
	var duel: DurakMatch = scene.duel
	var args := OS.get_cmdline_user_args()
	if "rows" in args:
		TableWorld.hand_layout = "rows"
	if "many" in args:
		# viele Karten auf die Hand, um das Layout zu prüfen
		var extra := 20 if "huge" in args else 12
		for k in extra:
			duel.player_hand.append(duel.deck.draw())
		DurakRules.sort_hand(duel.player_hand, duel.trump_suit)
		duel.changed.emit()
		await get_tree().create_timer(2.0).timeout
		await _shot("many")
		get_tree().quit()
		return
	if "boss" in args or ",".join(args).contains("opp="):
		await get_tree().create_timer(1.0).timeout
		await _shot("boss")
		get_tree().quit()
		return
	if "transfer" in args:
		# Du verteidigst gegen eine 9; du hast eine Trumpf-9 (schlagen oder schieben)
		var t := duel.trump_suit
		var other := (t + 1) % 4 as Card.Suit
		duel.attack_cards.clear()
		duel.defense_cards.clear()
		duel.attacker = DurakMatch.OPPONENT
		var attack := Card.new(other, 9)
		duel.attack_cards.append(attack)
		duel.defense_cards.append(null)
		var mine: Array[Card] = [Card.new(t, 9), Card.new(other, 12), Card.new((t + 2) % 4 as Card.Suit, 9),
			Card.new(other, 6), Card.new((t + 3) % 4 as Card.Suit, 11), Card.new(t, 13)]
		duel.player_hand.assign(mine)
		DurakRules.sort_hand(duel.player_hand, duel.trump_suit)
		scene._ai_pending = true # Gegner wartet
		duel.changed.emit()
		await get_tree().create_timer(1.5).timeout
		if "nohud" in args:
			scene.hud.visible = false
			await get_tree().create_timer(0.3).timeout
			await _shot("nohud")
			get_tree().quit()
			return
		await _shot("transfer_1")
		scene._on_player_card(mine[0])
		await get_tree().create_timer(0.8).timeout
		await _shot("transfer_2_choice")
		scene.hud.close_choice()
		duel.transfer(mine[0])
		await get_tree().create_timer(1.2).timeout
		await _shot("transfer_3_done")
		get_tree().quit()
		return
	if "bito" in args:
		# Du greifst an, Gegner schlägt, Bito → Stempel + Abwurf
		scene._ai_pending = true
		duel.attack(duel.legal_attacks()[0])
		await get_tree().create_timer(0.6).timeout
		var defs: Array = duel.legal_defenses()
		if not defs.is_empty():
			duel.defend(defs[0])
			await get_tree().create_timer(0.5).timeout
			if duel.can_pass():
				duel.pass_bout()
			for k in 3:
				await get_tree().create_timer(0.25).timeout
				await _shot("bito_%d" % k)
		get_tree().quit()
		return
	if "result" in args:
		# Ergebnis-Fenster prüfen: Ziel erreichen und Duell beenden
		scene.score.total = scene.score.target
		duel.force_finish(DurakMatch.OPPONENT, "Punkteziel erreicht!")
		await get_tree().create_timer(1.5).timeout
		await _shot("result")
		get_tree().quit()
		return
	await _shot("1_start")
	# ein paar Züge spielen
	for step in 6:
		if duel.is_over:
			break
		if duel.current_actor() == DurakMatch.PLAYER:
			_bot.take_turn(duel, DurakMatch.PLAYER)
		await get_tree().create_timer(1.2).timeout
		await _shot("2_step%d" % step)
	get_tree().quit()


## Nimmt eine Bildfolge auf (film_0000.png …), um Animationen zu prüfen:
## Austeilen, Hover-Kippen, Schieben, danach ein paar Züge (Ausspielen, Schlagen, Bito, Nehmen).
var _frame := 0
var _recording := false


func _film() -> void:
	# Zeitlupe, damit trotz langsamem Software-Rendering genug Bilder pro Bewegung entstehen
	Engine.time_scale = 0.15
	_recording = true
	_record_loop()
	await get_tree().create_timer(2.6).timeout
	var scene := get_tree().current_scene
	var duel: DurakMatch = scene.duel
	# Hover über die erste Handkarte wandern lassen
	var world: TableWorld = scene.world
	var hand_node: Card3D = world._cards.get(duel.player_hand[duel.player_hand.size() - 1])
	if hand_node != null:
		hand_node._set_hovered(true)
		for k in 30:
			hand_node._hover_uv = Vector2(0.15 + 0.7 * k / 29.0, 0.2 + 0.6 * k / 29.0)
			await get_tree().create_timer(0.04).timeout
		hand_node._set_hovered(false)
	await get_tree().create_timer(0.4).timeout
	# ein paar echte Züge, beide Seiten von der KI gespielt
	var bot := SimpleAI.new(RandomNumberGenerator.new(), 0.0)
	for step in 9:
		if duel.is_over:
			break
		if duel.current_actor() == DurakMatch.PLAYER:
			bot.take_turn(duel, DurakMatch.PLAYER)
		await get_tree().create_timer(1.1).timeout
	_recording = false


func _record_loop() -> void:
	while _recording:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
		img.save_png(out_dir.path_join("film_%04d.png" % _frame))
		_frame += 1


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("Screenshot: ", name)
