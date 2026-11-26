extends Node
## Bahnhof, U-Boot, Zirkuswagen: Die Blender-Modelle enthalten alle Teile, die der Code bewegt,
## einzeln schaltet oder umfärbt (Röhren, Zug, Periskop, Wal, Druckanzeigen, Spieluhr, Ballons).
##   godot --headless --path . res://tests/rooms_tests.tscn

var _checks := 0
var _failures := 0


func check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FEHLER: " + label)


func _ready() -> void:
	Profile.reset_for_tests()
	_run.call_deferred()


func _world(room: StringName) -> TableWorld:
	var w := TableWorld.new()
	w.room_id = room
	add_child(w)
	w.build(null)
	return w


## Filz und Rand des Tischs tragen die Materialien, die TableSkin tauscht.
func _check_table(room: Node, top_name: String, rim_name: String, label: String) -> void:
	var info: Dictionary = room.call(&"table_info")
	var top := room.find_child(top_name, true, false) as MeshInstance3D
	var rim := room.find_child(rim_name, true, false) as MeshInstance3D
	check(top != null and (info.felt as Array).has(top.material_override), label + ": Tischfläche hat das Filzmaterial")
	check(rim != null and (info.rim as Array).has(rim.material_override), label + ": Gestell hat das Randmaterial")
	check(top != null and absf(top.get_aabb().end.y + top.global_position.y - TableWorld.TABLE_Y) < 0.001, label + ": Tischfläche auf Kartenhöhe")


func _run() -> void:
	# --- Bahnhof ---
	var w := _world(Rooms.STATION)
	await get_tree().process_frame
	var st := w.station
	_check_table(st, "Tischplatte", "Tischgestell", "Bahnhof")
	for part in ["Fensterrahmen", "Heizkoerper", "Baenke_Latten", "Baenke_Eisen", "Koffer", "Kessel", "Tafelrahmen", "Klappfelder",
			"Neon_Gehaeuse", "Kachelleisten", "Bahnsteiglampen"]:
		check(st.find_child(part, true, false) != null, "Bahnhof: Teil „%s“ ist im Modell" % part)
	check(st._tubes.size() == 3, "Bahnhof: drei Neonröhren")
	var tube := st.find_child("Roehre_0", true, false) as MeshInstance3D
	check(tube != null and tube.material_override == st._tubes[0].mat, "Bahnhof: Röhre trägt ihr eigenes Leuchtmaterial")
	check(st._train != null and st._train.find_child("Zug_Wagen", true, false) != null, "Bahnhof: Zug im Modell")
	st.start_train()
	await get_tree().create_timer(0.3).timeout
	check(st._train.position.x > -50.0 and st._train.position.x < 999.0, "Bahnhof: Zug fährt")
	w.props.set_lives(3)
	st.lives_panel.lose_life()
	check(st._board_rows.size() == 6, "Bahnhof: Fahrplantafel mit sechs Zeilen")
	w.queue_free()
	await get_tree().process_frame
	# --- U-Boot ---
	w = _world(Rooms.SUBMARINE)
	await get_tree().process_frame
	var sub := w.special_room as SubmarineRoom
	_check_table(sub, "Tischplatte", "Tischgestell", "U-Boot")
	for part in ["Spanten", "Spanten_Nieten", "Rohre_Rot", "Ventilraeder", "Notlicht", "Bullauge", "Sonar_Gehaeuse", "Sonar_Schirm",
			"Lampen_Glas", "Blechbecher", "Seekarte", "Periskop_Manschette"]:
		check(sub.find_child(part, true, false) != null, "U-Boot: Teil „%s“ ist im Modell" % part)
	check((sub.find_child("Notlicht", true, false) as MeshInstance3D).material_override == sub._red_mat, "U-Boot: Notlicht pulsiert über sein Material")
	check(sub._periscope != null and sub._periscope.get_child_count() >= 3, "U-Boot: Periskop mit Rohr, Ringen, Okular")
	check(sub._fish.size() == 10 and ((sub._fish[0].node as Node3D).get_child(0) as MeshInstance3D).mesh != null, "U-Boot: zehn Fische")
	var start := sub._periscope.rotation.y
	sub.turn_periscope()
	await get_tree().create_timer(0.4).timeout
	check(sub._periscope.rotation.y > start + 0.3, "U-Boot: Periskop dreht sich")
	check(sub._whale != null and not sub._whale.visible and sub._whale.get_child_count() >= 3, "U-Boot: Wal wartet unsichtbar")
	sub.show_whale()
	await get_tree().create_timer(0.2).timeout
	check(sub._whale.visible, "U-Boot: Wal schwimmt vorbei")
	w.props.set_lives(3)
	var gauges := sub.lives_panel
	check(gauges._gauges.size() >= 3 and (gauges._gauges[0].needle as Node3D) != null, "U-Boot: Druckanzeigen mit Zeiger")
	var lamp := (gauges._gauges[0].root as Node3D).find_child("Leuchte", true, false) as MeshInstance3D
	check(lamp != null and lamp.material_override == gauges._gauges[0].lamp, "U-Boot: Kontrollleuchte trägt ihr eigenes Material")
	gauges.lose_life()
	await get_tree().create_timer(0.4).timeout
	check(gauges._gauges.any(func(g: Dictionary) -> bool: return not g.ok), "U-Boot: Leben weg, eine Anzeige im Roten")
	w.queue_free()
	await get_tree().process_frame
	# --- Zirkuswagen ---
	w = _world(Rooms.CIRCUS)
	await get_tree().process_frame
	var circ := w.special_room as CircusRoom
	_check_table(circ, "Tischtuch", "Tischplatte", "Zirkus")
	for part in ["Decke_Dunkel", "Decke_Hell", "Wandleisten", "Vorhang", "Vorhangstange", "Kostuem_0", "Kostuem_3", "Zylinderhut",
			"Clownshut", "Spiegelrahmen", "Spiegelbirnen", "Schminktisch", "Trommel", "Trommel_Schnuerung", "Lichterkette_Kabel"]:
		check(circ.find_child(part, true, false) != null, "Zirkus: Teil „%s“ ist im Modell" % part)
	check(circ._bulbs.size() == 22, "Zirkus: 22 Birnen an der Lichterkette")
	check(circ._box != null and circ._lid != null and circ._dancer != null and circ._jack != null and circ._box.has_node(^"Key"),
		"Zirkus: Spieluhr mit Deckel, Tänzerin, Springteufel, Schlüssel")
	check(not circ._jack.visible and circ._dancer.visible, "Zirkus: Springteufel versteckt")
	var turn := circ._dancer.rotation.y
	circ.wind_music_box()
	await get_tree().create_timer(0.3).timeout
	check(circ._dancer.rotation.y > turn, "Zirkus: Tänzerin dreht sich")
	circ.pop_jack()
	await get_tree().create_timer(0.3).timeout
	check(circ._jack.visible and circ._lid.rotation.x < -1.0, "Zirkus: Springteufel schnellt heraus, Deckel offen")
	w.props.set_lives(3)
	var balloons := circ.lives_panel
	check(balloons._balloons.size() == 3 and (balloons._balloons[0].ball as MeshInstance3D).mesh == balloons._ball_mesh, "Zirkus: drei Luftballons")
	balloons.lose_life()
	await get_tree().create_timer(0.5).timeout
	check(not (balloons._balloons[2].ball as MeshInstance3D).visible, "Zirkus: Leben weg, ein Ballon geplatzt")
	w.queue_free()
	await get_tree().process_frame
	print("\n%d Checks, %d Fehler" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
