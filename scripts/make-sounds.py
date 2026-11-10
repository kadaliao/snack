#!/usr/bin/env python3
"""make-sounds.py writes the app's sound effects into Snack/Sounds: soft bell
tones made from sines, so there is nothing to license. Run it again after
changing a sound."""
import math, os, struct, wave

RATE = 44100
here = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Snack', 'Sounds')

def note(freq, start, length, volume=0.5, decay=6.0, partials=((1, 1.0), (2, 0.35), (3, 0.12))):
    """A bell-like note: a few partials, a quick attack, then dying away."""
    return (freq, start, length, volume, decay, partials)

def render(name, notes, total):
    samples = [0.0] * int(RATE * total)
    for freq, start, length, volume, decay, partials in notes:
        first = int(RATE * start)
        for i in range(int(RATE * length)):
            t = i / RATE
            envelope = min(1.0, t / 0.004) * math.exp(-decay * t)
            value = sum(a * math.sin(2 * math.pi * freq * k * t) for k, a in partials)
            if first + i < len(samples):
                samples[first + i] += volume * envelope * value
    peak = max(abs(s) for s in samples) or 1
    scale = 0.6 / peak
    with wave.open(os.path.join(here, name), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(s * scale * 32767)) for s in samples))

os.makedirs(here, exist_ok=True)
# Right: two notes going up.
render('right.wav', [note(1318.5, 0, 0.35, decay=9), note(1760.0, 0.08, 0.45, decay=7)], 0.55)
# Wrong: two low notes going down, muffled.
soft = ((1, 1.0), (2, 0.15))
render('wrong.wav', [note(311.1, 0, 0.3, decay=8, partials=soft), note(233.1, 0.12, 0.4, decay=7, partials=soft)], 0.55)
# Done: a chord rolled up.
render('done.wav', [note(f, i * 0.09, 1.2, decay=3.5) for i, f in enumerate([523.3, 659.3, 784.0, 1046.5])], 1.5)
print('written to', os.path.normpath(here))
