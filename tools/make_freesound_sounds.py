#!/usr/bin/env python3
"""Звуки с freesound.org (только CC0): выстрелы пистолета и автомата, сухие щелчки,
перезарядка автомата и вскрики зомби от попаданий.

Пистолет — превью высокого качества записи https://freesound.org/s/731942/ (файл 731942.ogg).
Остальное — нарезки из открытого проекта webdevcody/survive-the-night-fps
(client/audio/samples, всё CC0, см. там CREDITS.md и таблицу нарезок samples.js):
gun_mp5.ogg, fol_dry.ogg, fol_mag_in.ogg, fol_mag_out.ogg, zv_pain.ogg, zv_death.ogg, zv_scream.ogg.
Откуда каждый звук — в sounds/weapons/LICENSE.md и sounds/zombies/LICENSE.md.

Запуск: python3 tools/make_freesound_sounds.py /папка/с/исходниками
Нужны numpy и ffmpeg.

Обработка почти никакая, как у выстрела дробовика: моно 44.1 кГц, срез гула,
обрезка, короткое затухание в конце, выравнивание громкости внутри группы.
Мычание при ходьбе и рык атаки не трогаются: они остаются синтезом в scripts/sfx.gd.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_weapon_sounds as w  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sounds")

# (файл, начало, длина) в секундах.
SHOTS = {
    # 9 мм, DledeSOUND «9mm Pistol Gunshots»: четыре выстрела одного ствола.
    "pistol": [("731942.ogg", 0.80, 1.1), ("731942.ogg", 3.72, 1.1),
               ("731942.ogg", 8.19, 1.1), ("731942.ogg", 9.39, 1.1)],
    # MP5: одиночные выстрелы из настоящей очереди со своим хвостом.
    "smg": [("gun_mp5.ogg", 0.0, 0.708), ("gun_mp5.ogg", 0.768, 0.708),
            ("gun_mp5.ogg", 1.536, 0.708), ("gun_mp5.ogg", 2.304, 0.708)],
}
CLICKS = {
    "pistol": ("fol_dry.ogg", 0.319, 0.256),  # 9-мм пистолет, сухой спуск
    "smg": ("fol_dry.ogg", 0.0, 0.258),  # винтовка, сухой спуск
}
# Перезарядка автомата: отстегнуть магазин Узи, пристегнуть. (файл, начало, длина, где поставить)
RELOAD_SMG = [("fol_mag_out.ogg", 0.53, 0.54, 0.0), ("fol_mag_in.ogg", 1.351, 0.759, 0.6)]

# Вскрики зомби: имя звука в игре -> куски записей.
VOICES = {
    # Короткий глухой стон боли (tonsil5 «Zombie Pain», OwNathan, Under7dude).
    "pain": [("zv_pain.ogg", 0.0, 1.07), ("zv_pain.ogg", 1.13, 0.51),
             ("zv_pain.ogg", 3.879, 0.878), ("zv_pain.ogg", 4.817, 0.309)],
    # Резкий вскрик от пули (tonsil5 «Zombie Hit», «Zombie Pain»).
    "yelp": [("zv_pain.ogg", 1.7, 0.649), ("zv_pain.ogg", 2.41, 0.538), ("zv_pain.ogg", 3.009, 0.81)],
    # Визг: оторвало руку, раскололо череп.
    "shriek": [("zv_scream.ogg", 0.0, 1.909), ("zv_scream.ogg", 1.97, 1.62), ("zv_scream.ogg", 3.65, 1.419)],
    # Предсмертный хрип.
    "death": [("zv_death.ogg", 0.0, 0.6), ("zv_death.ogg", 0.66, 0.83), ("zv_death.ogg", 1.55, 1.6),
              ("zv_death.ogg", 3.21, 1.21), ("zv_death.ogg", 4.48, 1.19)],
}


def cut(src, name, start, length, hp=30.0):
    x = w.highpass(w.load(src, name, start + 0.01, length), hp)  # load берёт 10 мс до начала
    return w.fade(x / (np.abs(x).max() + 1e-9), 0.002, min(0.15, length * 0.4))


def save_to(folder, name, x):
    os.makedirs(folder, exist_ok=True)
    w.OUT = folder
    w.save(name, x)


def main(src):
    weapons = os.path.join(ROOT, "weapons")
    zombies = os.path.join(ROOT, "zombies")
    for gun, takes in SHOTS.items():
        sounds = [cut(src, *t) for t in takes]
        for i, x in enumerate(w.fit(sounds, 0.2, rms_window=0.2)):
            save_to(weapons, f"shot_{gun}_{i + 1}", x)
    for gun, (name, start, length) in CLICKS.items():
        save_to(weapons, f"click_{gun}", cut(src, name, start, length, 80.0) * 0.8)
    mix = np.zeros(int(w.SR * 1.45))
    for name, start, length, at in RELOAD_SMG:
        x = cut(src, name, start, length, 60.0)
        i = int(w.SR * at)
        mix[i:i + len(x)] += x[: len(mix) - i]
    save_to(weapons, "reload_smg", w.limit(mix, 8.0, 0.03, 0.85))  # +8 дБ: слышно сквозь мычание
    for voice, takes in VOICES.items():
        sounds = [cut(src, *t, 60.0) for t in takes]
        for i, x in enumerate(w.fit(sounds, 0.16, peak=0.85)):
            save_to(zombies, f"{voice}_{i + 1}", x)
    print("готово")


if __name__ == "__main__":
    main(sys.argv[1])
