"""make_sound.py - generate Media/dispel.ogg, the "something to dispel" alert.

Generated, never hand-edited: change this file and rerun it.
    python Tools/make_sound.py

A short two-note glass chime (E6 then B6, soft attack, exponential decay,
a quiet octave partial for shimmer). WoW plays addon-shipped .ogg files
through PlaySoundFile (measured on 69977, porting guide). Needs numpy and
ffmpeg with libvorbis on PATH.
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

RATE = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media", "dispel.ogg")


def note(freq, start, length, total):
    t = np.arange(int(length * RATE)) / RATE
    env = np.minimum(t / 0.006, 1.0) * np.exp(-t * 7.0)
    tone = np.sin(2 * np.pi * freq * t) + 0.25 * np.sin(2 * np.pi * freq * 2 * t)
    out = np.zeros(total)
    i = int(start * RATE)
    out[i:i + len(t)] = (tone * env)[: total - i]
    return out


def main():
    total = int(0.6 * RATE)
    signal = note(1318.5, 0.0, 0.45, total) + note(1975.5, 0.11, 0.49, total)
    signal = signal / np.max(np.abs(signal)) * 0.7
    pcm = (signal * 32767).astype(np.int16)

    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "dispel.wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav,
                        "-c:a", "libvorbis", "-q:a", "5", OUT], check=True)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
