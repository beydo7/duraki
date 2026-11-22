extends Control
## „Der Weg“: Der nächste Gegner sitzt schon im Halbdunkel am Tisch.
## Links die Stationen der Nacht als Pfad, rechts unten der nächste Gegner,
## oben rechts Leben, Gold, Hand und Relikte.

const STOP_HEIGHT := 112.0

var _backdrop: RoomBackdrop


func _ready() -> void:
	if Run.encounters.is_empty():
		# Szene direkt mit F6 gestartet → einfach einen neuen Run beginnen.
		Run.start_new_run()
		return
	var next := Run.current_opponent()
	_backdrop = RoomBackdrop.new()
	_backdrop.opponent = next
	_backdrop.blur = 1.2
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
		Run.goto(Run.SCENE_MENU))
	UIKit.hover(%FightButton, 1.04)
	UIKit.hover(%AbandonButton, 1.03)
	_render(next)
	UIKit.appear(%Path, 0.1, Vector2(-30, 0), 0.6)
	UIKit.appear(%NextPanel, 0.35, Vector2(30, 0), 0.6)
	UIKit.appear(%RunInfo, 0.5, Vector2(0, -10), 0.5)
	%FightButton.grab_focus()


func _render(next: OpponentData) -> void:
	for c in %Stops.get_children():
		c.queue_free()
	for i in Run.encounters.size():
		%Stops.add_child(_stop(i))

	%NextCaption.text = "DER BOSS WARTET" if next.is_boss else "ALS NÄCHSTES AM TISCH"
	%NextCaption.add_theme_color_override("font_color", UIKit.RED if next.is_boss else UIKit.MUTED)
	%NextName.text = next.display_name
	%NextTaunt.text = "„%s“" % next.taunt if not next.taunt.is_empty() else ""
	for c in %NextFacts.get_children():
		c.queue_free()
	%NextFacts.add_child(_chip("ZIEL %d" % Run.score_target(), UIKit.GOLD, "So viele Punkte brauchst du an diesem Tisch."))
	%NextFacts.add_child(_chip("%d KARTEN" % next.hand_size, UIKit.CREAM, "Handkarten des Gegners."))
	%NextFacts.add_child(_chip("+%d GOLD" % next.gold_reward, UIKit.GOLD, "Belohnung bei Sieg (plus Zinsen)."))
	%FightButton.text = "AN DEN TISCH SETZEN"

	for c in %RunInfo.get_children():
		c.queue_free()
	%RunInfo.add_child(_chip("♥".repeat(Run.lives) if Run.lives <= 6 else "♥ %d" % Run.lives, UIKit.RED, "Leben"))
	%RunInfo.add_child(_chip("● %d" % Run.gold, UIKit.GOLD, "Gold"))
	%RunInfo.add_child(_chip("HAND %d" % Run.player_hand_size(), UIKit.CREAM, "Deine Handkarten"))
	for r in Run.relics:
		%RunInfo.add_child(_chip(MatchHUD.RELIC_SYMBOLS.get(r.id, r.display_name.left(1)), UIKit.LILAC,
			"%s – %s" % [r.display_name, r.description]))


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
	track.first = i == 0
	track.last = i == Run.encounters.size() - 1
	track.done = done
	track.current = current
	track.boss = o.is_boss
	track.portrait = o.portrait
	row.add_child(track)

	var info := VBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 0)
	row.add_child(info)
	var step := UIKit.label("BOSS" if o.is_boss else "TISCH %d" % (i + 1), 11,
		UIKit.RED if o.is_boss else UIKit.MUTED, &"HeaderLabel")
	info.add_child(step)
	var name_l := UIKit.label(o.display_name, 26 if current else 21,
		UIKit.CREAM if not done else Color(UIKit.MUTED, 0.6), &"BrushLabel")
	info.add_child(name_l)
	var status := UIKit.label("✓ besiegt" if done else ("%d Punkte" % Run.score_target(i)), 14,
		Color(UIKit.MUTED, 0.6) if done else (UIKit.GOLD if current else UIKit.MUTED))
	info.add_child(status)
	if current:
		UIKit.pulse(track, 0.75, 1.8)
	return row


func _chip(text: String, color: Color, tip: String) -> Control:
	var p := PanelContainer.new()
	var st := UIKit.glass(18, Vector4(14, 6, 14, 6), 0.82)
	st.border_color = Color(color, 0.45)
	p.add_theme_stylebox_override("panel", st)
	p.tooltip_text = tip
	var l := UIKit.label(text, 15, color, &"HeaderLabel")
	p.add_child(l)
	return p


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
	var first := false
	var last := false
	var done := false
	var current := false
	var boss := false
	var portrait: Texture2D

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		var r := 28.0 if current else 24.0
		var line := Color(1, 0.82, 0.4, 0.7) if done else Color(0.6, 0.5, 1.0, 0.35)
		if not first:
			_dashed(Vector2(c.x, 0), Vector2(c.x, c.y - r - 4), line)
		if not last:
			_dashed(Vector2(c.x, c.y + r + 4), Vector2(c.x, size.y), Color(0.6, 0.5, 1.0, 0.35))
		var ring := UIKit.GOLD if current else (UIKit.RED if boss else Color(0.6, 0.5, 1.0, 0.6))
		if done:
			ring = Color(1, 0.82, 0.4, 0.5)
		draw_circle(c, r + 3, Color(0.04, 0.03, 0.08, 0.95))
		if portrait != null:
			draw_texture_rect(portrait, Rect2(c - Vector2(r, r), Vector2(r, r) * 2), false,
				Color(0.5, 0.5, 0.55) if done else Color.WHITE)
		draw_arc(c, r + 2, 0, TAU, 48, ring, 2.5 if current else 1.5, true)
		if done:
			draw_string(UIKit.BRUSH, c + Vector2(-9, 9), "✓", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UIKit.GOLD)

	func _dashed(a: Vector2, b: Vector2, col: Color) -> void:
		var len := a.distance_to(b)
		var dir := (b - a) / maxf(len, 0.001)
		var d := 0.0
		while d < len:
			draw_line(a + dir * d, a + dir * minf(d + 6.0, len), col, 2.0)
			d += 11.0
