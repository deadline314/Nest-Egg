"""Describe and split NE-277's untouched native master recording; this is not human listening."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import wave
import numpy as np
from PIL import Image, ImageDraw, ImageFont


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    root = args.directory.resolve()
    result = json.loads((root / "result.json").read_text(encoding="utf-8"))
    with wave.open(str(root / "master.wav"), "rb") as wav:
        rate, channels, width, count = wav.getframerate(), wav.getnchannels(), wav.getsampwidth(), wav.getnframes()
        pcm = wav.readframes(count)
    if width != 2 or count < rate:
        raise ValueError("expected at least one second of original 16-bit PCM")
    samples = np.frombuffer(pcm, dtype="<i2").reshape(-1, channels).astype(np.float64) / 32768
    if not np.isfinite(samples).all() or not np.any(samples):
        raise ValueError("empty/nonfinite recording")
    clips = root / "clips"; clips.mkdir(exist_ok=True)
    rows = result["rows"]
    image = Image.new("RGB", (1400, len(rows) * 56 + 70), "#171922")
    draw = ImageDraw.Draw(image)
    font_path = Path("C:/Windows/Fonts/arial.ttf")
    font = ImageFont.truetype(str(font_path), 14) if font_path.exists() else ImageFont.load_default()
    draw.text((10, 8), "NE-277 native master mix / actual contacts / no human listening or isolated-layer loudness claim", font=font, fill="white")
    report = {"rate": rate, "channels": channels, "sample_width": width, "seconds": count / rate,
              "master_sha256": hashlib.sha256((root / "master.wav").read_bytes()).hexdigest(), "pcm_sha256": hashlib.sha256(pcm).hexdigest(),
              "scope": "master mix includes ambience/music and existing shared hit sounds", "rows": []}
    for index, row in enumerate(rows):
        start = int(row["start_seconds"] * rate); end = int(row["end_seconds"] * rate)
        if not 0 <= start < end <= count + int(rate * 0.1):
            raise ValueError("segment outside recording: " + row["name"])
        end = min(end, count)
        clip = samples[start:end]
        if not len(clip):
            raise ValueError("empty segment")
        name = row["name"].replace("/", "-") + ".wav"
        with wave.open(str(clips / name), "wb") as wav:
            wav.setnchannels(channels); wav.setsampwidth(width); wav.setframerate(rate)
            wav.writeframes(pcm[start * channels * width:end * channels * width])
        peak = float(np.max(np.abs(clip))); rms = float(np.sqrt(np.mean(clip * clip)))
        entry = {"name": row["name"], "file": "clips/" + name, "frames": end - start,
                 "peak_dbfs": 20 * float(np.log10(max(peak, 1e-12))), "rms_dbfs": 20 * float(np.log10(max(rms, 1e-12))),
                 "clip_sha256": hashlib.sha256((clips / name).read_bytes()).hexdigest()}
        report["rows"].append(entry)
        y = 56 * index + 60
        draw.text((10, y - 18), row["name"] + " / peak %.1f dBFS / RMS %.1f dBFS" % (entry["peak_dbfs"], entry["rms_dbfs"]), font=font, fill="white")
        mono = clip.mean(axis=1)
        for x, part in enumerate(np.array_split(mono, 1380)):
            if len(part):
                low, high = float(np.min(part)), float(np.max(part))
                draw.line((10 + x, y + 16 - high * 16, 10 + x, y + 16 - low * 16), fill="#f1b768" if row["reduced"] else "#77c9da")
    image.save(root / "waveforms.png")
    (root / "audio-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"segments": len(rows), "seconds": count / rate, "nonzero": True}))


if __name__ == "__main__":
    main()
