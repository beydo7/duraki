# Umgebungs-Überarbeitung (Start: 26.11.2026)

Auftrag von Pascal: Räume, Tische und Requisiten handwerklich auf das Niveau der überarbeiteten
Gegner bringen. **Das Design bleibt vollständig erhalten** – kein neues Raumkonzept, keine neuen
Requisiten, keine neuen Tischformen, gleiche Farben, gleiche Positionen, gleiche Kamera, gleiche
Lichtidee. Verbessert wird nur die Machart: echte Profile statt Kisten, gerundete Kanten, saubere
Materialien. Spiellogik wird nicht angefasst.

Pilot ist das **Alte Casino**. Die übrigen Räume (Hinterzimmer, Bahnhof, U-Boot, Zirkuswagen)
folgen erst nach Pascals Abnahme.

## 1. Sicherung und Arbeitsordner (auf Pascals PC)

- `D:\Games\Duraki\sicherung_environment_2026-11-26\` – Kopie von `scenes`, `assets/rooms`,
  `assets/models` (oberste Ebene), `tools`, `tests`, `art/blender/*.py`, `ui` (302 Dateien, geprüft).
- Git-Tag `vor-environment-overhaul` (Commit ffdbedc) im PC- und im Cloud-Repo.
- `D:\Games\Duraki\environment_overhaul\` – Arbeitsordner: `export/` (frisch exportierte .glb, bevor
  sie ins Projekt kommen), `blend/`, `renders/`.

## 2. Arbeitsweise

**Blender liefert die Form, Godot die Materialien und alles Bewegliche.**

- `art/blender/casino.py` baut die ganze Szene im laufenden Blender (`casino.build_all()`) und
  schreibt die Modelle (`casino.export_all()`). Alle Maße und Positionen stammen 1:1 aus den
  früheren Code-Bauten; Koordinaten im Skript sind Godot-Koordinaten (`geo.G`).
- `art/blender/casino.blend` ist die gespeicherte Szene zum Ansehen (ganzer Raum mit Kulisse und
  Licht). Achtung: `casino.build_all()` baut alles neu und verwirft Handarbeit in der Datei.
- In Godot setzt `RoomKit.model(parent, szene, {Materialname: Material})` das Modell ein und
  ordnet die Materialien **über ihren Namen** zu. Dadurch bleiben Farben, Lauflichter,
  Automatenfarbe (rot/blau) und die Tisch-Looks der Deck-Belohnungen (`TableSkin`) im Code.
  Materialien, die der Code nicht nennt, kommen so ins Spiel, wie sie in Blender sind
  (z. B. die drei Knopffarben am Automaten).
- Die .glb enthalten keine Bilder. Texturen liegen einmal im Projekt (`assets/models/table_*`,
  `assets/rooms/casino/*.png`) und werden vom Code geladen. Neue Feinstrukturen (Leder, Samt)
  erzeugt wie bisher `tools/generate_casino.py`.
- Bewegliche Teile sind eigene Knoten mit festem Drehpunkt, die der Code wie bisher bewegt:
  `Hebel` (Automat), `Kessel` (Roulette), `Schirm` und `Kette` (Bankerlampe). Einzeln schaltbare
  Lichter sind eigene Teile: `Birne_00…12` (Automat), `Schildbirne_00…23` (Neonschild).
- UVs der Modelle sind in Metern, Holzmaserung läuft längs der Teile (früher Triplanar).
- Objekte mit `Preview_` am Anfang (Boden, Tapete, zweiter Automat, Walzen) sind nur Kulisse in
  Blender und werden nicht exportiert.

Nach einer Änderung in Blender: `casino.export_all()` ausführen (oder die Sammlung von Hand als
.glb nach `assets/rooms/casino/` exportieren, ohne Bilder), Godot importiert neu.

## 3. Altes Casino – was ersetzt wurde

| Teil | vorher (Code) | jetzt (Blender) | Datei |
|---|---|---|---|
| Lederrand | Röhre | Polsterprofil mit Keder, Ledernarbung | `casino.glb` |
| Zarge, Füße | Platte, zwei Kegel, Kisten | profilierte Zarge, gedrechselte Säulen, gestufte Sockel | `casino.glb` |
| Filz, Ziernaht | Kasten + Zylinder, Röhre | ebene Fläche, flach gewölbte Goldeinlage | `casino.glb` |
| Vertäfelung | Platte mit aufgesetzten Kisten | Rahmen und Füllungen mit Nut und Fase, Sockel-, Stuhl- und Kranzleiste mit Profil, Ecken auf Gehrung | `casino.glb` |
| Vorhänge | 7 Zylinder je Seite, Ring | Stoff mit Falten, am Raffhalter gerafft, doppelte Kordel | `casino.glb` |
| Querbehang | Kasten + 30 Zylinder, Leiste | gefaltete Blende, Borte mit Fransen | `casino.glb` |
| Neonschild | Kasten, Kugeln | Tafel mit Rahmenrinne, Birnen mit Fassung (Schrift bleibt Label3D) | `casino.glb` |
| Kronleuchter | Stab, Ring, Kegel, Kugeln | Rosette, Kette aus Gliedern, gedrechselter Schaft, Arme, Kerzentüllen, geschliffene Kristalle | `casino.glb` |
| Wandleuchter | Kiste + Kegel | ovale Wandplatte, geschwungener Arm, Schirm mit Messingrändern | `casino.glb` |
| Würfel, Cocktailglas | Kisten/Zylinder | runde Kanten und Augen auf allen Seiten; Glas mit Wandstärke, Drink, Olive | `casino.glb` |
| Spielautomat | Kisten, Zylinder | Gehäuse aus einem Stück mit runden Kanten, Chromleiste, Fensterhaube mit Laibung, Münzschale, Sockel mit Zierrahmen, Hebel mit Lager | `slot_machine.glb` |
| Roulette | Zylinder, Bild auf Fläche | gedrechselte Schale, Scheibe mit vertieften Fächern, Stege, Ringe, Drehkreuz | `roulette.glb` |
| Bankerlampe | Zylinder, halbe Röhre | ovaler Stufenfuß, gedrechselte Säule, Glasschirm mit Innenseite und Messingrand, Kette, geschliffene Lämpchen mit Fassung | `banker_lamp.glb` |
| Pokerchips | Zylinder + Ringe | Chip mit Randeinlagen und Ring | `chip.glb` |

Im Code geblieben (schlichte Flächen bzw. Technik): Boden (Teppich), Decke, Tapetenwände, die drei
Walzen des Automaten (drehen sich, tragen das Walzenband), Schrift „CASINO“ und „DURAKI“ (Label3D),
Kugel und Aufleuchten des Roulettes, alle Lichter, Klickflächen, Geräusche, Erfolge.

Angepasste Skripte: `scenes/match/rooms/casino_room.gd`, `slot_machine.gd`, `mini_roulette.gd`,
`banker_lamp.gd`, `room_kit.gd` (neu: `model`, `apply_materials`), `scenes/match/table_props.gd`
(nur `_make_chip`). Regeln, Wertung, KI, Kartenplätze, Kamera und HUD sind unverändert.

## 4. Bewusste Abweichungen vom alten Bild (bitte prüfen)

1. **Lederrand ist jetzt sichtbar dunkelrot statt fast schwarz.** Die alte Röhre war verkehrt herum
   gebaut und wurde deshalb „von innen“ beleuchtet (oben schwarz, unten rötlich). Farbe und Glanz
   des Leders sind unverändert (`Color(0.26, 0.09, 0.06)`), nur stimmt jetzt das Licht.
2. **Knöpfe und Münzschlitz am Automaten sind jetzt zu sehen.** Im alten Code saßen sie hinter
   der Fensterhaube und waren unsichtbar; sie sitzen jetzt zwischen Fenster und Münzschale.
3. **Vorhänge sind am Raffhalter gerafft** (vorher gerade Säulen mit frei schwebendem Ring).
   Position und Breite oben sind gleich.
4. **Kronleuchter hat acht Arme** zwischen Schaft und Reif (vorher schwebte der Reif frei).
5. Fuß der Bankerlampe: der Kegel unter der Säule ist schmaler, damit er nicht mehr über den
   ovalen Fuß hinausragt.

## 5. Prüfen

- Vorher/Nachher aus festen Kameras: `tests/screenshot.tscn` mit `room=casino`, `nohud`,
  `cam=x,y,z,zielx,ziely,zielz[,fov]`, `gold=n`.
- Tests wie in `docs/GD.md`, Abschnitt Tests; `cosmetics_tests` baut das Casino mit allen
  Deck-Belohnungen (Filz, Rand, Ecken, Extras).
