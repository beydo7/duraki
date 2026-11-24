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
## Kleine Sprüche des Gegners (Sprechblase), zufällig.
const LINES_TAKES := ["Das merk ich mir.", "Noch ist nichts entschieden.", "Glück. Nichts als Glück.", "Hmpf."]
const LINES_GLOAT := ["Schwer, nicht wahr?", "Nimm nur. Nimm alles.", "Deine Hand wird schwer …"]
const LINES_TRANSFER := ["Zurück zu dir.", "Nicht so schnell.", "Fang!"]
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
## Bis zu diesem Zeitpunkt (Sekunden) wartet der Gegner, damit man den Tisch noch sieht
var _hold_until := 0.0
## Tutorial: solange ein Hinweis-Schritt offen ist, wartet der Gegner
var coach_hold := false
var coach: TutorialCoach
## Maus über Karte / Stapel (Shift-Info, Stapelanzahl)
var _hover_card: Card
var _deck_hover := false
var _think_style := 0
var hud: MatchHUD
var _was_my_turn := false
## zuletzt spielbare Karten (für „Hinweise aus“: falsche Klicks abfangen)
var _playable: Array[Card] = []


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
	_fit_viewport()
	get_viewport().size_changed.connect(_fit_viewport)
	world.card_clicked.connect(_on_player_card)
	world.card_hovered.connect(func(card: Card, on: bool) -> void:
		if on:
			_hover_card = card
		elif _hover_card == card:
			_hover_card = null)
	world.deck_hovered.connect(func(on: bool) -> void: _deck_hover = on)
	world.card_dropped.connect(_on_player_card)

	ai = SimpleAI.new(Run.rng, Run.mistake_chance(opponent))
	Card3D.hints = Run.hints
	duel = DurakMatch.new()
	var target := Run.score_target() if Run.current_opponent() != null else Run.SCORE_TARGETS[0]
	score = ScoreTracker.new(target, Run.base_mult())
	score.suit_chip_bonus = Run.suit_chip_bonus
	score.trump_mult_bonus = Run.trump_mult_bonus
	score.gold_found.connect(func(amount: int, source: String) -> void:
		Sfx.play(&"coins")
		Run.add_gold(amount)
		world.props.set_gold(Run.gold)
		hud.toast("%s: +%d Gold" % [source, amount], MatchHUD.COLOR_GOLD))
	score.lucky_hit.connect(func(extra: int) -> void:
		hud.toast("Glück! +%d Mult" % extra, MatchHUD.COLOR_GOLD))
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
	duel.cards_taken.connect(func(who: int, count: int) -> void:
		if who == DurakMatch.OPPONENT:
			world.figure.recoil()
			_maybe_say(LINES_TAKES, 0.45)
		else:
			world.figure.laugh()
			if count >= 3:
				_maybe_say(LINES_GLOAT, 0.6))
	duel.transferred.connect(func(who: int, card: Card) -> void:
		world.note_transfer(card)
		hud.speed_lines(who == DurakMatch.PLAYER)
		hud.close_choice()
		if who == DurakMatch.OPPONENT:
			world.figure.laugh()
			hud.show_banner("GESCHOBEN!", UIKit.RED)
			_maybe_say(LINES_TRANSFER, 0.5)
			_was_my_turn = true # kein zweites Banner „Verteidige dich“
		else:
			world.figure.recoil()
			hud.show_banner("WEITERGESCHOBEN"))
	duel.cards_discarded.connect(func(_count: int) -> void:
		hud.stamp("FERTIG")
		# verteidigte Karten bleiben liegen und werden dann abgeräumt; so lange wartet der Gegner
		_hold_until = _now() + TableWorld.DISCARD_DELAY + 0.9)
	duel.take_declared.connect(func(who: int) -> void:
		if who == DurakMatch.OPPONENT and duel.taking:
			# klar zeigen: der Gegner gibt auf – du darfst aber noch Karten dazulegen
			var sub := "DU DARFST NACHWERFEN" if not Run.hints or not duel.legal_attacks().is_empty() else "NICHTS ZUM NACHWERFEN – FERTIG"
			hud.show_banner("%s GIBT AUF" % opponent.display_name.to_upper(), Color(1, 0.86, 0.5), sub, 1.6))

	hud.take_button.pressed.connect(func() -> void:
		hud.close_choice()
		duel.take())
	hud.pass_button.pressed.connect(func() -> void:
		if duel.taking:
			duel.finish_take()
		else:
			duel.pass_bout())
	hud.continue_button.pressed.connect(func() -> void: Run.on_match_finished(_result()))

	hud.setup(opponent, score.target, Run.floor_index, 0 if Run.tutorial else maxi(Run.encounters.size(), 1))
	hud.set_relics(Run.relics)
	world.props.set_lives(maxi(Run.lives, 1))
	world.props.set_gold(Run.gold, false)
	if not opponent.taunt.is_empty():
		hud.say(opponent.taunt, 5.0)
	hud.toast("Punkteziel: %d" % score.target, MatchHUD.COLOR_GOLD)
	if Run.tutorial:
		coach = TutorialCoach.new()
		hud.add_child(coach)
		coach.setup(self)
	duel.start(Run.rng, Run.player_hand_size(), opponent.hand_size, Run.apply_card_enhancements)
	_render_score()


func _on_settings_changed() -> void:
	Settings.apply_viewport(%Viewport)


## Die 3D-Welt in voller Bildschirmauflösung rendern. Mit stretch = true würde der
## SubViewport nur in der Basisauflösung (1280×720) rendern und hochskaliert werden –
## auf 1440p/4K wird dann alles unscharf. Darum: Viewport in echten Pixeln, Container
## entsprechend verkleinert (Eingaben rechnet der Container mit seiner Skalierung um).
func _fit_viewport() -> void:
	UIKit.fit_viewport(self, %View, %Viewport)


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
	elif not duel.attack_cards.is_empty() and not duel.defense_cards.has(null):
		wait = maxf(wait, 1.2) # du hast alles geschlagen: deine Karte erst mal liegen lassen
	wait = maxf(wait, _hold_until - _now()) # Tisch wird noch abgeräumt
	await get_tree().create_timer(wait, false).timeout
	while coach_hold and is_inside_tree():
		await get_tree().process_frame
	if _thinking:
		_thinking = false
		world.figure.stop_thinking()
		hud.set_thinking(false)
	_ai_pending = false
	if duel.current_actor() == DurakMatch.OPPONENT:
		ai.take_turn(duel, DurakMatch.OPPONENT)


## Karte angeklickt (`target` = -1) oder auf eine Angriffskarte gezogen (`target` = deren Index).
func _on_player_card(card: Card, target := -1) -> void:
	hud.close_choice()
	if not _playable.has(card):
		# nur möglich, wenn Hinweise aus sind: alle Handkarten sind anklickbar
		hud.toast("%s passt gerade nicht." % card, MatchHUD.COLOR_GOLD)
		return
	if duel.defender() == DurakMatch.PLAYER:
		if duel.current_actor() != DurakMatch.PLAYER:
			return
		var can_shift := duel.can_transfer_with(card)
		if target >= 0:
			if duel.can_defend_at(card, target):
				duel.defend(card, target)
			elif can_shift:
				duel.transfer(card)
			else:
				hud.toast("%s schlägt %s nicht." % [card, duel.attack_cards[target]], MatchHUD.COLOR_GOLD)
			return
		# Mehrere Möglichkeiten? Dann fragen: welche Karte schlagen – oder schieben.
		var targets := duel.defense_targets(card)
		var labels: Array[String] = []
		for i in targets:
			labels.append("AUF %s" % duel.attack_cards[i])
		if can_shift:
			labels.append("SCHIEBEN")
		if labels.size() == 1:
			if can_shift:
				duel.transfer(card)
			else:
				duel.defend(card, targets[0])
			return
		var question := "%s: welche Karte schlagen?" % card if not can_shift else "%s: schlagen oder weiterschieben?" % card
		hud.ask_choice(question, labels, func(i: int) -> void:
			if i < targets.size():
				duel.defend(card, targets[i])
			else:
				duel.transfer(card))
	else:
		# als Angreifer jederzeit (auch während der Gegner noch überlegt)
		duel.attack(card)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


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
	var won := score.reached_target()
	_render()
	if won:
		world.figure.slump()
	else:
		world.figure.laugh()
		world.props.snuff_candle()
		await get_tree().create_timer(1.1, false).timeout
	hud.show_result(won, "SIEG!" if won else "DURAK!", _result_text(won),
		"%d / %d Punkte" % [score.total, score.target])


func _result_text(won: bool) -> String:
	if Run.tutorial:
		if won:
			return "Tutorial geschafft! Die Tutorial-Karte verschwindet – in den Optionen kannst du sie zurückholen."
		return "Knapp daneben – über die Tutorial-Karte im Menü kannst du es gleich nochmal versuchen."
	if won:
		return "Punkteziel erreicht. %s steht auf." % opponent.display_name
	if Run.lives <= 1:
		return "Die letzte Kerze ist aus – der Run endet hier."
	return "Ziel verfehlt. Eine Kerze erlischt – noch %d übrig." % (Run.lives - 1)


func _maybe_say(lines: Array, chance: float) -> void:
	if randf() < chance:
		hud.say(lines[randi() % lines.size()], 2.6)


func _process(_delta: float) -> void:
	if duel == null:
		return
	if _deck_hover and not duel.deck.is_empty():
		var n := duel.deck.size()
		hud.show_info("NACHZIEHSTAPEL", "Noch %d %s im Stapel (die unterste ist der Trumpf %s)." % [
			n, "Karte" if n == 1 else "Karten", duel.trump_card])
	elif _hover_card != null and Input.is_key_pressed(KEY_SHIFT) and _is_visible_card(_hover_card):
		hud.show_info(_card_title(_hover_card), _card_info(_hover_card))
	else:
		hud.hide_info()


## Nur offene Karten erklären (deine Hand, der Tisch, der Trumpf) – nie die Gegnerhand.
func _is_visible_card(c: Card) -> bool:
	return duel.player_hand.has(c) or duel.table_cards().has(c) or c == duel.trump_card


func _card_title(c: Card) -> String:
	var name := "%s %s" % [Card.RANK_NAMES[c.rank], Card.SUIT_NAMES[c.suit]]
	if c.enhancement != Card.Enhancement.NONE:
		name = "%s · %s" % [name, Card.ENHANCEMENT_NAMES[c.enhancement]]
	return name.to_upper()


func _card_info(c: Card) -> String:
	var lines := PackedStringArray()
	lines.append("%d Chips, wenn du sie spielst." % score.card_chips(c))
	if c.suit == duel.trump_suit:
		lines.append("Trumpf: schlägt jede andere Farbe und gibt +%d Mult." % (1 + score.trump_mult_bonus))
	if c.enhancement != Card.Enhancement.NONE:
		lines.append(Card.ENHANCEMENT_TEXT[c.enhancement])
	return "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or duel == null or duel.is_over:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_SPACE and hud.pass_button.visible and not hud.pass_button.disabled:
		hud.pass_button.pressed.emit()
		get_viewport().set_input_as_handled()
	elif key == KEY_E and hud.take_button.visible:
		hud.take_button.pressed.emit()
		get_viewport().set_input_as_handled()


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
	_playable = playable
	world.sync(duel, playable)

	if duel.taking:
		hud.set_actions(false, not defending, not defending, "FERTIG")
	else:
		hud.set_actions(my_turn and defending and duel.can_take(), not defending and duel.can_pass(), duel.can_pass())
	var info := _turn_info(my_turn, defending)
	hud.set_turn(info[0], info[1], info[2])
	# ohne Hinweise nicht verraten, ob Schieben geht
	var can_shift := Run.hints and defending and my_turn and not duel.legal_transfers().is_empty()
	hud.set_bout(duel.attack_cards.size(), duel.bout_limit, can_shift)
	if defending and my_turn:
		hud.set_danger(minf(0.1 + 0.05 * duel.unbeaten_count(), 0.3))
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
		hud.show_banner("VERTEIDIGE DICH", Color(1, 0.6, 0.6))


func _render_score() -> void:
	if score == null:
		return
	var sub := "Noch %d Punkte bis zum Ziel" % score.remaining()
	if duel != null and duel.is_over:
		sub = score.last_text
	elif score.reached_target():
		sub = "Ziel erreicht!"
	hud.set_score(score.total, score.target, score.chips, score.mult, sub)


## [Modus, Titel, Hinweis] für die Zug-Anzeige oben in der Mitte.
func _turn_info(my_turn: bool, defending: bool) -> Array:
	var them := opponent.display_name.to_upper()
	if duel.is_over:
		var won := score.reached_target()
		return [MatchHUD.Turn.OVER, "GEWONNEN" if won else "VERLOREN", "%d / %d Punkte" % [score.total, score.target]]
	if duel.taking:
		if defending:
			return [MatchHUD.Turn.WAIT, "DU NIMMST AUF", "%s wirft noch Karten nach …" % opponent.display_name]
		if Run.hints and duel.legal_attacks().is_empty():
			return [MatchHUD.Turn.THROW_IN, "%s NIMMT" % them, "Nichts mehr nachzuwerfen – drück FERTIG."]
		return [MatchHUD.Turn.THROW_IN, "%s NIMMT – NACHWERFEN!" % them, "Leg passende Ränge dazu, er muss alles aufnehmen. Dann FERTIG."]
	if not my_turn:
		if not defending and (not Run.hints or not duel.legal_attacks().is_empty()):
			return [MatchHUD.Turn.WAIT, "%s VERTEIDIGT" % them, "Du darfst noch passende Ränge dazuwerfen."]
		if _thinking:
			return [MatchHUD.Turn.WAIT, "%s IST AM ZUG" % them, THINK_TEXT[_think_style] % opponent.display_name]
		return [MatchHUD.Turn.WAIT, "%s IST AM ZUG" % them, "Warte ab …"]
	if defending:
		if not Run.hints:
			return [MatchHUD.Turn.DEFEND, "VERTEIDIGE DICH", "Schlagen, mit gleichem Rang schieben – oder nehmen."]
		if not duel.legal_transfers().is_empty():
			return [MatchHUD.Turn.DEFEND, "VERTEIDIGE DICH", "Schlagen, mit gleichem Rang schieben – oder nehmen."]
		if duel.legal_defenses().is_empty():
			return [MatchHUD.Turn.DEFEND, "VERTEIDIGE DICH", "Nichts passt – du musst die Karten nehmen."]
		return [MatchHUD.Turn.DEFEND, "VERTEIDIGE DICH", "Höher in gleicher Farbe oder Trumpf – sonst nehmen."]
	if duel.attack_cards.is_empty():
		return [MatchHUD.Turn.ATTACK, "DEIN ANGRIFF", "Lege eine Karte – gleiche Ränge auch mehrere."]
	return [MatchHUD.Turn.ATTACK, "NACHLEGEN ODER FERTIG", "Passende Ränge nachlegen oder die Runde beenden."]
