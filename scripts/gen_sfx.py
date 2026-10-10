#!/usr/bin/env python3
"""Render the synth sound effects of the web version (src/core/Audio.ts) to WAV files for Godot.

One-shots are rendered as they sounded in Web Audio; the continuous sounds (engine, scrape, squeal,
siren) become seamless loops that the game pitches and filters live on its own audio buses.

    python3 scripts/gen_sfx.py      # writes godot/assets/sfx/*.wav
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'godot', 'assets', 'sfx')
rng = np.random.default_rng(35)


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def exp_ramp(a, b, sec, n):
    """Web Audio exponentialRampToValueAtTime from a to b over `sec`, held after."""
    t = np.arange(n) / SR
    k = np.clip(t / sec, 0, 1)
    return a * (b / a) ** k


def saw(phase):
    return 2 * (phase % 1.0) - 1


def square(phase):
    return np.where(phase % 1.0 < 0.5, 1.0, -1.0)


def tri(phase):
    return 2 * np.abs(2 * (phase % 1.0) - 1) - 1


def phase_of(freq):
    return np.cumsum(freq) / SR


def lowpass(x, cutoff, q=0.707):
    """Biquad low-pass with a (possibly time-varying) cutoff, like a BiquadFilterNode."""
    return _biquad(x, cutoff, q, 'low')


def bandpass(x, cutoff, q=1.0):
    return _biquad(x, cutoff, q, 'band')


def _biquad(x, cutoff, q, kind):
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), x.shape)
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        w0 = 2 * np.pi * min(cutoff[i], SR * 0.45) / SR
        alpha = np.sin(w0) / (2 * q)
        cw = np.cos(w0)
        if kind == 'low':
            b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
        else:
            b0, b1, b2 = alpha, 0.0, -alpha
        a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
        yi = (b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1 = x1, x[i]
        y2, y1 = y1, yi
        y[i] = yi
    return y


def write(name, x, peak=0.9):
    x = np.asarray(x, dtype=float)
    m = np.max(np.abs(x)) or 1
    x = x / m * peak
    data = (x * 32767).astype('<i2').tobytes()
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print(f'{name}.wav  {len(x) / SR:.2f}s')


def crash():
    n = int(SR * 0.8)
    noise = rng.uniform(-1, 1, n)
    # playbackRate 0.6-0.9 on the noise buffer: darker noise
    noise = lowpass(noise, 9000)
    cut = exp_ramp(3500, 300, 0.4, n)
    body = lowpass(noise, cut) * exp_ramp(0.9, 0.001, 0.65, n)
    t = t_axis(0.8)
    thump = np.sin(2 * np.pi * phase_of(exp_ramp(120, 40, 0.2, n))) * exp_ramp(0.8, 0.001, 0.25, n)
    thump[t > 0.3] = 0
    return body + thump


def whoosh():
    n = int(SR * 0.35)
    noise = rng.uniform(-1, 1, n)
    f = bandpass(noise, exp_ramp(400, 2500, 0.2, n), 1.5)
    t = t_axis(0.35)
    env = np.where(t < 0.06, exp_ramp(0.0001, 0.4, 0.06, n), 0.4 * (0.001 / 0.4) ** np.clip((t - 0.06) / 0.24, 0, 1))
    return f * env


def beep(high):
    sec = 0.7
    n = int(SR * sec)
    f = 1320 if high else 660
    env = exp_ramp(0.18, 0.001, 0.6 if high else 0.25, n)
    return square(np.full(n, f) * t_axis(sec)) * env


def chime():
    n = int(SR * 0.6)
    out = np.zeros(n)
    t = t_axis(0.6)
    for i, f in enumerate([660, 880, 1320]):
        t0 = i * 0.08
        k = t - t0
        env = np.where(k < 0, 0, np.where(k < 0.02, 0.0001 * (0.25 / 0.0001) ** np.clip(k / 0.02, 0, 1),
                                          0.25 * (0.001 / 0.25) ** np.clip((k - 0.02) / 0.33, 0, 1)))
        env[k > 0.4] = 0
        out += tri(f * np.maximum(k, 0)) * env
    return out


def horn(truck):
    sec = 0.9 if truck else 0.45
    n = int(SR * sec)
    t = t_axis(sec)
    x = sum(square(f * t) for f in ([155, 196] if truck else [392, 494]))
    x = lowpass(x, 900 if truck else 1800)
    env = np.minimum(1, t / 0.03) * np.minimum(1, (sec - t) / 0.05)
    return x * env


def flash():
    n = int(SR * 0.25)
    x = np.sin(2 * np.pi * phase_of(exp_ramp(2400, 900, 0.15, n)))
    return x * exp_ramp(0.25, 0.001, 0.2, n)


def engine_loop():
    # Two detuned saws (0 and ~9 cents) and a square an octave down, at 100 Hz: the game sets
    # pitch_scale = rpm frequency / 100. 2 s holds whole cycles of every partial, so it loops cleanly.
    t = t_axis(2.0)
    x = 0.35 * saw(100 * t) + 0.3 * saw(100.5 * t) + 0.25 * square(50 * t)
    return lowpass(x, 3000)


def noise_loop():
    n = int(SR * 2)
    x = rng.uniform(-1, 1, n)
    # Crossfade the ends so the loop has no click.
    f = int(SR * 0.05)
    x[:f] = x[:f] * np.linspace(0, 1, f) + x[-f:] * np.linspace(1, 0, f)
    return x[:-f]


def siren_loop():
    # Two-tone: 520 Hz ± 85 Hz switched by a 0.85 Hz square LFO, through a 2.2 kHz low-pass.
    period = 1 / 0.85
    t = t_axis(period)
    f = np.where(t < period / 2, 605.0, 435.0)
    x = saw(phase_of(f))
    return lowpass(x, 2200)


if __name__ == '__main__':
    write('crash', crash())
    write('whoosh', whoosh())
    write('beep_lo', beep(False), 0.5)
    write('beep_hi', beep(True), 0.5)
    write('chime', chime(), 0.6)
    write('horn_car', horn(False), 0.5)
    write('horn_truck', horn(True), 0.5)
    write('flash', flash(), 0.5)
    write('engine', engine_loop(), 0.8)
    write('noise', noise_loop(), 0.8)
    write('siren', siren_loop(), 0.8)
