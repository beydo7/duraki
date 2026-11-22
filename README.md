# DURAKI

Kartenspiel-Roguelike auf Basis von Schiebe-Durak. Nachts in einem verrauchten Hinterzimmer sitzt du am grünen Filz und spielst nacheinander gegen unheimliche Gestalten: den Banditen, den Sumpfmann, die Krähe, die Wölfin, den Gaukler, den Knochenmann, die Hexe und am Ende den Riesen. Punkte gibt es wie bei Balatro (Chips × Mult), beim Händler kaufst du Relikte und verbesserte Karten, die die Regeln zu deinen Gunsten verbiegen. Wer verliert, ist der Durak.

Gebaut mit [Godot 4.7.2](https://godotengine.org) (GDScript, GL Compatibility), 3D-Modelle aus [Blender](https://www.blender.org). Sprache im Projekt: Deutsch.

## Loslegen

1. **Godot 4.7.2** herunterladen (Standard-Version, nicht .NET): https://godotengine.org/download
2. Repo klonen:
   ```bash
   git clone https://github.com/beydo7/duraki.git
   ```
3. Godot starten → **Importieren** → `project.godot` auswählen → **F5**.

**Ohne Editor:** Doppelklick auf `Spiel_starten.bat`. Die Godot-exe wird gefunden, wenn sie in einem Ordner `Godot` neben dem Repo liegt (oder Umgebungsvariable `GODOT` setzen):

```
Duraki\
  Godot\Godot_v4.7.2-stable_win64.exe
  duraki\            ← dieses Repo
    Spiel_starten.bat
```

Einzelne Szenen startet **F6** im Editor, z. B. `scenes/match/match.tscn` (Duell gegen einen Testgegner).

Die Schriften (Russo One, Oswald, Cinzel Decorative u. a.) liegen in `assets/fonts/` und stehen unter der SIL Open Font License, die Lizenztexte liegen daneben. Das Spiel braucht kein Internet.

## Was schon drin ist

- **Schiebe-Durak 1 gegen 1:** 36 Karten, Trumpf, Angreifen, Nachlegen, Schlagen, Nehmen, Bito, **Schieben** und **Nachwerfen** beim Aufnehmen.
- **Wertung wie Balatro:** Chips × Mult pro Runde, Volltreffer × 2, Durak-Bonus, Punkteziel pro Tisch.
- **Run:** 3 Gegner + Boss, 3 Leben (Kerzen auf dem Tisch), Gold, Händler nach jedem Sieg mit Relikten, Karten-Verbesserungen (Gold, Glas, Glück) und Zinsen.
- **Decks:** 12 Kartenrücken mit kleinem Spieleffekt, freizuschalten über besiegte Gegner oder mit Seelen.
- **3D-Duell** in Ich-Perspektive. Die Gegner halten ihre Karten als Fächer in den Händen, denken, reagieren und spielen mit Animationen aus.
- **Stil „Plakat“** für HUD und Menüs (russischer Konstruktivismus, Rot / Schwarz / Creme) und Kartenblatt **„Okkult-Gold“** mit Animationen (Austeilen, Hover-Kippen, Wirbel beim Schieben, Stempel „БИТО“, Folienglanz).
- **Optionen:** Grafik, Audio, Allgemein; Esc-Pause im Spiel.

Alles Weitere zu Regeln, Wertung, Stil und offenen Punkten: [`docs/GD.md`](docs/GD.md).

## Projektstruktur

| Pfad | Inhalt |
|---|---|
| `scripts/core/` | Spiellogik ohne UI: `Card`, `Deck`, `DurakRules`, `DurakMatch`, `ScoreTracker` |
| `scripts/ai/` | Gegner-KI (`SimpleAI`) |
| `scripts/data/` | Ressourcen-Typen: `OpponentData`, `RelicData`, `DeckData` |
| `scripts/autoload/` | Globale Dienste: `Run` (Run-Zustand), `Settings`, `Profile` (Seelen, Decks), `Pause`, `Fade` |
| `scenes/match/` | 3D-Duell: `table_world.gd` (Raum, Licht, Kamera, Karten-Layout), `card_3d.gd`, `opponent_figure.gd` (setzt die Gegner zusammen und animiert sie), `hud.gd` (komplettes HUD im Code), `match.gd` (Ablauf) |
| `scenes/menu/`, `scenes/run/` | 3D-Hauptmenü, Weg, Händler, Run-Ende |
| `ui/` | Theme, Plakat-Bausteine (`slab.gd`, `roundel.gd`, `seg_bar.gd`), Farben und Animationen (`ui_kit.gd`), Optionen |
| `data/` | Gegner, Relikte und Decks als `.tres` (im Inspektor bearbeitbar, neue werden automatisch geladen) |
| `assets/` | Kartenbilder, Schriften, Porträts, 3D-Modelle (`.glb`, nicht direkt bearbeiten) |
| `art/blender/` | Blender-Quellen (`.blend`) und Build-Skripte der Modelle |
| `tools/` | `generate_cards.py` erzeugt alle Kartenbilder (Python + Pillow + numpy) |
| `tests/` | Regeltests, Autoplay, Klicktest, Screenshots |
| `docs/GD.md` | Game-Design-Dokument und aktueller Stand |
| `docs/CHARAKTERE.md` | Wie die HD-Gegner in Blender gebaut werden |

**Grundprinzip:** Die Regeln (`DurakMatch`) kennen keine UI. Szenen hören auf die Signale `changed`, `message` und `finished` und rufen nur Aktionen wie `attack()`, `defend()`, `transfer()`, `take()` und `pass_bout()` auf. So bleiben die Regeln testbar.

## Tests

```bash
godot --headless --path . -s res://tests/run_tests.gd     # Regeltests + KI-gegen-KI-Partien
godot --headless --path . res://tests/deck_tests.tscn     # Decks und Seelen
godot --headless --path . res://tests/autoplay.tscn       # 5 komplette Runs durch alle Szenen

# brauchen ein echtes Fenster (kein --headless):
godot --path . res://tests/click_test.tscn                # klickt eine Handkarte an
godot --path . res://tests/screenshot.tscn -- opp=wolf    # Duell-Screenshot gegen einen bestimmten Gegner
godot --path . res://tests/screenshot.tscn -- opp=wolf close   # Nahaufnahme des Gegners
godot --path . res://tests/ui_shots.tscn                  # Menü, Weg, Händler, Ende
```

Weitere Screenshot-Optionen: `boss`, `many`, `enh`, `result`, `transfer`, `bito`, `film`. Bilder landen in `user://shots` (oder `-- out=<ordner>`).

## Gegner und 3D-Modelle (Blender)

Vorlage für alle Gegner ist das Konzeptblatt „Am Spieltisch“. Jede Figur hat ein eigenes Build-Skript (`art/blender/hd_<id>.py`), eine `.blend` in `art/blender/opponents/` und einen Export nach `assets/models/opponents/<id>.glb`. Fertig in HD: Bandit, Sumpfmann, Wölfin. Die Krähe ist HD vom älteren Stand, die übrigen folgen.

```bash
pip install bpy numpy pillow                             # Blender als Python-Modul
python art/blender/build_models.py --rebuild wolf        # einen Gegner neu bauen (überschreibt die .blend!)
python art/blender/render_portraits.py wolf              # Porträt für das HUD neu rendern
```

Godot setzt die Figuren über **Objektnamen** zusammen (`Torso`, `Head`, `EyeL/EyeR`, `Shoulder_L/R`, `Hand_L/R`, `SleeveUpper/SleeveFore`, `Void*` …). Die Namen also nicht ändern. Das vollständige Rezept steht in [`docs/CHARAKTERE.md`](docs/CHARAKTERE.md). Einstellungen pro Gegner (Name, Spruch, Stärke, Augenfarbe, Größe) in `data/opponents/<id>.tres`.

Raum, Tisch und Requisiten liegen in `art/blender/room.blend`, `table.blend` und `props.blend`, exportiert nach `assets/models/`.

## Kartenbilder

```bash
pip install pillow numpy
python tools/generate_cards.py
```

Oder die PNGs in `assets/cards/` durch eigene ersetzen (Dateinamen beibehalten).

## Zusammenarbeit

- Team: [beydo7](https://github.com/beydo7) (Pascal), [Florry7](https://github.com/Florry7), Leon.
- `main` ist immer spielbar. Vor dem Arbeiten `git pull`.
- Größere Features in einem eigenen Branch und per Pull Request.
- Möglichst nicht gleichzeitig an derselben `.tscn` oder `.blend` arbeiten, beides lässt sich schlecht mergen.
- `.godot/` ist lokal und wird nicht committet, `.uid`- und `.import`-Dateien dagegen schon.
- Wer mit Claude arbeitet: zuerst [`CLAUDE.md`](CLAUDE.md) und [`docs/GD.md`](docs/GD.md) lesen lassen.

## Lizenz

Alle Rechte vorbehalten. Schriften: SIL Open Font License (siehe `assets/fonts/`).
