"""Loudness table and waveform sheet for a recording made by tools/melee_sound_probe.tscn (NE-261).

    python tools/audio/melee_sound_report.py <folder with melee-master.wav, melee-sfx.wav, melee-index.json> [--png <path>]

For every recorded segment (reference pistol shots and footsteps, then each melee weapon's idle hum, combo that misses and
combo that hits) it prints, measured on the SFX bus only:
    peak (dBFS), loud (the 95th percentile of 50 ms RMS windows: how loud the events are) and floor (the median window).
and it checks the two balance rules of the ticket:
    - a combo that misses is not louder than the pistol fired into the air, and a combo that hits is not louder than the pistol
      hitting the same enemy (compared on the loud level; the hit segments include the shared material and hurt sounds on both
      sides). Peaks are printed for information only: the sample peak of a mix depends on how those shared layers happen to line
      up and moves by several dB between two identical runs, and the master bus has a limiter.
    - every idle hum stays at least 6 dB under the footsteps and 10 dB under the ambience-and-music bed, and stops after holstering.
The waveform sheet shows the master mix (what the player hears) with the segments marked. Exit code 1 when a rule fails.
"""
from __future__ import annotations

import argparse
import json
import sys
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

WINDOW = 0.05
# The hum has to stay this far under the footsteps (their loud level) and under everything that is not a sound effect (ambience and music).
HUM_UNDER_STEPS_DB = 6.0
HUM_UNDER_BED_DB = 10.0
COLOURS = {"ref": (150, 150, 160), "blade": (255, 140, 60), "dagger": (150, 230, 255), "glaive": (120, 150, 255), "maul": (255, 215, 80), "whip": (220, 110, 255)}
NAMES = {"ref": "對照", "blade": "熱能長刀", "dagger": "單分子匕首", "glaive": "離子戰戟", "maul": "液壓錘", "whip": "單分子鞭"}
PARTS = {"silence": "安靜", "pistol": "手槍空射", "pistol_hit": "手槍命中", "walk": "走路", "idle": "待機", "combo_miss": "連段揮空", "combo_hit": "連段命中", "holster": "收起"}


def read(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as handle:
        rate = handle.getframerate()
        data = np.frombuffer(handle.readframes(handle.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
        if handle.getnchannels() > 1:
            data = data.reshape(-1, handle.getnchannels()).mean(axis=1)
    return data, rate


def db(value: float) -> float:
    return float(20.0 * np.log10(max(value, 1e-6)))


def levels(samples: np.ndarray, rate: int) -> tuple[float, float, float]:
    if samples.size == 0:
        return -120.0, -120.0, -120.0
    step = max(1, int(rate * WINDOW))
    count = max(1, samples.size // step)
    windows = np.sqrt((samples[: count * step].reshape(count, -1) ** 2).mean(axis=1)) if samples.size >= step else np.array([np.sqrt((samples ** 2).mean())])
    return db(float(np.abs(samples).max())), db(float(np.percentile(windows, 95))), db(float(np.percentile(windows, 50)))


def font(size: int) -> ImageFont.ImageFont:
    for name in ("C:/Windows/Fonts/msjh.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"):
        if Path(name).exists():
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()


def sheet(master: np.ndarray, rate: int, segments: list[dict], rows: list[dict], path: Path) -> None:
    groups: list[list[dict]] = []
    for segment in segments:
        if not groups or groups[-1][0]["weapon"] != segment["weapon"]:
            groups.append([])
        groups[-1].append(segment)
    width, lane = 1600, 150
    image = Image.new("RGB", (width, lane * len(groups) + 10), (14, 15, 20))
    draw = ImageDraw.Draw(image)
    small, big = font(15), font(20)
    by_key = {(row["weapon"], row["part"], row["start"]): row for row in rows}
    for index, group in enumerate(groups):
        top = index * lane + 8
        start, end = group[0]["start"], group[-1]["end"]
        colour = COLOURS.get(group[0]["weapon"], (200, 200, 200))
        chunk = master[int(start * rate): int(end * rate)]
        if chunk.size:
            bins = np.array_split(np.abs(chunk), width - 20)
            mid = top + lane // 2 + 8
            for x, part in enumerate(bins):
                height = int(min(1.0, float(part.max()) if part.size else 0.0) * (lane // 2 - 14))
                draw.line([(10 + x, mid - height), (10 + x, mid + height)], fill=colour)
        draw.text((12, top), NAMES.get(group[0]["weapon"], group[0]["weapon"]), font=big, fill=(255, 255, 255))
        for segment in group:
            x = 10 + int((segment["start"] - start) / max(end - start, 1e-6) * (width - 20))
            draw.line([(x, top + 26), (x, top + lane - 6)], fill=(90, 90, 100))
            row = by_key[(segment["weapon"], segment["part"], segment["start"])]
            draw.text((x + 4, top + 28), "%s  峰值 %.0f／響度 %.0f dB" % (PARTS.get(segment["part"], segment["part"]), row["peak"], row["loud"]), font=small, fill=(225, 225, 230))
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("folder")
    parser.add_argument("--png", default="")
    args = parser.parse_args()
    folder = Path(args.folder)
    index = json.loads((folder / "melee-index.json").read_text(encoding="utf-8"))
    sfx, rate = read(folder / "melee-sfx.wav")
    master, master_rate = read(folder / "melee-master.wav")
    rows = []
    for segment in index["segments"]:
        cut = slice(int(segment["start"] * rate), int(segment["end"] * rate))
        peak, loud, floor = levels(sfx[cut], rate)
        # Both recorders sit before their bus volume, so the master recording is the SFX bus plus everything else (ambience, music).
        rest = master[cut][: sfx[cut].size] - sfx[cut][: master[cut].size]
        rows.append({**segment, "peak": peak, "loud": loud, "floor": floor, "bed": levels(rest, rate)[2]})
    print("%-8s %-11s %7s %7s %7s %7s  %s" % ("weapon", "part", "peak", "loud", "floor", "bed", "sounds"))
    for row in rows:
        print("%-8s %-11s %7.1f %7.1f %7.1f %7.1f  %s" % (row["weapon"], row["part"], row["peak"], row["loud"], row["floor"], row["bed"], ", ".join(row["sounds"])))
    refs = {part: next((row for row in rows if row["weapon"] == "ref" and row["part"] == part), None) for part in ("pistol", "pistol_hit", "walk")}
    walk = refs["walk"]
    problems = []
    if None in refs.values():
        problems.append("recording has no pistol / pistol_hit / walk reference segment")
    else:
        for row in rows:
            if row["weapon"] == "ref":
                continue
            gun = refs["pistol_hit"] if row["part"] == "combo_hit" else refs["pistol"]
            if row["part"] in ("combo_miss", "combo_hit") and row["loud"] > gun["loud"]:
                problems.append("%s %s is louder than the pistol (loud %.1f vs %.1f dB)" % (row["weapon"], row["part"], row["loud"], gun["loud"]))
            if row["part"] == "idle" and row["floor"] > walk["loud"] - HUM_UNDER_STEPS_DB:
                problems.append("%s idle hum (%.1f dB) is not %.0f dB under the footsteps (%.1f dB)" % (row["weapon"], row["floor"], HUM_UNDER_STEPS_DB, walk["loud"]))
            if row["part"] == "idle" and row["floor"] > row["bed"] - HUM_UNDER_BED_DB:
                problems.append("%s idle hum (%.1f dB) is not %.0f dB under the ambience and music (%.1f dB)" % (row["weapon"], row["floor"], HUM_UNDER_BED_DB, row["bed"]))
            if row["part"] == "idle" and row["floor"] < -75.0:
                problems.append("%s idle hum is inaudible (%.1f dB)" % (row["weapon"], row["floor"]))
            if row["part"] == "holster" and row["floor"] > -70.0 and row["floor"] > next(r for r in rows if r["weapon"] == row["weapon"] and r["part"] == "idle")["floor"] - 10.0:
                problems.append("%s hum still sounds after holstering (%.1f dB)" % (row["weapon"], row["floor"]))
    if args.png:
        sheet(master, master_rate, index["segments"], rows, Path(args.png))
    for problem in problems:
        print("PROBLEM:", problem)
    print("MELEE_SOUND_REPORT problems", len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
