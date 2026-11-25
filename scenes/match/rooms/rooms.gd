class_name Rooms
extends RefCounted
## Welche Räume es gibt und an welchem Tisch welcher Raum dran ist.
##
## Jeder Raum hat eigene Details (das Hinterzimmer: Aschenbecher, Zigaretten, Whiskey;
## das Casino: Roulette, Spielautomaten, Pokerchips). TableWorld fragt hier nach und
## baut den passenden Raum (`TableWorld.room_id`).

const HINTERZIMMER := &"hinterzimmer"
const CASINO := &"casino"

## Anzeigename (z. B. für das Entwicklermenü)
const NAMES := {
	HINTERZIMMER: "Hinterzimmer",
	CASINO: "Altes Casino",
}

## Raum pro Tisch (0 = Tisch 1 … 3 = Boss). Tisch 2 spielt im Casino.
const BY_FLOOR: Array[StringName] = [HINTERZIMMER, CASINO, HINTERZIMMER, HINTERZIMMER]

## Zum Testen (Entwicklermenü): erzwingt einen Raum für alle Tische, leer = normal.
static var forced: StringName = &""


static func for_floor(floor_index: int) -> StringName:
	if forced != &"":
		return forced
	return BY_FLOOR[clampi(floor_index, 0, BY_FLOOR.size() - 1)]
