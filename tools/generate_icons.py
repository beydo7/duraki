#!/usr/bin/env python3
"""Eigene Item-Symbole (wo es kein passendes Emoji gibt).

    python3 tools/generate_icons.py

Zeichnet 4-fach überabgetastet und verkleinert auf 256 px (weiche Kanten).
- assets/items/schnaps.png: Schnapsglas ohne Eiswürfel (Item und „betrunken“-Anzeige)
- assets/items/no_transfer.png: Schieben verboten (Falle-Anzeige über dem Gegner)
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "items"
S = 1024  # Arbeitsgröße
FINAL = 256


def save(img: Image.Image, name: str) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    img.resize((FINAL, FINAL), Image.LANCZOS).save(OUT / name)
    print("geschrieben:", OUT / name)


def shot_glass() -> Image.Image:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Glas: oben breiter als unten, dicker Boden
    top_l, top_r, top_y = 250, 774, 150
    bot_l, bot_r, bot_y = 330, 694, 860
    wall = 34
    glass = [(top_l, top_y), (top_r, top_y), (bot_r, bot_y), (bot_l, bot_y)]
    d.polygon(glass, fill=(205, 225, 240, 120))
    # Innenraum (etwas dunkler, damit das Glas Kontur bekommt)
    inner_bot = 730
    def x_at(y: float, left: bool) -> float:
        t = (y - top_y) / (bot_y - top_y)
        return (top_l + (bot_l - top_l) * t) + wall if left else (top_r + (bot_r - top_r) * t) - wall
    inner = [(x_at(top_y + 6, True), top_y + 6), (x_at(top_y + 6, False), top_y + 6),
             (x_at(inner_bot, False), inner_bot), (x_at(inner_bot, True), inner_bot)]
    d.polygon(inner, fill=(150, 175, 200, 70))
    # Schnaps (bernsteinfarben), oben eine helle Oberfläche – kein Eiswürfel
    liq_top = 330
    liquid = [(x_at(liq_top, True), liq_top), (x_at(liq_top, False), liq_top),
              (x_at(inner_bot, False), inner_bot), (x_at(inner_bot, True), inner_bot)]
    d.polygon(liquid, fill=(232, 150, 40, 255))
    # dunklerer Bereich unten für Tiefe
    deep = 560
    d.polygon([(x_at(deep, True), deep), (x_at(deep, False), deep),
               (x_at(inner_bot, False), inner_bot), (x_at(inner_bot, True), inner_bot)], fill=(200, 110, 25, 255))
    d.ellipse([x_at(liq_top, True), liq_top - 34, x_at(liq_top, False), liq_top + 34], fill=(255, 205, 110, 255))
    # dicker Glasboden
    d.polygon([(x_at(inner_bot, True) - wall, inner_bot), (x_at(inner_bot, False) + wall, inner_bot),
               (bot_r, bot_y), (bot_l, bot_y)], fill=(215, 232, 245, 200))
    # Rand oben
    d.ellipse([top_l, top_y - 40, top_r, top_y + 40], outline=(235, 245, 255, 255), width=18)
    # Kontur
    d.line(glass + [glass[0]], fill=(235, 245, 255, 255), width=18, joint="curve")
    # Glanzstreifen
    hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(hl).polygon([(top_l + 62, top_y + 60), (top_l + 92, top_y + 60), (bot_l + 58, bot_y - 170),
                                (bot_l + 40, bot_y - 170)], fill=(255, 255, 255, 95))
    img.alpha_composite(hl)
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    return img


def no_transfer() -> Image.Image:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cream, edge = (240, 228, 205, 255), (60, 40, 40, 255)
    # zwei Karten, dazwischen der Schiebe-Pfeil
    for x0, y0 in ((240, 430), (580, 470)):
        d.rounded_rectangle([x0, y0, x0 + 210, y0 + 290], 28, fill=cream, outline=edge, width=12)
        d.rounded_rectangle([x0 + 30, y0 + 30, x0 + 180, y0 + 260], 14, outline=(205, 40, 50, 255), width=10)
    gold = (236, 184, 70, 255)
    d.arc([330, 250, 700, 620], 205, 325, fill=gold, width=40)
    d.polygon([(690, 300), (760, 420), (620, 400)], fill=gold)
    # Verbotsschild: roter Kreis mit Schrägstrich
    red = (226, 30, 44, 255)
    d.ellipse([110, 110, 914, 914], outline=red, width=86)
    d.line([(250, 250), (774, 774)], fill=red, width=86)
    return img


if __name__ == "__main__":
    save(shot_glass(), "schnaps.png")
    save(no_transfer(), "no_transfer.png")
