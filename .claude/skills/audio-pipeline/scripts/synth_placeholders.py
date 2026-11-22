"""
Synthesize EMP Escape's placeholder sounds (mono, 44.1 kHz, 16-bit WAV) with numpy only.
Usage (from the project root):  python3 .claude/skills/audio-pipeline/scripts/synth_placeholders.py [out_dir]
Default out_dir: Assets/EMPEscape/Resources/Audio
Real recordings replace these by using the same file name (any of .wav/.ogg/.mp3; delete the placeholder).
Pass --only name1,name2 to regenerate some; existing files not in the list are left alone.
"""
import os
import sys
import wave
import numpy as np

SR = 44100
rng = np.random.default_rng(7)


# ---------- building blocks ----------

def t(seconds):
    return np.arange(int(SR * seconds)) / SR


def white(seconds):
    return rng.standard_normal(int(SR * seconds))


def band(x, lo=None, hi=None, order=4):
    """Zero-phase band filter in the frequency domain with soft Butterworth-like edges."""
    n = len(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    h = np.ones_like(f)
    if hi is not None:
        h /= np.sqrt(1 + (f / hi) ** (2 * order))
    if lo is not None:
        with np.errstate(divide="ignore"):
            h /= np.sqrt(1 + (lo / np.maximum(f, 1e-6)) ** (2 * order))
    return np.fft.irfft(np.fft.rfft(x) * h, n)


def env_exp(n, decay, attack=0.002):
    tt = np.arange(n) / SR
    a = np.clip(tt / max(attack, 1e-6), 0, 1)
    return a * np.exp(-tt / decay)


def smooth_random(seconds, rate, lo=0.0, hi=1.0):
    """Slowly varying random curve (for gusts, flicker)."""
    points = max(2, int(seconds * rate) + 2)
    knots = rng.uniform(lo, hi, points)
    x = np.linspace(0, points - 1, int(SR * seconds))
    i = np.floor(x).astype(int)
    frac = x - i
    frac = frac * frac * (3 - 2 * frac)
    return knots[i] * (1 - frac) + knots[np.minimum(i + 1, points - 1)] * frac


def tone(freq, seconds, decay=None, phase_mod=None):
    tt = t(seconds)
    if callable(freq):
        f = freq(tt)
        sig = np.sin(2 * np.pi * np.cumsum(f) / SR)
    else:
        sig = np.sin(2 * np.pi * freq * tt)
    if decay:
        sig *= env_exp(len(sig), decay)
    return sig


def reverb(x, seconds=1.0, decay=0.35, mix=0.25, bright=4000):
    ir = band(white(seconds), hi=bright) * np.exp(-t(seconds) / decay)
    ir /= np.max(np.abs(ir)) + 1e-9
    n = len(x) + len(ir)
    wet = np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)
    wet /= np.max(np.abs(wet)) + 1e-9
    dry = np.concatenate([x, np.zeros(len(ir))])
    dry /= np.max(np.abs(dry)) + 1e-9
    return dry * (1 - mix) + wet * mix


def place(buffer, sound, at_seconds, gain=1.0):
    start = int(at_seconds * SR)
    end = min(len(buffer), start + len(sound))
    buffer[start:end] += sound[: end - start] * gain


def make_loop(x, fade=1.0):
    """Crossfade the tail into the head so the clip loops without a seam."""
    k = int(fade * SR)
    head, body, tail = x[:k], x[k:-k], x[-k:]
    ramp = np.linspace(0, 1, k)
    seam = tail * (1 - ramp) + head * ramp
    return np.concatenate([body, seam])


def fade_out(x, seconds=0.02):
    k = min(len(x), int(seconds * SR))
    x = x.copy()
    x[-k:] *= np.linspace(1, 0, k)
    return x


def finish(x, peak_db=-3.0, loop=False):
    x = x - np.mean(x)
    x = x / (np.max(np.abs(x)) + 1e-9) * (10 ** (peak_db / 20))
    return x if loop else fade_out(x, 0.01)  # a fade at the end of a loop would click at the seam


# ---------- sounds ----------

def amb_wind():
    s = 24
    brown = np.cumsum(white(s))
    brown = band(brown, lo=20, hi=500)
    gust = smooth_random(s, 0.35, 0.25, 1.0)
    whistle = band(white(s), lo=500, hi=1400) * smooth_random(s, 0.5, 0.0, 1.0) ** 2 * 0.35
    x = brown / np.max(np.abs(brown)) * gust + whistle / (np.max(np.abs(whistle)) + 1e-9) * 0.25
    return finish(make_loop(x, 2.0), -6, loop=True)


def chirp(f0, f1, seconds):
    return tone(lambda tt: f0 + (f1 - f0) * (tt / seconds), seconds) * np.sin(np.pi * t(seconds) / seconds) ** 2


def amb_birds():
    s = 22
    x = np.zeros(int(SR * s))
    for _ in range(9):
        at = rng.uniform(1.0, s - 3.0)
        base = rng.uniform(2400, 3600)
        for k in range(rng.integers(2, 5)):
            c = chirp(base, base * rng.uniform(1.2, 1.5), rng.uniform(0.05, 0.09))
            place(x, c, at + k * rng.uniform(0.09, 0.14), rng.uniform(0.4, 1.0))
    x = reverb(x, 1.2, 0.4, 0.35, 6000)[: int(SR * s)]
    return finish(make_loop(x, 1.0), -10, loop=True)


def fire_crackle():
    s = 10
    rumble = band(white(s), hi=250) * smooth_random(s, 3, 0.6, 1.0)
    x = rumble / np.max(np.abs(rumble)) * 0.35
    for at in np.cumsum(rng.exponential(0.09, 200)):
        if at > s - 0.05:
            break
        n = int(rng.uniform(0.002, 0.012) * SR)
        click = band(rng.standard_normal(n), lo=1500) * env_exp(n, rng.uniform(0.002, 0.006))
        place(x, click, at, rng.uniform(0.2, 1.0))
    return finish(make_loop(x, 0.5), -6, loop=True)


def distant_shot():
    crack = band(white(0.03), hi=1500) * env_exp(int(0.03 * SR), 0.01)
    boom = tone(lambda tt: 70 - 30 * tt, 0.4, decay=0.12)
    x = np.zeros(int(SR * 0.5))
    place(x, crack, 0, 1.0)
    place(x, boom, 0, 0.8)
    x = reverb(band(x, hi=1200), 2.2, 0.7, 0.6, 1500)
    return finish(x, -6)


def distant_crash():
    s = 1.6
    metal = sum(tone(f, s, decay=rng.uniform(0.3, 0.8)) * g for f, g in [(310, 1), (523, .7), (790, .5), (1210, .35)])
    hit = band(white(0.08), hi=2000) * env_exp(int(0.08 * SR), 0.03)
    x = np.zeros(int(SR * s))
    place(x, hit, 0, 1.0)
    place(x, metal, 0.005, 0.6)
    x = reverb(band(x, hi=1800), 2.0, 0.6, 0.55, 2000)
    return finish(x, -6)


def step(seed):
    r = np.random.default_rng(seed)
    n = int(0.12 * SR)
    scuff = band(r.standard_normal(n), lo=r.uniform(250, 400), hi=r.uniform(2500, 4000)) * env_exp(n, r.uniform(0.015, 0.03))
    thump = tone(r.uniform(80, 110), 0.12, decay=0.025)
    return finish(scuff * 0.8 + thump * 0.6, -4)


def ui_tap():
    x = tone(1800, 0.04, decay=0.008) + band(white(0.04), lo=3000) * env_exp(int(0.04 * SR), 0.002) * 0.3
    return finish(x, -8)


def blips(freqs, gap=0.07, length=0.06, decay=0.03):
    x = np.zeros(int(SR * (gap * len(freqs) + length)))
    for i, f in enumerate(freqs):
        place(x, tone(f, length, decay=decay), i * gap)
    return x


def ui_open():
    return finish(blips([660, 880, 1320]), -8)


def ui_close():
    return finish(blips([1320, 880, 660]), -10)


def ui_type():
    return finish(band(white(0.012), lo=2500) * env_exp(int(0.012 * SR), 0.002), -16)


def device_beep():
    return finish(blips([1046, 1568], gap=0.09, length=0.08, decay=0.05), -9)


def device_error():
    return finish(blips([330, 330], gap=0.14, length=0.11, decay=0.2), -8)


def bell(f, seconds=1.4):
    return sum(tone(f * m, seconds, decay=d) * g for m, d, g in [(1, 0.6, 1), (2.01, 0.3, .4), (3.03, 0.15, .2)])


def remember_chime():
    x = np.zeros(int(SR * 1.8))
    place(x, bell(659), 0)
    place(x, bell(988), 0.16, 0.8)
    return finish(reverb(x, 1.0, 0.35, 0.25)[: int(SR * 2.2)], -9)


def qte_press():
    return finish(tone(lambda tt: 300 - 800 * tt, 0.05, decay=0.015) + band(white(0.05), lo=1000) * env_exp(int(0.05 * SR), 0.004) * 0.4, -8)


def qte_success():
    return finish(reverb(blips([523, 659, 784, 1046], gap=0.06, length=0.18, decay=0.12), 0.6, 0.25, 0.2), -8)


def qte_fail():
    x = tone(lambda tt: 220 - 120 * tt / 0.5, 0.5, decay=0.25) + tone(70, 0.5, decay=0.12) * 0.8
    return finish(x, -6)


def gunshot():
    x = np.zeros(int(SR * 0.6))
    place(x, white(0.006) * env_exp(int(0.006 * SR), 0.002), 0, 1.0)
    place(x, band(white(0.08), lo=800, hi=7000) * env_exp(int(0.08 * SR), 0.018), 0, 0.9)
    place(x, tone(lambda tt: 110 - 120 * tt, 0.3, decay=0.06), 0, 0.9)
    return finish(reverb(x, 1.0, 0.3, 0.3, 5000), -1)


def target_hit():
    s = 0.6
    ping = sum(tone(f, s, decay=d) * g for f, d, g in [(1820, .25, 1), (2730, .15, .6), (4110, .08, .4)])
    click = band(white(0.01), lo=2000) * env_exp(int(0.01 * SR), 0.002)
    x = np.zeros(int(SR * s))
    place(x, click, 0, 0.8)
    place(x, ping, 0, 0.7)
    return finish(x, -5)


def whoosh(seconds, lo_band, hi_band, peak=0.45):
    n = int(seconds * SR)
    pos = np.linspace(0, 1, n)
    shape = np.exp(-((pos - peak) ** 2) / 0.03)
    low = band(rng.standard_normal(n), *lo_band)
    high = band(rng.standard_normal(n), *hi_band)
    mix = np.clip((pos - 0.2) / 0.4, 0, 1)
    return (low * (1 - mix * 0.7) + high * mix) * shape


def swing_whoosh():
    return finish(whoosh(0.32, (200, 700), (700, 2200)), -6)


def knife_slash():
    x = whoosh(0.2, (600, 1600), (1600, 5000), 0.4)
    scrape = band(white(0.06), lo=3000, hi=8000) * env_exp(int(0.06 * SR), 0.02)
    place(x, scrape, 0.1, 0.5)
    return finish(x, -6)


def hit_flesh():
    x = tone(lambda tt: 95 - 60 * tt, 0.16, decay=0.05) + band(white(0.16), hi=900) * env_exp(int(0.16 * SR), 0.025) * 0.7
    return finish(x, -3)


def door_bang():
    s = 1.0
    x = np.zeros(int(SR * s))
    place(x, tone(lambda tt: 75 - 20 * tt, 0.4, decay=0.1), 0, 1.0)
    place(x, band(white(0.15), lo=180, hi=1500) * env_exp(int(0.15 * SR), 0.04), 0, 0.9)
    for k in range(6):
        click = band(white(0.02), lo=800, hi=4000) * env_exp(int(0.02 * SR), 0.005)
        place(x, click, 0.08 + k * rng.uniform(0.04, 0.07), 0.5 / (k + 1))
    return finish(reverb(x, 0.6, 0.18, 0.2, 3000), -2)


def glass_shatter():
    s = 1.0
    x = np.zeros(int(SR * s))
    place(x, band(white(0.04), lo=1500) * env_exp(int(0.04 * SR), 0.01), 0, 1.0)
    for _ in range(40):
        at = abs(rng.normal(0.05, 0.12))
        if at > s - 0.25:
            continue
        place(x, tone(rng.uniform(3000, 8500), 0.2, decay=rng.uniform(0.02, 0.08)), at, rng.uniform(0.1, 0.5))
    place(x, band(white(0.6), lo=4000) * env_exp(int(0.6 * SR), 0.12), 0, 0.25)
    return finish(x, -4)


def metal_scrape():
    s = 0.9
    n = int(s * SR)
    grit = band(white(s), lo=900, hi=4500) * (0.5 + 0.5 * smooth_random(s, 25, 0, 1)) * np.sin(np.pi * np.arange(n) / n) ** 0.5
    ring = tone(lambda tt: 760 + 40 * np.sin(2 * np.pi * 3 * tt), s) * 0.15
    return finish(grit + ring * np.sin(np.pi * np.arange(n) / n), -5)


def death_sting():
    s = 3.0
    n = int(s * SR)
    swell = np.sin(np.pi * np.clip(np.arange(n) / (n * 0.9), 0, 1)) ** 1.5
    drone = (tone(55, s) + tone(82.5, s) * 0.6 + band(white(s), hi=300) * 0.3) * swell
    hit = tone(lambda tt: 60 - 25 * tt, 0.8, decay=0.3)
    x = drone * 0.6
    place(x, hit, 0, 1.0)
    return finish(reverb(x, 1.5, 0.5, 0.3, 1500), -3)


def pickup():
    s = 0.35
    n = int(s * SR)
    rustle = band(white(s), lo=1000, hi=5000) * smooth_random(s, 60, 0, 1) * np.sin(np.pi * np.arange(n) / n)
    x = rustle * 0.6
    place(x, tone(1400, 0.03, decay=0.006), 0.22, 0.4)
    return finish(x, -8)


def bag_open():
    s = 0.7
    n = int(s * SR)
    rip = band(white(s), lo=1500, hi=7000) * (0.4 + 0.6 * (np.sin(2 * np.pi * 70 * np.arange(n) / SR) > 0))
    rip *= np.clip(np.arange(n) / (0.05 * SR), 0, 1) * np.clip((n - np.arange(n)) / (0.1 * SR), 0, 1)
    return finish(rip, -6)


def solar_charge():
    s = 1.2
    rise = tone(lambda tt: 400 + 500 * (tt / s) ** 1.5, s) * np.sin(np.pi * np.clip(t(s) / s, 0, 1)) ** 0.6 * 0.5
    x = np.zeros(int(SR * 1.8))
    place(x, rise, 0)
    place(x, bell(1318, 0.8), 1.15, 0.6)
    return finish(x, -9)


def camera_shutter():
    x = np.zeros(int(SR * 0.25))
    for at, gain in [(0.0, 1.0), (0.07, 0.7)]:
        click = band(white(0.03), lo=1200, hi=9000) * env_exp(int(0.03 * SR), 0.006)
        place(x, click, at, gain)
    place(x, tone(2600, 0.04, decay=0.01), 0.0, 0.3)
    return finish(x, -6)


def msg_in():
    return finish(blips([1175, 1568], gap=0.08, length=0.12, decay=0.06), -10)


def msg_out():
    return finish(whoosh(0.18, (800, 2000), (2000, 6000), 0.5) * 0.6 + np.concatenate([np.zeros(int(0.1 * SR)), tone(1760, 0.08, decay=0.03)])[: int(0.18 * SR)], -12)


def light_click():
    x = np.zeros(int(SR * 0.08))
    place(x, band(white(0.015), lo=1500) * env_exp(int(0.015 * SR), 0.003), 0, 1.0)
    place(x, tone(900, 0.03, decay=0.008), 0.004, 0.4)
    return finish(x, -9)


SOUNDS = {
    # ambience (loops)
    "amb_wind": amb_wind, "amb_birds": amb_birds, "fire_crackle": fire_crackle,
    # distant one-shots
    "distant_shot": distant_shot, "distant_crash": distant_crash,
    # footsteps
    "step_1": lambda: step(1), "step_2": lambda: step(2), "step_3": lambda: step(3), "step_4": lambda: step(4),
    # interface and device
    "ui_tap": ui_tap, "ui_open": ui_open, "ui_close": ui_close, "ui_type": ui_type,
    "device_beep": device_beep, "device_error": device_error, "remember_chime": remember_chime,
    # quick-time events and weapons
    "qte_press": qte_press, "qte_success": qte_success, "qte_fail": qte_fail,
    "gunshot": gunshot, "target_hit": target_hit, "swing_whoosh": swing_whoosh,
    "knife_slash": knife_slash, "hit_flesh": hit_flesh,
    # story beats
    "door_bang": door_bang, "glass_shatter": glass_shatter, "metal_scrape": metal_scrape,
    "death_sting": death_sting, "pickup": pickup, "bag_open": bag_open, "solar_charge": solar_charge,
    # phone
    "camera_shutter": camera_shutter, "msg_in": msg_in, "msg_out": msg_out, "light_click": light_click,
}


def write_wav(path, x):
    data = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--only")]
    only = None
    for i, a in enumerate(sys.argv[1:]):
        if a.startswith("--only"):
            only = set((a.split("=", 1)[1] if "=" in a else sys.argv[i + 2]).split(","))
            if "=" not in a and sys.argv[i + 2] in args:
                args.remove(sys.argv[i + 2])
    out = args[0] if args else "Assets/EMPEscape/Resources/Audio"
    os.makedirs(out, exist_ok=True)
    for name, make in SOUNDS.items():
        if only and name not in only:
            continue
        x = make()
        write_wav(os.path.join(out, name + ".wav"), x)
        print(f"{name}.wav  {len(x) / SR:.2f}s")


if __name__ == "__main__":
    main()
