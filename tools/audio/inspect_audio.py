"""看原始素材的聲音特徵，用來挑適合的檔案（NE-155）。

用法：python tools/audio/inspect_audio.py <素材包 id> <相對路徑或萬用字元> [...]
例：python tools/audio/inspect_audio.py oga_the-free-firearm-sound-library "Prepared SFX Library/AK-47/*.wav"

每個檔案印出：時長、第一個聲音的範圍、衰減到 -30／-45 dB 的時間、峰值、頻譜重心（越高越尖銳）、起音數（連發／多次撞擊）。
"""
import glob
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audio_lib as lib  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "assets_src" / "raw" / "audio"
MANIFEST = ROOT / "assets_src" / "audio" / "manifest.json"


def decay_time(env: np.ndarray, peak_i: int, drop_db: float, win_ms: float) -> float:
    below = np.where(env[peak_i:] < env[peak_i] * lib.from_db(-drop_db))[0]
    return (below[0] * win_ms / 1000.0) if len(below) else float("nan")


def count_onsets(env: np.ndarray) -> int:
    peak = env.max()
    if peak <= 0:
        return 0
    loud = env > peak * lib.from_db(-20.0)
    return int(np.sum(loud[1:] & ~loud[:-1]) + (1 if loud[0] else 0))


def inspect(path: Path) -> str:
    x = lib.decode(path)
    if len(x) == 0:
        return "（空檔）"
    win_ms = 4.0
    env = lib.envelope(x, lib.SR, win_ms)
    peak_i = int(np.argmax(env))
    start, end = lib.find_shot(x, max_len=3.0)
    segment = x[start:end]
    spectrum = np.abs(np.fft.rfft(segment * np.hanning(len(segment))))
    freqs = np.fft.rfftfreq(len(segment), 1.0 / lib.SR)
    centroid = float(np.sum(freqs * spectrum) / max(np.sum(spectrum), 1e-9))
    return (f"{len(x) / lib.SR:6.2f}s  shot {start / lib.SR:5.2f}-{end / lib.SR:5.2f}s  -30dB@{decay_time(env, peak_i, 30, win_ms):5.2f}s  "
            f"-45dB@{decay_time(env, peak_i, 45, win_ms):5.2f}s  peak {lib.db(float(np.max(np.abs(x)))):6.1f}  centroid {centroid:6.0f} Hz  onsets {count_onsets(env)}")


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    packs = {p["id"]: p["dir"] for p in json.loads(MANIFEST.read_text(encoding="utf-8"))["packs"]}
    pack = sys.argv[1]
    if pack not in packs:
        print(f"素材包「{pack}」不在 manifest.json", file=sys.stderr)
        return 1
    base = RAW / packs[pack]
    for pattern in sys.argv[2:]:
        for match in sorted(glob.glob(str(base / pattern), recursive=True)):
            path = Path(match)
            if path.is_file():
                print(f"{path.relative_to(base).as_posix():60} {inspect(path)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
