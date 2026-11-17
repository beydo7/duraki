# Duraki

Ein Roguelike auf Basis des Kartenspiels **Durak**, gebaut mit **Godot 4.7**.

## Über das Projekt

Duraki verbindet das klassische Durak mit Roguelike-Elementen: Du kämpfst dich in einem Run durch mehrere Gegner bis zum Boss, sammelst Gold und Relikte, die die Regeln zu deinen Gunsten verbiegen. Verlierst du zu oft, ist der Run vorbei – und du bist der Durak.

## Status

🚧 Frühe Entwicklung – spielbares Grundgerüst:

- Durak 1 gegen 1 (36 Karten, Trumpf, Angreifen/Nachlegen/Schlagen/Nehmen/Bito)
- Einfache Gegner-KI mit einstellbarer Fehlerquote
- Run-Ablauf: 3 Gegner + Boss, 3 Leben, Gold, Relikt-Belohnungen
- Platzhalter-Grafik (Karten werden im Code gezeichnet)

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

Doppelklick auf **`Spiel_starten.bat`** startet das Spiel direkt. Godot wird automatisch gefunden, wenn die exe in einem Ordner `Godot` neben dem Projektordner liegt:

```
Duraki\
  Godot\Godot_v4.7.2-stable_win64.exe
  duraki\            ← dieses Repo
    Spiel_starten.bat
```

Liegt Godot woanders, die Umgebungsvariable `GODOT` auf den Pfad der exe setzen. Beim allerersten Start importiert das Skript das Projekt einmal (dauert ein paar Sekunden).

Einzelne Szenen lassen sich mit **F6** direkt starten (z. B. `scenes/match/match.tscn` startet ein Duell gegen einen Testgegner).

## Projektstruktur

```
scripts/
  core/        Spiellogik ohne UI: Card, Deck, DurakRules, DurakMatch
  ai/          Gegner-KI (SimpleAI)
  data/        Ressourcen-Typen: OpponentData, RelicData
  autoload/    run_state.gd → globales "Run" (Run-Zustand, Szenenwechsel)
scenes/
  menu/        Hauptmenü
  run/         Run-Übersicht, Belohnung, Run-Ende
  match/       Duell-Szene und Kartenanzeige (CardView)
data/
  opponents/   Gegner als .tres (im Editor bearbeitbar)
  relics/      Relikte als .tres
tests/         Regeltests + Autoplay-Smoke-Test
assets/        Grafiken, Sounds, Fonts (noch leer)
```

**Grundprinzip:** Die Regeln (`DurakMatch`) kennen keine UI. Szenen hören auf die Signale `changed`, `message` und `finished` und rufen nur Aktionen wie `attack()`, `defend()`, `take()` und `pass_bout()` auf. So lassen sich Regeln testen und Relikte/Mods später sauber einbauen.

### Neue Gegner oder Relikte

Im Godot-Dateisystem unter `data/opponents/` bzw. `data/relics/` eine bestehende `.tres` duplizieren und im Inspektor anpassen. Neue Dateien werden automatisch geladen.

## Tests

```bash
# Regeltests + 500 KI-gegen-KI-Partien
godot --headless --path . -s res://tests/run_tests.gd

# Spielt 5 komplette Runs automatisch durch alle Szenen
godot --headless --path . res://tests/autoplay.tscn
```

## Zusammenarbeit mit Git

- `main` ist immer spielbar.
- Für neue Features einen Branch anlegen (`feature/shop`, `fix/ki-nachlegen` …) und per Pull Request mergen.
- Vor dem Arbeiten immer `git pull`.
- Möglichst nicht gleichzeitig an derselben `.tscn`-Datei arbeiten – Szenen-Konflikte sind lästig zu mergen.
- Der Ordner `.godot/` ist lokal und wird nicht committet. `.uid`- und `.import`-Dateien dagegen **schon**.

## Ideen / Nächste Schritte

- Echte Kartengrafiken und Animationen
- Shop zwischen den Kämpfen (Gold ausgeben)
- Relikte, die Regeln ändern (z. B. „Einmal pro Runde Trumpf tauschen“)
- Verzweigte Karte statt fester Gegnerfolge
- Stärkere KI (Karten mitzählen, Trümpfe aufheben)

## Lizenz

Alle Rechte vorbehalten.
