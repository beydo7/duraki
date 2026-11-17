extends Control
## Duell-Szene: verbindet DurakMatch (Logik) mit der Anzeige und der KI.

const CARD_VIEW := preload("res://scenes/match/card_view.tscn")
const AI_DELAY := 0.6
const LOG_LINES := 6

var duel: DurakMatch
var ai: SimpleAI
var opponent: OpponentData
var score: ScoreTracker
var _ai_pending := false
var _log: PackedStringArray = []


func _ready() -> void:
	opponent = Run.current_opponent()
	if opponent == null:
		# Szene direkt mit F6 gestartet → Testgegner.
		opponent = OpponentData.new()
		opponent.display_name = "Testgegner"
		Run.rng.randomize()

	ai = SimpleAI.new(Run.rng, opponent.mistake_chance)
	duel = DurakMatch.new()
	var target := Run.score_target() if Run.current_opponent() != null else Run.SCORE_TARGETS[0]
	score = ScoreTracker.new(target, Run.base_mult())
	score.attach(duel) # vor den UI-Signalen verbinden, damit zuerst gewertet wird
	score.changed.connect(_render_score)
	score.bout_scored.connect(func(_points: int, text: String) -> void: _on_message(text))
	score.target_reached.connect(_on_target_reached)
	duel.changed.connect(_on_changed)
	duel.message.connect(_on_message)
	duel.finished.connect(_on_finished)

	%TakeButton.pressed.connect(func() -> void: duel.take())
	%PassButton.pressed.connect(func() -> void: duel.pass_bout())
	%ContinueButton.pressed.connect(func() -> void: Run.on_match_finished(_result()))

	if not opponent.taunt.is_empty():
		_on_message("%s: „%s“" % [opponent.display_name, opponent.taunt])
	_on_message("Punkteziel: %d" % score.target)
	duel.start(Run.rng, Run.player_hand_size(), opponent.hand_size)
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
	await get_tree().create_timer(AI_DELAY).timeout
	_ai_pending = false
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
	%ContinueButton.visible = true
	%ContinueButton.grab_focus()


# --- Anzeige ------------------------------------------------------------------

func _render() -> void:
	var opp_cards := duel.opponent_hand.size()
	%OpponentLabel.text = "%s  –  %d Karten" % [opponent.display_name, opp_cards]
	%RunInfoLabel.text = "Leben: %d   Gold: %d" % [Run.lives, Run.gold]
	_render_score()

	_clear(%OpponentHand)
	for i in opp_cards:
		%OpponentHand.add_child(_make_card(null, true))

	%DeckLabel.text = "Stapel: %d\nTrumpf: %s" % [duel.deck.size(), Card.SUIT_NAMES[duel.trump_suit]]
	_clear(%TrumpSlot)
	if not duel.deck.is_empty():
		%TrumpSlot.add_child(_make_card(duel.trump_card))

	_clear(%Table)
	for i in duel.attack_cards.size():
		var pair := VBoxContainer.new()
		pair.add_theme_constant_override("separation", -70)
		pair.add_child(_make_card(duel.attack_cards[i]))
		if duel.defense_cards[i] != null:
			pair.add_child(_make_card(duel.defense_cards[i]))
		%Table.add_child(pair)

	var my_turn := duel.current_actor() == DurakMatch.PLAYER
	var defending := duel.defender() == DurakMatch.PLAYER
	var playable: Array[Card] = []
	if my_turn:
		playable = duel.legal_defenses() if defending else duel.legal_attacks()

	_clear(%PlayerHand)
	for card in duel.player_hand:
		var view := _make_card(card, false, true)
		view.set_playable(playable.has(card))
		view.card_pressed.connect(_on_player_card)
		%PlayerHand.add_child(view)

	%TakeButton.visible = my_turn and defending
	%PassButton.visible = my_turn and not defending
	%PassButton.disabled = not duel.can_pass()
	%StatusLabel.text = _status_text(my_turn, defending)


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
		return "%s ist am Zug …" % opponent.display_name
	if defending:
		return "Verteidige dich – schlage die Karte oder nimm alles."
	if duel.attack_cards.is_empty():
		return "Du greifst an – lege eine Karte."
	return "Lege passende Ränge nach oder beende die Runde."


func _make_card(card: Card, face_down := false, interactive := false) -> CardView:
	var view: CardView = CARD_VIEW.instantiate()
	var is_trump := card != null and card.suit == duel.trump_suit
	return view.setup(card, face_down, is_trump, interactive)


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
