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
Ein Run = 3 Akte mit je 3 normalen Gegnern + Boss (12 Tische), 3 Leben (Kerzen). Nach dem
3. Boss beginnt der Endlos-Modus. Wer verliert, ist der Durak.

## 2. Regeln (fest, nicht verhandelbar)

- 36 Karten (6 bis Ass), Trumpf, 1 gegen 1, Hand 6.
- Angreifen, Nachlegen (passende Ränge, auch mehrere auf einmal, nie mehr ungeschlagene Karten als
  der Verteidiger auf der Hand hat, höchstens 6), Schlagen, Nehmen, Fertig (klassisch „Bito“).
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
- Rundenende: Fertig/abgewehrter Angriff → Chips × Mult; Gegner muss nehmen → × 2 („Volltreffer“);
  du musst nehmen → 0.
- Ist der Gegner am Ende der Durak: +15 pro Karte auf seiner Hand.
- Punkteziele pro Akt: 300 / 380 / 450 / 550 (Boss), jeder weitere Akt × 1,6 (`Run.ACT_GROWTH`).
  Ziel erreicht → Tisch gewonnen, sonst ein Leben weg.

## 4. Run-Struktur & Meta

- `scripts/autoload/run_state.gd` (Autoload `Run`): Weg → Duell → Händler → … → Boss → Boss-Händler
  → nächster Akt … → 3. Boss → Boss-Händler → **Endlos-Modus** → Run-Ende.
- **3 Akte** (`Run.ACTS`, `FIGHTS_PER_ACT` = 4): je 3 normale Gegner (leichtere zuerst) und ein Boss.
  Der Weg zeigt nur den aktuellen Akt („AKT 2 VON 3“), das Duell oben „AKT 2/3 · TISCH 1/3“.
  `Run.act_of()`, `act_pos()`, `act_floors()`.
- **Boss-Händler** (nach jedem Boss, `Run.boss_shop`): 30 % Rabatt auf alles (`BOSS_DISCOUNT`, alter
  Preis durchgestrichen) und vorher ein Relikt geschenkt (1 von 3, `boss_gift_choices`).
- **Endlos-Modus** (`Run.endless`, nach dem 3. Boss): kein Punkteziel, gespielt wird bis einer Durak
  ist. Gegner Durak → Punkte bleiben, Gold, neues Deck und neuer zufälliger Gegner (auch Bosse).
  Selbst Durak → ein Leben weg und zum Händler, danach weiter. Leben 0 → Ergebnis kommt in die
  **Bestenliste** (`Profile.endless_records`, vorerst lokal, oben rechts im Startmenü; online mit
  Freunden folgt). Gekaufte Karten/Relikte bleiben. Erfolg „Durchgezogen“ = alle drei Bosse.
- **Platzhalter-Gegner** (bis es genug echte gibt): Der Fremde, Die Fremde, Der Schattenfürst (Boss),
  Die Graue Herrin (Boss) – Kapuzengestalt aus Grundformen (`tools/build_placeholder.gd` →
  `assets/models/placeholder/shadow_figure.tscn`), Porträts `assets/portraits/placeholder_*.png`.
  Durch echte Gegner ersetzen: einfach die `placeholder_*.tres` löschen, sobald 9 normale + 3 Bosse da sind.
- **F8**: Gegner überspringen, zum Boss des Akts, Boss-Händler, Endlos-Modus starten.
- **Tägliche Herausforderung** (Menükarte TÄGLICH, `ui/daily_menu.gd`, `Run.start_daily`): Seed aus dem
  Datum (`Run.daily_seed`), Deck des Tages (`Run.daily_deck`, jeden Tag ein anderes, auch nicht
  freigeschaltete), Schwierigkeit Normal → alle spielen denselben Run (Gegner, Räume, Händler, Deck). Gewertet: alle Punkte des Runs (`Run.run_points`, auch Endlos). 3 Versuche pro Tag
  (`Profile.DAILY_TRIES`), der beste zählt; angefangene Versuche sind verbraucht; danach „Üben“.
  Anzeige ●●○ im Fenster, „Versuch 2/3“ auf dem Weg und am Run-Ende (`Profile.daily_results`). Serie und bester Tag in der Statistik.
- **Statistik** (Index → STATISTIK, `Profile.stats`, `wins_vs`, `losses_vs`): Runs, Siegquote, bester
  Akt, Duelle, Bosse, Punkte, beste Runde, bester Run, Endlos-Rekord, Schieben, Items, Gold, Zigaretten,
  Spielzeit, Erfolge; Siege : Niederlagen je Gegner mit Lieblings- und Angstgegner; Tägliche.
- **Händler** nach jedem Sieg: Relikte (Ass im Ärmel, Glücksmünze, Samowar, Wodka), verbesserte
  Karten (Gold/Glas/Glück), Verbesserungen (Farb-Schliff, Trumpf-Kenner, Pflaster, Sparschwein),
  Neu mischen, Zinsen (je 5 Gold +1, max. 5).
- **Decks = Skins mit kleinem Effekt** (`data/decks/*.tres`, `scripts/data/deck_data.gd`), 12 Stück:
  Starter „Hinterzimmer“; je eins pro besiegtem Gegner (Bandit, Sumpfmann, Krähe, Wölfin, Gaukler,
  Knochenmann, Hexe, Riese/Run-Sieg); kaufbar mit **Seelen**: Kaufmann 25, Zar 40, Goldrand 60.
  Effekte z. B. +6 Gold, +1 Leben, Farbe +3 Chips, Trumpf +1 Mult, Start-Glaskarten.
- **Seelen** (Autoload `Profile`, `user://profile.cfg`): 3 pro gewonnenem Tisch, 10 für Run-Sieg,
  multipliziert mit `Run.souls_factor()` (Schwierigkeit × 1,5 ohne Hinweise).
- **Schwierigkeit** (Dialog „Neuer Run“ beim Klick auf SPIELEN, `ui/run_setup_menu.gd`; gemerkt in
  `general/difficulty`): Leicht / Normal / Schwer = Punkteziel ×0,8 / ×1,15 / ×1,45, Fehlerquote der
  Gegner ×1,3 / ×0,6 / ×0,25, Leben +1 / 0 / −1, Seelen ×0,75 / ×1 / ×1,25 (`Run.DIFF_*`).
  Autoplay-Bot (fehlerfrei): Leicht 8/8, Normal 6/8, Schwer 2/8 Runs gewonnen.
- **Hinweise aus** (`general/hints`): spielbare Karten leuchten nicht, alle Handkarten sind anklickbar,
  unpassende werden mit „passt gerade nicht“ abgewiesen → ×1,5 Seelen.
- **Tutorial** (Hauptmenü-Karte „TUTORIAL“, solange `general/show_tutorial` an ist): `Run.start_tutorial()`
  → Übungstisch gegen den Gaukler, Ziel 150, Hinweise an. `scenes/match/tutorial_coach.gd` blendet rechts
  passende Hinweise ein (Willkommen, Trumpf, Hand – diese halten den Gegner an – dann Angriff,
  Verteidigen, Schieben, Nehmen, Nachwerfen, Punkte), jeden nur einmal. Gewonnen → Karte verschwindet;
  in den Optionen „Tutorial im Hauptmenü anzeigen“ holt sie zurück.
- **Verteidigen**: Reihenfolge frei. Passt eine Karte auf mehrere Angriffskarten (oder geht auch
  Schieben), fragt eine Auswahl „AUF 7♠ / AUF 9♠ / SCHIEBEN“. Handkarten lassen sich auch direkt auf
  eine Angriffskarte (oder beim Angriff auf den Tisch) ziehen. Beendet die letzte Verteidigung die Runde
  sofort, landet die Karte trotzdem erst sichtbar auf dem Tisch und wird dann abgeräumt.
- **Infos**: Shift über einer offenen Karte zeigt Chips, Trumpf- und Verbesserungs-Effekt; Maus über dem
  Nachziehstapel zeigt die Anzahl. Relikte wie in Slay the Spire: frei stehende Emojis ohne Rahmen
  (`RelicData.emoji`, im Duell oben rechts), Maus drüber → Name und Wirkung darunter, wirkt ein
  Relikt, blitzt es auf (`MatchHUD.flash_relic`). Daneben zwei leere Item-Plätze als Platzhalter.
- **Items** (`Run.ITEMS`, höchstens 2, beim Händler im Stand ITEMS, einmal einsetzbar; im Duell oben
  rechts anklicken):
  - 🔥 **Feuerzeug** (6 G): eine Gegnerkarte auf dem Tisch wählen (leuchtet) → sie verbrennt mit Glut-Shader
    (`burn` in `card_face.gdshaderinc`), Flammen und Knistern (`burn.wav`). Seine ungeschlagene Angriffskarte
    → er muss neu angreifen; seine Verteidigungskarte → er muss neu schlagen oder nehmen
    (`DurakMatch.burnable_cards/burn`). Rechtsklick/Esc bricht ab, das Feuerzeug bleibt.
  - 🪞 **Spiegel** (5 G): schwebt hinter dem Gegner vorbei (`TableWorld.mirror_flight`, `mirror.wav`) und
    deckt eine zufällige Karte seiner Hand auf; sie ragt 2,6 s offen aus seinem Fächer (`TableWorld.revealed`),
    dann dreht er sie um und sie bleibt klein über ihm sichtbar (`MatchHUD.add_known`), bis er sie spielt
    (platzt dann weg).
  - Feuerzeug gezückt: verbrennbare Gegnerkarten bekommen einen pulsierenden orangen Rahmen.
- **Erfolge** (`Profile.ACHIEVEMENTS`, gespeichert in profile.cfg, Index-Reiter ERFOLGE): Lehrling,
  Erster Sieg, Weitergeschoben, Brandstifter, Volltreffer (100+ Punkte in einer Runde), Sammler
  (5 Relikte), Riesentöter (Boss), Durchgezogen (Run gewonnen), Eiskalt (Run auf Schwer) und die
  geheimen Raucher (eine Zigarette zu Ende), Kettenraucher (6 Zigaretten in einem Run = die ganze Schachtel) und Alkoholiker (Whiskeyflasche im Hauptmenü leer getrunken), Alles auf Grün (Casino-Roulette landet auf der 0), Jackpot (drei Siebenen am Casino-Automaten, ca. 1 %), Moby Durak (Periskop im U-Boot dreimal schnell drehen), Überraschung! (Spieluhr im Zirkuswagen fünfmal aufziehen). Geheime zeigen ein „?“ und
  eine zensierte Aufgabe, bis sie erreicht sind. Meldung oben in der Mitte (Autoload `Pause`).
  Belohnungen: noch offen (Leon entscheidet).
- **Räume** (`scenes/match/rooms/`, `Rooms.for_floor`): Jeder Tisch spielt in einem zufälligen Raum
  (Hinterzimmer, **Altes Casino**, **Bahnhofswartesaal**, **U-Boot** oder **Zirkuswagen**), fest pro Run-Seed und Tisch, damit Weg und Duell denselben Raum
  zeigen; eigener Zufallsgenerator, `Run.rng` bleibt unberührt. Das Tutorial spielt immer im Hinterzimmer.
  Das Casino: Formen aus Blender (`art/blender/casino.py` → `assets/rooms/casino/*.glb`), Materialien,
  Lichter und alles Bewegliche im Code; Zuordnung über Materialnamen mit `RoomKit.model` (Einzelheiten
  und Liste der Teile: `docs/UMGEBUNG_OVERHAUL.md`). Boden, Decke, Tapetenwände, Walzen und Schriften
  bleiben Code. Damast-Tapete, Teppich, Vorhänge, Kronleuchter,
  Neonschild „CASINO“, zwei alte Spielautomaten mit „DURAKI“-Schild und großem Hebel (anklickbar: Walzen
  drehen, selten 7-7-7), größerer abgerundeter Pokertisch, Würfel, Cocktailglas, Pokerchips statt
  Goldmünzen (`TableProps.chip_style`), kein Aschenbecher, keine Zigaretten.
  Statt der Kerzen steht eine **grüne Bankerlampe** (`BankerLamp`, `TableProps.lamp_style`): pro Leben
  ein rotes Lämpchen auf dem Messingfuß; Leben weg → Lampe flackert, ein Lämpchen geht aus; beim letzten
  geht die Lampe aus.
  **Roulette** (Easter Egg, `MiniRoulette`): 1–4 Klicks stupsen den Kessel nur an, beim 5. Klick kurz
  hintereinander wird gedreht. Das Fach wird vorher gleichverteilt gezogen (37 Fächer wie beim
  europäischen Roulette, grüne 0 = 1/37), die Kugel rollt dorthin und hüpft über die letzten Stege.
  Grün → geheimer Erfolg „Alles auf Grün“. Fach und Zahlenfeld blinken in ihrer Farbe. Leise
  Geräusche (`roulette*.wav`, -14 dB). Bankerlampe: Zugkette anklicken schaltet sie an/aus
  (`lamp_chain.wav`).
  Texturen und Geräusche: `tools/generate_casino.py` → `assets/rooms/casino/`.
  **Bahnhofswartesaal** (`StationRoom`, ebenfalls ganz in Code): unten grüne, darüber weiße Kacheln,
  Schachbrett-Fliesen, Holzbänke, Heizkörper, Heißwasserkessel, zwei Fenster zum Bahnsteig, Fahrplantafel
  „DURAKI BAHNHOF“ mit deutschen Städten (Hannover, Neustadt am Rübenberge …), brummende Neonröhren, die
  ab und zu flackern. Alle 40–80 s rauscht draußen ein Zug vorbei (Signal `train_passing`): Licht huscht
  durch den Raum, das Bild zittert leicht (`TableWorld.shake`, nur mit Kamera-Schwenk); danach klappt die
  Tafel eine Zeile weiter. Leben = **LED-Anzeige** an der Rückwand links unter der Tafel (`LedLives`, über
  `TableProps.external_lives`): eine rote LED pro Leben, Leben weg → LED blinkt und geht aus.
  Aufgeschlagene Zeitung „Bahnhofs-Anzeiger“ auf der hinteren linken Bank; auf dem Holztisch Fahrkarte
  und Zucker. Texturen und Geräusche: `tools/generate_station.py` → `assets/rooms/station/`.
  **U-Boot** (`SubmarineRoom`, in Code, Bausteine aus `RoomKit`): grüne Stahlwände mit Nieten und
  Spanten, bunte Rohre mit Ventilrädern, Gitterlampen, pulsierendes rotes Notlicht, Metalltisch mit
  Linoleum, Blechbecher und Seekarte. Hinten links ein **Bullauge** (Platte mit rundem Loch, Messingring):
  draußen ziehen Fische und Luftblasen vorbei. Links eine **Sonar-Konsole**: der Strahl kreist, bei jeder
  Umdrehung „Ping“ und ein Echo-Punkt. Leben = **Druckanzeigen** an der Rückwand rechts (`GaugeLives`):
  Zeiger zittert im Grünen, Leben weg → Zeiger schnellt ins Rote, Ventil zischt Dampf. Im Hintergrund
  Maschinenbrummen, ab und zu Tropfen und Metallknarzen. Easter Egg: **Periskop** rechts anklicken = eine
  Umdrehung; dreimal innerhalb von je 6 s → ein Wal schwimmt am Bullauge vorbei (Walgesang), geheimer
  Erfolg „Moby Durak“. Texturen und Geräusche: `tools/generate_submarine.py` → `assets/rooms/submarine/`.
  **Zirkuswagen** (`CircusRoom`): bunt gestrichene Bretter, gewölbte Bretterdecke mit blinkender
  Lichterkette, Kostüme an Haken, Clownshut und Zylinder, Plakat „ZIRKUS DURAKI“, rechts Schminkspiegel mit
  Glühbirnenrahmen. Hinten links ein Vorhangspalt zum rot-weißen Zelt mit wandernden Scheinwerfern;
  gedämpfte Zirkusmusik, ab und zu Applaus und Lachen. Spieltisch auf einer roten Zirkustrommel.
  Leben = **Luftballons** hinten links an der Tischkante (`BalloonLives`): Leben weg → Ballon zittert und
  platzt mit Konfetti. Easter Egg: **Spieluhr** rechts auf dem Tisch anklicken = aufziehen, die Tänzerin
  dreht sich zur Melodie; fünfmal (je innerhalb von 8 s) → Springteufel schnellt heraus, geheimer Erfolg
  „Überraschung!“. Texturen und Geräusche: `tools/generate_circus.py` → `assets/rooms/circus/`.
  Beide Räume hängen über `TableWorld.special_room` am Tisch (`lives_panel`, `interactive`,
  `apply_environment`, `add_lights`).
  F8-Menü: Raum für alle Tische erzwingen (`Rooms.forced`, „ZUFÄLLIG“ = normal).
- **Der Weg** zeigt den Raum scharf wie im Duell (`RoomBackdrop.blur = 0`, MSAA 4×).
- **Tutorial**: zeigt zum Start eine Glücksmünze und einen Spiegel und erklärt Relikte und Item-Plätze
  oben rechts. Nach dem Sieg öffnet sich der Händler mit 15 Gold und fünf Erklärschritten
  (`shop.gd`, `Run.tutorial_shop`); „TUTORIAL BEENDEN“ führt ins Hauptmenü.
- **Entwicklermenü** (F8, `ui/dev_menu.gd`): beliebige Karte mit Verbesserung auf die Hand,
  Items, Relikte, +10 Gold. Der Gegner wartet, solange es offen ist. Im Duell öffnet es `match.gd`,
  überall sonst (Hauptmenü, Weg, Händler) der Autoload `Pause` (Karten gibt es dort nicht).
- **Abzeichen** (`Profile.badges`): pro Deck drei Plätze Leicht/Normal/Schwer im Deck-Menü; ein Run-Sieg
  mit dem Deck auf der Stufe füllt den Platz.
- **Deck-Belohnungen** (`Cosmetics`, `scenes/match/table_skin.gd`): jedes Abzeichen schaltet eine
  Aussehen-Belohnung frei, jede Stufe einzeln (Sieg auf Schwer schaltet Leicht/Normal nicht mit frei).
  Frisch freigeschaltet → sofort angelegt, Meldung „BELOHNUNG · …“ oben; wählen im Index-Reiter
  **AUSSEHEN** (je Platz eine: Tischfilz, Tischrand, Tischecken, Extras, Zigaretten, Münzen; „Standard“ =
  wie der Raum). Filz/Rand/Ecken/Extras gelten in allen Räumen: jeder Raum meldet über `table_info()`
  seine Filz- und Randmaterialien und den Umriss des Rands (`TableSkin.rect_info`; Casino: Stadion).
  Andere Münzen ersetzen im Casino auch die Pokerchips. Liste (Leicht / Normal / Schwer):
  Hinterzimmer Zigaretten blau/schwarz/gold · Banditen Filz grau/gelb/blau · Knochen Filz knochenweiß /
  Knochenrand / Totenköpfe an den Ecken · Krähe Federfilz / Ebenholzrand / Krähe auf dem Tisch (krächzt) ·
  Riese grobe Eiche / Steinplatte / Felsrand mit Moos · Goldrand Goldkante / weinrot mit Gold / ganzer
  Goldrand · Gaukler rot-gelb gestreift / Harlekin-Rauten / Glöckchen am Rand (klingeln beim Ausspielen) ·
  Kaufmann Silber-/Kupfer-/Edelstein-Münzen · Sumpf moosgrün / Moos und Seerosen / Glühwürmchen · Hexe
  violett / Sterne und Monde / grüne Hexenkerzen · Wolf Fellrand / Krallenspuren / Vollmond (Wolf heult
  beim Duellsieg) · Zar roter Samt / goldene Doppeladler / Fabergé-Leuchter.
  Texturen und Geräusche: `tools/generate_cosmetics.py` → `assets/cosmetics/`.
- Händler verkauft keine Boni mehr (die bringen die Decks mit), nur Karten, Relikte, Items.
- Glaskarten wie bei Balatro: bläulicher, durchscheinender Glasgrund (Alpha ~0,65) mit Lichtbändern,
  dunkle deckende Linien (`glass_version` in `tools/generate_cards.py`, Shader mit ALPHA).
- **Relikte (25.11.)**: Ass im Ärmel (+1 Handkarte, eigenes Icon), Glücksmünze, Med-Kit (+1 Leben, früher
  Samowar, eigenes Icon), Wodka, Gezinkter Würfel (Glück 1 zu 2), Böser Blick (Gegner −1 Startkarte),
  Matrjoschka (nach jedem Tischsieg eine zufällige Karte verbessert), Wolfszahn (+10 Chips je Trumpf-Verteidigung),
  Sparstrumpf (Zinsen bis 8), Wirbel (erstes Schieben im Duell +3 Mult), Hufeisen (Glücks-Treffer +2 Gold).
  Eigene Icons liegen in `assets/relics/` (`RelicData.icon_image`), sonst Emoji. Wirkt eins, blitzt es auf
  (`ScoreTracker.relic_triggered`).
- **Items**: Feuerzeug, Spiegel, Magnet, Runde Schnaps, Kartentausch, Maske, Falle, Bestechung (+50 Punkte).
  Händler legt je Besuch 3 zufällige aus (`Run.SHOP_ITEMS`).
  - Magnet: nur einsetzbar (sonst ausgegraut), wenn sichtbar etwas auf dem Ablagestapel liegt.
    Karte fliegt sichtbar vom Ablagestapel in die Hand (`TableWorld.take_from_discard` vor der
    Änderung am Duell aufrufen, Stil „magnet“), Sound `magnet.wav`.
  - Runde Schnaps: Gegner trinkt ein Schnapsglas (`OpponentFigure.drink_shot`), taumelt danach deutlich
    (`set_drunk`) bis Rundenende; über ihm steht ein Schnapsglas-Symbol (`MatchHUD.add_status`). Eigenes
    Icon ohne Eiswürfel (`assets/items/schnaps.png`, `tools/generate_icons.py`).
  - Kartentausch: Fenster mit allen Handkarten (`MatchHUD.open_card_picker`); die gewählte Karte wird in
    den Stapel gemischt (`TableWorld.send_to_deck`), die offene Karte unter dem Stapel kommt auf die Hand.
    Danach liegt keine offene Karte mehr unter dem Stapel (`DurakMatch.trump_hidden`), ein zweiter
    Tausch im selben Duell geht nicht. Die Trumpffarbe bleibt.
  - Feuerzeug im Besitz: Hat der Gegner alles geschlagen, endet deine Angriffsrunde nicht automatisch
    (`DurakMatch.burn_option_for`) – du entscheidest: verbrennen oder FERTIG. Hat der Gegner keine
    Handkarten mehr, ist nichts verbrennbar.
  - Maske: hinter Chips × Mult steht sofort „×2“ (`MatchHUD.set_factor`).
  - Falle: Symbol „Schieben verboten“ über dem Gegner bis Rundenende (`assets/items/no_transfer.png`).
- Entwicklermenü (F8): zusätzlich „ALLES FREISCHALTEN“ (alle Decks, alle Abzeichen), scrollbar.
- Schärfe: Kartenbilder/Rückseiten/Porträts/Icons mit Mipmaps, Standard-Filter für 2D „Linear Mipmap“.
  Schrift: Hinting „Leicht“ (volles Hinting verschob die Buchstaben bei krummer Skalierung),
  2D-Transformationen auf ganze Pixel (`snap_2d_transforms_to_pixel`). Texttafeln bleiben gerade
  (gedrehte Schrift wird unscharf); die schräge Unterzeile im Titelkeil nutzt eine MSDF-Schrift
  (`UIKit.msdf_body_font`).
- Relikte stehen höchstens zu fünft in einer Reihe (Duell und Weg). Händler: „Dein Besitz“ klein unten,
  Relikte/Items nur als Symbol mit Tooltip; Item-Texte brechen fest in ihrer Spalte um.
- Glaskarten: Farbsymbole knallig (Herz rot, Karo orange, Kreuz schiefergrau, Pik schwarz), die
  goldenen Linien der Bildkarten in Herz-/Karo-Rot bzw. -Orange, Bildfelder nur leicht getönt.
- Farben der Kartenfarben (`tools/generate_cards.py`): Herz knallrot (`CORAL`), Karo orange (`ORANGE`),
  Kreuz grau (`SILVER`), Pik schwarz mit feiner Goldkante (`BLACK`, sonst unsichtbar auf dem dunklen Grund) – so unterscheidet man Herz/Karo und Kreuz/Pik leichter. Gold-, Glas- und
  Glückskarten übernehmen das (eigene dunkle Töne auf Gold/Glas). HUD-Farben passend (`UIKit.SUIT_COLORS`).
- **Regel: Auf Karten steht nie ein Schriftzug der Verbesserung** (kein GOLD/GLAS/GLÜCK) – auch nicht bei
  künftigen Kartenarten. Man erkennt sie am Bild.
- **Look**: Nachschärfen (Aus/Normal/Stark, Standard Normal) nur fürs 3D-Bild
  (`ui/view_sharpen.gdshader` als Material der SubViewportContainer, gesetzt in `UIKit.fit_viewport`) –
  Texte und HUD werden nicht mitgeschärft (keine Lichthöfe an der Schrift). Kantenglättung Standard 4×
  (`GRAPHICS_VERSION` hebt ältere Einstellungen einmalig an). Ein Retro-Look war kurz drin und ist
  auf Wunsch wieder raus.
- Während ausgeteilt wird, kann man nicht ausspielen (`TableWorld.busy_until`).
- **Balance (25.11.)**: Siegprämien der Gegner −20 %, Zinsen max. 4, Spiegel 4 G, Schwer-Ziel ×1,4.
  Bot: Leicht 8/8, Normal 6/8, Schwer ~1–2/8.
- Glückskarten: grün getönter Grund + Klee-Ecken (Variante A, von Leon gewählt, `LUCKY_STYLE`).
- Index ohne Boni-Reiter (Boni gehören zu den Decks); Relikte/Items wachsen beim Drüberfahren.
- Nachgeworfene Karte, die die Runde sofort beendet, landet erst sichtbar auf dem Tisch (`THROWN_PAUSE`).
- Händler zeigt Relikte wie im Duell (freie Emojis, `UIKit.relic_icon`); Trumpf unten links mit dem
  Goldrahmen der Trumpfkarten.
- **Reihenfolge**: erst wird abgeräumt bzw. aufgenommen, dann nachgezogen (Gegner wartet so lange).
- Angriffskarten lassen sich beim Ziehen links oder rechts neben die anderen legen (`attack(card, at)`).
- Gegner-Animationen laufen über geglättete Werte (`OpponentFigure.SMOOTH`), nichts springt mehr.
- **Nachwerfen**: nimmt der Gegner, erscheint ein Banner „<NAME> GIBT AUF – DU DARFST NACHWERFEN“,
  die Zugtafel wird gold („<NAME> NIMMT – NACHWERFEN!“) und der Rand leuchtet gold.
- Gegner (`data/opponents/`): Bandit, Sumpfmann, Krähe, Wölfin, Gaukler, Knochenmann, Hexe, Riese (Boss),
  dazu die vier Platzhalter (siehe oben).

## 5. Look & Feel

### Raum (3D)
Dunkles Hinterzimmer, lila Nachtlicht, grüner Filz. **Kerzen = Leben** (erlöschen mit Rauch),
**Münzstapel = Gold**. Gegner sitzen gegenüber, mit Reaktionen und Denk-Animationen.
3D wird in voller Bildschirmauflösung gerendert (`UIKit.fit_viewport`), damit Karten scharf sind.

### UI-Stil „Plakat“ (aktuell, von Pascal gewählt)
Russisches Konstruktivismus-Plakat, modern umgesetzt (Referenz-Gefühl: Balatro-Lesbarkeit,
Persona-Dynamik). **Rot `#CE2628` / Schwarz `#120E0E` / Creme `#F0E4CC`**, Gold `#E8B446` als Akzent,
Chips lila, Mult gold (bewusst nicht Balatro-Blau/Rot).
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
- links am Rand drei kleine runde Plaketten untereinander (Leben / Gold / Stapel), darunter roter Stern = Trumpf, „ANGRIFF x/y“
- rechts oben schwarzer Balken: Foto, „GEGNER“/„ENDGEGNER“ + Name, Tisch x/y, Handkarten
- darunter Relikte als Briefmarken (Tooltip)
- rechts unten Zug-Plakette (Farbe je Zustand: Angriff creme, Verteidigung rot, Warten schwarz,
  Nachwerfen gold) mit Etikett „SCHIEBEN MÖGLICH“, darunter Knöpfe NEHMEN [E] / FERTIG [LEER]
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

**Händler** (`scenes/run/shop.gd`): Hintergrund ist sein Tisch (RoomBackdrop mit `merchant = true`:
Kerzenkränze + Goldstapel, weichgezeichnet). Davor drei Stände als Plakatflächen mit rotem Schild:
KARTEN (echtes Kartenbild + Etikett GOLD/GLAS/GLÜCK), RELIKTE (Relikte und Boni als Medaillons),
ITEMS (Platzhalter: drei Münzen mit „?“ und Stempel „COMING SOON“). Preise als goldene Schrägschilder.

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

### Kartenarten (eigene Bilder, von Leon gewählt)
- **Goldkarte** „Blattgold“ (`assets/cards/gold/`): ganze Karte vergoldet mit Craquelé und Glanzband,
  Linien dunkel eingraviert, Herz/Karo tiefrot. Effekt: **+3 Gold**, wenn gespielt (Preis 6 G).
- **Glückskarte** „Klee-Ecken“ (`assets/cards/lucky/`): normales Kartenbild, vierblättrige Kleeblätter
  in den freien Ecken, grüne Innenlinie. Effekt: **1 zu 3 Chance auf +5 Mult** in dieser Runde,
  also mehr Punkte (Preis 5 G).
- **Glaskarte** (`assets/cards/glass/`): unverändert durchscheinend. Effekt: doppelte Chips (Preis 5 G).
- Erzeugen: `python tools/generate_cards.py special` (nur Gold + Glück). `Card3D.face_texture()`
  wählt den Ordner nach `card.enhancement`.

### Karten-Animationen
- Vorderseite: `scenes/match/card_face.gdshader` (+ `_glass`, gemeinsamer Teil `.gdshaderinc`):
  Folienglanz, der mit Blickwinkel und Zeit wandert (Trumpf leicht gold, Goldkarte warm,
  Glückskarte grün, Glas irisierend), Lichtreflex an der Mausposition, Leuchten für spielbare Karten.
- `Card3D` (`scenes/match/card_3d.gd`): alle sichtbaren Teile hängen an `_body`; darauf liegen
  Kippen zur Maus (Hover), Wiegen in der Hand, Anheben spielbarer Karten, Federn beim Landen
  (`land()`) und Schubsen (`nudge()`). Die Wurzel bewegt `TableWorld`.
- `TableWorld.sync` merkt sich die Zone jeder Karte und wählt daraus die Bewegung (`_move` mit Stil):
  Austeilen (Bogen, Drehung, Federn), Ausspielen (hoher Bogen, Wumms, Staubring, kurzes Wackeln
  der Kamera – bei Trumpf stärker mit Goldblitz), Schlagen (Angriffskarte wird geschubst),
  Schieben (Wirbel um die Hochachse + rote Tempo-Streifen im HUD), Nehmen (hoch und zurück in die
  Hand), Fertig (Stempel „FERTIG“ im HUD, verteidigte Karten bleiben 1,5 s liegen, Karten drehen sich zum Ablagestapel).
- Kamerawackeln nur, wenn „Kamera-Schwenk“ in den Optionen an ist; alle Zeiten folgen der
  Einstellung „Kartenanimationen“.
- Prüfen: `tests/screenshot.tscn -- film` nimmt eine Bildfolge in Zeitlupe auf.

### Gegner / 3D-Modelle
Modelle aus Blender (Skripte in `art/blender/`), Vorlage ist das Konzeptblatt „Am Spieltisch“.
**Charakter-Überarbeitung vom 25.11. (`docs/CHARAKTER_OVERHAUL.md`):** alle acht Gegner stehen auf
anatomischer MPFB-Basis (`dk.py`, `dk_<id>.py`); vier Köpfe kommen noch aus den alten `hd_<id>.py`.
HD-Versionen auf aktuellem Stand: **Bandit** (`hd_bandit.py`), **Sumpfmann** (`hd_swamp_man.py`),
**Wölfin** (`hd_wolf.py`), **Gaukler** (`hd_jester.py`), **Knochenmann** (`hd_bone_man.py`, Kerze auf
dem Hut mit flackerndem Licht über den Marker `FlameLight`), **Hexe** (`hd_witch.py`, Laterne mit
Licht), **Riese** (`hd_giant.py`, genähte Narben, Eisenkragen mit Kette, Boss mit `figure_scale` 1.1)
und **Krähe** (`hd_crow.py`, komplett neu: Alpha-Federkragen, Goldketten, Zierfibeln).
Wie die Figuren gebaut werden: **`docs/CHARAKTERE.md`**.
Exporte als glb in `assets/models/opponents/`, .blend-Dateien in `art/blender/opponents/`,
Porträts per `art/blender/render_portraits.py`.
- Gegner halten die Karten als Fächer zwischen beiden Händen; Arme mit Ellbogen (Zwei-Knochen-IK
  in `opponent_figure.gd`). `OpponentData.eye_glow = false` bei Figuren mit echten Augen.

### Sound
Alle Effekte sind synthetisch erzeugt: `python tools/generate_sfx.py` → `assets/sfx/*.wav`.
Abspielen über Autoload `Sfx` (`Sfx.play(&"card_hover", pitch, db)`, Bus „SFX“). Vorhanden: Intro (passt
zum Zeitplan in `studio_intro.gd`: Fallen, Aufprall, Ecken, HIT!, Glanz), Menükarten-Hover (Tonhöhe je
Karte) und -Auswahl, Index-Hover und -Klick, Feuerzeug, Zug, Auspusten, Schnaps, Glas-Klirren,
Flaschen-Klopfen, Einschenken, Kerzen-Flackern (als Schleife, blendet nur beim Verweilen ein),
Karten im Duell (Austeilen, Legen, Nehmen, Fertig, Handkarten-Hover), Knöpfe, Münzen, Sieg/Niederlage.
Lautstärken zentral in `Sfx.VOLUME` (bewusst leise, Hover-Töne nur angedeutet). Kartengeräusche
ohne Hall und steil gefiltert (`soft()`): die kurzen Hall-Echos klangen wie ein Metallkamm.
**Musik**: Hauptthema `assets/music/main_theme.ogg` (≈ 2 min, D-Moll, 76 BPM, Balalaika-Zupfen,
Celesta/Klarinette, nahtlose Schleife), erzeugt mit `python tools/generate_music.py`. Autoload `Music`
startet es im Hauptmenü und lässt es weiterlaufen. Musik-Lautstärke Standard 20 % (`Settings.AUDIO_VERSION`
setzt ältere Einstellungsdateien einmalig darauf).

### Index & Kleinigkeiten
- **Index** (Hauptmenü-Karte ★ INDEX, `ui/index_menu.gd`): alle 36 Karten (Normal/Gold/Glas/Glück
  umschaltbar), alle Relikte, alle Boni, Items als Platzhalter – alles sofort sichtbar (zum Testen).
- **Easter Egg Schnapsglas** (`scenes/menu/shot_glass.gd`): im Hauptmenü 5× aufs Glas klicken
  (Ton wird höher) → austrinken (Glas und Kopf kippen gemeinsam), danach schwankt die Kamera, die
  Gestalt lacht. Leeres Glas klirrt immer gleich. 5× auf die Whiskeyflasche → sie kippt, erst dann läuft
  der Strahl, und schenkt nach. Reicht für 6 Gläser, dann ist die Flasche leer (klingt hohl).
- **Whiskeyflasche** (`scenes/match/whiskey_bottle.gd`, ersetzt die grüne Flasche überall): eckig,
  Bernsteinglas mit Füllstand, erfundene Marke „Hinterzimmer Whiskey · seit 1926“, Etikett zur Kamera,
  offen – der Verschluss steht daneben.
- **Zigarettenschachtel** (`scenes/match/cigarette_pack.gd`, eigene Marke „DURAKI“, rot-weiß, kein
  echtes Markenlogo) rechts neben deinem Aschenbecher: 1. Klick Deckel auf, 2. Klick drei Zigaretten
  rutschen halb raus, 3. Klick eine wandert in den Aschenbecher (der startet im Duell leer). Ist sie
  aufgeraucht, holt der nächste Klick sofort die nächste – alle drei lassen sich rauchen. Pro Run
  gibt es nur eine Schachtel mit 6 Zigaretten (zweimal 3, `Run.cigarettes_taken`), die Stummel
  bleiben in der Mulde liegen (`Ashtray.STUB_SPOTS`). Vorne und hinten ein rotes Dreieck, das vom
  Deckel nach unten zeigt (eigenes Design), darin ein Stern.
- **Aschenbecher** (`scenes/match/ashtray.gd`): hinten links der des Gegners (Filter zeigt zu ihm, Deko),
  im Duell zusätzlich dein eigener vorne links neben den Kerzen. Klick = anzünden, dann 5 Züge
  (Zigarette zum Mund, brennt ab, Rauchwolke), danach qualmt der Stummel in der Kerbe 12 s und geht aus.
  Rauch aus Sprites (CPU-Partikel sind im Compatibility-Renderer unzuverlässig).
- **Kerzen**: Maus über den Kerzen/Flammen → Flammen und Licht werden dunkler; das Flackern ist erst
  nach kurzem Verweilen zu hören und wird langsam lauter.
- **Händler** ohne Einblend-/Schwebe-Animationen; Waren werden nur beim Drüberfahren etwas größer.
- Nach erfolgreicher Verteidigung bleiben die Karten 1,5 s liegen, der Gegner wartet, bis abgeräumt ist.

## 6. Optionen
Grafik (Anzeigemodus, Fenstergröße, VSync, FPS-Limit, Kantenglättung, Renderauflösung, Schatten,
Glow, Helligkeit), Audio (Gesamt/Musik/Effekte, stumm im Hintergrund),
Allgemein (Bedenkzeit der Gegner, Kartenanimationen, Meldungen, Kamera-Schwenk, UI-Größe;
Run: Schwierigkeit, Hinweise, Tutorial im Hauptmenü anzeigen).
`user://settings.cfg`, Autoload `Settings`. Esc = Pause.

## 7. Tests
- `godot --headless --path . -s res://tests/run_tests.gd` → Regeln/KI (73 Checks)
- `godot --headless --path . res://tests/deck_tests.tscn` → Decks/Seelen/Schwierigkeit (46 Checks)
- `godot --headless --path . res://tests/autoplay.tscn` → 5 komplette Runs automatisch
  (`DURAKI_DIFF=0/1/2` wählt die Schwierigkeit, `DURAKI_RUNS=n` die Anzahl)
- `godot --headless --path . res://tests/tutorial_test.tscn` → Tutorial komplett durchspielen
- `godot --headless --path . res://tests/daily_tests.tscn` → Tägliche Herausforderung und Statistik (16 Checks)
- `godot --headless --path . res://tests/cosmetics_tests.tscn` → Deck-Belohnungen: je Deck drei, Freischalten je Stufe,
  alle Räume mit allen Belohnungen bauen (107 Checks)
- `godot --headless --path . res://tests/casino_tests.tscn` → Casino-Modelle: alle Teile da, Hebel, Kessel,
  Zugkette, Lämpchen, Pokerchips, Deck-Belohnungen am Tisch (32 Checks)
- `godot --headless --path . res://tests/relic_tests.tscn` → jedes Relikt im echten Ablauf (28 Checks),
  auch Relikte, die mitten im Duell dazukommen (wirken sofort, `match.gd` `_apply_relics`)
- Absturz-Suche unter Windows: `Spiel_starten.bat` schreibt das Log nach `logs\letzter_start.log`.
- `xvfb-run godot --path . res://tests/click_test.tscn` → Handkarten per Klick
- `tests/screenshot.tscn` (Args: transfer, result, boss, opp=<id>, room=<id>, nohud, many, enh, film,
  gold=<n>, cam=x,y,z,zielx,ziely,zielz[,fov] für eine freie Kamera) und
  `tests/ui_shots.tscn` → Screenshots aller Bildschirme
- Tests rufen `Profile.reset_for_tests()` auf, damit das echte Profil nicht überschrieben wird.

## 8. Offene Punkte / nächste Schritte
1. Juice ausbauen: rollende Zahlen beim Punkten, Sounds zu den Kartenbewegungen.
2. Alle acht Gegner sind in HD fertig (Rezept `docs/CHARAKTERE.md`). Feinschliff nach Bedarf
   (z. B. Federn oben auf dem Krähenkopf, Falten der Hexe).
3. Lila Lampen-Scheiben im Raum sind Platzhalter → echte Lampen.
5. Die 3D-Menükarten im Hauptmenü an den Okkult-Gold-Stil der Karten anpassen.
6. Belohnungen für die Erfolge festlegen (Leon überlegt noch).
7. Alte Gegner ohne Porträt (Betrunkener Wirt, Babuschka …) aus `data/opponents/` löschen.
8. Easter-Egg-Absturz unter Windows: Log aus `logs\letzter_start.log` ansehen, falls er wieder auftritt.

## 9. Zusammenarbeit
- Repo: https://github.com/beydo7/duraki (Team: beydo7/Pascal, Florry7, Leon).
- **Auf GitHub wird nur gepusht, wenn Pascal es ausdrücklich sagt („veröffentlichen“ / „hochladen“).**
- Sprache im Projekt: Deutsch (Code-Kommentare, UI-Texte, Commits).
