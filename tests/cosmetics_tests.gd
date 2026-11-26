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
	print("\n%d Checks, %d Fehler" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
