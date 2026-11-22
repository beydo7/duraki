# Gegner in HD bauen – Rezept (Stand: Bandit, Nov. 2026)

Vorlage für alle Gegner ist das Konzeptblatt **„Am Spieltisch“** (4 × 2 Felder: Bandit, Sumpfmann,
Krähe, Wölfin / Gaukler, Knochenmann, Hexe, Riese). Jeder Gegner soll so detailliert werden wie
der Bandit – aber im eigenen Stil laut Konzept. Musterbeispiel: `art/blender/hd_bandit.py`.

## 1. Was Godot vom Modell erwartet (`scenes/match/opponent_figure.gd`)

```
Torso (Empty)                  Oberkörper; Kinder atmen/beugen sich mit
  Head (Empty)                 Kopf; Kinder drehen sich mit
    EyeL, EyeR (Empty)         Augen-Marker (Glut-Augen nur, wenn eye_glow = true)
    Jaw (optional)             Unterkiefer
  Shoulder_L, Shoulder_R       Schultergelenke (Torso-lokal) für die Arme
Hand_L, Hand_R                 Hände; Objekt-Position = Ruhelage der Hand (hält den Fächer)
SleeveUpper, SleeveFore        Ober-/Unterarm, Länge 1 entlang lokal Z (-0.5 körpernah)
Props (optional) + PropLight   Dinge auf dem Tisch
Void*                          wird in Godot pechschwarz und unbeleuchtet (Augenhöhlen, Mäuler)
Preview_*                      nur Blender-Vorschau, wird nicht exportiert
```

- Arme: Godot setzt Ober- und Unterarm per Zwei-Knochen-IK zwischen Schulter und Hand,
  Ellbogen nach außen/hinten/unten. Segmentlänge `hd.ARM_SEGMENT` = 0.34 (× figure_scale).
- Karten: Fächer um einen Drehpunkt mittig zwischen den Händen (+ `CARD_GRIP`), 68° gekippt.
  Die Hände müssen also unten am Fächer liegen (Bandit: G(±0.085, 0.9, 0.22)).
- `OpponentData.eye_glow`: `false` bei echten Augäpfeln (Bandit), `true` bei glühenden Augen.
- Fell, Haare, Fransen: Objekte `*_Fur`, `*_Brows`, `*_Fringe` werfen in Godot keine Schatten und
  glänzen nicht (sonst wird Fell im Lampenlicht lila fleckig). Neue Haar-Objekte so benennen.

## 2. Bausteine in `art/blender/hd.py`

| Baustein | Wofür |
|---|---|
| `tex_skin`, `tex_leather`, `tex_cloth`, `tex_fur`, `tex_keratin`, `tex_scales` | gekachelte Texturen (numpy) |
| `tex_hair(name, root, tip, …)` | Haarbüschel **mit Alpha** → Fell/Haare/Moos-Fäden |
| `material(…, alpha_clip=True)` | Alpha-Clip (glTF MASK → Godot Alpha-Scissor) |
| `planar_uv(bm, center, hw, hh)` | Frontprojektion für gemalte Gesichter |
| `organic(ob, voxel, smooth, faces)` | Grundkörper per Voxel-Remesh zu einer Form verschmelzen |
| `add_feather` + `MeshBuilder` | Büschel, Federn, Haarsträhnen (viele kleine Karten) |
| `sample_surface` | Punkte auf einer Fläche verteilen (für Fell) |
| `grip_hand(side, …)` | greifende Hand (knobby, claw, bony, finger_len …) |
| `sleeve_segment` | Ärmelstück mit Falten/Aufschlag |
| `shade_like` | Fell schattiert wie die Fläche darunter |
| `preview_setup`, `game_camera`, `preview_cards`, `preview_arms` | Vorschau wie im Spiel |
| `export_character(path)` | GLB-Export ohne Preview_* |

## 3. Vorgehen (so wurde der Bandit gebaut)

1. **Konzeptfeld genau ansehen**: Silhouette, Kopfform, Augen (glühend?), Kleidung, Hände,
   Materialien, Farben. Alles aufschreiben, was man erkennen kann.
2. **Kopf**: `ch.Head` (Ellipsoid) + `deform(face_shape)` für die Grundform (Stirn, Wangenknochen,
   Kiefer, Augenhöhlen). Markante Teile (Nase, Hörner, Schnauze, Kinn) als **eigene Grundkörper**
   bauen, mit dem Kopf zusammenführen und mit `hd.organic` verschmelzen – eine Gauß-Beule allein
   wirkt wie eine Kartoffel. Danach `planar_uv` neu setzen.
3. **Gemalte Haut** (`tex_face` im Bandit): Textur frontal projiziert, per numpy gemalt:
   Grundton + Rauschen, Rötungen (Nase/Wangen), dunkle Augenhöhlen, Falten (Stirn, Zornesfalte,
   Krähenfüße) in Farbe **und** Höhe, Besonderheiten (Narbe, Warzen, Nähte). Poren nur schwach
   (Höhe ≤ 0.25, Normalstärke ~3.5), sonst Orangenhaut.
4. **Augen**: echte Augäpfel (Weiß, Iris, Pupille) + Lider als dünne Wülste; bei Glut-Augen
   die Augen-Marker setzen und `eye_glow = true` lassen.
5. **Haare/Fell/Brauen**: `tex_hair` + `alpha_clip=True`, viele Büschel (Hut: ~9500), Richtung
   per Rauschen in Strähnen gruppiert, **Vorderseite jedes Büschels nach außen drehen**
   (Godot spiegelt Rückseiten-Normalen → schwarze Flecken), oben flach anliegend.
6. **Kleidung**: Körper per Profil (`PROFILE`, `body_point` mit Falten), Revers/Kragen/Säume als
   eigene Teile mit `SOLIDIFY`, runde Kanten (keine Polygon-Ecken), Nähte, Knöpfe, Flicken,
   lose Enden (Schalende mit Fransen).
7. **Hände + Arme**: `grip_hand` passend zur Figur (Klauen, Knochen, Warzen …), Hände an den
   Fächer setzen, `SleeveUpper`/`SleeveFore` (oder nackte Arme mit gleichem Namen),
   Schulter-Marker setzen.
8. **Prüfen** – immer beide Ansichten:
   - Blender: `hd.preview_setup(1.42); hd.game_camera(True); hd.preview_cards(); hd.preview_arms(…)`
     dann Render durch die Spielkamera **und** eine Nahaufnahme.
   - Godot: `tests/screenshot.tscn -- opp=<id>` und `-- opp=<id> close` (Nahaufnahme).
     Godot sieht anders aus als Cycles (lila Raumlicht, harte Schatten, Glanz)!
9. **Export**: `hd.export_character(…/assets/models/opponents/<id>.glb)`,
   `geo.save_blend(…/art/blender/opponents/<id>.blend)`, `characters.CHARACTERS[id] = _hd("hd_<id>")`.
   Texturen heißen in Godot `<id>_<bildname>.png` → Bildnamen ohne Figurennamen wählen
   (`face_color`, nicht `bandit_face_color`). Alte, nicht mehr benutzte Texturen löschen,
   neue `.png.import` wie die übrigen einstellen (VRAM-komprimiert, Mipmaps).

## 4. Stolperfallen (alle schon einmal passiert)

- Gauß-Nase/Schnauze wirkt flach → modellierte Grundkörper + `organic`.
- Tiefe Wangen-Mulden werfen in Godot harte Schattenbänder → Mulden flach halten.
- Fell ohne Alpha sieht aus wie Laub; Alpha-Fell ohne Außen-Drehung ist fleckig schwarz.
- Godot nimmt Glanz 0.5 an → Fell/Haar-Objekte richtig benennen (siehe oben).
- Fingernägel/Krallen nicht zu hell und nicht glänzend.
- Lange Blender-Aufrufe brechen ab → Bauen, Vorschau und Rendern in getrennten Aufrufen.
- `preview_setup()` löscht Preview_* → `preview_cards`/`preview_arms` danach aufrufen.
