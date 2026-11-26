class_name Cosmetics
extends RefCounted
## Deck-Belohnungen: Aussehen von Tisch, Zigaretten und Münzen.
##
## Jedes Deck hat drei Belohnungen, eine je Schwierigkeit. Gewinnt man einen Run mit dem Deck
## auf dieser Stufe (Abzeichen in `Profile.badges`), ist die Belohnung frei. Jede Stufe zählt
## einzeln (ein Sieg auf Schwer schaltet Leicht und Normal nicht mit frei).
## Pro Platz (Zigaretten, Filz, Rand …) ist höchstens eine Belohnung aktiv; ausgewählt wird im
## Index-Reiter AUSSEHEN (`Profile.cosmetics`). Frisch freigeschaltet → sofort aktiv.
## Filz und Rand gelten in allen Räumen (TableSkin).

const DIR := "res://assets/cosmetics/"

## Plätze in der Reihenfolge der Anzeige: id → [Überschrift, Symbol]
const SLOTS := {
	&"felt": ["TISCHFILZ", "🟩"],
	&"rim": ["TISCHRAND", "🪵"],
	&"corners": ["TISCHECKEN", "💀"],
	&"extra": ["EXTRAS", "✨"],
	&"cigs": ["ZIGARETTEN", "🚬"],
	&"coins": ["MÜNZEN", "🪙"],
}

## id → {slot, deck, level, name, …Aussehen}
## Filz: tex (Datei), color (Grundfarbe fürs Menü), scale (Kachelgröße in m, 0 = ein Bild für den Tisch)
## Rand: tex, color, metal, rough, trim (Goldleiste), lily (Seerosen)
const ITEMS := {
	# Hinterzimmer – Zigaretten
	&"cig_blue": {"slot": &"cigs", "deck": &"hinterzimmer", "level": 0, "name": "Blaue Zigaretten",
		"paper": Color(0.42, 0.62, 0.92), "pack": Color(0.12, 0.3, 0.7), "band": Color(0.85, 0.88, 0.95)},
	&"cig_black": {"slot": &"cigs", "deck": &"hinterzimmer", "level": 1, "name": "Schwarze Zigaretten",
		"paper": Color(0.07, 0.07, 0.08), "pack": Color(0.06, 0.06, 0.07), "band": Color(0.85, 0.7, 0.3)},
	&"cig_gold": {"slot": &"cigs", "deck": &"hinterzimmer", "level": 2, "name": "Goldene Zigaretten",
		"paper": Color(0.92, 0.74, 0.3), "pack": Color(0.8, 0.6, 0.2), "band": Color(0.98, 0.9, 0.6), "metal": true},
	# Banditen – Filzfarben
	&"felt_grey": {"slot": &"felt", "deck": &"bandit", "level": 0, "name": "Grauer Filz", "tex": "felt_grey.png", "color": Color("6e7070")},
	&"felt_yellow": {"slot": &"felt", "deck": &"bandit", "level": 1, "name": "Gelber Filz", "tex": "felt_yellow.png", "color": Color("c8a02e")},
	&"felt_blue": {"slot": &"felt", "deck": &"bandit", "level": 2, "name": "Blauer Filz", "tex": "felt_blue.png", "color": Color("224082")},
	# Knochen
	&"felt_bone": {"slot": &"felt", "deck": &"bone_man", "level": 0, "name": "Knochenweißer Filz", "tex": "felt_bone.png", "color": Color("d6ccb0")},
	&"rim_bone": {"slot": &"rim", "deck": &"bone_man", "level": 1, "name": "Knochenrand", "tex": "rim_bone.png", "color": Color("e2d6b8"), "rough": 0.55},
	&"corner_skulls": {"slot": &"corners", "deck": &"bone_man", "level": 2, "name": "Totenköpfe", "emoji": "💀"},
	# Krähe
	&"felt_feather": {"slot": &"felt", "deck": &"crow", "level": 0, "name": "Federfilz", "tex": "felt_feather.png", "color": Color("1a1a1e")},
	&"rim_ebony": {"slot": &"rim", "deck": &"crow", "level": 1, "name": "Ebenholzrand", "tex": "rim_ebony.png", "color": Color("281e1c"), "rough": 0.3},
	&"extra_crow": {"slot": &"extra", "deck": &"crow", "level": 2, "name": "Krähe auf dem Tisch", "emoji": "🐦‍⬛"},
	# Riese
	&"rim_oak": {"slot": &"rim", "deck": &"giant", "level": 0, "name": "Grobe Eiche", "tex": "rim_oak.png", "color": Color("966c40"), "rough": 0.8},
	&"rim_stone": {"slot": &"rim", "deck": &"giant", "level": 1, "name": "Steinplatte", "tex": "rim_stone.png", "color": Color("8c8880"), "rough": 0.9},
	&"rim_rock": {"slot": &"rim", "deck": &"giant", "level": 2, "name": "Felsrand mit Moos", "tex": "rim_rock.png", "color": Color("6e7a5a"), "rough": 0.95},
	# Goldrand
	&"rim_goldtrim": {"slot": &"rim", "deck": &"goldrand", "level": 0, "name": "Goldkante", "tex": "rim_wood.png", "color": Color("6e4022"), "rough": 0.45, "trim": true},
	&"felt_wine": {"slot": &"felt", "deck": &"goldrand", "level": 1, "name": "Weinrot mit Gold", "tex": "felt_wine.png", "color": Color("60141e"), "scale": 1.0},
	&"rim_gold": {"slot": &"rim", "deck": &"goldrand", "level": 2, "name": "Goldrand", "color": Color(0.95, 0.74, 0.32), "metal": 1.0, "rough": 0.28},
	# Gaukler
	&"felt_stripes": {"slot": &"felt", "deck": &"jester", "level": 0, "name": "Rot-gelb gestreift", "tex": "felt_stripes.png", "color": Color("aa221e"), "scale": 0.8},
	&"felt_harlequin": {"slot": &"felt", "deck": &"jester", "level": 1, "name": "Harlekin-Rauten", "tex": "felt_harlequin.png", "color": Color("cea02c"), "scale": 1.0},
	&"extra_bells": {"slot": &"extra", "deck": &"jester", "level": 2, "name": "Glöckchen am Rand", "emoji": "🔔"},
	# Kaufmann – Münzen
	&"coin_silver": {"slot": &"coins", "deck": &"kaufmann", "level": 0, "name": "Silbermünzen", "color": Color(0.92, 0.93, 0.96), "metal": 0.75, "rough": 0.38},
	&"coin_copper": {"slot": &"coins", "deck": &"kaufmann", "level": 1, "name": "Alte Kupfermünzen", "color": Color(0.8, 0.45, 0.26), "metal": 0.75, "rough": 0.5},
	&"coin_gem": {"slot": &"coins", "deck": &"kaufmann", "level": 2, "name": "Edelstein-Münzen", "color": Color(0.85, 0.08, 0.2), "metal": 0.2, "rough": 0.08, "glow": true},
	# Sumpf
	&"felt_moss": {"slot": &"felt", "deck": &"swamp_man", "level": 0, "name": "Moosgrüner Filz", "tex": "felt_moss.png", "color": Color("426028")},
	&"rim_mossy": {"slot": &"rim", "deck": &"swamp_man", "level": 1, "name": "Moos und Seerosen", "tex": "rim_mossy.png", "color": Color("5a5a2c"), "rough": 0.85, "lily": true},
	&"extra_fireflies": {"slot": &"extra", "deck": &"swamp_man", "level": 2, "name": "Glühwürmchen", "emoji": "🪲"},
	# Hexe
	&"felt_violet": {"slot": &"felt", "deck": &"witch", "level": 0, "name": "Violetter Filz", "tex": "felt_violet.png", "color": Color("542c78")},
	&"felt_stars": {"slot": &"felt", "deck": &"witch", "level": 1, "name": "Sterne und Monde", "tex": "felt_stars.png", "color": Color("3e2260")},
	&"extra_green_candles": {"slot": &"extra", "deck": &"witch", "level": 2, "name": "Grüne Hexenkerzen", "emoji": "🕯️"},
	# Wolf
	&"rim_fur": {"slot": &"rim", "deck": &"wolf", "level": 0, "name": "Grauer Fellrand", "tex": "rim_fur.png", "color": Color("78766f"), "rough": 1.0},
	&"felt_claws": {"slot": &"felt", "deck": &"wolf", "level": 1, "name": "Krallenspuren", "tex": "felt_claws.png", "color": Color("36423a")},
	&"felt_moon": {"slot": &"felt", "deck": &"wolf", "level": 2, "name": "Vollmond (Wolf heult)", "tex": "felt_moon.png", "color": Color("161e36"), "scale": 0.0, "howl": true},
	# Zar
	&"felt_velvet": {"slot": &"felt", "deck": &"zar", "level": 0, "name": "Roter Samt", "tex": "felt_velvet.png", "color": Color("96101a")},
	&"corner_eagles": {"slot": &"corners", "deck": &"zar", "level": 1, "name": "Goldene Doppeladler", "emoji": "🦅"},
	&"extra_faberge": {"slot": &"extra", "deck": &"zar", "level": 2, "name": "Fabergé-Leuchter", "emoji": "🥚"},
}


## Entwicklermenü: alles anlegbar, auch Gesperrtes (bis zum Neustart).
static var dev_free := false


static func is_unlocked(id: StringName) -> bool:
	var it: Dictionary = ITEMS.get(id, {})
	return not it.is_empty() and Profile.has_badge(it.deck, it.level)


## Ausgewähltes Item für einen Platz (&"" = Standard des Raums).
static func selected(slot: StringName) -> StringName:
	var id := StringName(Profile.cosmetics.get(String(slot), ""))
	return id if ITEMS.has(id) and (dev_free or is_unlocked(id)) else &""


## Daten des ausgewählten Items (leer = Standard).
static func pick(slot: StringName) -> Dictionary:
	var id := selected(slot)
	return {} if id == &"" else ITEMS[id]


static func items_for(slot: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in ITEMS:
		if ITEMS[id].slot == slot:
			out.append(id)
	return out


## Belohnung eines Decks auf einer Stufe (&"" = keine).
static func reward_of(deck_id: StringName, level: int) -> StringName:
	for id: StringName in ITEMS:
		if ITEMS[id].deck == deck_id and ITEMS[id].level == level:
			return id
	return &""


## Wie man es freischaltet (für Menü und Tooltips).
static func how_to(id: StringName) -> String:
	var it: Dictionary = ITEMS[id]
	var d := Profile.deck(it.deck)
	var dn := d.display_name if d != null else String(it.deck)
	return "Gewinne einen Run mit „%s“ auf %s." % [dn, Settings.DIFFICULTY_NAMES[it.level]]


# --- Materialien ---------------------------------------------------------------------

static var _cache := {}


## Filz-Material (Weltkoordinaten, damit es auf jedem Tisch gleich groß aussieht).
static func felt_material(id: StringName) -> StandardMaterial3D:
	var key := "felt_%s" % id
	if _cache.has(key):
		return _cache[key]
	var it: Dictionary = ITEMS[id]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(DIR + it.tex)
	m.roughness = 0.95
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	var tile: float = it.get("scale", 0.5)
	if tile <= 0.0: # ein Bild über den ganzen Tisch, Mitte auf der Tischmitte
		m.uv1_scale = Vector3.ONE * 0.55
		m.uv1_offset = Vector3(0.5, 0.5, 0.5)
	else:
		m.uv1_scale = Vector3.ONE / tile
	m.normal_enabled = true
	m.normal_texture = preload("res://assets/models/table_felt_normal.png")
	m.normal_scale = 0.6
	_cache[key] = m
	return m


static func rim_material(id: StringName) -> StandardMaterial3D:
	var key := "rim_%s" % id
	if _cache.has(key):
		return _cache[key]
	var it: Dictionary = ITEMS[id]
	var m := StandardMaterial3D.new()
	if it.has("tex"):
		m.albedo_texture = load(DIR + it.tex)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * 2.2
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		m.albedo_color = it.color
	m.metallic = it.get("metal", 0.0)
	m.roughness = it.get("rough", 0.6)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED # Casino-Rand ist eine offene Röhre
	_cache[key] = m
	return m


static func coin_material(id: StringName) -> StandardMaterial3D:
	var key := "coin_%s" % id
	if _cache.has(key):
		return _cache[key]
	var it: Dictionary = ITEMS[id]
	var m := StandardMaterial3D.new()
	m.albedo_color = it.color
	m.metallic = it.get("metal", 1.0)
	m.roughness = it.get("rough", 0.3)
	if it.get("glow", false):
		m.emission_enabled = true
		m.emission = it.color
		m.emission_energy_multiplier = 0.5
		m.clearcoat_enabled = true
	_cache[key] = m
	return m


## Farben der Zigaretten (leer = normal weiß/rot).
static func cig_style() -> Dictionary:
	return pick(&"cigs")


## Gemeinsame Materialien für alle Zigaretten (Papier, Ring am Filter, Stummel, Schachtel).
## Werden beim Umschalten direkt umgefärbt, so ändert sich alles sofort.
static func cig_mat(part: StringName) -> StandardMaterial3D:
	var key := "cig_%s" % part
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		_cache[key] = m
		_color_cig(part, m)
	return _cache[key]


static func refresh_cigs() -> void:
	for part: StringName in [&"paper", &"band", &"stub", &"pack"]:
		if _cache.has("cig_%s" % part):
			_color_cig(part, _cache["cig_%s" % part])


static func _color_cig(part: StringName, m: StandardMaterial3D) -> void:
	var cs := cig_style()
	var metal: bool = cs.get("metal", false)
	match part:
		&"paper":
			m.albedo_color = cs.get("paper", Color(0.93, 0.91, 0.86))
			m.roughness = 0.75
			m.metallic = 0.6 if metal else 0.0
		&"band":
			m.albedo_color = cs.get("band", Color(0.85, 0.7, 0.3))
			m.roughness = 0.4
			m.metallic = 0.6
		&"stub":
			m.albedo_color = (cs.get("paper", Color(0.93, 0.91, 0.86)) as Color) * 0.68
			m.roughness = 0.9
			m.metallic = 0.0
		&"pack":
			m.albedo_color = cs.get("pack", Color(0.74, 0.08, 0.1))
			m.roughness = 0.45
			m.metallic = 0.7 if metal else 0.0
