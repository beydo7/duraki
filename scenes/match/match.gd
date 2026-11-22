extends Control
## Duell-Szene: verbindet DurakMatch (Logik) mit der 3D-Welt (TableWorld),
## dem HUD und der KI.

## Bedenkzeiten (Sekunden, zufällig dazwischen): sofort, kurz, lang.
const DELAY_QUICK := Vector2(0.45, 0.8)
const DELAY_SHORT := Vector2(1.0, 1.8)
const DELAY_LONG := Vector2(2.0, 3.6)
## Wahrscheinlichkeiten [sofort, kurz, lang] je nach Situation.
const ODDS_DECISION := [0.2, 0.45, 0.35] # Nachlegen oder Bito? Schlagen oder nehmen?
const ODDS_NORMAL := [0.5, 0.35, 0.15]
## Kurzform fürs Porträt im HUD
const THINK_VERB := ["überlegt", "starrt auf den Tisch", "mustert seine Karten", "trommelt mit den Fingern"]
const THINK_TEXT := [
	"%s überlegt …",
	"%s starrt auf den Tisch …",
	"%s mustert seine Karten …",
	"%s trommelt mit den Fingern …",
]

var duel: DurakMatch
var ai: SimpleAI
var opponent: OpponentData
var score: ScoreTracker
var world: TableWorld
var _ai_pending := false
var _thinking := false
var _think_style := 0
var hud: MatchHUD
var _was_my_turn := false


func _ready() -> void:
	opponent = Run.current_opponent()
	if opponent == null:
		# Szene direkt mit F6 gestartet → Testgegner.
		opponent = OpponentData.new()
		opponent.display_name = "Testgegner"
		Run.rng.randomize()

	hud = %HUD
	world = TableWorld.new()
	%Viewport.add_child(world)
	world.build(opponent)
	Settings.apply_viewport(%Viewport)
	Settings.changed.connect(_on_settings_changed)
	world.card_clicked.connect(_on_player_card)

	ai = SimpleAI.new(Run.rng, opponent.mistake_chance)
	duel = DurakMatch.new()
	var target := Run.score_target() if Run.current_opponent() != null else Run.SCORE_TARGETS[0]
	score = ScoreTracker.new(target, Run.base_mult())
	score.suit_chip_bonus = Run.suit_chip_bonus
	score.trump_mult_bonus = Run.trump_mult_bonus
	score.gold_found.connect(func(amount: int) -> void:
		Run.add_gold(amount)
		hud.toast("Glückskarte: +%d Gold" % amount, MatchHUD.COLOR_GOLD))
	score.attach(duel) # vor den UI-Signalen verbinden, damit zuerst gewertet wird
	score.changed.connect(_render_score)
	score.bout_scored.connect(func(points: int, text: String) -> void: hud.bout_scored(points, text))
	score.target_reached.connect(_on_target_reached)
	duel.changed.connect(_on_changed)
	duel.message.connect(_on_message)
	duel.finished.connect(_on_finished)

	# Reaktionen der Gestalt
	duel.card_played.connect(func(who: int, _card: Card, attack: bool) -> void:
		if who == DurakMatch.OPPONENT:
			world.figure.gesture()
			if attack:
				_maybe_throw_more())
	duel.cards_taken.connect(func(who: int, _count: int) -> void:
		if who == DurakMatch.OPPONENT:
			world.figure.recoil()
		else:
			world.figure.laugh())
	duel.transferred.connect(func(who: int, _card: Card) -> void:
		hud.close_choice()
		if who == DurakMatch.OPPONENT:
			world.figure.laugh()
			hud.show_banner("GESCHOBEN!")
			_was_my_turn = true # kein zweites Banner „Verteidige dich“
		else:
			world.figure.recoil()
			hud.show_banner("WEITERGESCHOBEN"))
	duel.take_declared.connect(func(who: int) -> void:
		if who == DurakMatch.OPPONENT and duel.taking:
			hud.toast("%s nimmt – du darfst passende Karten nachwerfen." % opponent.display_name, MatchHUD.COLOR_GOLD))

	%TakeButton.pressed.connect(func() -> void:
		hud.close_choice()
		duel.take())
	%PassButton.pressed.connect(func() -> void:
		if duel.taking:
			duel.finish_take()
		else:
			duel.pass_bout())
	%ContinueButton.pressed.connect(func() -> void: Run.on_match_finished(_result()))

	hud.setup(opponent, score.target)
	if not opponent.taunt.is_empty():
		hud.toast("%s: „%s“" % [opponent.display_name, opponent.taunt], MatchHUD.COLOR_MUTED)
	hud.toast("Punkteziel: %d" % score.target, MatchHUD.COLOR_GOLD)
	duel.start(Run.rng, Run.player_hand_size(), opponent.hand_size, Run.apply_card_enhancements)
	_render_score()


func _on_settings_changed() -> void:
	Settings.apply_viewport(%Viewport)


## Für den Run zählt nur das Punkteziel: erreicht → Gegner verliert.
func _result() -> int:
	return DurakMatch.OPPONENT if score.reached_target() else DurakMatch.PLAYER


func _on_target_reached() -> void:
	duel.force_finish(DurakMatch.OPPONENT, "Punkteziel erreicht!")


func _on_changed() -> void:
	_render()
	if duel.current_actor() == DurakMatch.OPPONENT:
		_run_ai_turn()


func _run_ai_turn() -> void:
	if _ai_pending:
		return
	_ai_pending = true
	# Wichtige Entscheidung? (als Angreifer: nachlegen oder Bito,
	# als Verteidiger: schlagen oder aufnehmen)
	var decision := false
	if duel.attacker == DurakMatch.OPPONENT:
		decision = not duel.attack_cards.is_empty() and not duel.defense_cards.has(null)
	else:
		decision = duel.legal_defenses().size() > 0
	var odds: Array = ODDS_DECISION if decision else ODDS_NORMAL
	# eigener Zufall, damit Runs mit gleichem Seed gleich ablaufen
	var roll := randf()
	var delay := DELAY_QUICK
	if roll >= odds[0]:
		delay = DELAY_SHORT if roll < odds[0] + odds[1] else DELAY_LONG
		_thinking = true
		_think_style = randi_range(0, THINK_TEXT.size() - 1)
		world.figure.think(_think_style)
		hud.set_thinking(true, THINK_VERB[_think_style])
		_render()
	var wait := randf_range(delay.x, delay.y) * Settings.ai_delay_factor()
	if duel.defender() == DurakMatch.OPPONENT:
		wait = maxf(wait, 0.9) # Zeit, um noch Karten dazuzuwerfen
	await get_tree().create_timer(wait, false).timeout
	if _thinking:
		_thinking = false
		world.figure.stop_thinking()
		hud.set_thinking(false)
	_ai_pending = false
	if duel.current_actor() == DurakMatch.OPPONENT:
		ai.take_turn(duel, DurakMatch.OPPONENT)


func _on_player_card(card: Card) -> void:
	hud.close_choice()
	if duel.defender() == DurakMatch.PLAYER:
		if duel.current_actor() != DurakMatch.PLAYER:
			return
		var can_beat := duel.can_defend_with(card)
		var can_shift := duel.can_transfer_with(card)
		if can_beat and can_shift:
			hud.ask_choice("%s: schlagen oder weiterschieben?" % card, ["SCHLAGEN", "SCHIEBEN"],
				func(i: int) -> void:
					if i == 0:
						duel.defend(card)
					else:
						duel.transfer(card))
		elif can_shift:
			duel.transfer(card)
		else:
			duel.defend(card)
	else:
		# als Angreifer jederzeit (auch während der Gegner noch überlegt)
		duel.attack(card)


## Der Gegner wirft manchmal direkt eine zweite (dritte …) Karte gleichen Rangs.
func _maybe_throw_more() -> void:
	var extra := ai.extra_attack(duel, DurakMatch.OPPONENT)
	if extra == null:
		return
	await get_tree().create_timer(randf_range(0.35, 0.65) * Settings.ai_delay_factor(), false).timeout
	if duel.can_attack_with(extra):
		duel.attack(extra)


## Spielprotokoll („Du legst 7♥.“ …) – lässt sich in den Optionen ausblenden.
func _on_message(text: String) -> void:
	if Settings.show_messages():
		hud.toast(text)


func _on_finished(_loser: int) -> void:
	if score.reached_target():
		world.figure.slump()
	else:
		world.figure.laugh()
	var won := score.reached_target()
	hud.show_result(won, "SIEG!" if won else "DURAK!", _status_text(false, false),
		"%d / %d Punkte" % [score.total, score.target])


# --- Anzeige ------------------------------------------------------------------

func _render() -> void:
	hud.set_opponent_cards(duel.opponent_hand.size())
	hud.set_run_info(Run.lives, Run.gold, duel.deck.size(), duel.trump_suit)

	var my_turn := duel.current_actor() == DurakMatch.PLAYER
	var defending := duel.defender() == DurakMatch.PLAYER
	var playable: Array[Card] = []
	if defending:
		if my_turn:
			playable = duel.legal_defenses()
			for c in duel.legal_transfers():
				if not playable.has(c):
					playable.append(c)
	else:
		playable = duel.legal_attacks() # auch während der Gegner verteidigt
	world.sync(duel, playable)

	if duel.taking:
		hud.set_actions(false, not defending, not defending, "FERTIG")
	else:
		hud.set_actions(my_turn and defending and duel.can_take(), not defending and duel.can_pass(), duel.can_pass())
	hud.set_status(_status_text(my_turn, defending), my_turn and not duel.is_over)
	_announce_turn(my_turn, defending)
	_render_score()


## Banner zu Beginn deines Angriffs bzw. wenn du dich verteidigen musst.
func _announce_turn(my_turn: bool, defending: bool) -> void:
	var fresh := my_turn and not _was_my_turn and not duel.is_over
	_was_my_turn = my_turn
	if not fresh:
		return
	if not defending and duel.attack_cards.is_empty():
		hud.show_banner("DEIN ANGRIFF")
	elif defending and duel.attack_cards.size() == 1 and duel.defense_cards[0] == null:
		hud.show_banner("VERTEIDIGE DICH")


func _render_score() -> void:
	if score == null:
		return
	var sub := "Noch %d Punkte bis zum Ziel" % score.remaining()
	if duel != null and duel.is_over:
		sub = score.last_text
	elif score.reached_target():
		sub = "Ziel erreicht!"
	hud.set_score(score.total, score.target, score.chips, score.mult, sub)


func _status_text(my_turn: bool, defending: bool) -> String:
	if duel.is_over:
		if score.reached_target():
			return "Gewonnen! Punkteziel erreicht (%d / %d)." % [score.total, score.target]
		if duel.loser == DurakMatch.PLAYER:
			return "Verloren – du bist der Durak und hast das Ziel verfehlt."
		return "Verloren – Ziel verfehlt (%d / %d)." % [score.total, score.target]
	if duel.taking:
		if defending:
			return "Du nimmst auf – %s wirft noch Karten nach …" % opponent.display_name
		return "%s nimmt auf – wirf passende Karten nach oder klicke FERTIG." % opponent.display_name
	if not my_turn:
		if not defending and not duel.legal_attacks().is_empty():
			return "%s verteidigt – du kannst noch passende Karten dazuwerfen." % opponent.display_name
		return "%s ist am Zug …" % opponent.display_name
	if defending:
		if not duel.legal_transfers().is_empty():
			return "Verteidige dich – schlagen, mit gleichem Rang weiterschieben oder alles nehmen."
		return "Verteidige dich – klicke eine Karte zum Schlagen oder nimm alles."
	if duel.attack_cards.is_empty():
		return "Du greifst an – klicke Karten (gleiche Ränge auch mehrere auf einmal)."
	return "Lege passende Ränge nach oder beende die Runde."
