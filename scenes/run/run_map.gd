extends Control
## „Der Weg“: Der nächste Gegner sitzt schon im Halbdunkel am Tisch.
## Links die Stationen der Nacht als Pfad, rechts unten der nächste Gegner,
## oben rechts Leben, Gold, Hand und Relikte.

const STOP_HEIGHT := 112.0

var _backdrop: RoomBackdrop


func _ready() -> void:
	UIKit.poster_wedge(self, Vector2(500, 150), %Path)
	if Run.encounters.is_empty():
		# Szene direkt mit F6 gestartet → einfach einen neuen Run beginnen.
		Run.start_new_run()
		return
	var next := Run.current_opponent()
	_backdrop = RoomBackdrop.new()
	_backdrop.opponent = next
	_backdrop.blur = 0.0 # Gegner so scharf wie am Tisch
	_backdrop.darken = 0.35
	_backdrop.cam_from = Vector3(0.12, 1.32, 0.95)
	_backdrop.cam_to = Vector3(0.12, 1.12, -0.4)
	add_child(_backdrop)
	move_child(_backdrop, 0)
	var shade := TextureRect.new()
	shade.texture = _side_shade()
	shade.set_anchors_and_offsets_preset(PRESET_LEFT_WIDE)
	shade.offset_right = 520
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(shade)
	move_child(shade, 1)

	%FightButton.pressed.connect(func() -> void: Run.goto(Run.SCENE_MATCH))
	var confirm := [false]
	%AbandonButton.pressed.connect(func() -> void:
		if not confirm[0]:
			confirm[0] = true
			%AbandonButton.text = "WIRKLICH AUFGEBEN?"
			return
		Run.abandon())
	UIKit.hover(%FightButton, 1.04)
	UIKit.hover(%AbandonButton, 1.03)
	_render(next)
	UIKit.appear(%Path, 0.1, Vector2(-30, 0), 0.6)
	UIKit.appear(%NextPanel, 0.35, Vector2(30, 0), 0.6)
	UIKit.appear(%RunInfo, 0.5, Vector2(0, -10), 0.5)
	%FightButton.grab_focus()
	UIKit.show_unlocks.call_deferred(self)


func _render(next: OpponentData) -> void:
	for c in %Stops.get_children():
		c.queue_free()
	if Run.endless:
		_render_endless()
	else:
		# nur der aktuelle Akt (3 Tische und der Boss), darüber „AKT x VON 3“
		var act := UIKit.label("AKT %d VON %d" % [Run.act_of() + 1, Run.ACTS], 15, Color(1, 0.84, 0.55), &"HeaderLabel")
		%Stops.add_child(act)
		for i in Run.act_floors():
			%Stops.add_child(_stop(i))

	%NextCaption.text = "DER BOSS WARTET" if next.is_boss else "ALS NÄCHSTES AM TISCH"
	if Run.endless:
		%NextCaption.text = "ENDLOS · NÄCHSTER GEGNER"

	%NextName.text = next.display_name
	%NextTaunt.text = "„%s“" % next.taunt if not next.taunt.is_empty() else ""
	for c in %NextFacts.get_children():
		c.queue_free()
	if Run.endless:
		%NextFacts.add_child(_fact("Kein Ziel", UIKit.INK_RED, "Endlos: Punkte sammeln, bis du selbst Durak wirst."))
	else:
		%NextFacts.add_child(_fact("Ziel %d" % Run.score_target(), UIKit.INK_RED, "So viele Punkte brauchst du an diesem Tisch."))
	%NextFacts.add_child(_fact("· %d Karten" % next.hand_size, UIKit.INK_SOFT, "Handkarten des Gegners."))
	%NextFacts.add_child(_fact("· +%d Gold" % next.gold_reward, UIKit.INK_SOFT, "Belohnung bei Sieg (plus Zinsen)."))
	%FightButton.text = "AN DEN TISCH SETZEN"

	for c in %RunInfo.get_children():
		c.queue_free()
	%RunInfo.add_child(_chip("♥".repeat(Run.lives) if Run.lives <= 6 else "♥ %d" % Run.lives, UIKit.INK_RED, "Leben"))
	%RunInfo.add_child(_chip("%d Gold" % Run.gold, UIKit.INK, "Gold"))
	%RunInfo.add_child(_chip("Hand %d" % Run.player_hand_size(), UIKit.INK, "Deine Handkarten"))
	%RunInfo.add_child(_chip("Deck: %s" % Run.deck_name(), UIKit.INK, Run.deck_description()))
	if Run.daily:
		%RunInfo.add_child(_chip("Täglich" if Run.daily_counts else "Täglich · Übung", UIKit.INK_RED,
			"Tägliche Herausforderung – %s" % ("dieser Versuch zählt" if Run.daily_counts else "nur Übung, zählt nicht")))
	# Relikte darunter als freie Symbole, höchstens 5 pro Reihe (rechtsbündig)
	if _relic_grid == null:
		_relic_grid = VBoxContainer.new()
		_relic_grid.add_theme_constant_override("separation", 4)
		_relic_grid.anchor_left = 1.0
		_relic_grid.anchor_right = 1.0
		_relic_grid.offset_left = -48.0
		_relic_grid.offset_right = -48.0
		_relic_grid.offset_top = 80.0
		_relic_grid.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		add_child(_relic_grid)
	for c in _relic_grid.get_children():
		c.queue_free()
	var row: HBoxContainer
	for i in Run.relics.size():
		var r: RelicData = Run.relics[i]
		if i % 5 == 0:
			row = HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_END
			row.add_theme_constant_override("separation", 8)
			_relic_grid.add_child(row)
		var icon := UIKit.relic_icon(r.visual(), 40, 28)
		icon.tooltip_text = "%s – %s" % [r.display_name, r.description]
		icon.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(icon)


## Eine Station auf dem Pfad: Linie, Porträt, Name, Ziel/Status.
func _stop(i: int) -> Control:
	var o := Run.encounters[i]
	var done := i < Run.floor_index
	var current := i == Run.floor_index
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, STOP_HEIGHT)
	row.add_theme_constant_override("separation", 16)

	var track := _Track.new()
	track.custom_minimum_size = Vector2(64, STOP_HEIGHT)
	var act := Run.act_floors(i)
	track.first = i == act[0]
	track.last = i == act[-1]
	track.done = done
	track.current = current
	track.boss = o.is_boss
	track.portrait = o.portrait
	row.add_child(track)

	var info := VBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	var step := UIKit.label("BOSS" if o.is_boss else "TISCH %d" % (Run.act_pos(i) + 1), 12,
		Color(1, 0.5, 0.45) if o.is_boss else UIKit.MUTED, &"HeaderLabel")
	info.add_child(step)
	var name_l := UIKit.label(o.display_name, 26 if current else 21,
		UIKit.CREAM if not done else Color(UIKit.MUTED, 0.6), &"BrushLabel")
	info.add_child(name_l)
	var status := UIKit.label("✓ besiegt" if done else ("%d Punkte" % Run.score_target(i)), 14,
		Color(UIKit.MUTED, 0.6) if done else (Color(1, 0.84, 0.55) if current else UIKit.MUTED), &"TypeLabel")
	info.add_child(status)
	if current:
		UIKit.pulse(track, 0.75, 1.8)
	return row


var _relic_grid: VBoxContainer


## Endlos-Modus: statt der Stationen Punkte, Decks und Rekord.
func _render_endless() -> void:
	%Stops.add_child(UIKit.label("ENDLOS-MODUS", 15, Color(1, 0.84, 0.55), &"HeaderLabel"))
	var big := UIKit.label("%d" % Run.endless_score, 64, UIKit.CREAM, &"TitleLabel")
	%Stops.add_child(big)
	%Stops.add_child(UIKit.label("Punkte bisher", 14, UIKit.MUTED, &"TypeLabel"))
	%Stops.add_child(UIKit.label("%d Decks geschafft" % Run.endless_decks, 21, UIKit.CREAM, &"BrushLabel"))
	var best := Profile.endless_best()
	%Stops.add_child(UIKit.label("Rekord: %d" % best if best > 0 else "Noch kein Rekord", 18,
		Color(1, 0.84, 0.55), &"TypeLabel"))
	%Stops.add_child(UIKit.label("Gegner Durak → neues Deck.\nDu Durak → eine Kerze weniger.", 14, UIKit.MUTED, &"TypeLabel"))


func _chip(text: String, color: Color, tip: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UIKit.paper(Vector4(10, 5, 12, 5)))
	p.tooltip_text = tip
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	l.text = text
	p.add_child(l)
	return p


func _fact(text: String, color: Color, tip: String) -> Control:
	var l := Label.new()
	l.theme_type_variation = &"InkType"
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", color)
	l.text = text
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


func _side_shade() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.012, 0.045, 0.9))
	g.set_color(1, Color(0.02, 0.012, 0.045, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_to = Vector2(1, 0)
	return t


## Pfadstück mit Porträt-Kreis.
class _Track extends Control:
	const SYM := preload("res://assets/fonts/DejaVuSans-Bold.ttf")
	var first := false
	var last := false
	var done := false
	var current := false
	var boss := false
	var portrait: Texture2D

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		var r := 28.0 if current else 24.0
		var line := Color(0.94, 0.89, 0.8, 0.7) if done else Color(0.75, 0.7, 0.66, 0.35)
		if not first:
			_dashed(Vector2(c.x, 0), Vector2(c.x, c.y - r - 4), line)
		if not last:
			_dashed(Vector2(c.x, c.y + r + 4), Vector2(c.x, size.y), Color(0.75, 0.7, 0.66, 0.35))
		var ring := Color(0.81, 0.15, 0.16) if current else (Color(0.96, 0.34, 0.3) if boss else Color(0.75, 0.7, 0.66, 0.6))
		if done:
			ring = Color(0.94, 0.89, 0.8, 0.5)
		draw_circle(c, r + 3, Color(0.04, 0.03, 0.08, 0.95))
		if portrait != null:
			draw_texture_rect(portrait, Rect2(c - Vector2(r, r), Vector2(r, r) * 2), false,
				Color(0.5, 0.5, 0.55) if done else Color.WHITE)
		draw_arc(c, r + 2, 0, TAU, 48, ring, 4.0 if current else 1.5, true)
		if done:
			draw_string(SYM, c + Vector2(-9, 9), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.94, 0.89, 0.8))

	func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
		var len := a.distance_to(b)
		var dir := (b - a) / maxf(len, 0.001)
		var d := 0.0
		while d < len:
			draw_line(a + dir * d, a + dir * minf(d + 6.0, len), col, 2.0)
			d += 11.0
