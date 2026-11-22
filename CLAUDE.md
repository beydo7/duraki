# Hinweise für Claude

Lies zuerst **`docs/GD.md`** – dort stehen Regeln, Wertung, Stil („Plakat“), Aufbau des HUDs,
Tests und offene Punkte. Kurzfassung der wichtigsten Abmachungen:

- Projekt: Duraki, Durak-Roguelike in **Godot 4.7.2** (GDScript, GL Compatibility).
- Sprache: **Deutsch** – UI-Texte, Kommentare, Commit-Nachrichten.
- Schiebe-Durak (Perevodnoy) inkl. Nachwerfen ist Grundregel; Bube heißt „J“.
- UI-Stil ist **„Plakat“** (Rot/Schwarz/Creme, Russo One + Oswald, schräge Flächen über `Slab`).
  Keine Rückkehr zu Glas/Marker- oder Papier/Zettel-Look.
- Das Duell-HUD wird komplett in `scenes/match/hud.gd` gebaut; `match.gd` spricht nur dessen
  öffentliche Funktionen an.
- Vor Änderungen an Logik die Tests laufen lassen (siehe `docs/GD.md`, Abschnitt Tests).
- **Nicht auf GitHub pushen, außer der Nutzer sagt ausdrücklich „veröffentlichen“.**
- Wenn etwas unklar ist: nachfragen statt raten.
