# Duraki

Ein Roguelike auf Basis des Kartenspiels **Durak**, gebaut mit **Godot 4.7**.

## Über das Projekt

Duraki verbindet das klassische Durak mit Roguelike-Elementen: Du kämpfst dich in einem Run durch mehrere Gegner bis zum Boss, sammelst Gold und Relikte, die die Regeln zu deinen Gunsten verbiegen. Verlierst du zu oft, ist der Run vorbei – und du bist der Durak.

## Status

🚧 Frühe Entwicklung – spielbar:

- **Schiebe-Durak 1 gegen 1** (Perevodnoy: 36 Karten, Trumpf, Angreifen/Nachlegen/Schlagen/Nehmen/Bito).
  Der Angreifer darf passende Ränge jederzeit dazuwerfen – auch mehrere auf einmal
  (nie mehr ungeschlagene Karten, als der Verteidiger auf der Hand hat).
  - **Schieben:** Solange noch nichts geschlagen ist, legt der Verteidiger eine Karte gleichen
    Rangs dazu und gibt den Angriff zurück (nur wenn der andere genug Karten hat). Kann die
    Karte auch schlagen, fragt das Spiel „Schlagen oder Schieben?“.
  - **Nachwerfen:** Nimmt der Verteidiger auf, darf der Angreifer noch passende Karten
    hinterherwerfen (Knopf „FERTIG“ beendet das).
- **Optionen** (Hauptmenü oder Esc im Spiel): Grafik (Anzeigemodus, Fenstergröße, VSync,
  FPS-Limit, Kantenglättung, Renderauflösung, Schatten, Glow, Helligkeit), Audio (Gesamt/Musik/
  Effekte, stumm im Hintergrund), Allgemein (Bedenkzeit der Gegner, Kartenanimationen,
  Spielmeldungen, Kamera-Schwenk, Größe der Oberfläche). Gespeichert in `user://settings.cfg`.
- **Punkteziel wie bei Balatro:** Chips × Mult pro Runde, Volltreffer ×2, Durak-Bonus.
  Ziel erreicht → Tisch gewonnen, sonst ein Leben weg.
- **3D-Duell:** dunkle Kammer, Ich-Perspektive am Tisch, Gegner als Gestalt mit
  Porzellanmaske gegenüber (Reaktionen + 4 Denk-Animationen, variable Bedenkzeit).
- **Echtes Kartenblatt:** Symbole nach Rang, Bildkarten mit Figuren, Glaskarten.
- **Shop nach jedem Sieg:** Relikte, verbesserte Karten (Gold/Glas/Glück),
  Verbesserungen (Farb-Schliff, Trumpf-Kenner, Pflaster, Sparschwein), Neu mischen, Zinsen.
- **Stil „Plakat“** (russisches Konstruktivismus-Plakat, Rot / Schwarz / Creme): schräge Flächen mit hartem
  Schatten, kyrillische Unterzeilen. Schriften: **Russo One** (Titel/Zahlen) und **Oswald** (Text), beide OFL,
  in `assets/fonts/`. Bausteine: `ui/slab.gd` (Plakatfläche), `ui/roundel.gd` (runde Plakette/Stern),
  `ui/seg_bar.gd` (Segmentbalken), Farben/Animationen in `ui/ui_kit.gd`, Theme `ui/theme.tres`.
- **Kartenblatt** im Holzschnitt-Stil auf gealtertem Papier (`tools/generate_cards.py`).
- **Decks (Skins mit kleinem Effekt):** 12 Decks mit eigener Rückseite (`data/decks/`). Freischalten,
  indem man den passenden Gegner besiegt oder mit **Seelen** kauft (gibt es am Run-Ende).
  Auswahl im Hauptmenü unter „Decks“. Fortschritt in `user://profile.cfg` (Autoload `Profile`).
- **Hauptmenü in 3D:** Kamera fährt an den Tisch, Menüpunkte liegen als Karten auf dem Filz.
- **Duell-HUD (Plakat, komplett im Code in `scenes/match/hud.gd`):** roter Punkte-Keil mit Segmentbalken,
  Chips × Mult, Gegnerbalken (Foto, Name kyrillisch + deutsch, Handkarten), Relikte als Briefmarken,
  runde Plaketten für Leben/Gold/Stapel, Trumpf-Stern, Zug-Plakette mit „Schieben möglich“, Schrägbanner,
  Tastenkürzel (Leertaste = Bito/Fertig, E = Nehmen).
  Im Raum: **Kerzen = Leben** (erlöschen mit Rauch), **Münzstapel = Gold**, roter Rand bei Verteidigung.
- Weg, Händler und Run-Ende vor dem weichgezeichneten Hinterzimmer (`ui/room_backdrop.gd`).
- Run-Ablauf: 3 Gegner + Boss, 3 Leben, Gold.

Design-Dokument und aktueller Stand: [`docs/GD.md`](docs/GD.md).

## Team

- [@beydo7](https://github.com/beydo7)
- [@Florry7](https://github.com/Florry7)

## Setup

1. **Godot 4.7.2** herunterladen: https://godotengine.org/download (Standard-Version, nicht .NET).
2. Repo klonen:
   ```bash
   git clone https://github.com/beydo7/duraki.git
   ```
3. Godot starten → **Importieren** → `project.godot` im Repo-Ordner auswählen.
4. Mit **F5** starten.

### Schnell testen ohne Editor

Doppelklick auf **`Spiel_starten.bat`** startet das Spiel direkt. Godot wird automatisch gefunden, wenn die exe im Projektordner selbst oder in einem Ordner `Godot` neben dem Projektordner liegt:

```
Duraki\
  Godot\Godot_v4.7.2-stable_win64.exe
  duraki\            ← dieses Repo
    Spiel_starten.bat
```

Liegt Godot woanders, die Umgebungsvariable `GODOT` auf den Pfad der exe setzen. Vor jedem Start importiert das Skript das Projekt kurz (ein paar Sekunden), damit neue Skripte/Klassen erkannt werden.

Einzelne Szenen lassen sich mit **F6** direkt starten (z. B. `scenes/match/match.tscn` startet ein Duell gegen einen Testgegner).

## Projektstruktur

```
scripts/
  core/        Spiellogik ohne UI: Card, Deck, DurakRules, DurakMatch
  ai/          Gegner-KI (SimpleAI)
  data/        Ressourcen-Typen: OpponentData, RelicData
  autoload/    run_state.gd → globales "Run" (Run-Zustand, Szenenwechsel)
               settings.gd → globales "Settings" (Optionen laden/speichern/anwenden)
               pause_menu.gd → globales "Pause" (Esc-Menü im Spiel)
               profile.gd → globales "Profile" (Seelen, Decks, Statistik – bleibt über Runs erhalten)
  core/score_tracker.gd   Punktewertung (Chips × Mult, Kartenverbesserungen)
scenes/
  menu/        Hauptmenü
  run/         Run-Übersicht (Der Weg), Shop, Run-Ende
  match/       3D-Duell: table_world.gd (lädt Raum/Tisch/Requisiten, Licht, Kamera, Karten-Layout),
               card_3d.gd (3D-Karte), opponent_figure.gd (setzt die Figur zusammen + animiert sie),
               hud.gd (animiertes HUD), match.gd (Ablauf)
ui/            Theme (Farben, Schriften, Buttons), Hintergrund, gezeichnete Durak-Karte, Masken-Porträt,
               options_menu.gd (Optionen-Fenster)
data/
  opponents/   Gegner als .tres (im Editor bearbeitbar, inkl. Aussehen der Gestalt)
  relics/      Relikte als .tres
assets/
  cards/       Kartenbilder (+ glass/ für Glaskarten) – erzeugt von tools/generate_cards.py
  fonts/       Schriften (freie Lizenzen, Lizenztexte liegen daneben)
  models/      3D-Modelle als .glb (Export aus art/blender/, nicht direkt bearbeiten)
art/
  blender/     Blender-Quelldateien (.blend) + Build-Skripte (Godot ignoriert diesen Ordner)
tools/         generate_cards.py – erzeugt alle Kartenbilder (Python + Pillow + numpy)
tests/         Regeltests, Autoplay, Klicktest, Screenshot-Skripte
```

**Grundprinzip:** Die Regeln (`DurakMatch`) kennen keine UI. Szenen hören auf die Signale `changed`, `message` und `finished` und rufen nur Aktionen wie `attack()`, `defend()`, `transfer()`, `take()`/`finish_take()` und `pass_bout()` auf. So lassen sich Regeln testen und Relikte/Mods später sauber einbauen.

### Neue Gegner oder Relikte

Im Godot-Dateisystem unter `data/opponents/` bzw. `data/relics/` eine bestehende `.tres` duplizieren und im Inspektor anpassen. Neue Dateien werden automatisch geladen.

## 3D-Modelle (Blender)

Raum, Tisch, Requisiten (Lampe, Scheinwerfer, Flasche …) und die Gegnerfigur sind Blender-Modelle:

| Quelle (bearbeiten)            | Export (lädt Godot)          | Inhalt |
|--------------------------------|------------------------------|--------|
| `art/blender/room.blend`       | `assets/models/room.glb`     | Kammer: Wände, Dielen, Balken, Tür, Regal |
| `art/blender/table.blend`      | `assets/models/table.glb`    | Spieltisch mit Filz, Holzrand, gedrechselten Beinen |
| `art/blender/props.blend`      | `assets/models/props.glb`    | Hängelampe, Scheinwerfer, Lautsprecher, Kisten, Tischdeko |
| `art/blender/opponents/<id>.blend` | `assets/models/opponents/<id>.glb` | Die acht Gegner (Bandit, Sumpfmann, Krähe, Wölfin, Gaukler, Knochenmann, Hexe, Riese) |

**Ein Modell ändern:**
1. `.blend` in Blender (4.2 oder neuer) öffnen, bearbeiten, speichern.
2. Exportieren: *Datei → Exportieren → glTF 2.0 (.glb)* nach `assets/models/<name>.glb` (Format „glTF Binary“, „Modifikatoren anwenden“ an).
   Alternativ alles auf einmal: `blender -b -P art/blender/build_models.py`
3. Godot importiert die neue `.glb` automatisch beim nächsten Öffnen bzw. Start.

**Wichtig bei den Gegnern:** Godot setzt die Figur über **Objektnamen** zusammen und animiert sie – Namen also nicht ändern:

- `Torso` (leeres Objekt): alles darunter atmet und beugt sich mit
- `Head` (unter Torso): alles darunter dreht/zuckt mit dem Kopf; darin `EyeL`, `EyeR` (optional `EyeX1` …) als Marker für die glühenden Augen und optional `Jaw` (Unterkiefer, klappert beim Lachen)
- `Hand_L`, `Hand_R` (Ursprung = Handgelenk, Finger zeigen nach vorne) und `Sleeve` (Ärmel, Länge 1 entlang Z, +0.5 = Handgelenk)
- optional `Props` mit `PropLight` – Dinge auf dem Tisch mit Licht (die Laterne der Hexe)
- Objekte, deren Name mit `Void` beginnt (Augenhöhlen, Mäuler), werden im Spiel pechschwarz

Einstellungen pro Gegner in `data/opponents/<id>.tres`: Name, Spruch, Stärke, Augenfarbe, Größe, Modell und Porträt.
Die Porträts (`assets/portraits/`) rendert `python3 art/blender/render_portraits.py` aus den .blend-Dateien.

**Alles neu aus dem Skript erzeugen** (überschreibt die .blend-Dateien!):
```bash
pip install bpy numpy pillow        # Blender als Python-Modul (Python 3.13)
python3 art/blender/build_models.py --rebuild           # alles
python3 art/blender/build_models.py --rebuild crow      # nur ein Modell (Gegner-IDs siehe characters.py)
```
`art/blender/textures.py` erzeugt dabei die kachelbaren Texturen (Holz, Ziegel, Filz, Stoff, Porzellan, Metall).

## Tests

```bash
# Regeltests + 500 KI-gegen-KI-Partien
godot --headless --path . -s res://tests/run_tests.gd

# Spielt 5 komplette Runs automatisch durch alle Szenen (inkl. Shop)
godot --headless --path . res://tests/autoplay.tscn

# Brauchen ein echtes Fenster (kein --headless):
godot --path . res://tests/click_test.tscn      # klickt eine 3D-Handkarte an
godot --path . res://tests/screenshot.tscn      # Screenshots vom Duell (Optionen: -- boss many enh result)
godot --path . res://tests/ui_shots.tscn        # Screenshots von Menü, Weg, Shop, Ende
```

### Kartenbilder ändern

```bash
pip install pillow numpy
python tools/generate_cards.py
```
Oder einfach die PNGs in `assets/cards/` durch eigene ersetzen (Dateinamen beibehalten).

## Zusammenarbeit mit Git

- `main` ist immer spielbar.
- Für neue Features einen Branch anlegen (`feature/shop`, `fix/ki-nachlegen` …) und per Pull Request mergen.
- Vor dem Arbeiten immer `git pull`.
- Möglichst nicht gleichzeitig an derselben `.tscn`-Datei arbeiten – Szenen-Konflikte sind lästig zu mergen.
- Der Ordner `.godot/` ist lokal und wird nicht committet. `.uid`- und `.import`-Dateien dagegen **schon**.

## Ideen / Nächste Schritte

- Balance: Punkteziele anheben (mit Shop + Mehrfach-Werfen gewinnt der Test-Bot fast immer)
- Hauptmenü, Weg und Shop ebenfalls in 3D / im Raum
- Sounds und Musik
- Relikte, die Regeln ändern (z. B. „Einmal pro Runde Trumpf tauschen“)
- Verzweigte Karte statt fester Gegnerfolge
- Stärkere KI (Karten mitzählen, Trümpfe aufheben)
- Gegnergestalt durch echtes 3D-Modell (Blender) ersetzen

## Lizenz

Alle Rechte vorbehalten.
