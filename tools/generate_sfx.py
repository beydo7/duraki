#!/usr/bin/env python3
"""Erzeugt die Soundeffekte für Duraki (alles synthetisch, keine fremden Aufnahmen).

Aufruf (aus dem Projektordner):
    python tools/generate_sfx.py
Benötigt: numpy

Ausgabe in assets/sfx/ (16 Bit, mono, 44,1 kHz):
  intro.wav        Studio-Intro, passend zum Zeitplan in scenes/intro/studio_intro.gd:
                   0,25 s Fallen (Luftzug) → 0,60 s Aufprall („Klonk“ des Moduls)
                   → 0,78 s Hitbox-Ecken schnappen (4 Klicks) → 1,05 s „HIT!“-Stempel
                   → 1,55 s Glanz über das Etikett (Glitzern)
  card_hover.wav   Menükarte unter der Maus: Kartenrascheln + weicher Holz-Tock + Ton
  card_select.wav  Menükarte gewählt: kräftiger Schnipp
  lighter.wav      Feuerzeug (Rad + Flamme)
  inhale.wav       Zug an der Zigarette (Knistern + Atem)
  exhale.wav       Rauch auspusten (gespitzte Lippen, weich)
  gulp.wav         Schnaps trinken (Schluck + Glas abstellen)
  candle_flicker.wav  Kerzen flackern (weiches Flattern, feines Knistern)
  clink.wav        Fingernagel ans Schnapsglas
  bottle_knock.wav Klopfen an die Whiskeyflasche
  pour.wav         Whiskey einschenken (Gluckern)
  index_hover.wav  ganz leiser, heller Tick (Karten im Index/Händler)
  ui_click.wav     weicher Klick (Reiter, Kartenarten)

Die Lautstärke im Spiel regelt Sfx.VOLUME (scripts/autoload/sfx.gd).
"""
import os
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sfx")
SR = 44100
rng = np.random.RandomState(7)


def t(dur):
    return np.arange(int(dur * SR)) / SR


def env(n, attack, decay, sustain=0.0):
    """Hüllkurve: linearer Anstieg, exponentielles Abklingen."""
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    d = np.exp(-np.maximum(x - attack, 0) / max(decay, 1e-4))
    return a * (sustain + (1 - sustain) * d)


def noise(dur):
    return rng.uniform(-1, 1, int(dur * SR))


def lowpass(x, cutoff):
    """Einfacher Tiefpass (1. Ordnung), cutoff darf ein Array sein."""
    cutoff = np.broadcast_to(np.asarray(cutoff, np.float64), x.shape)
    out = np.zeros_like(x)
    y = 0.0
    for i in range(len(x)):
        a = 1 - np.exp(-2 * np.pi * cutoff[i] / SR)
        y += a * (x[i] - y)
        out[i] = y
    return out


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, lo, hi):
    return highpass(lowpass(x, hi), lo)


def sine(freq, dur, phase=0.0):
    """Sinus mit (optional) gleitender Frequenz."""
    n = int(dur * SR)
    f = np.broadcast_to(np.asarray(freq, np.float64), (n,))
    return np.sin(2 * np.pi * np.cumsum(f) / SR + phase)


def square(freq, dur):
    return np.sign(sine(freq, dur))


def place(buf, snd, at, gain=1.0):
    i = int(at * SR)
    end = min(len(buf), i + len(snd))
    buf[i:end] += snd[: end - i] * gain


def reverb(x, room=0.35, mix=0.25):
    """Kleiner Raumhall aus ein paar Echos (Hinterzimmer)."""
    out = x.copy()
    for delay, g in ((0.023, 0.5), (0.037, 0.42), (0.051, 0.35), (0.079, 0.25), (0.113, 0.18)):
        d = int(delay * SR * (0.6 + room))
        out[d:] += x[:-d] * g * mix * 2
    return out


def save(name, x, peak=0.89):
    x = x / max(1e-6, np.max(np.abs(x))) * peak
    data = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("  ", name, "%.2f s" % (len(x) / SR))


# --- Bausteine ----------------------------------------------------------------------------

def whoosh(dur, f0, f1):
    n = noise(dur)
    cut = np.geomspace(f0, f1, len(n))
    e = np.sin(np.linspace(0, np.pi, len(n))) ** 1.5
    return lowpass(n, cut) * e


def thud(f0=95, f1=42, dur=0.45):
    x = sine(np.geomspace(f0, f1, int(dur * SR)), dur) * env(int(dur * SR), 0.002, 0.12)
    click = lowpass(noise(0.03), 2500) * env(int(0.03 * SR), 0.0005, 0.008)
    x[: len(click)] += click * 0.8
    return x


def clack(freq=1800, dur=0.06):
    """Hartes Plastik-/Holzklacken."""
    n = int(dur * SR)
    body = sine(freq, dur) * 0.5 + sine(freq * 1.53, dur) * 0.3
    x = body * env(n, 0.0005, 0.012) + bandpass(noise(dur), 1500, 6000) * env(n, 0.0003, 0.006)
    return x


def tick(freq=4200):
    n = int(0.025 * SR)
    return (sine(freq, 0.025) * 0.6 + bandpass(noise(0.025), 3000, 9000)) * env(n, 0.0002, 0.004)


def chime(freq, dur=0.9):
    n = int(dur * SR)
    x = sine(freq, dur) + 0.35 * sine(freq * 2.01, dur) + 0.15 * sine(freq * 3.98, dur)
    return x * env(n, 0.003, dur * 0.3)


def blip_down(f0, f1, dur):
    n = int(dur * SR)
    return lowpass(square(np.geomspace(f0, f1, n), dur), 5000) * env(n, 0.001, dur * 0.45)


# --- Sounds ------------------------------------------------------------------------------

def intro():
    buf = np.zeros(int(3.0 * SR))
    # Fallen: Luftzug, der schneller und höher wird
    place(buf, whoosh(0.36, 300, 3500), 0.25, 0.35)
    # Aufprall: tiefer Schlag + Modul-Klacken + kurzes Scheppern
    place(buf, thud(110, 38, 0.6), 0.6, 1.0)
    place(buf, clack(900, 0.08), 0.6, 0.55)
    place(buf, clack(1300, 0.06), 0.615, 0.3)
    place(buf, bandpass(noise(0.25), 200, 1200) * env(int(0.25 * SR), 0.001, 0.05), 0.6, 0.35)
    # Hitbox-Ecken: vier schnelle Klicks
    for i in range(4):
        place(buf, tick(3800 + i * 350), 0.8 + i * 0.035, 0.45)
    # HIT!: Kick + Snare + 8-Bit-Treffer
    place(buf, thud(160, 55, 0.3), 1.05, 0.8)
    snare = bandpass(noise(0.18), 900, 7000) * env(int(0.18 * SR), 0.001, 0.045)
    place(buf, snare, 1.05, 0.55)
    place(buf, blip_down(1400, 220, 0.22), 1.05, 0.28)
    place(buf, blip_down(2100, 700, 0.09), 1.07, 0.12)
    # Glanz: Glitzer-Arpeggio
    for i, f in enumerate((1568, 2093, 2637, 3136)):
        place(buf, chime(f, 0.7), 1.55 + i * 0.06, 0.12)
    sparkle = highpass(noise(0.5), 7000) * env(int(0.5 * SR), 0.05, 0.12)
    place(buf, sparkle, 1.55, 0.08)
    # Abschluss: tiefer, warmer Ton (Plakat „steht“)
    pad = (sine(110, 1.2) + 0.5 * sine(165, 1.2)) * env(int(1.2 * SR), 0.25, 0.4)
    place(buf, pad, 1.6, 0.18)
    save("intro.wav", reverb(buf, 0.4, 0.22))


def card_hover():
    dur = 0.22
    n = int(dur * SR)
    buf = np.zeros(n)
    # Kartenrascheln: gefiltertes Rauschen, schnell
    swish = bandpass(noise(0.07), 1800, 8000) * env(int(0.07 * SR), 0.004, 0.018)
    place(buf, swish, 0.0, 0.5)
    # weicher Tock auf Filz/Holz
    tock = sine(np.geomspace(320, 180, int(0.09 * SR)), 0.09) * env(int(0.09 * SR), 0.001, 0.025)
    place(buf, tock, 0.012, 0.8)
    # kleiner Glanz-Ton (Quinte), macht es „satisfying“
    place(buf, chime(1175, 0.18), 0.015, 0.1)
    place(buf, chime(1760, 0.15), 0.03, 0.06)
    save("card_hover.wav", reverb(buf, 0.2, 0.12))


def card_select():
    dur = 0.4
    buf = np.zeros(int(dur * SR))
    place(buf, bandpass(noise(0.05), 2500, 9000) * env(int(0.05 * SR), 0.001, 0.01), 0.0, 0.7)
    place(buf, thud(140, 70, 0.25), 0.005, 0.6)
    place(buf, chime(880, 0.35), 0.01, 0.18)
    place(buf, chime(1320, 0.3), 0.04, 0.12)
    save("card_select.wav", reverb(buf, 0.3, 0.18))


def lighter():
    buf = np.zeros(int(1.0 * SR))
    # Reibrad: schnelle Kratzer
    for i in range(7):
        place(buf, bandpass(noise(0.012), 2000, 9000) * env(int(0.012 * SR), 0.0005, 0.004), 0.02 + i * 0.012, 0.6)
    place(buf, clack(2600, 0.04), 0.1, 0.4)
    # Flamme: weiches Fauchen
    flame = lowpass(noise(0.8), 900) * env(int(0.8 * SR), 0.05, 0.3, 0.2)
    place(buf, flame, 0.12, 0.5)
    save("lighter.wav", buf)


def inhale():
    dur = 1.1
    n = int(dur * SR)
    breath = bandpass(noise(dur), 400, 3500) * np.sin(np.linspace(0, np.pi, n)) ** 1.2
    crackle = np.zeros(n)
    r = np.random.RandomState(3)
    for _ in range(40):
        i = r.randint(int(0.1 * SR), n - 400)
        crackle[i:i + 200] += highpass(noise(200 / SR), 3000) * env(200, 0.0002, 0.0015) * r.uniform(0.3, 1)
    save("inhale.wav", breath * 0.6 + crackle * 0.5)


def exhale():
    """Auspusten durch gespitzte Lippen: zwei Resonanzen im Rauschen, weich an- und abschwellend."""
    dur = 1.5
    n = int(dur * SR)
    base = noise(dur)
    lips = bandpass(base, 700, 1900) * 0.8 + bandpass(base, 2200, 3600) * 0.25
    lips = lowpass(lips, np.geomspace(3800, 1400, n))
    shape = np.clip(np.arange(n) / (0.18 * SR), 0, 1) ** 1.5 * np.exp(-np.maximum(np.arange(n) / SR - 0.35, 0) / 0.42)
    flutter = 1.0 + 0.08 * np.sin(2 * np.pi * 5.5 * np.arange(n) / SR)
    save("exhale.wav", lips * shape * flutter, peak=0.5)


def gulp():
    buf = np.zeros(int(1.4 * SR))
    for i, at in enumerate((0.0, 0.22, 0.42)):
        g = sine(np.geomspace(260, 140, int(0.12 * SR)), 0.12) * env(int(0.12 * SR), 0.004, 0.03)
        g += lowpass(noise(0.12), 700) * env(int(0.12 * SR), 0.002, 0.03) * 0.5
        place(buf, g, at, 0.8 - i * 0.1)
    # „Ahh“ als warmer Hauch
    place(buf, lowpass(noise(0.35), 1200) * env(int(0.35 * SR), 0.03, 0.12), 0.62, 0.35)
    # Glas auf den Tisch
    place(buf, clack(2400, 0.1), 1.05, 0.7)
    place(buf, chime(3100, 0.25), 1.05, 0.28)
    save("gulp.wav", reverb(buf, 0.3, 0.15))


def candle_flicker():
    """Kerzen im Luftzug: weiches, unregelmäßiges Flattern + ganz feines Knistern des Dochts."""
    dur = 1.2
    n = int(dur * SR)
    r = np.random.RandomState(11)
    # Flattern: tiefes Rauschen, Lautstärke zittert unregelmäßig (8–14 Hz)
    wob = np.interp(np.arange(n), np.linspace(0, n, 16), r.uniform(0.2, 1.0, 16))
    wob *= 0.75 + 0.25 * np.sin(2 * np.pi * 11 * np.arange(n) / SR + r.uniform(0, 6))
    flap = lowpass(noise(dur), 380) * wob
    crack = np.zeros(n)
    for _ in range(9):
        i = r.randint(0, n - 300)
        crack[i:i + 260] += highpass(noise(260 / SR), 2500) * env(260, 0.0002, 0.002) * r.uniform(0.2, 0.6)
    shape = np.sin(np.linspace(0, np.pi, n)) ** 0.7
    save("candle_flicker.wav", (flap * 1.2 + crack * 0.35) * shape, peak=0.45)


def bottle_knock():
    dur = 0.4
    buf = np.zeros(int(dur * SR))
    place(buf, thud(260, 200, 0.18), 0.0, 0.5)
    place(buf, chime(880, 0.3), 0.0, 0.25)
    place(buf, chime(1460, 0.2), 0.0, 0.1)
    save("bottle_knock.wav", buf, peak=0.6)


def pour():
    """Einschenken: Gluckern aus der Flasche + Plätschern ins Glas."""
    dur = 1.6
    n = int(dur * SR)
    buf = np.zeros(n)
    r = np.random.RandomState(5)
    at = 0.05
    while at < 1.25:
        d = r.uniform(0.04, 0.07)
        f0 = r.uniform(260, 380)
        blob = sine(np.geomspace(f0, f0 * 1.9, int(d * SR)), d) * env(int(d * SR), 0.003, d * 0.35)
        place(buf, blob, at, r.uniform(0.5, 0.9))
        at += r.uniform(0.07, 0.12)
    trickle = bandpass(noise(1.3), 1200, 5000) * env(int(1.3 * SR), 0.08, 0.5, 0.4)
    place(buf, trickle, 0.05, 0.25)
    save("pour.wav", reverb(buf, 0.2, 0.1), peak=0.6)


def index_hover():
    dur = 0.12
    buf = np.zeros(int(dur * SR))
    place(buf, bandpass(noise(0.03), 3000, 9000) * env(int(0.03 * SR), 0.001, 0.006), 0.0, 0.25)
    place(buf, chime(1976, 0.1), 0.002, 0.35)
    place(buf, chime(2637, 0.08), 0.004, 0.12)
    save("index_hover.wav", buf, peak=0.5)


def ui_click():
    dur = 0.18
    buf = np.zeros(int(dur * SR))
    place(buf, clack(1500, 0.04), 0.0, 0.4)
    place(buf, chime(1318, 0.15), 0.004, 0.25)
    save("ui_click.wav", buf, peak=0.55)


def clink():
    dur = 0.5
    buf = np.zeros(int(dur * SR))
    place(buf, chime(2960, 0.45), 0.0, 0.5)
    place(buf, chime(4420, 0.3), 0.0, 0.22)
    place(buf, tick(6000), 0.0, 0.3)
    save("clink.wav", buf)


def main():
    os.makedirs(OUT, exist_ok=True)
    intro()
    card_hover()
    card_select()
    lighter()
    inhale()
    exhale()
    gulp()
    candle_flicker()
    clink()
    bottle_knock()
    pour()
    index_hover()
    ui_click()
    print("Sounds erzeugt in", OUT)


if __name__ == "__main__":
    main()
