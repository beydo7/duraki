# Charakter-Überarbeitung (Start: 25.11.2026)

Auftrag von Pascal: alle acht Gegner auf professionelles Niveau bringen – sauberes Character Design,
saubere Modellierung, überzeugende Materialien, einheitlicher Stil (leicht stilisierte Dark Fantasy).
Konzepte bleiben erhalten (Vorlage: Konzeptblatt „Am Spieltisch“). Keine Spiellogik anfassen,
Namen/Zuordnungen/Referenzen behalten.

## 1. Sicherung und Arbeitsordner (auf Pascals PC)

- `D:\Games\Duraki\sicherung_charaktere_2026-11-25\` – vollständige Kopie von `art/blender`,
  `assets/models/opponents`, `assets/portraits`, `data/opponents` (673 MB, geprüft).
- Git-Tag `vor-charakter-overhaul` (Commit e567880) im PC- und im Cloud-Repo.
- `D:\Games\Duraki\charakter_overhaul\` – Arbeitsordner: `renders/ist` (Ausgangszustand, 4 Ansichten
  je Figur unter neutralem Licht), `renders/`, `blend/`, `export/`, `werkzeuge/`, `analyse.py`.
- Fertige Exporte kommen erst nach dem Godot-Test ins Projekt.

## 2. Vorgefundene Werkzeuge

Blender 5.3 (D:\Program Files\Blender Foundation), RTX 3060 + Ryzen 9 5950X. Kein Krita, Substance,
GIMP o. Ä. installiert. Cycles rendert bisher auf der CPU (Einstellung „Compute Device“ = None).

Neu installiert (kostenlos, offizielle Quellen):
- **MPFB 2.0.18** (MakeHuman für Blender) über extensions.blender.org – Code GPL, Ergebnisse CC0.
- **MakeHuman system assets** (CC0, 267 MB) von files.makehumancommunity.org: Haut-Texturen,
  Augen, Zähne, Brauen, Wimpern. Zip liegt in `charakter_overhaul\werkzeuge\`.

## 3. Befund am Ausgangszustand (neutrales Licht, `renders/ist`)

Gemeinsame Ursachen des „KI-/Bastel-Looks“:
1. **Keine Anatomie.** Köpfe sind verformte Kugeln mit aufgesetzten Grundkörpern (Nase = Röhre,
   Lippen = Wülste), im Profil stimmt keine Schädelform. Körper sind extrudierte Profile
   („Säule“) ohne Schultern, Brustkorb, Hals.
2. **Rauschen statt Gestaltung.** Texturen sind Rausch-Flecken; Schmutz/Abnutzung liegt überall
   gleich statt in Vertiefungen und an Kanten. Details (Narben-Würmer, Pilze, Flicken) sind zufällig verteilt.
3. **Fell/Federn als Blätter.** Breite Einzelkarten ohne Unterwolle, harte Silhouette.
4. **Übergänge.** Kopf/Hals, Kragen/Körper, Ärmel/Hand stoßen ohne Überlappung oder Naht aneinander.
5. **Hände zu klein** im Verhältnis zum Kopf; Augen meist nur Glutscheiben.

Je Figur: Bandit (Plastikgesicht, Spitznase, Mantel = Block), Sumpfmann (Kugelkopf mit Relief-Gesicht,
Moos = gestreute Blättchen), Krähe (Schnabel gut, Federn flach, Körper = schwarzer Kasten), Wölfin
(Plüschtier, Ohren stechen durch die Kapuze), Gaukler (Maske brauchbar, Krause zackig), Knochenmann
(Schädel zu simpel, Kiefer Klotz), Hexe (Stocknase, flaches Gesicht), Riese (Knetkopf, Schlauchlippen,
Teller-Kragen).

## 4. Neuer Workflow

1. **Anatomische Basis aus MPFB** (`art/blender/dk.py`): Mensch über Formregler gestalten
   (Alter, Muskeln, Gewicht + Gesichtsregler, bewusst über 1.0 hinaus übertrieben = Stilisierung),
   echte Augen/Zähne/Brauen, Skelett. Arme und Finger werden in die Kartenhaltung gestellt.
2. **Zerlegen in die Spielteile** (`dk.Figure`): `Face` (Kopf + Hals, am `Head`-Empty), `Body_Skin`
   (Büste mit Schulteransatz), `Hand_L`/`Hand_R` (gleiche Lage wie bisher `hd.grip_hand`),
   Marker `EyeL/EyeR`, `Shoulder_L/R`. Maßstab Mensch → Figur `S` (ca. 1,7), Kopf leicht größer.
3. **Kleidung, Fell, Requisiten** je Figur in `art/blender/dk_<id>.py`, auf der Körperoberfläche
   aufgebaut. Fell als Schalen-Fell (mehrere Hüllen mit Alpha) statt Blattkarten.
4. **Materialien**: Hauttextur aus den CC0-Scans als Basis, im Skript gegradet; Schmutz über
   AO/Krümmung statt Flächenrauschen; Normal-Maps aus Höhen-Details gebacken.
5. **Kontrolle**: Spielkamera + Nahaufnahme + neutrales Studio-Licht in Blender, dann
   `tests/screenshot.tscn` in Godot. Erst danach Export ins Projekt und neues Porträt.

Nicht-menschliche Figuren (Krähe, Wölfin, Sumpfmann) bekommen Hände/Körperbau ebenfalls aus der
MPFB-Basis; Köpfe werden eigens modelliert (Schädel-Grundform, dann Details), Knochenmann aus
einem anatomischen Schädel.

## 5. Stand (25.11.2026, spät)

Fertig, in Godot getestet und **ins Projekt übernommen** (Modelle, .blend, Texturen, Porträts):

| Figur | Skript | Neu |
|---|---|---|
| Bandit | `dk_bandit.py` | Gesicht/Hände/Oberkörper aus MPFB, Schalen-Fell (Mütze, Kragen, Stulpen), Strick, Mantel |
| Hexe | `dk_witch.py` | altes Gesicht mit Hakennase und spitzem Kinn, Kopftuch auf dem Schädel geformt, Tuch und Kleid auf echten Schultern, Zahnkette, Laterne |
| Riese | `dk_giant.py` | massiger Körper mit echter Anatomie, graue Haut, genähte Narben, Eisenring am Hals, nackte Arme mit Schellen |
| Gaukler | `dk_jester.py` | Maske/Kappe/Krause aus `hd_jester.py` bleiben, neu: Oberkörper im Rautenwams, Bauschärmel mit Rüschen, echte Hände |

Arme (alle vier): `dk.sleeve` – Ober-/Unterarm mit runden Gelenkenden, unregelmäßige Stauchfalten,
Stulpe/Futter/Schelle/Rüsche am Handgelenk; das Handgelenk sitzt genau am Ärmelende.

Noch alter Stand: **Knochenmann, Wölfin, Krähe, Sumpfmann** (`hd_*.py`). Für sie müssen die Köpfe
eigens modelliert und die Kleidung (Umhang, Federkragen, Moos) auf den neuen Körper umgebaut werden.

Offen / Ideen: Narbe und Riss im Tuch beim Banditen (Pascal fragen), Haare der Hexe weicher,
Rauten am Gaukler-Wams entzerren, `build_models.py` läuft mit den `dk_*`-Figuren nur in einem
Blender mit Fenster (MPFB braucht den 3D-View-Kontext).

## 6. Bedienung

```python
import dk_bandit; dk_bandit.build()          # baut die Figur in der aktuellen Szene
hd.export_character(r"...\bandit.glb")       # Export wie bisher
import analyse; analyse.shoot("", r"...\renders\neu", "bandit", open_file=False)   # 4 Studio-Ansichten
```
