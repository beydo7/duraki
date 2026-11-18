# Duraki

Ein Roguelike auf Basis des Kartenspiels **Durak**, gebaut mit **Godot 4.7**.

## Über das Projekt

Duraki verbindet das klassische Durak mit Roguelike-Elementen: Du kämpfst dich in einem Run durch mehrere Gegner bis zum Boss, sammelst Gold und Relikte, die die Regeln zu deinen Gunsten verbiegen. Verlierst du zu oft, ist der Run vorbei – und du bist der Durak.

## Status

🚧 Frühe Entwicklung – spielbar:

- **Durak 1 gegen 1** (36 Karten, Trumpf, Angreifen/Nachlegen/Schlagen/Nehmen/Bito).
  Der Angreifer darf passende Ränge jederzeit dazuwerfen – auch mehrere auf einmal
  (nie mehr ungeschlagene Karten, als der Verteidiger auf der Hand hat).
- **Punkteziel wie bei Balatro:** Chips × Mult pro Runde, Volltreffer ×2, Durak-Bonus.
  Ziel erreicht → Tisch gewonnen, sonst ein Leben weg.
- **3D-Duell:** dunkle Kammer, Ich-Perspektive am Tisch, Gegner als Gestalt mit
  Porzellanmaske gegenüber (Reaktionen + 4 Denk-Animationen, variable Bedenkzeit).
- **Echtes Kartenblatt:** Symbole nach Rang, Bildkarten mit Figuren, Glaskarten.
- **Shop nach jedem Sieg:** Relikte, verbesserte Karten (Gold/Glas/Glück),
  Verbesserungen (Farb-Schliff, Trumpf-Kenner, Pflaster, Sparschwein), Neu mischen, Zinsen.
- **Einheitliches UI-Design** (Nacht-Lila, Pinsel- + Schreibmaschinenschrift).
- Run-Ablauf: 3 Gegner + Boss, 3 Leben, Gold.

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
  core/score_tracker.gd   Punktewertung (Chips × Mult, Kartenverbesserungen)
scenes/
  menu/        Hauptmenü
  run/         Run-Übersicht (Der Weg), Shop, Run-Ende
  match/       3D-Duell: table_world.gd (Raum, Tisch, Licht, Kamera, Karten-Layout),
               card_3d.gd (3D-Karte), opponent_figure.gd (Gegnergestalt), match.gd (HUD + Ablauf)
ui/            Theme (Farben, Schriften, Buttons), Hintergrund, gezeichnete Durak-Karte
data/
  opponents/   Gegner als .tres (im Editor bearbeitbar, inkl. Aussehen der Gestalt)
  relics/      Relikte als .tres
assets/
  cards/       Kartenbilder (+ glass/ für Glaskarten) – erzeugt von tools/generate_cards.py
  fonts/       Schriften (freie Lizenzen, Lizenztexte liegen daneben)
tools/         generate_cards.py – erzeugt alle Kartenbilder (Python + Pillow + numpy)
tests/         Regeltests, Autoplay, Klicktest, Screenshot-Skripte
```

**Grundprinzip:** Die Regeln (`DurakMatch`) kennen keine UI. Szenen hören auf die Signale `changed`, `message` und `finished` und rufen nur Aktionen wie `attack()`, `defend()`, `take()` und `pass_bout()` auf. So lassen sich Regeln testen und Relikte/Mods später sauber einbauen.

### Neue Gegner oder Relikte

Im Godot-Dateisystem unter `data/opponents/` bzw. `data/relics/` eine bestehende `.tres` duplizieren und im Inspektor anpassen. Neue Dateien werden automatisch geladen.

## Tests

```bash
# Regeltests + 500 KI-gegen-KI-Partien
godot --headless --path . -s res://tests/run_tests.gd

# Spielt 5 komplette Runs automatisch durch alle Szenen (inkl. Shop)
godot --headless --path . res://tests/autoplay.tscn

# Brauchen ein echtes Fenster (kein --headless):
godot --path . res://tests/click_test.tscn      # klickt eine 3D-Handkarte an
godot --path . res://tests/screenshot.tscn      # Screenshots vom Duell (Optionen: -- boss many enh)
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
