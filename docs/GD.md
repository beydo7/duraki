# Duraki – Game Design & aktueller Stand

Dieses Dokument fasst zusammen, was in den Chats zwischen Pascal (beydo7) und Claude entschieden und
gebaut wurde. Es ist für das Team **und für Claude-Instanzen** gedacht, damit alle auf demselben Stand
sind. Bitte aktuell halten, wenn sich etwas Grundlegendes ändert.

Stand: 22.11.2026 · Godot 4.7.2 (GL Compatibility) · Build 0.6

---

## 1. Kurzbeschreibung

Duraki ist ein **Roguelike auf Basis von Schiebe-Durak (Perevodnoy)**. Man sitzt nachts in einem
Hinterzimmer (Ich-Perspektive, 3D) an einem Kartentisch und spielt nacheinander gegen unheimliche
Gestalten. Die Wertung funktioniert wie bei **Balatro** (Chips × Mult, Punkteziel pro Tisch).
Ein Run = 3 normale Gegner + Boss, 3 Leben (Kerzen). Wer verliert, ist der Durak.

## 2. Regeln (fest, nicht verhandelbar)

- 36 Karten (6 bis Ass), Trumpf, 1 gegen 1, Hand 6.
- Angreifen, Nachlegen (passende Ränge, auch mehrere auf einmal, nie mehr ungeschlagene Karten als
  der Verteidiger auf der Hand hat, höchstens 6), Schlagen, Nehmen, Bito.
- **Schieben ist Grundregel:** solange noch nichts geschlagen ist, darf der Verteidiger eine Karte
  gleichen Rangs dazulegen und den Angriff weitergeben (nur wenn der andere genug Karten hat).
  Kann die Karte auch schlagen, fragt das Spiel „Schlagen oder Schieben?“.
- **Nachwerfen:** Nimmt der Verteidiger auf, darf der Angreifer passende Karten hinterherwerfen
  (Knopf „FERTIG“).
- Bube wird als **„J“** angezeigt (nicht „B“), Dame als „D“, König „K“, Ass „A“.
- Logik: `scripts/core/durak_match.gd` (`transfer()`, `take()`/`finish_take()`, Signale
  `transferred`, `take_declared`), KI: `scripts/ai/simple_ai.gd`.

## 3. Wertung (Balatro-artig)

`scripts/core/score_tracker.gd`
- Jede eigene Karte bringt Chips (nach Rang), jede Verteidigung +1 Mult, jede nachgelegte
  Angriffskarte ab der zweiten +1 Mult, jeder gespielte Trumpf +1 Mult.
- Rundenende: Bito/abgewehrter Angriff → Chips × Mult; Gegner muss nehmen → × 2 („Volltreffer“);
  du musst nehmen → 0.
- Ist der Gegner am Ende der Durak: +15 pro Karte auf seiner Hand.
- Punkteziele: 300 / 380 / 450 / 550 (Boss), danach × 1,25. Ziel erreicht → Tisch gewonnen,
  sonst ein Leben weg.

## 4. Run-Struktur & Meta

- `scripts/autoload/run_state.gd` (Autoload `Run`): Weg → Duell → Händler → … → Boss → Run-Ende.
- **Händler** nach jedem Sieg: Relikte (Ass im Ärmel, Glücksmünze, Samowar, Wodka), verbesserte
  Karten (Gold/Glas/Glück), Verbesserungen (Farb-Schliff, Trumpf-Kenner, Pflaster, Sparschwein),
  Neu mischen, Zinsen (je 5 Gold +1, max. 5).
- **Decks = Skins mit kleinem Effekt** (`data/decks/*.tres`, `scripts/data/deck_data.gd`), 12 Stück:
  Starter „Hinterzimmer“; je eins pro besiegtem Gegner (Bandit, Sumpfmann, Krähe, Wölfin, Gaukler,
  Knochenmann, Hexe, Riese/Run-Sieg); kaufbar mit **Seelen**: Kaufmann 25, Zar 40, Goldrand 60.
  Effekte z. B. +6 Gold, +1 Leben, Farbe +3 Chips, Trumpf +1 Mult, Start-Glaskarten.
- **Seelen** (Autoload `Profile`, `user://profile.cfg`): 3 pro gewonnenem Tisch, 10 für Run-Sieg.
- Gegner (`data/opponents/`): Bandit, Sumpfmann, Krähe, Wölfin, Gaukler, Knochenmann, Hexe, Riese (Boss).

## 5. Look & Feel

### Raum (3D)
Dunkles Hinterzimmer, lila Nachtlicht, grüner Filz. **Kerzen = Leben** (erlöschen mit Rauch),
**Münzstapel = Gold**. Gegner sitzen gegenüber, mit Reaktionen und Denk-Animationen.
3D wird in voller Bildschirmauflösung gerendert (`UIKit.fit_viewport`), damit Karten scharf sind.

### UI-Stil „Plakat“ (aktuell, von Pascal gewählt)
Russisches Konstruktivismus-Plakat, modern umgesetzt (Referenz-Gefühl: Balatro-Lesbarkeit,
Persona-Dynamik). **Rot `#CE2628` / Schwarz `#120E0E` / Creme `#F0E4CC`**, Gold `#E8B446` als Akzent,
Chips blau, Mult rot.
- Schräge Flächen mit hartem Versatz-Schatten, keine runden „Web“-Panels.
- Alle Texte auf Deutsch, **keine kyrillischen Zeilen mehr** (auf Leons Wunsch entfernt).
- Schriften: **Russo One** (Titel, Zahlen), **Oswald** (Text, variable Stärke) – beide OFL.
- Bausteine: `ui/slab.gd` (Plakatfläche aus Vielecken), `ui/roundel.gd` (runde Plakette / Stern),
  `ui/seg_bar.gd` (Segmentbalken). Helfer in `ui/ui_kit.gd`: `body_font()`, `display_font()`,
  `poster_label()`, `poster_wedge()`, `paper()`/`dark()`/`stamp()` (liefern Plakat-Styles), Animationen
  `pop`, `shake`, `appear`, `hover`, `count`. Theme: `ui/theme.tres` (Variationen PrimaryButton,
  DangerButton, CardButton, ActivePanel, InkTitle …).

**Duell-HUD** (`scenes/match/hud.gd`, komplett im Code gebaut, Basis 1280×720, an Rändern verankert):
- links oben roter Keil: Punkte groß, „/Ziel“, Segmentbalken; darunter Chips × Mult + Hinweis
- darunter Spielprotokoll (Toasts)
- links runde Plaketten Leben / Gold / Stapel, roter Stern = Trumpf, „ANGRIFF x/y“
- rechts oben schwarzer Balken: Foto, „GEGNER“/„ENDGEGNER“ + Name, Tisch x/y, Handkarten
- darunter Relikte als Briefmarken (Tooltip)
- rechts unten Zug-Plakette (Farbe je Zustand: Angriff creme, Verteidigung rot, Warten schwarz,
  Nachwerfen gold) mit Etikett „SCHIEBEN MÖGLICH“, darunter Knöpfe NEHMEN [E] / BITO [LEER]
- Mitte: kurze Schrägbanner; Ergebnis als rotes (Sieg) bzw. schwarzes (Durak) Plakat
- `match.gd` nutzt nur die öffentliche API: `setup`, `set_turn`, `set_danger`, `set_opponent_cards`,
  `set_thinking`, `say`, `set_run_info`, `set_bout`, `set_relics`, `set_score`, `bout_scored`, `toast`,
  `show_banner`, `set_actions`, `ask_choice`, `close_choice`, `show_result`, sowie
  `take_button` / `pass_button` / `continue_button`.

**Studio-Intro** (`scenes/intro/studio_intro.tscn`, Hauptszene): ~3 s, Logo „Hitbox Hooligans“ als
Spielmodul – fällt, knallt auf (roter Plakat-Keil, Wackeln), Hitbox-Ecken schnappen zu, Stempel „HIT!“,
„PRÄSENTIERT“, dann Hauptmenü. Komplett im Code gezeichnet, jede Eingabe überspringt,
headless (Tests) direkt ins Menü.

Hauptmenü: nur die vier Karten auf dem Tisch (Maus, Pfeiltasten/Controller + Enter/A), keine
Knopfleiste links; im roten Keil unten die Zeile „BEYD & FLÖRRY“.

Menüs (Hauptmenü in 3D mit Karten auf dem Tisch, Weg, Händler, Pause, Optionen, Decks, Run-Ende)
nutzen dasselbe Theme; Hauptmenü, Weg und Händler haben den roten Keil hinter dem Titel.

**Verworfene Stile** (nicht wieder einführen): lila Glas mit Marker-Schrift („zu KI“),
„Papier & Tinte“ mit gerissenen Zetteln („wie ein Browsergame, billig“).

### Karten (Stil „Okkult-Gold“, von Pascal gewählt)
Nachtblaue Karten mit leuchtender Goldlinie und Sternenstaub, erzeugt mit `tools/generate_cards.py`.
Herz/Karo in Korallenrot, Pik/Kreuz in Gold; Indizes in Cinzel Decorative (OFL).
Bildkarten als doppelköpfige Goldlinien-Figuren mit Heiligenschein (König mit Krone/Bart/Zepter,
Dame mit Kokoschnik/Zöpfen/Kerze, Bube mit Pelzmütze/Feder/Hellebarde). Asse mit Himmelsmotiven:
Herz = Sonne, Karo = Auge, Pik = Mond (+ „DURAKI“), Kreuz = Stern. Glasversionen und alle
12 Deck-Rückseiten (Deckfarbe ins Nachtblau gemischt, Gold-Sternengitter, Medaillon mit Emblem)
im selben Stil. Nachtblau/Gold der Karten und Rot/Schwarz/Creme des HUDs sind bewusst
zwei Ebenen: Karten = Spielwelt, HUD = Plakat darüber.

### Karten-Animationen
- Vorderseite: `scenes/match/card_face.gdshader` (+ `_glass`, gemeinsamer Teil `.gdshaderinc`):
  Folienglanz, der mit Blickwinkel und Zeit wandert (Trumpf leicht gold, Goldkarte kräftig,
  Glückskarte grün, Glas irisierend), Lichtreflex an der Mausposition, Leuchten für spielbare Karten.
- `Card3D` (`scenes/match/card_3d.gd`): alle sichtbaren Teile hängen an `_body`; darauf liegen
  Kippen zur Maus (Hover), Wiegen in der Hand, Anheben spielbarer Karten, Federn beim Landen
  (`land()`) und Schubsen (`nudge()`). Die Wurzel bewegt `TableWorld`.
- `TableWorld.sync` merkt sich die Zone jeder Karte und wählt daraus die Bewegung (`_move` mit Stil):
  Austeilen (Bogen, Drehung, Federn), Ausspielen (hoher Bogen, Wumms, Staubring, kurzes Wackeln
  der Kamera – bei Trumpf stärker mit Goldblitz), Schlagen (Angriffskarte wird geschubst),
  Schieben (Wirbel um die Hochachse + rote Tempo-Streifen im HUD), Nehmen (hoch und zurück in die
  Hand), Bito (Stempel „BITO“ im HUD, Karten drehen sich zum Ablagestapel).
- Kamerawackeln nur, wenn „Kamera-Schwenk“ in den Optionen an ist; alle Zeiten folgen der
  Einstellung „Kartenanimationen“.
- Prüfen: `tests/screenshot.tscn -- film` nimmt eine Bildfolge in Zeitlupe auf.

### Gegner / 3D-Modelle
Modelle aus Blender (Skripte in `art/blender/`), Vorlage ist das Konzeptblatt „Am Spieltisch“.
HD-Versionen auf aktuellem Stand: **Bandit** (`hd_bandit.py`), **Sumpfmann** (`hd_swamp_man.py`),
**Wölfin** (`hd_wolf.py`). Die **Krähe** (`hd_crow.py`) ist HD, aber noch vom alten Stand (steifer
Ärmel, kein Kartenfächer in den Händen). Wie die Figuren gebaut werden: **`docs/CHARAKTERE.md`**.
Exporte als glb in `assets/models/opponents/`, .blend-Dateien in `art/blender/opponents/`,
Porträts per `art/blender/render_portraits.py`.
- Gegner halten die Karten als Fächer zwischen beiden Händen; Arme mit Ellbogen (Zwei-Knochen-IK
  in `opponent_figure.gd`). `OpponentData.eye_glow = false` bei Figuren mit echten Augen.

## 6. Optionen
Grafik (Anzeigemodus, Fenstergröße, VSync, FPS-Limit, Kantenglättung, Renderauflösung, Schatten,
Glow, Helligkeit), Audio (Gesamt/Musik/Effekte, stumm im Hintergrund – Sounds fehlen noch),
Allgemein (Bedenkzeit der Gegner, Kartenanimationen, Meldungen, Kamera-Schwenk, UI-Größe).
`user://settings.cfg`, Autoload `Settings`. Esc = Pause.

## 7. Tests
- `godot --headless --path . -s res://tests/run_tests.gd` → Regeln/KI (47 Checks)
- `godot --headless --path . res://tests/deck_tests.tscn` → Decks/Seelen (39 Checks)
- `godot --headless --path . res://tests/autoplay.tscn` → 5 komplette Runs automatisch
- `xvfb-run godot --path . res://tests/click_test.tscn` → Handkarten per Klick
- `tests/screenshot.tscn` (Args: transfer, result, boss, opp=<id>, nohud, many, enh, film) und
  `tests/ui_shots.tscn` → Screenshots aller Bildschirme
- Tests rufen `Profile.reset_for_tests()` auf, damit das echte Profil nicht überschrieben wird.

## 8. Offene Punkte / nächste Schritte
1. Juice ausbauen: rollende Zahlen beim Punkten, Sounds zu den Kartenbewegungen.
2. Restliche Gegner in HD (Rezept `docs/CHARAKTERE.md`): als Nächstes Gaukler + Knochenmann,
   dann Hexe + Riese, danach die Krähe auf den neuen Stand bringen. Fertig: Bandit, Sumpfmann, Wölfin.
3. Lila Lampen-Scheiben im Raum sind Platzhalter → echte Lampen.
4. Sound & Musik (Busse „Music“ und „SFX“ existieren schon).
5. Die 3D-Menükarten im Hauptmenü an den Okkult-Gold-Stil der Karten anpassen.

## 9. Zusammenarbeit
- Repo: https://github.com/beydo7/duraki (Team: beydo7/Pascal, Florry7, Leon).
- **Auf GitHub wird nur gepusht, wenn Pascal es ausdrücklich sagt („veröffentlichen“ / „hochladen“).**
- Sprache im Projekt: Deutsch (Code-Kommentare, UI-Texte, Commits).
