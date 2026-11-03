#!/usr/bin/env python3
"""Нарезает звуки дробовика и перезарядку пистолета из Free Firearm Sound Library (CC0) в sounds/weapons/.
Пистолет и автомат делает tools/make_freesound_sounds.py.

Источник: https://github.com/buddingmonkey/FreeFirearmsSFXLibrary
(зеркало библиотеки Бена Ящака с Kickstarter 2014 года, лицензия CC0 1.0).

Выстрел дробовика взят отдельно: «Shotgun - Fire.wav» от AbuNijmeh, тоже CC0,
https://freesound.org/people/AbuNijmeh/sounds/318973/ (его выбрал Олег).
Он почти не обрабатывается: моно, срез гула ниже 30 Гц, нормализация.

Запуск: python3 tools/make_weapon_sounds.py /путь/к/FreeFirearmsSFXLibrary /путь/к/Shotgun-Fire.wav
Нужны numpy и ffmpeg.

Что делается с записями:
  * вырезается нужный кусок по времени (начало выстрела/щелчка задано вручную);
  * перевод в моно 44.1 кГц, обрезка ультразвука и гула ниже 40 Гц;
  * к выстрелам подмешано эхо короткой бетонной комнаты: записи сделаны
    на открытом полигоне, а в игре этажи и комнаты;
  * верх приглушён (срез около 7–9 кГц), чтобы звук был глухим и мрачным,
    а не звонким;
  * компрессор и пиковый лимитер поджимают первый пик, чтобы «тело» и эхо выстрела
    не тонули под ним, а тихие щелчки затвора были слышны;
  * громкость выстрелов выравнивается по RMS внутри группы, пик не выше -1 дБ;
  * в конце плавное затухание, без щелчков.
"""
import os
import subprocess
import sys
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds", "weapons")
P = "Prepared SFX"
M = "Master Tracks"

# Выстрелы пистолета и автомата, сухие щелчки и перезарядка автомата теперь с freesound.org,
# их делает tools/make_freesound_sounds.py. Здесь остались дробовик и перезарядка пистолета.
SHOTS = {}
SHOT_LEN = {}
SHOT_DRIVE = {}
SHOT_ROOM = {}
SHOT_LOWPASS = {}

# Перезарядка собирается из отдельных движений: (файл, начало, длина, где поставить).
RELOADS = {
    # 1.1 с: вынуть магазин, вставить полный, отпустить затвор.
    "pistol": [(f"{M}/1911/A_5.wav", 0.205, 0.35, 0.0),
               (f"{M}/1911/A_4.wav", 0.92, 0.4, 0.38),
               (f"{M}/1911/A_9.wav", 0.62, 0.4, 0.78)],
    # 1.8 с: три патрона в трубчатый магазин и помпа.
    "shotgun": [(f"{M}/Nova/O_3.wav", 1.555, 0.3, 0.0),
                (f"{M}/Nova/O_3.wav", 1.865, 0.3, 0.33),
                (f"{M}/Nova/O_3.wav", 7.2, 0.18, 0.66),
                (f"{M}/Nova/O_6.wav", 1.165, 0.6, 1.1)],
}
# Сухой щелчок спуска, когда патронов нет.
CLICKS = {
    "shotgun": (f"{M}/Nova/O_8.wav", 0.255),
}


def load(lib, path, start, length):
    pre = 0.01
    cmd = ["ffmpeg", "-v", "error", "-ss", f"{max(0.0, start - pre):.4f}", "-t", f"{length + pre:.4f}",
           "-i", os.path.join(lib, path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    x = np.frombuffer(subprocess.run(cmd, check=True, capture_output=True).stdout, np.float32).astype(np.float64)
    return x - x.mean()


def onepole_lowpass(x, cutoff):
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    s = 0.0
    for i, v in enumerate(x):
        s = (1.0 - a) * v + a * s
        y[i] = s
    return y


def highpass(x, cutoff=40.0):
    return x - onepole_lowpass(x, cutoff)


def darken(x, cutoff):
    # Два каскада однополюсного фильтра: мягкий срез 12 дБ/окт.
    return onepole_lowpass(onepole_lowpass(x, cutoff), cutoff)


def fade(x, fade_in=0.004, fade_out=0.15):
    n_in, n_out = int(SR * fade_in), min(int(SR * fade_out), len(x))
    x = x.copy()
    x[:n_in] *= np.linspace(0.0, 1.0, n_in)
    x[-n_out:] *= np.linspace(1.0, 0.0, n_out) ** 2
    return x


def _follow(a, release):
    k = np.exp(-1.0 / (SR * release))
    env = np.empty_like(a)
    e = 0.0
    for i, v in enumerate(a):
        e = v if v > e else e * k + v * (1.0 - k)
        env[i] = e
    return env


def envelope(x, release, lookahead=0.003):
    """Огибающая с мгновенной атакой и заглядыванием вперёд: пик гасится до того, как придёт."""
    a = np.abs(x)
    return np.maximum(_follow(a, release), _follow(a[::-1], lookahead)[::-1])


def limit(x, drive_db, release=0.06, ceiling=0.89):
    """Пиковый лимитер: поднимает тихое тело звука, не давая пику перегрузиться."""
    x = x / (np.abs(x).max() + 1e-9) * 10 ** (drive_db / 20.0) * ceiling
    env = envelope(x, release)
    return x * np.minimum(1.0, ceiling / np.maximum(env, 1e-9))


def compress(x, threshold_db, ratio, release=0.08):
    """Компрессор: сближает громкость хлопка и эха после него."""
    x = x / (np.abs(x).max() + 1e-9)
    thr = 10 ** (threshold_db / 20.0)
    env = np.maximum(envelope(x, release), thr)
    return x * (env / thr) ** (1.0 / ratio - 1.0)


def _comb(x, delay, feedback, damp):
    d = int(SR * delay)
    buf = np.zeros(d)
    y = np.empty_like(x)
    lp = 0.0
    for i, v in enumerate(x):
        out = buf[i % d]
        lp = out * (1.0 - damp) + lp * damp
        buf[i % d] = v + lp * feedback
        y[i] = out
    return y


def _allpass(x, delay, g=0.5):
    d = int(SR * delay)
    buf = np.zeros(d)
    y = np.empty_like(x)
    for i, v in enumerate(x):
        b = buf[i % d]
        buf[i % d] = v + b * g
        y[i] = b - v * g
    return y


def room(x, mix):
    """Короткая гулкая комната (бетонные стены этажа), чтобы выстрел не звучал как в чистом поле."""
    wet = sum(_comb(x, d, 0.72, 0.4) for d in (0.0297, 0.0371, 0.0411, 0.0437)) / 4.0
    wet = _allpass(_allpass(wet, 0.005), 0.0017)
    return x + wet * mix


def rms(x, seconds=None):
    part = x[: int(SR * seconds)] if seconds else x
    return np.sqrt(np.mean(part ** 2)) + 1e-9


def fit(sounds, target_rms, peak=0.89, rms_window=None):
    out = []
    for x in sounds:
        x = x * (target_rms / rms(x, rms_window))
        p = np.abs(x).max()
        if p > peak:
            x = x * (peak / p)
        out.append(x)
    return out


def save(name, x):
    data = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2").tobytes()
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def shotgun_shot(path):
    x = highpass(load("", os.path.abspath(path), 0.0, 10.0), 30.0)
    x = x / np.abs(x).max() * 0.89
    save("shot_shotgun", fade(x, 0.0005, 0.25))


def main(lib, shotgun_file):
    os.makedirs(OUT, exist_ok=True)
    shotgun_shot(shotgun_file)
    for gun, takes in SHOTS.items():
        sounds = []
        for path, t in takes:
            x = highpass(load(lib, path, t, SHOT_LEN[gun]), 40.0)
            x = darken(x, SHOT_LOWPASS[gun])
            x = room(x / np.abs(x).max(), SHOT_ROOM[gun])
            x = compress(x, -34.0, 3.0)  # хлопок тише, эхо громче: выстрел гулкий, а не щелчок
            x = limit(x, SHOT_DRIVE[gun])
            sounds.append(fade(x, 0.002, SHOT_LEN[gun] * 0.6))
        for i, x in enumerate(fit(sounds, 0.16, rms_window=0.2)):
            save(f"shot_{gun}_{i + 1}", x)

    for gun, parts in RELOADS.items():
        total = max(at + length for _, _, length, at in parts) + 0.05
        mix = np.zeros(int(SR * total) + 1)
        pieces = []
        for path, t, length, at in parts:
            x = highpass(load(lib, path, t, length), 60.0)
            x = fade(x, 0.002, length * 0.5)
            pieces.append((limit(x, 9.0, 0.03, 0.5), at))
        for x, at in pieces:
            i = int(SR * at)
            mix[i:i + len(x)] += x
        mix = darken(mix, 9000)
        save(f"reload_{gun}", limit(mix, 0.0, 0.03, 0.8))

    for gun, (path, t) in CLICKS.items():
        x = darken(highpass(load(lib, path, t, 0.25), 80.0), 9000)
        save(f"click_{gun}", fade(limit(x, 8.0, 0.02, 0.8), 0.002, 0.12))
    print("готово:", os.path.abspath(OUT))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
