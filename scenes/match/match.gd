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
const THINK_TEXT := [
	"%s überlegt …",
	"%s starrt auf den Tisch …",
	"%s mustert seine Karten …",
	"%s trommelt mit den Fingern …",
]
const LOG_LINES := 7

var duel: DurakMatch
var ai: SimpleAI
var opponent: OpponentData
var score: ScoreTracker
var world: TableWorld
var _ai_pending := false
var _thinking := false
var _think_style := 0
var _log: PackedStringArray = []


func _ready() -> void:
	opponent = Run.current_opponent()
	if opponent == null:
		# Szene direkt mit F6 gestartet → Testgegner.
		opponent = OpponentData.new()
		opponent.display_name = "Testgegner"
		Run.rng.randomize()

	world = TableWorld.new()
	%Viewport.add_child(world)
	world.build(opponent)
	world.card_clicked.connect(_on_player_card)

	ai = SimpleAI.new(Run.rng, opponent.mistake_chance)
	duel = DurakMatch.new()
	var target := Run.score_target() if Run.current_opponent() != null else Run.SCORE_TARGETS[0]
	score = ScoreTracker.new(target, Run.base_mult())
	score.suit_chip_bonus = Run.suit_chip_bonus
	score.trump_mult_bonus = Run.trump_mult_bonus
	score.gold_found.connect(func(amount: int) -> void:
		Run.add_gold(amount)
		_on_message("Glückskarte: +%d Gold" % amount))
	score.attach(duel) # vor den UI-Signalen verbinden, damit zuerst gewertet wird
	score.changed.connect(_render_score)
	score.bout_scored.connect(func(_points: int, text: String) -> void: _on_message(text))
	score.target_reached.connect(_on_target_reached)
	duel.changed.connect(_on_changed)
	duel.message.connect(_on_message)
	duel.finished.connect(_on_finished)

	# Reaktionen der Gestalt
	duel.card_played.connect(func(who: int, _card: Card, _attack: bool) -> void:
		if who == DurakMatch.OPPONENT:
			world.figure.gesture())
	duel.cards_taken.connect(func(who: int, _count: int) -> void:
		if who == DurakMatch.OPPONENT:
			world.figure.recoil()
		else:
			world.figure.laugh())

	%TakeButton.pressed.connect(func() -> void: duel.take())
	%PassButton.pressed.connect(func() -> void: duel.pass_bout())
	%ContinueButton.pressed.connect(func() -> void: Run.on_match_finished(_result()))

	if not opponent.taunt.is_empty():
		_on_message("%s: „%s“" % [opponent.display_name, opponent.taunt])
	_on_message("Punkteziel: %d" % score.target)
	duel.start(Run.rng, Run.player_hand_size(), opponent.hand_size, Run.apply_card_enhancements)
	_render_score()


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
		_render()
	await get_tree().create_timer(randf_range(delay.x, delay.y)).timeout
	if _thinking:
		_thinking = false
		world.figure.stop_thinking()
	_ai_pending = false
	if duel.current_actor() == DurakMatch.OPPONENT:
		ai.take_turn(duel, DurakMatch.OPPONENT)


func _on_player_card(card: Card) -> void:
	if duel.current_actor() != DurakMatch.PLAYER:
		return
	if duel.defender() == DurakMatch.PLAYER:
		duel.defend(card)
	else:
		duel.attack(card)


func _on_message(text: String) -> void:
	_log.append(text)
	if _log.size() > LOG_LINES:
		_log = _log.slice(_log.size() - LOG_LINES)
	%LogLabel.text = "\n".join(_log)


func _on_finished(_loser: int) -> void:
	if score.reached_target():
		world.figure.slump()
	else:
		world.figure.laugh()
	%ContinueButton.visible = true
	%ContinueButton.grab_focus()


# --- Anzeige ------------------------------------------------------------------

func _render() -> void:
	%OpponentLabel.text = "%s  ·  %d Karten" % [opponent.display_name, duel.opponent_hand.size()]
	%RunInfoLabel.text = "Leben: %d   Gold: %d\nStapel: %d   Trumpf: %s %s" % [
		Run.lives, Run.gold, duel.deck.size(),
		Card.SUIT_SYMBOLS[duel.trump_suit], Card.SUIT_NAMES[duel.trump_suit]]

	var my_turn := duel.current_actor() == DurakMatch.PLAYER
	var defending := duel.defender() == DurakMatch.PLAYER
	var playable: Array[Card] = []
	if my_turn:
		playable = duel.legal_defenses() if defending else duel.legal_attacks()
	world.sync(duel, playable)

	%TakeButton.visible = my_turn and defending
	%PassButton.visible = my_turn and not defending
	%PassButton.disabled = not duel.can_pass()
	%StatusLabel.text = _status_text(my_turn, defending)
	_render_score()


func _render_score() -> void:
	if score == null:
		return
	%ScoreLabel.text = "%d / %d" % [score.total, score.target]
	if duel != null and duel.is_over:
		%BoutLabel.text = score.last_text
	elif score.chips > 0:
		%BoutLabel.text = "Runde: %d Chips × %d Mult" % [score.chips, score.mult]
	else:
		%BoutLabel.text = "Noch %d Punkte" % score.remaining()


func _status_text(my_turn: bool, defending: bool) -> String:
	if duel.is_over:
		if score.reached_target():
			return "Gewonnen! Punkteziel erreicht (%d / %d)." % [score.total, score.target]
		if duel.loser == DurakMatch.PLAYER:
			return "Verloren – du bist der Durak und hast das Ziel verfehlt."
		return "Verloren – Ziel verfehlt (%d / %d)." % [score.total, score.target]
	if not my_turn:
		if _thinking:
			return THINK_TEXT[_think_style] % opponent.display_name
		return "%s ist am Zug …" % opponent.display_name
	if defending:
		return "Verteidige dich – klicke eine Karte zum Schlagen oder nimm alles."
	if duel.attack_cards.is_empty():
		return "Du greifst an – klicke eine Karte."
	return "Lege passende Ränge nach oder beende die Runde."
