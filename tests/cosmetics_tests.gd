extends Node
## Deck-Belohnungen (Cosmetics, TableSkin).
##   godot --headless --path . res://tests/cosmetics_tests.tscn

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


func _run() -> void:
	# jedes Deck hat genau eine Belohnung je Stufe, alle Texturen gibt es
	for d in Profile.decks():
		for level in 3:
			check(Cosmetics.reward_of(d.id, level) != &"", "%s Stufe %d hat Belohnung" % [d.id, level])
	check(Cosmetics.ITEMS.size() == Profile.decks().size() * 3, "36 Belohnungen")
	for id: StringName in Cosmetics.ITEMS:
		var it: Dictionary = Cosmetics.ITEMS[id]
		check(Cosmetics.SLOTS.has(it.slot), "%s: Platz bekannt" % id)
		if it.has("tex"):
			check(ResourceLoader.exists(Cosmetics.DIR + it.tex), "%s: Textur da" % id)
	# Freischalten: nur die gewonnene Stufe, sofort angelegt, Meldung
	var got: Array[StringName] = []
	Profile.reward_unlocked.connect(func(id: StringName) -> void: got.append(id))
	check(Cosmetics.selected(&"felt") == &"", "am Anfang Standard")
	Profile.on_run_finished(true, 12, 1.0, &"bandit", 2)
	check(got == [&"felt_blue"], "Schwer-Sieg meldet nur blauen Filz")
	check(Cosmetics.is_unlocked(&"felt_blue") and not Cosmetics.is_unlocked(&"felt_grey"), "Stufen einzeln")
	check(Cosmetics.selected(&"felt") == &"felt_blue", "frisch freigeschaltet = angelegt")
	Profile.select_cosmetic(&"felt", &"felt_grey")
	check(Cosmetics.selected(&"felt") == &"felt_blue", "gesperrtes lässt sich nicht anlegen")
	Profile.on_run_finished(true, 12, 1.0, &"bandit", 2)
	check(got.size() == 1, "zweiter Sieg auf gleicher Stufe meldet nichts")
	Profile.select_cosmetic(&"felt", &"")
	check(Cosmetics.selected(&"felt") == &"", "zurück auf Standard")
	# alle Räume bauen mit allen Belohnungen ohne Fehler
	Profile.unlock_all()
	for slot: StringName in Cosmetics.SLOTS:
		var ids := Cosmetics.items_for(slot)
		Profile.select_cosmetic(slot, ids[ids.size() - 1])
	for room: StringName in Rooms.ALL:
		var w := TableWorld.new()
		w.room_id = room
		add_child(w)
		w.build(null)
		check(w.skin != null, "%s: Belohnungen am Tisch" % room)
		w.skin.on_card_played()
		w.queue_free()
		await get_tree().process_frame
	await _models()
	print("\n%d Checks, %d Fehler" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


## Blender-Modelle der Belohnungen, Items und des Rauchzeugs (art/blender/cosmetics.py).
func _models() -> void:
	var parts := {
		"res://assets/cosmetics/cosmetics.glb": ["Totenkopf", "Doppeladler", "Doppeladler_Juwel", "Kraehe", "Kraehe_Kopf",
			"Kraehe_Schnabel", "Gloeckchen", "Seerosenblatt", "Seerose", "Hexenkerze", "Skinflamme", "Faberge", "Faberge_Ei",
			"Faberge_Kerze", "Tischrahmen_Ecke", "Tischrahmen_Leiste"],
		"res://assets/models/items.glb": ["Spiegel", "Spiegel_Glas", "Schnapsglas"],
		"res://assets/models/smoking.glb": ["Aschenbecher", "Schachtel", "Schachtel_Deckel", "Zigarette_Stange"],
	}
	for path: String in parts:
		var lib := (load(path) as PackedScene).instantiate()
		for n: String in parts[path]:
			check(lib.find_child(n, true, false) != null, "%s: Teil %s" % [path.get_file(), n])
		lib.free()
	# jede Rand-Textur hat ihr Relief, Muster-Filze sind fein gezeichnet
	for id in Cosmetics.items_for(&"rim"):
		if Cosmetics.ITEMS[id].has("tex"):
			check(Cosmetics.rim_material(id).normal_texture != null, "%s: Relief" % id)
	for id: StringName in [&"felt_feather", &"felt_wine", &"felt_stripes", &"felt_harlequin", &"felt_stars", &"felt_claws", &"felt_moon"]:
		check(Cosmetics.felt_material(id).albedo_texture.get_width() == 1024, "%s: 1024 px" % id)
	# Bahnhof (Tisch ohne eigenen Rand): Rahmen aus vier Ecken und vier Leisten in passender Länge
	var w := await _world(Rooms.STATION, {&"rim": &"rim_mossy", &"corners": &"corner_skulls", &"extra": &"extra_crow"})
	var bars := w.skin.find_children("*Tischrahmen_Leiste*", "MeshInstance3D", true, false)
	check(w.skin.find_children("*Tischrahmen_Ecke*", "MeshInstance3D", true, false).size() == 4 and bars.size() == 4, "Rahmen: 4 Ecken, 4 Leisten")
	var frame: Vector2 = w.station.table_info().frame
	check(bars.size() == 4 and is_equal_approx((bars[0] as Node3D).scale.x, (frame.x - 0.07) * 2.0)
		and is_equal_approx((bars[1] as Node3D).scale.x, (frame.y - 0.07) * 2.0), "Leisten auf Tischlänge gestreckt")
	for b: MeshInstance3D in bars:
		check(b.material_override == Cosmetics.rim_material(&"rim_mossy"), "Leiste trägt das Rand-Material")
	check(w.skin.find_children("*Seerosenblatt*", "MeshInstance3D", true, false).size() > 4, "Seerosenblätter auf dem Rand")
	check(w.skin.find_children("*Totenkopf*", "MeshInstance3D", true, false).size() == 4, "vier Totenköpfe")
	# Krähe: Kopf und Unterschnabel sind Gelenke des Modells
	check(w.skin._crow != null and w.skin._crow_head != null and w.skin._crow_beak != null, "Krähe mit Kopf und Schnabel")
	check(w.skin._crow_head.get_parent() == w.skin._crow and w.skin._crow_beak.get_parent() == w.skin._crow_head, "Schnabel hängt am Kopf")
	check(is_equal_approx(w.skin._crow.scale.x, 1.5), "Krähe 1,5-fach wie bisher")
	w.skin.caw()
	var beak: Node3D = w.skin._crow_beak
	check(await _soon(func() -> bool: return beak.rotation.z < -0.2), "Krächzen öffnet den Schnabel")
	w.queue_free()
	# Glöckchen wackeln, Kerzen und Leuchter haben je eine Flamme
	w = await _world(Rooms.CASINO, {&"corners": &"corner_eagles", &"extra": &"extra_bells"})
	check(w.skin._bells.size() > 4 and w.skin._bells[0] is MeshInstance3D, "Glöckchen am Rand")
	w.skin.on_card_played()
	var bells: Array[Node3D] = w.skin._bells
	check(await _soon(func() -> bool: return absf(bells[0].rotation.z) > 0.001 or absf(bells[1].rotation.z) > 0.001), "Glöckchen wackeln")
	check(w.skin.find_children("*Doppeladler_Juwel*", "MeshInstance3D", true, false).size() == 4, "vier Doppeladler mit Juwel")
	w.queue_free()
	for extra: StringName in [&"extra_green_candles", &"extra_faberge"]:
		w = await _world(Rooms.SUBMARINE, {&"extra": extra})
		check(w.skin._flames.size() == 2, "%s: zwei Flammen" % extra)
		var flame: Node3D = w.skin._flames[0].node
		check(flame.get_child_count() == 1 and flame.get_child(0) is MeshInstance3D, "%s: Flamme ist ein Modell" % extra)
		check(await _soon(func() -> bool: return flame.scale.y != 1.0 and flame.scale.x == 1.0), "%s: Flamme flackert in der Höhe" % extra)
		w.queue_free()
	# Hinterzimmer: Aschenbecher und Schachtel aus dem Modell, Deckel am Scharnier, drei Zigaretten
	w = await _world(Rooms.HINTERZIMMER, {&"cigs": &"cig_gold"})
	var tray := w.ashtray.find_child("*Aschenbecher*", true, false) as MeshInstance3D
	check(tray != null and tray.mesh.get_surface_count() == 3, "Aschenbecher: Körper, Rand, Mulde")
	var dir := w.ashtray.notch_dir.normalized()
	check(tray != null and (tray.global_transform.basis.z.normalized() * Vector3(1, 0, 1)).normalized().dot(dir) > 0.999, "Kerbe zeigt zur Zigarette")
	var pack: CigarettePack = null
	for c in w.get_children():
		if c is CigarettePack:
			pack = c
	check(pack != null and pack._lid != null and pack._lid.name.begins_with("Schachtel_Deckel"), "Schachtel mit Deckel")
	check(pack != null and pack._lid.position.is_equal_approx(Vector3(0, CigarettePack.H - CigarettePack.LID_H, -CigarettePack.D * 0.5)), "Scharnier hinten oben")
	check(pack != null and pack._cigs.size() == 3 and pack._cigs[0].get_child_count() == 1, "drei Zigaretten in der Schachtel")
	var strip := pack.find_child("*Schachtel_Streifen*", true, false) as MeshInstance3D
	check(strip != null and strip.material_override == Cosmetics.cig_mat(&"pack"), "Schachtel trägt die Skin-Farbe")
	# Spiegel fliegt als Modell und räumt sich weg
	var before := w.get_child_count()
	w.mirror_flight(func() -> void: pass)
	var mirror := w.get_child(w.get_child_count() - 1)
	var glass := mirror.find_child("*Spiegel_Glas*", true, false) as MeshInstance3D
	check(w.get_child_count() == before + 1 and glass != null, "Spiegel aus dem Modell")
	check(glass != null and (glass.material_override as StandardMaterial3D).emission_enabled, "Spiegelglas leuchtet auf")
	w.queue_free()
	await get_tree().process_frame
	# Schnapsglas des Gegners
	var fig := OpponentFigure.new()
	add_child(fig)
	var shot := fig._make_shot()
	check(shot.find_child("*Schnapsglas*", true, false) is MeshInstance3D and fig._shot_liquid != null, "Schnapsglas aus dem Modell")
	shot.free()
	fig.queue_free()


## Wartet ein paar Bilder, bis `ok` stimmt (Tweens laufen erst mit dem nächsten Bild an).
func _soon(ok: Callable, frames := 90) -> bool:
	for i in frames:
		if ok.call():
			return true
		await get_tree().process_frame
	return ok.call()


func _world(room: StringName, picks: Dictionary) -> TableWorld:
	for slot: StringName in Cosmetics.SLOTS:
		Profile.select_cosmetic(slot, picks.get(slot, &""))
	var w := TableWorld.new()
	w.room_id = room
	add_child(w)
	w.build(null)
	await get_tree().process_frame
	return w
