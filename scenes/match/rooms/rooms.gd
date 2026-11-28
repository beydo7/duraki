class_name Rooms
extends RefCounted
## Welche Räume es gibt und welcher Raum an einem Tisch dran ist (zufällig pro Tisch).
##
## Jeder Raum hat eigene Details (das Hinterzimmer: Aschenbecher, Zigaretten, Whiskey;
## das Casino: Roulette, Spielautomaten, Pokerchips; der Bahnhofswartesaal: Teegläser,
## Fahrplantafel, vorbeifahrende Züge; das U-Boot: Bullauge, Sonar,
## Periskop; der Zirkuswagen: Spiegel, Luftballons, Spieluhr). TableWorld fragt hier nach und
## baut den passenden Raum (`TableWorld.room_id`).

const HINTERZIMMER := &"hinterzimmer"
const CASINO := &"casino"
const STATION := &"bahnhof"
const SUBMARINE := &"uboot"
const CIRCUS := &"zirkus"

## Anzeigename (z. B. für das Entwicklermenü)
const NAMES := {
	HINTERZIMMER: "Hinterzimmer",
	CASINO: "Altes Casino",
	STATION: "Bahnhofswartesaal",
	SUBMARINE: "U-Boot",
	CIRCUS: "Zirkuswagen",
}

## Alle Räume, aus denen für jeden Tisch zufällig gewählt wird
const ALL: Array[StringName] = [HINTERZIMMER, CASINO, STATION, SUBMARINE, CIRCUS]

## Zum Testen (Entwicklermenü): erzwingt einen Raum für alle Tische, leer = normal.
static var forced: StringName = &""


## Raum für einen Tisch: zufällig, aber pro Run und Tisch fest (gleicher Seed → gleicher
## Raum), damit der Weg auf der Karte und das Duell denselben Raum zeigen. Benutzt einen
## eigenen Zufallsgenerator, damit der Spielzufall (Run.rng) unverändert bleibt.
## Das Tutorial spielt immer im Hinterzimmer (es erklärt Aschenbecher und Zigaretten).
static func for_floor(floor_index: int) -> StringName:
	if forced != &"":
		return forced
	if Run.tutorial:
		return HINTERZIMMER
	var r := RandomNumberGenerator.new()
	r.seed = hash([Run.seed_value, floor_index, "raum"])
	if Run.endless and floor_index >= Run.encounters.size():
		# Endlos: jedes Duell in einem neuen Raum (sonst bliebe es immer derselbe)
		r.seed = hash([Run.seed_value, floor_index, "raum", Run.endless_duels])
	return ALL[r.randi() % ALL.size()]
