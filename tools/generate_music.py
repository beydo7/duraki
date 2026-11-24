#!/usr/bin/env python3
"""Erzeugt das Hauptthema von Duraki – komplett synthetisch, ohne fremde Aufnahmen.

Aufruf (aus dem Projektordner):
    python tools/generate_music.py
Benötigt: numpy, scipy und ffmpeg (mit libvorbis) im PATH oder unter /usr/local/bin.

Ausgabe:
  assets/music/main_theme.ogg   Stereo, 44,1 kHz, OGG Vorbis (-q:a 5), nahtlos loopbar.
  Die Zwischen-WAV landet in /tmp (nicht im Repo).

Stück: „Hinterzimmer“ – d-Moll (harmonisch, mit phrygischen Es-Farben), 76 BPM, 4/4,
40 Takte (~126 s). Nachts, grüner Filz, Kerzen, Rauch: Spannung am Tisch, ein Hauch
russischer Volksmusik (Domra-/Balalaika-Zupfen im 3+3+2-Akzent im B-Teil).

Aufbau (Takte / Zeit):
  Intro  T. 1–4    0:00  Bordun, Streicher-Fläche, Zupf-Ostinato, Glocke
  A1     T. 5–12   0:13  Celesta-Melodie, weicher Kick auf 1, Besen auf 2 und 4
  A2     T. 13–20  0:38  Klarinette (tief, warm) übernimmt, Celesta antwortet oben, Shaker
  B      T. 21–28  1:03  Spannung: Gm–Dm/F–Es–A, Klarinette hoch, Tom-Puls schwillt an
  A3     T. 29–36  1:28  Celesta + Klarinette (Oktave tiefer), Melodie variiert
  Outro  T. 37–40  1:53  dünnt aus, endet auf A-Dur (Dominante) → führt in Takt 1 zurück

Nahtloser Loop: Alles wird mit Überhang gerendert; was über das Ende hinausklingt
(Ausklang, Hall), wird auf den Anfang gefaltet. Kompressor und Automation arbeiten
zirkulär, deshalb passt das Ende sample-genau an den Anfang.
"""
import os
import shutil
import subprocess

import numpy as np
from scipy import signal
from scipy.ndimage import uniform_filter1d

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "music")
OUT_OGG = os.path.join(OUT_DIR, "main_theme.ogg")
TMP_WAV = "/tmp/duraki_main_theme.wav"

SR = 44100
BPM = 76
BEAT = 60.0 / BPM
BAR = 4 * BEAT
BARS = 40
LOOP_LEN = int(round(BARS * BAR * SR))     # Länge des Loops in Samples
TAIL = int(8 * SR)                          # Überhang für Ausklang/Hall (wird gefaltet)
NTOT = LOOP_LEN + TAIL

rng = np.random.RandomState(1979)


# ---------------------------------------------------------------------------
# Grundwerkzeuge
# ---------------------------------------------------------------------------

NOTEN = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5,
         "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def midi(name):
    """Notenname wie 'D5' oder 'Bb4' → MIDI-Nummer."""
    if isinstance(name, (int, np.integer)):
        return int(name)
    return NOTEN[name[:-1]] + 12 * (int(name[-1]) + 1)


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def zeit(bar, beat=0.0):
    """Takt (ab 0) und Schlag → Sekunden."""
    return bar * BAR + beat * BEAT


def lowpass(x, fc, order=2):
    sos = signal.butter(order, fc, "low", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=-1)


def highpass(x, fc, order=2):
    sos = signal.butter(order, fc, "high", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=-1)


def bandpass(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], "band", fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=-1)


def adsr(n, a, d, s, r, gate):
    """Hüllkurve in Samples: Anstieg a, Abfall d auf Haltepegel s, Ausklang r ab gate (alles in s)."""
    tt = np.arange(n) / SR
    e = np.where(tt < a, tt / max(a, 1e-4),
                 s + (1 - s) * np.exp(-(tt - a) / max(d, 1e-4)))
    # weicher Anstieg (Sinus-Form statt linear)
    e = np.where(tt < a, np.sin(0.5 * np.pi * np.clip(tt / max(a, 1e-4), 0, 1)) ** 2, e)
    rel = np.where(tt > gate, np.exp(-(tt - gate) / max(r, 1e-4)), 1.0)
    return e * rel


def fade_kanten(x, ms=4):
    """Kurze Ein-/Ausblendung gegen Klicks."""
    k = min(int(ms * SR / 1000), len(x) // 2)
    if k > 0:
        w = np.sin(np.linspace(0, np.pi / 2, k)) ** 2
        x[:k] *= w
        x[-k:] *= w[::-1]
    return x


class Bus:
    """Stereo-Spur mit Pan und Hall-Anteil."""

    def __init__(self, name, gain=1.0, hall=0.3):
        self.name = name
        self.gain = gain
        self.hall = hall
        self.buf = np.zeros((2, NTOT))

    def add(self, snd, t, gain=1.0, pan=0.0):
        """Mono- oder Stereo-Klang zur Zeit t (s) einsetzen. pan: -1 links … +1 rechts."""
        i = int(round(t * SR))
        if i >= NTOT or i < 0:
            return
        if snd.ndim == 1:
            p = (pan + 1) * np.pi / 4
            snd = np.vstack([snd * np.cos(p), snd * np.sin(p)])
        n = min(snd.shape[1], NTOT - i)
        self.buf[:, i:i + n] += gain * snd[:, :n]


def human(t, ms=7):
    """Leichte Timing-Ungenauigkeit (Mensch statt Maschine)."""
    return t + rng.normal(0, ms / 1000.0)


def vel(v, streu=0.1):
    return v * (1 + rng.uniform(-streu, streu))


# ---------------------------------------------------------------------------
# Instrumente
# ---------------------------------------------------------------------------

def bordun(m, dauer, a=1.2, r=1.6):
    """Tiefer, warmer Bordun wie ein gestrichener Kontrabass (additiv, verstimmte Stimmen)."""
    n = int((dauer + r * 4) * SR)
    tt = np.arange(n) / SR
    f = mtof(m)
    out = np.zeros((2, n))
    for ch, det in ((0, -0.0025), (1, 0.0025)):
        # langsames Bogen-Schwanken in Tonhöhe und Lautstärke
        wob = 1 + 0.0012 * np.sin(2 * np.pi * (0.23 + 0.05 * ch) * tt + rng.uniform(0, 6))
        ph = 2 * np.pi * np.cumsum(f * (1 + det) * wob) / SR
        s = np.zeros(n)
        for k in range(1, 11):
            amp = (1.0 / k) * (1.0 if k > 1 else 0.55)   # Grundton etwas leiser → weniger Dröhnen
            s += amp * np.sin(k * ph + rng.uniform(0, 6))
        bogen = 1 + 0.08 * np.sin(2 * np.pi * 0.37 * tt + ch) + 0.05 * np.sin(2 * np.pi * 0.9 * tt)
        out[ch] = s * bogen
    # Bogengeräusch, sehr leise
    out += 0.03 * bandpass(rng.randn(2, n), 300, 1200)
    out = lowpass(out, 700, 2)
    out = highpass(out, 38, 2)
    return out * adsr(n, a, 0.1, 1.0, r, dauer)


def flaeche(noten, dauer, a=1.4, r=1.8, hell=1800):
    """Streicher-/Chor-Fläche: verstimmte Sägezähne, weich gefiltert, breit im Stereobild."""
    n = int((dauer + r * 4) * SR)
    tt = np.arange(n) / SR
    out = np.zeros((2, n))
    for m in noten:
        f = mtof(m)
        for ch in (0, 1):
            for det in (-0.004, 0.0, 0.004):
                vib = 1 + 0.0018 * np.sin(2 * np.pi * rng.uniform(4.2, 5.4) * tt + rng.uniform(0, 6))
                ph = 2 * np.pi * np.cumsum(f * (1 + det + (ch - 0.5) * 0.002) * vib) / SR
                s = np.zeros(n)
                for k in range(1, 9):
                    s += np.sin(k * ph + rng.uniform(0, 6)) / k
                out[ch] += s
    out = lowpass(out, hell, 2)
    out = highpass(out, 150, 1)
    return out / (len(noten) * 3) * adsr(n, a, 0.2, 1.0, r, dauer)


_zupf_cache = {}


def zupf(m, variante=0):
    """Domra/Balalaika-Zupfton per Karplus-Strong (4-fach überabgetastet für saubere Stimmung)."""
    key = (m, variante)
    if key in _zupf_cache:
        return _zupf_cache[key]
    os4 = 4
    fs = SR * os4
    f = mtof(m)
    lang = 1.6
    n = int(lang * fs)
    # Schleifenfilter: Binomial-Tiefpass (dämpft Obertöne mit jeder Runde)
    h = np.array([1.0])
    for _ in range(14):
        h = np.convolve(h, [0.5, 0.5])
    gd = (len(h) - 1) / 2
    periode = fs / f
    d = int(round(periode - gd))
    t60 = 1.1 if m < 55 else 0.8
    g = 10 ** (-3.0 / (f * t60))
    a = np.zeros(d + len(h))
    a[0] = 1.0
    a[d:d + len(h)] -= g * h
    r = np.random.RandomState(100 + m * 7 + variante)
    burst = r.uniform(-1, 1, int(periode))
    burst = signal.lfilter([0.5, 0.5], [1], burst)               # Plektrum etwas weicher
    pick = int(0.13 * len(burst))
    burst = burst - np.concatenate([np.zeros(pick), burst[:-pick]])  # Anschlagstelle
    x = np.zeros(n)
    x[:len(burst)] = burst
    y = signal.lfilter([1.0], a, x)
    y = signal.resample_poly(y, 1, os4)
    # Korpus: zwei weiche Resonanzen
    y = y + 0.6 * bandpass(y, 220, 380) + 0.3 * bandpass(y, 900, 1300)
    y = lowpass(y, 3200, 2)
    y = y / (np.max(np.abs(y)) + 1e-9)
    y *= adsr(len(y), 0.002, 0.5, 0.0, 0.25, lang - 0.4) * 0.7 + 0.3 * adsr(len(y), 0.002, 0.08, 0.0, 0.2, lang - 0.4)
    y = fade_kanten(y, 3)
    _zupf_cache[key] = y
    return y


def celesta(m, dauer=1.0, v=1.0):
    """Celesta / Spieluhr: Stahlplatte mit Filzhammer – Grundton, Oktave, leichte Inharmonie."""
    f = mtof(m)
    klang = max(2.2, dauer + 1.2)
    n = int(klang * SR)
    tt = np.arange(n) / SR
    teil = [(1.0, 1.0, 1.6), (2.0, 0.28, 0.7), (3.01, 0.07, 0.35), (4.18, 0.05, 0.18), (5.43, 0.025, 0.1)]
    s = np.zeros(n)
    for ratio, amp, dec in teil:
        fr = f * ratio
        if fr > 9000:
            continue
        s += amp * np.sin(2 * np.pi * fr * tt + rng.uniform(0, 6)) * np.exp(-tt / (dec * (1.4 - 0.3 * (m > 84))))
    # Filzhammer-Klopfen
    klick = lowpass(rng.randn(int(0.012 * SR)), 2500) * np.linspace(1, 0, int(0.012 * SR)) * 0.08
    s[:len(klick)] += klick
    s *= np.clip(tt / 0.003, 0, 1)
    # Abdämpfen nach Notenende (Pedal halb): sanfter Ausklang
    s *= np.where(tt > dauer + 0.6, np.exp(-(tt - dauer - 0.6) / 0.35), 1.0)
    s = lowpass(s, 6000, 1)
    return fade_kanten(s * v, 2)


def klarinette(m, dauer, v=1.0):
    """Klarinetten-artiger Ton: betonte ungerade Obertöne, Atemgeräusch, verzögertes Vibrato."""
    f = mtof(m)
    r = 0.18
    n = int((dauer + r * 5) * SR)
    tt = np.arange(n) / SR
    vib_tiefe = 0.0045 * np.clip((tt - 0.35) / 0.6, 0, 1)
    vib = 1 + vib_tiefe * np.sin(2 * np.pi * 5.1 * tt + rng.uniform(0, 6))
    glide = 1 - 0.006 * np.exp(-tt / 0.04)                       # kleiner Ansatz von unten
    ph = 2 * np.pi * np.cumsum(f * vib * glide) / SR
    e = adsr(n, 0.07, 0.3, 0.85, r, dauer)
    s = np.zeros(n)
    for k in range(1, 14):
        if f * k > 7000:
            break
        amp = (1.0 / k) if k % 2 else (0.12 / k)
        # höhere Obertöne erst mit voller Lautstärke (dynamische Helligkeit)
        s += amp * (e ** (1 + 0.25 * k)) * np.sin(k * ph)
    atem = bandpass(rng.randn(n), f * 1.5, min(f * 5, 9000)) * 0.035 * e
    s = s + atem
    s = lowpass(s, 2600, 2)
    return fade_kanten(s * v, 3)


def glocke(m, v=1.0):
    """Leise, tiefe Kirchenglocke für geheimnisvolle Akzente (Hum, Prime, Terz, Quinte, Nominal)."""
    f = mtof(m)
    n = int(7 * SR)
    tt = np.arange(n) / SR
    teil = [(0.5, 0.6, 4.5), (1.0, 1.0, 3.0), (1.19, 0.55, 2.2), (1.5, 0.3, 1.8),
            (2.0, 0.45, 1.5), (2.52, 0.18, 0.9), (3.0, 0.12, 0.7), (4.07, 0.06, 0.4)]
    s = np.zeros(n)
    for ratio, amp, dec in teil:
        for det in (-0.0015, 0.0015):          # Schwebung
            s += amp * np.sin(2 * np.pi * f * ratio * (1 + det) * tt + rng.uniform(0, 6)) * np.exp(-tt / dec)
    s *= np.clip(tt / 0.006, 0, 1)
    s = lowpass(s, 4000, 1)
    return fade_kanten(s * v / 4, 5)


def kick(v=1.0):
    """Weicher, gedämpfter Kick (Fellschlag mit Filzschlegel)."""
    n = int(0.45 * SR)
    tt = np.arange(n) / SR
    f = 46 + 44 * np.exp(-tt / 0.03)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.16)
    s += 0.15 * lowpass(rng.randn(n), 900) * np.exp(-tt / 0.01)
    return fade_kanten(lowpass(s, 220) * v, 2)


def tom(v=1.0, m=43):
    """Tiefe, gedämpfte Tom für den Spannungs-Puls."""
    n = int(0.6 * SR)
    tt = np.arange(n) / SR
    f0 = mtof(m)
    f = f0 * (1 + 0.25 * np.exp(-tt / 0.05))
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = (np.sin(ph) + 0.35 * np.sin(1.58 * ph)) * np.exp(-tt / 0.22)
    s += 0.2 * bandpass(rng.randn(n), 150, 900) * np.exp(-tt / 0.02)
    return fade_kanten(lowpass(s, 500) * v, 2)


def besen(v=1.0, lang=False):
    """Jazz-Besen: gefiltertes Rauschen mit weichem Wisch."""
    dur = 0.38 if lang else 0.16
    n = int(dur * SR)
    tt = np.arange(n) / SR
    a = 0.035 if lang else 0.006
    e = np.clip(tt / a, 0, 1) * np.exp(-np.maximum(tt - a, 0) / (0.12 if lang else 0.05))
    s = bandpass(rng.randn(n), 1800, 7000) * e
    return fade_kanten(lowpass(s, 6000) * v, 2)


def shaker(v=1.0):
    n = int(0.09 * SR)
    tt = np.arange(n) / SR
    e = np.clip(tt / 0.012, 0, 1) * np.exp(-tt / 0.03)
    s = highpass(rng.randn(n), 4500) * e
    return fade_kanten(lowpass(s, 9000) * v, 2)


def rueckwaerts_schwall(m, laenge=None):
    """Umgekehrter Glockenhall: schwillt geheimnisvoll an und endet genau auf dem Zielschlag."""
    laenge = laenge or BAR
    g = glocke(m, 1.0)
    g = np.concatenate([g, np.zeros(int(1 * SR))])
    ir = hall_ir(2.6, seed=5)[0]
    nass = signal.fftconvolve(g, ir)[: int(laenge * SR)]
    s = nass[::-1].copy()
    s += 0.25 * lowpass(rng.randn(len(s)), 2500) * np.linspace(0, 1, len(s)) ** 3
    s *= np.linspace(0, 1, len(s)) ** 1.5
    s = s / (np.max(np.abs(s)) + 1e-9)
    s[-int(0.03 * SR):] *= np.linspace(1, 0, int(0.03 * SR))
    return fade_kanten(s, 5)


# ---------------------------------------------------------------------------
# Hall
# ---------------------------------------------------------------------------

def hall_ir(rt60=2.2, seed=1):
    """Synthetische Raumantwort: dichtes Rauschen, das in den Höhen schneller abklingt."""
    r = np.random.RandomState(seed)
    n = int(rt60 * 1.3 * SR)
    tt = np.arange(n) / SR
    ir = np.zeros((2, n))
    for ch in (0, 1):
        roh = r.randn(n)
        tief = lowpass(roh, 900, 2) * np.exp(-6.9 * tt / rt60)
        hoch = highpass(roh, 900, 2) * np.exp(-6.9 * tt / (rt60 * 0.45))
        ir[ch] = tief + 0.6 * hoch
    vor = int(0.022 * SR)                              # Vorverzögerung
    ir = np.concatenate([np.zeros((2, vor)), ir], axis=1)
    ir *= np.clip(np.arange(ir.shape[1]) / (0.01 * SR), 0, 1)
    ir /= np.sqrt(np.sum(ir ** 2, axis=1, keepdims=True))
    return ir


# ---------------------------------------------------------------------------
# Partitur
# ---------------------------------------------------------------------------

# Abschnitte: Name, erster Takt, Taktanzahl
ABSCHNITTE = [("Intro", 0, 4), ("A1", 4, 8), ("A2", 12, 8), ("B", 20, 8), ("A3", 28, 8), ("Outro", 36, 4)]

# Akkorde: Bassnote (MIDI), Flächen-Voicing, Zupf-Töne
AKKORDE = {
    "Dm":   (38, [57, 62, 65], [50, 57, 62, 65]),
    "Dm/F": (41, [57, 62, 65], [50, 57, 62, 65]),
    "Bb":   (34, [58, 62, 65], [46, 53, 58, 62]),
    "Gm":   (43, [58, 62, 67], [43, 50, 55, 58]),
    "A":    (33, [57, 61, 64], [45, 52, 57, 61]),
    "A7":   (33, [55, 61, 64], [45, 52, 55, 61]),
    "Eb":   (39, [58, 63, 67], [51, 58, 63, 67]),
}

# Akkordfolgen (Akkord, Schläge)
FOLGE_INTRO = [("Dm", 4), ("Dm", 4), ("Bb", 4), ("A", 4)]
FOLGE_A = [("Dm", 4), ("Bb", 4), ("Gm", 4), ("A", 4), ("Dm", 4), ("Bb", 4), ("Gm", 2), ("A", 2), ("Dm", 4)]
FOLGE_B = [("Gm", 4), ("Dm/F", 4), ("Eb", 4), ("A", 4), ("Gm", 4), ("Dm/F", 4), ("Eb", 4), ("A7", 4)]
FOLGE_OUTRO = [("Bb", 4), ("Gm", 4), ("Dm", 4), ("A", 4)]
FOLGE = FOLGE_INTRO + FOLGE_A + FOLGE_A + FOLGE_B + FOLGE_A + FOLGE_OUTRO

# Melodien: je Takt Liste aus (Note, Schlag, Dauer in Schlägen) – eigene Komposition
MEL_A = [
    [("A4", 0, 1.5), ("D5", 1.5, 0.5), ("F5", 2, 1), ("E5", 3, 1)],
    [("D5", 0, 2), ("C5", 2, 0.5), ("Bb4", 2.5, 0.5), ("A4", 3, 1)],
    [("G4", 0, 1.5), ("Bb4", 1.5, 0.5), ("D5", 2, 1), ("Eb5", 3, 1)],
    [("C#5", 0, 1.5), ("E5", 1.5, 0.5), ("A4", 2, 2)],
    [("A4", 0, 1.5), ("D5", 1.5, 0.5), ("F5", 2, 1), ("A5", 3, 1)],
    [("G5", 0, 1.5), ("F5", 1.5, 0.5), ("E5", 2, 1), ("D5", 3, 1)],
    [("Bb4", 0, 1), ("D5", 1, 1), ("C#5", 2, 1), ("E5", 3, 0.5), ("C#5", 3.5, 0.5)],
    [("D5", 0, 3)],
]
# Variation für A3 (zweite Hälfte steigt höher und endet lang)
MEL_A3 = MEL_A[:4] + [
    [("A4", 0, 1.5), ("D5", 1.5, 0.5), ("F5", 2, 1), ("A5", 3, 1)],
    [("Bb5", 0, 1.5), ("A5", 1.5, 0.5), ("G5", 2, 1), ("F5", 3, 1)],
    [("D5", 0, 1), ("G5", 1, 1), ("E5", 2, 1), ("C#5", 3, 1)],
    [("D5", 0, 4)],
]
MEL_B = [
    [("Bb4", 0, 2), ("A4", 2, 1), ("G4", 3, 1)],
    [("F4", 0, 3), ("A4", 3, 1)],
    [("G4", 0, 1.5), ("Bb4", 1.5, 0.5), ("Eb5", 2, 2)],
    [("D5", 0, 1), ("C#5", 1, 3)],
    [("D5", 0, 1.5), ("Bb4", 1.5, 0.5), ("G5", 2, 2)],
    [("F5", 0, 1.5), ("E5", 1.5, 0.5), ("D5", 2, 1), ("A4", 3, 1)],
    [("Bb4", 0, 1), ("Eb5", 1, 1), ("D5", 2, 1), ("C5", 3, 1)],
    [("Bb4", 0, 1), ("A4", 1, 3)],
]
# Kleine Celesta-Erinnerung an das Motiv im Outro
MEL_OUTRO = [
    [("A5", 2, 1), ("D6", 3, 1)],
    [],
    [("A5", 0, 1.5), ("D6", 1.5, 0.5), ("F6", 2, 2)],
    [("E6", 2, 1), ("C#6", 3, 1)],
]

# Zupf-Muster (Index in die Zupf-Töne), je 8 Achtel
MUSTER_A = [0, 1, 2, 1, 3, 1, 2, 1]
MUSTER_B = [0, 1, 2, 0, 1, 3, 0, 2]          # 3+3+2-Akzent
AKZENT_A = [1.0, 0.55, 0.7, 0.55, 0.85, 0.55, 0.7, 0.6]
AKZENT_B = [1.0, 0.5, 0.6, 0.9, 0.5, 0.6, 0.9, 0.55]

# Automation je Taktanfang (wird linear interpoliert; Wert bei Takt 40 = Takt 0 → Loop)
AUTO = {
    #           Intro            A1                       A2                       B                                 A3                       Outro
    "flaeche": [0.55] * 4 + [0.75] * 8 + [0.8] * 8 + [1.0, 1.0, 1.05, 1.1, 1.15, 1.2, 1.25, 1.2] + [0.9] * 8 + [0.8, 0.7, 0.6, 0.55],
    "zupf":    [0.8] * 4 + [0.85] * 8 + [0.9] * 8 + [1.0] * 8 + [0.9] * 8 + [0.85, 0.85, 0.8, 0.8],
}


def akkord_zeitleiste():
    """Akkorde als (Start-s, Dauer-s, Name); gleiche Nachbarn werden zusammengefasst."""
    leiste = []
    beat = 0.0
    for name, schlaege in FOLGE:
        if leiste and leiste[-1][2] == name:
            leiste[-1][1] += schlaege * BEAT
        else:
            leiste.append([beat * BEAT, schlaege * BEAT, name])
        beat += schlaege
    assert abs(beat - BARS * 4) < 1e-9, beat
    return leiste


def akkord_bei_takt(bar, beat=0.0):
    pos = bar * 4 + beat
    b = 0.0
    for name, schlaege in FOLGE:
        if b <= pos < b + schlaege:
            return name
        b += schlaege
    return FOLGE[-1][0]


def automation(name):
    """Hüllkurve über die ganze Loop-Länge (+ Überhang, der wieder bei Takt 0 beginnt)."""
    werte = np.array(AUTO[name] + [AUTO[name][0]])
    assert len(werte) == BARS + 1
    x = np.arange(NTOT) / SR
    x_loop = np.mod(x, BARS * BAR)
    return np.interp(x_loop, np.arange(BARS + 1) * BAR, werte)


def spiele_melodie(bus, takte, start_bar, instrument, transponiere=0, gain=1.0, pan=0.0):
    for i, takt in enumerate(takte):
        for note, beat, dauer in takt:
            t = human(zeit(start_bar + i, beat), 9)
            m = midi(note) + transponiere
            if instrument == "celesta":
                snd = celesta(m, dauer * BEAT, vel(1.0, 0.12))
            else:
                snd = klarinette(m, dauer * BEAT * 0.97, vel(1.0, 0.08))
            # Phrasenanfänge (Schlag 0) leicht betont
            g = gain * (1.08 if beat == 0 else 1.0)
            bus.add(snd, max(t, 0), g, pan)


# ---------------------------------------------------------------------------
# Arrangement
# ---------------------------------------------------------------------------

def arrangieren():
    busse = {
        "bordun":  Bus("bordun", 0.09, hall=0.15),
        "flaeche": Bus("flaeche", 0.26, hall=0.45),
        "zupf":    Bus("zupf", 0.85, hall=0.28),
        "celesta": Bus("celesta", 0.21, hall=0.45),
        "klar":    Bus("klar", 0.21, hall=0.35),
        "perk":    Bus("perk", 0.30, hall=0.18),
        "akzent":  Bus("akzent", 0.20, hall=0.6),
    }

    # --- Bordun und Fläche folgen den Akkorden
    for start, dauer, name in akkord_zeitleiste():
        bass, voicing, _ = AKKORDE[name]
        busse["bordun"].add(bordun(bass, dauer), start, 1.0)
        busse["bordun"].add(bordun(bass + 7 if bass < 40 else bass - 5, dauer), start, 0.35)
        busse["flaeche"].add(flaeche(voicing, dauer), start, 1.0)

    # --- Zupf-Ostinato (Achtel)
    for bar in range(BARS):
        teil = abschnitt(bar)
        muster, akzent = (MUSTER_B, AKZENT_B) if teil == "B" else (MUSTER_A, AKZENT_A)
        for achtel in range(8):
            beat = achtel * 0.5
            name = akkord_bei_takt(bar, beat)
            toene = AKKORDE[name][2]
            v = akzent[achtel]
            if teil == "Intro" and bar < 2 and achtel % 2:
                v *= 0.6                                    # Intro beginnt zurückhaltend
            m = toene[muster[achtel]]
            pan = -0.25 + 0.1 * (muster[achtel] - 1.5)
            busse["zupf"].add(zupf(m, rng.randint(3)), human(zeit(bar, beat), 6), vel(v, 0.12), pan)
            # im B-Teil: leise Oktav-Doppelung auf den Akzenten (Domra-Tremolo-Anmutung)
            if teil == "B" and achtel in (0, 3, 6) and bar >= 24:
                busse["zupf"].add(zupf(m + 12, rng.randint(3)), human(zeit(bar, beat), 6) + 0.012, vel(0.3), 0.35)

    # --- Melodien
    spiele_melodie(busse["celesta"], MEL_A, 4, "celesta", 0, 1.0, 0.1)
    spiele_melodie(busse["klar"], MEL_A, 12, "klar", -12, 1.1, -0.1)
    # Celesta antwortet in A2 oben: absteigende Akkordtöne in den "Antwort"-Takten
    for i in (1, 3, 5, 7):
        bar = 12 + i
        name = akkord_bei_takt(bar, 2)
        tones = sorted(AKKORDE[name][1], reverse=True)
        for j, b in enumerate((2.0, 2.5, 3.0)):
            m = tones[j % len(tones)] + 24
            busse["celesta"].add(celesta(m, 0.6, vel(0.55)), human(zeit(bar, b), 8), 1.0, 0.35)
    spiele_melodie(busse["klar"], MEL_B, 20, "klar", 0, 0.95, -0.05)
    # in der zweiten B-Hälfte doppelt die Celesta die Klarinette eine Oktave höher, leise
    spiele_melodie(busse["celesta"], MEL_B[4:], 24, "celesta", 12, 0.35, 0.3)
    spiele_melodie(busse["celesta"], MEL_A3, 28, "celesta", 0, 1.0, 0.1)
    spiele_melodie(busse["klar"], MEL_A3, 28, "klar", -12, 0.75, -0.15)
    spiele_melodie(busse["celesta"], MEL_OUTRO, 36, "celesta", 0, 0.55, 0.25)

    # --- Perkussion
    p = busse["perk"]
    for bar in range(BARS):
        teil = abschnitt(bar)
        if teil in ("Intro", "Outro"):
            stufe = {0: 0.0, 1: 0.0, 2: 0.4, 3: 0.55}[bar] if teil == "Intro" else [0.7, 0.55, 0.4, 0.0][bar - 36]
            if stufe > 0:
                p.add(kick(vel(0.8 * stufe)), human(zeit(bar), 4), 1.0)
                p.add(besen(vel(0.25 * stufe), True), human(zeit(bar, 3), 8), 1.0, 0.3)
            continue
        p.add(kick(vel(0.85)), human(zeit(bar), 4), 1.0)
        if bar % 2 == 1 and teil != "B":
            p.add(kick(vel(0.4)), human(zeit(bar, 3.5), 4), 1.0)       # leiser Auftakt
        for b in (1, 3):
            p.add(besen(vel(0.35), True), human(zeit(bar, b), 8), 1.0, 0.3)
        if teil in ("A2", "A3", "B"):
            for achtel in range(8):
                v = 0.22 if achtel % 2 else 0.12
                p.add(shaker(vel(v, 0.25)), human(zeit(bar, achtel * 0.5), 6), 1.0, -0.4)
        if teil == "B":
            p.add(kick(vel(0.6)), human(zeit(bar, 2), 4), 1.0)
            k = bar - 20
            stark = 0.25 + 0.6 * k / 7                                  # Tom-Puls schwillt an
            for b in range(4):
                p.add(tom(vel(stark * (1.0 if b == 0 else 0.7))), human(zeit(bar, b), 5), 1.0, -0.15)
            if k >= 4:
                for b in (3.5,) if k < 6 else (2.5, 3.5):
                    p.add(tom(vel(stark * 0.55), 40), human(zeit(bar, b), 5), 1.0, 0.15)

    # --- Akzente: Glocken und rückwärts laufende Schwälle
    a = busse["akzent"]
    for bar, note, v in ((0, "D3", 0.8), (12, "A2", 0.55), (20, "G2", 0.75), (24, "Eb3", 0.5), (28, "D3", 0.8)):
        a.add(glocke(midi(note), v), zeit(bar), 1.0, -0.2)
    for ziel, note in ((12, "A4"), (20, "D5"), (28, "A4"), (BARS, "A4")):
        s = rueckwaerts_schwall(midi(note), BAR)
        a.add(s, zeit(ziel) - BAR, 0.5, 0.25)

    # Automation anwenden
    busse["flaeche"].buf *= automation("flaeche")
    busse["zupf"].buf *= automation("zupf")
    return busse


def abschnitt(bar):
    for name, start, laenge in ABSCHNITTE:
        if start <= bar < start + laenge:
            return name
    return ABSCHNITTE[-1][0]


# ---------------------------------------------------------------------------
# Mischung und Mastering
# ---------------------------------------------------------------------------

def mischen(busse):
    trocken = np.zeros((2, NTOT))
    hall_send = np.zeros((2, NTOT))
    for b in busse.values():
        trocken += b.gain * b.buf
        hall_send += b.gain * b.hall * b.buf
    ir = hall_ir(2.3, seed=11)
    nass = np.zeros((2, NTOT + ir.shape[1] - 1))
    for ch in (0, 1):
        nass[ch] = signal.oaconvolve(hall_send[ch], ir[ch])
    nass = highpass(nass, 120, 1)                      # Hall nicht im Bass matschen lassen
    mix = np.zeros((2, nass.shape[1]))
    mix[:, :NTOT] += trocken
    mix += nass * 0.9
    return falten(mix)


def falten(x):
    """Alles hinter dem Loop-Ende wird auf den Anfang addiert → nahtloser Übergang."""
    loop = x[:, :LOOP_LEN].copy()
    rest = x[:, LOOP_LEN:]
    while rest.shape[1] > 0:
        n = min(rest.shape[1], LOOP_LEN)
        loop[:, :n] += rest[:, :n]
        rest = rest[:, n:]
    return loop


def master(x):
    """Sanftes Mastering: Hochpass, zirkulärer RMS-Kompressor, weicher Limiter, Peak −1 dBFS."""
    # zirkulärer Hochpass: dreimal hintereinander gelegt filtern, die Mitte nehmen
    drei = np.concatenate([x, x, x], axis=1)
    drei = highpass(drei, 32, 2)
    # leichte Höhenabsenkung gegen Schärfe
    drei = drei - 0.15 * highpass(drei, 6000, 1)
    x = drei[:, LOOP_LEN:2 * LOOP_LEN]

    # Kompressor (2:1 über Schwelle, RMS 80 ms, zirkulär geglättet)
    mono = np.mean(x ** 2, axis=0)
    rms = np.sqrt(uniform_filter1d(mono, int(0.08 * SR), mode="wrap") + 1e-12)
    db = 20 * np.log10(rms)
    schwelle = np.percentile(db, 85)
    gr_db = np.where(db > schwelle, -(db - schwelle) * 0.5, 0.0)
    gr = 10 ** (uniform_filter1d(gr_db, int(0.2 * SR), mode="wrap") / 20)
    x = x * gr

    # weicher Limiter (tanh rundet nur die obersten Spitzen ab), danach Peak auf −1,5 dBFS
    # (Vorbis überschwingt beim Dekodieren um ca. 0,4 dB → im Spiel ≈ −1 dBFS)
    x = x / np.max(np.abs(x)) * 1.1
    x = np.tanh(x)
    return x / np.max(np.abs(x)) * 10 ** (-1.5 / 20)


def schreiben(x):
    os.makedirs(OUT_DIR, exist_ok=True)
    pcm = np.clip(x.T, -1, 1)
    pcm16 = (pcm * 32767).astype("<i2")
    import wave
    with wave.open(TMP_WAV, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm16.tobytes())
    ffmpeg = shutil.which("ffmpeg") or "/usr/local/bin/ffmpeg"
    subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-i", TMP_WAV,
                    "-c:a", "libvorbis", "-q:a", "5", OUT_OGG], check=True)


def main():
    print("Arrangiere …")
    busse = arrangieren()
    for b in busse.values():
        r = np.sqrt(np.mean((b.gain * b.buf) ** 2))
        print(f"  {b.name:8s} RMS {20 * np.log10(r + 1e-12):6.1f} dB  Peak {np.max(np.abs(b.gain * b.buf)):.3f}")
    print("Mische und mastere …")
    x = master(mischen(busse))
    print(f"  Länge {x.shape[1] / SR:.2f} s, Peak {20 * np.log10(np.max(np.abs(x))):.2f} dBFS, "
          f"RMS {20 * np.log10(np.sqrt(np.mean(x ** 2))):.1f} dBFS")
    schreiben(x)
    print("Fertig:", OUT_OGG)


if __name__ == "__main__":
    main()
