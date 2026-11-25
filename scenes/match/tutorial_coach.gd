class_name TutorialCoach
extends Control
## Geführte Übungsrunde: blendet rechts eine Hinweistafel ein, passend zu dem, was gerade
## am Tisch passiert (Angreifen, Schlagen, Schieben, Nehmen, Nachwerfen, Punkte …).
## Jeder Hinweis kommt nur einmal. Die ersten Schritte halten den Gegner an, bis „WEITER“
## gedrückt wird. Wird nur im Tutorial erzeugt (siehe match.gd, Run.start_tutorial).

const PANEL_W := 360.0

var _m: Node # match.gd
var _seen := {}
var _queue: Array = [] # [key, Titel, Text, hält an?]
var _open_key := ""
var _panel: PanelContainer
var _step: Label
var _title: Label
var _text: Label
var _button: Button
var _shown := 0
var _tw: Tween


func setup(match_node: Node) -> void:
	_m = match_node
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	var duel: DurakMatch = _m.duel
	duel.changed.connect(_check.call_deferred)
	duel.take_declared.connect(func(who: int) -> void:
		if who == DurakMatch.OPPONENT:
			_tip("throw_in", "ER NIMMT – NACHWERFEN!",
				"Der Gegner gibt auf und nimmt alles. Du darfst jetzt noch Karten mit Rängen, die schon liegen, dazuwerfen – die muss er auch nehmen. Danach FERTIG.", false, true)
		else:
			_tip("you_take", "DU NIMMST AUF",
				"Kein Problem: Die Karten wandern auf deine Hand. Der Gegner darf noch passende Ränge nachwerfen. Mit mehr Karten hast du später mehr Auswahl."))
	duel.transferred.connect(func(who: int, _c: Card) -> void:
		if who == DurakMatch.OPPONENT:
			_tip("shifted", "WEITERGESCHOBEN!",
				"Der Gegner hat eine Karte gleichen Rangs dazugelegt und den Angriff an dich weitergeschoben. Jetzt musst du alle Karten schlagen."))
	(_m.score as ScoreTracker).bout_scored.connect(func(_p: int, _t: String) -> void:
		_tip("score", "PUNKTE",
			"Am Ende jeder Runde werden deine Karten gewertet: Chips (lila) × Mult (gold). Höhere Karten und Trümpfe bringen mehr. Erreiche das Punkteziel oben, um den Tisch zu gewinnen."))
	# Einstieg: diese Schritte halten den Gegner an
	_tip("hello", "WILLKOMMEN AM TISCH",
		"Das ist Durak mit Punkten. Ihr legt abwechselnd Angriffe und verteidigt euch. Wer am Ende noch Karten hat, ist der Durak. Für den Sieg zählt hier aber dein Punkteziel.", true)
	_tip("trump", "TRUMPF",
		"Die offene Karte unter dem Stapel zeigt den Trumpf: %s. Trumpf schlägt jede andere Farbe – spar ihn dir für schwierige Momente." % Card.SUIT_NAMES[duel.trump_suit], true)
	_tip("hand", "DEINE HAND",
		"Unten liegen deine Karten. Leuchtende Karten kannst du gerade spielen – einfach anklicken. Halte Shift über einer Karte, um zu sehen, was sie bringt.", true)
	_tip("relics", "RELIKTE",
		"Oben rechts stehen deine Relikte als Symbole – hier die Glücksmünze. Sie wirken dauerhaft, den ganzen Run lang. Fahr mit der Maus drüber, um die Wirkung zu sehen; wirkt eins, blitzt es kurz auf.", true)
	_tip("items", "ITEMS",
		"Links neben den Relikten sind die runden Item-Plätze (höchstens 2). Ein Item setzt du einmal ein: einfach anklicken. Probier den Spiegel – er verrät dir eine Karte des Gegners. Neue Relikte und Items gibt es beim Händler.", true)


func _build() -> void:
	_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UIKit.P_BLACK, 0.95)
	box.border_color = UIKit.P_RED
	box.border_width_left = 8
	box.content_margin_left = 22
	box.content_margin_right = 20
	box.content_margin_top = 14
	box.content_margin_bottom = 16
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 0
	box.shadow_offset = Vector2(6, 6)
	_panel.add_theme_stylebox_override("panel", box)
	_panel.custom_minimum_size = Vector2(PANEL_W, 0)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -PANEL_W - 28
	_panel.offset_right = -28
	_panel.offset_top = 172 # unter Relikten und Items (die erklärt das Tutorial)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)
	_step = UIKit.poster_label("", UIKit.body_font(700, 4), 13, UIKit.P_GOLD)
	col.add_child(_step)
	_title = UIKit.poster_label("", UIKit.display_font(2), 26, UIKit.P_CREAM)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	_text = UIKit.poster_label("", UIKit.body_font(400), 17, UIKit.P_CREAM)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(PANEL_W - 44, 0)
	col.add_child(_text)
	_button = Button.new()
	_button.custom_minimum_size = Vector2(0, 44)
	_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_button.pressed.connect(_dismiss)
	UIKit.hover(_button, 1.04)
	col.add_child(_button)


## Nach jeder Änderung am Tisch: passt gerade ein neuer Hinweis?
func _check() -> void:
	if not is_inside_tree():
		return
	var duel: DurakMatch = _m.duel
	if duel.is_over:
		_close_current()
		return
	var mine := duel.current_actor() == DurakMatch.PLAYER
	if duel.defender() == DurakMatch.PLAYER:
		if mine and duel.defense_cards.has(null):
			if not duel.legal_transfers().is_empty():
				_tip("transfer", "SCHIEBEN",
					"Du hast eine Karte gleichen Rangs! Leg sie dazu, dann muss der Gegner alles verteidigen. Schlagen geht natürlich auch.", false, true)
			elif duel.legal_defenses().is_empty():
				_tip("must_take", "NICHTS PASST",
					"Keine deiner Karten schlägt den Angriff. Drück NEHMEN – die Karten kommen auf deine Hand.", false, true)
			else:
				_tip("defend", "VERTEIDIGE DICH",
					"Schlag die Karte mit einer höheren derselben Farbe oder mit einem Trumpf. Klick eine leuchtende Karte an oder zieh sie direkt auf die Angriffskarte – oder drück NEHMEN.", false, true)
		elif _open_key in ["defend", "transfer", "must_take"]:
			_close_current()
	elif not duel.taking:
		if mine and duel.attack_cards.is_empty():
			_tip("attack", "DEIN ANGRIFF",
				"Leg eine beliebige Karte aus. Niedrige Karten sind gut zum Angreifen – die hohen und die Trümpfe brauchst du zum Verteidigen.", false, true)
		elif not duel.attack_cards.is_empty() and not duel.defense_cards.has(null) and duel.can_pass():
			_tip("more", "NACHLEGEN ODER FERTIG",
				"Der Gegner hat geschlagen. Du darfst Karten mit einem Rang nachlegen, der schon auf dem Tisch liegt. Oder drück FERTIG – dann wandern die Karten weg.", false, true)
		elif _open_key in ["attack", "more"] and not mine:
			_close_current()
	elif _open_key == "throw_in" and duel.defender() != DurakMatch.OPPONENT:
		_close_current()


## Hinweis einreihen (jeder nur einmal). `hold`: Gegner wartet bis WEITER.
## `now`: sofort zeigen und einen offenen, nicht anhaltenden Hinweis ersetzen.
func _tip(key: String, title: String, text: String, hold := false, now := false) -> void:
	if _seen.has(key):
		return
	_seen[key] = true
	var entry := [key, title, text, hold]
	if now and not _is_holding():
		_queue.push_front(entry)
		_close_current(false)
	else:
		_queue.append(entry)
	if _open_key == "":
		_next()


func _is_holding() -> bool:
	return _open_key != "" and bool(_m.coach_hold)


func _next() -> void:
	if _queue.is_empty():
		_open_key = ""
		_m.coach_hold = false
		_hide()
		return
	var e: Array = _queue.pop_front()
	_open_key = e[0]
	_shown += 1
	_step.text = "TUTORIAL · SCHRITT %d" % _shown
	_title.text = e[1]
	_text.text = e[2]
	_m.coach_hold = e[3]
	_button.text = "WEITER" if e[3] else "VERSTANDEN"
	_button.theme_type_variation = &"PrimaryButton" if e[3] else &""
	_show()


func _dismiss() -> void:
	Sfx.play(&"button")
	_close_current()


## Aktuellen Hinweis schließen und den nächsten zeigen (oder ausblenden).
func _close_current(advance := true) -> void:
	_open_key = ""
	_m.coach_hold = false
	if advance:
		_next()


func _show() -> void:
	_panel.visible = true
	_panel.size = Vector2(PANEL_W, 0)
	_panel.reset_size()
	_panel.reset_size.call_deferred() # Umbruch steht erst nach dem Layout fest
	_panel.pivot_offset = Vector2(_panel.size.x, 0)
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.92, 0.92)
	if _tw != null:
		_tw.kill()
	var tw := _panel.create_tween()
	_tw = tw
	tw.tween_property(_panel, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hide() -> void:
	if not _panel.visible:
		return
	if _tw != null:
		_tw.kill()
	var tw := _panel.create_tween()
	_tw = tw
	tw.tween_property(_panel, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func() -> void: _panel.visible = false)
