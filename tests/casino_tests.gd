extends Node
## Altes Casino: Die Blender-Modelle enthalten alle Teile, die der Code bewegt oder umfärbt
## (Hebel, Kessel, Zugkette, Lauflichter, Filz und Rand für die Deck-Belohnungen).
##   godot --headless --path . res://tests/casino_tests.tscn

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


func _world() -> TableWorld:
	var w := TableWorld.new()
	w.room_id = Rooms.CASINO
	add_child(w)
	w.build(null)
	return w


func _run() -> void:
	var w := _world()
	await get_tree().process_frame
	var room := w.casino
	check(room != null, "Raum ist das Casino")
	# Tisch: Filz und Rand sind die Teile, die TableSkin umfärbt
	var info := room.table_info()
	var felt := room.find_child("Filz", true, false) as MeshInstance3D
	var rail := room.find_child("Lederrand", true, false) as MeshInstance3D
	var apron := room.find_child("Zarge", true, false) as MeshInstance3D
	check(felt != null and (info.felt as Array).has(felt.material_override), "Filz hat das Filzmaterial")
	check(rail != null and (info.rim as Array).has(rail.material_override), "Lederrand hat das Randmaterial")
	check(apron != null and (info.rim as Array).has(apron.material_override), "Zarge hat das Randmaterial")
	check(is_equal_approx(felt.get_aabb().end.y + felt.global_position.y, TableWorld.TABLE_Y - 0.0006), "Filz liegt knapp unter der Kartenhöhe")
	for part in ["Vertaefelung", "Zierleisten", "Vorhaenge", "Borten", "Neonschild", "Kronleuchter", "Wandleuchter",
			"Wuerfel", "Cocktailglas", "Tischfuesse"]:
		check(room.find_child(part, true, false) != null, "Teil „%s“ ist im Modell" % part)
	check(room._sign_bulbs.size() == 24, "24 Birnen am Neonschild")
	# Spielautomaten: Hebel dreht sich, Walzen laufen, 13 Lauflichter
	check(room.slots.size() == 2, "zwei Automaten")
	var slot := room.slots[0]
	check(slot._lever != null and slot._reels.size() == 3 and slot._bulbs.size() == 13, "Automat: Hebel, 3 Walzen, 13 Birnen")
	check(slot.find_child("Gehaeuse", true, false) != null, "Automat: Gehäuse im Modell")
	var red := (room.slots[0].find_child("Gehaeuse", true, false) as MeshInstance3D).material_override as StandardMaterial3D
	var blue := (room.slots[1].find_child("Gehaeuse", true, false) as MeshInstance3D).material_override as StandardMaterial3D
	check(red != null and blue != null and red.albedo_color != blue.albedo_color, "Automaten rot und blau")
	slot.pull()
	await get_tree().create_timer(0.3).timeout
	check(slot._lever.rotation.x > 0.3, "Hebel wird gezogen")
	# Roulette: Kessel dreht, Kugel landet im gezogenen Fach
	var roulette := room.roulette
	check(roulette._wheel != null and roulette._wheel.get_child_count() >= 5, "Roulette: Kessel mit Scheibe, Stegen, Drehkreuz")
	var landed: Array[int] = []
	roulette.landed.connect(func(n: int) -> void: landed.append(n))
	var start_angle := roulette._wheel.rotation.y
	roulette.spin(5)
	await get_tree().create_timer(0.5).timeout
	check(not is_equal_approx(roulette._wheel.rotation.y, start_angle), "Kessel dreht sich")
	for i in 400:
		if not landed.is_empty():
			break
		await get_tree().create_timer(0.05).timeout
	check(landed == [MiniRoulette.ORDER[5]], "Kugel landet im gezogenen Fach")
	# Bankerlampe: Lämpchen je Leben, Zugkette, Flackern
	w.props.set_lives(3)
	var lamp := w.props._lamp
	check(lamp != null and lamp._jewels.size() == 3, "Bankerlampe: 3 Lämpchen")
	check(lamp._chain != null and lamp._spot != null and lamp._jewel_mesh != null, "Bankerlampe: Kette, Licht, Lämpchen-Vorlage")
	check(lamp.find_child("Juwel", true, false) == null, "Lämpchen-Vorlage liegt nicht mehr im Modell")
	lamp.pull_chain()
	await get_tree().create_timer(0.1).timeout
	check(lamp._chain.position.y < -0.01, "Zugkette wird gezogen")
	lamp.lose_life()
	await get_tree().create_timer(0.8).timeout
	check(lamp._jewels[2].material_override == lamp._jewel_off, "Leben weg: ein Lämpchen aus")
	# Pokerchips statt Münzen
	w.props.set_gold(10, false)
	var chip := w.props._coins[0] as MeshInstance3D
	check(chip.mesh.get_surface_count() == 2 and chip.get_surface_override_material(0) != null, "Pokerchip mit zwei Materialien")
	w.queue_free()
	await get_tree().process_frame
	# Deck-Belohnungen: Filz und Rand werden am neuen Tisch getauscht
	Profile.unlock_all()
	var felt_id := Cosmetics.items_for(&"felt")[0]
	var rim_id := Cosmetics.items_for(&"rim")[0]
	Profile.select_cosmetic(&"felt", felt_id)
	Profile.select_cosmetic(&"rim", rim_id)
	w = _world()
	await get_tree().process_frame
	felt = w.casino.find_child("Filz", true, false) as MeshInstance3D
	rail = w.casino.find_child("Lederrand", true, false) as MeshInstance3D
	check(felt.material_override == Cosmetics.felt_material(felt_id), "Deck-Belohnung: Filz getauscht")
	check(rail.material_override == Cosmetics.rim_material(rim_id), "Deck-Belohnung: Rand getauscht")
	w.queue_free()
	await get_tree().process_frame
	print("\n%d Checks, %d Fehler" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
