"""音訊加工的共用函式（NE-155）：解碼、找槍聲範圍、修剪靜音、淡出入、響度標準化、濾波、迴圈接縫、編碼成 OGG。

全部以 ffmpeg 解碼與編碼、numpy／scipy 處理，沒有隨機成分，同樣的輸入重跑會得到同樣的輸出。
"""
import subprocess
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
EPS = 1e-9


def db(value: float) -> float:
    return 20.0 * np.log10(max(float(value), EPS))


def from_db(value: float) -> float:
    return float(10.0 ** (value / 20.0))


def decode(path: Path, sr: int = SR, mono: bool = True) -> np.ndarray:
    """解碼任何 ffmpeg 讀得懂的檔案成 float32；mono 時形狀 (n,)，否則 (n, 2)。"""
    channels = 1 if mono else 2
    cmd = ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-ac", str(channels), "-ar", str(sr), "-"]
    out = subprocess.run(cmd, capture_output=True, check=True).stdout
    data = np.frombuffer(out, dtype=np.float32).copy()
    return data if mono else data.reshape(-1, 2)


def encode_ogg(samples: np.ndarray, out_path: Path, sr: int = SR, quality: float = 4.0) -> None:
    """把 float32 取樣編成 OGG Vorbis（立體聲樣本形狀 (n, 2)）。"""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    channels = 1 if samples.ndim == 1 else samples.shape[1]
    cmd = ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(sr), "-ac", str(channels), "-i", "-",
           "-c:a", "libvorbis", "-q:a", str(quality), "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", str(out_path)]
    subprocess.run(cmd, input=np.ascontiguousarray(samples, dtype=np.float32).tobytes(), check=True, capture_output=True)


def envelope(x: np.ndarray, sr: int = SR, win_ms: float = 4.0) -> np.ndarray:
    """每個視窗一格的 RMS 包絡（視窗不重疊）。"""
    mono = x if x.ndim == 1 else x.mean(axis=1)
    win = max(1, int(sr * win_ms / 1000.0))
    count = len(mono) // win
    if count == 0:
        return np.array([float(np.sqrt(np.mean(mono ** 2))) if len(mono) else 0.0])
    return np.sqrt(np.mean(mono[: count * win].reshape(count, win) ** 2, axis=1))


def find_shot(x: np.ndarray, sr: int = SR, max_len: float = 1.5, single: bool = True, win_ms: float = 4.0) -> tuple[int, int]:
    """找出第一發槍聲／第一個撞擊的範圍 (start, end)：從起音前一點開始，到衰減到很小或下一發開始為止。"""
    env = envelope(x, sr, win_ms)
    win = int(sr * win_ms / 1000.0)
    peak_i = int(np.argmax(env))
    peak = env[peak_i]
    if peak < EPS:
        return 0, len(x)
    onset = int(np.argmax(env > peak * from_db(-24.0)))
    start = max(0, (onset - 1) * win)
    end_floor = peak * from_db(-45.0)
    limit = min(len(env), peak_i + int(max_len * 1000.0 / win_ms))
    end_i = limit
    quiet = 0
    seen_decay = False
    for i in range(peak_i + 1, limit):
        if env[i] < peak * from_db(-25.0):
            seen_decay = True
        if single and seen_decay and env[i] > peak * from_db(-16.0) and env[i] > env[i - 1] * 1.8:
            end_i = i
            break
        if env[i] < end_floor:
            quiet += 1
            if quiet * win_ms >= 60.0:
                end_i = min(limit, i + int(40.0 / win_ms))
                break
        else:
            quiet = 0
    end = min(len(x), end_i * win)
    end = min(end, start + int(max_len * sr))
    return start, max(end, start + int(0.03 * sr))


def shot_segments(x: np.ndarray, sr: int = SR, max_len: float = 1.5, min_gap_ms: float = 150.0, win_ms: float = 4.0) -> list[tuple[int, int]]:
    """找出檔案裡每一發（每一次撞擊）的範圍：安靜至少 min_gap_ms 之後突然變響才算新的一發。一個檔案含多發時，每發都能當獨立變體。"""
    env = envelope(x, sr, win_ms)
    win = int(sr * win_ms / 1000.0)
    peak = env.max()
    if peak < EPS:
        return []
    loud = env > peak * from_db(-30.0)
    gap_frames = int(min_gap_ms / win_ms)
    onsets: list[int] = []
    quiet = gap_frames  # 檔案開頭視為已經安靜
    for i, is_loud in enumerate(loud):
        if is_loud:
            if quiet >= gap_frames:
                onsets.append(i)
            quiet = 0
        else:
            quiet += 1
    segments = []
    for n, onset in enumerate(onsets):
        start = max(0, (onset - 1) * win)
        limit = start + int(max_len * sr)
        nxt = (onsets[n + 1] - 1) * win - int(0.005 * sr) if n + 1 < len(onsets) else len(x)
        segments.append((start, max(start + int(0.03 * sr), min(limit, nxt, len(x)))))
    return segments


def find_segments(x: np.ndarray, sr: int = SR, threshold_db: float = -45.0, min_gap_ms: float = 150.0, min_len_ms: float = 30.0,
                  pad_ms: float = 10.0, win_ms: float = 5.0) -> list[tuple[float, float]]:
    """依靜音把音訊分成幾段，回傳每段的 (起, 迄) 秒數：比最響處低 threshold_db 以上算有聲，靜音不到 min_gap_ms 的相鄰兩段併成一段，
    短於 min_len_ms 的雜音丟掉，前後各留 pad_ms（不超出檔案）。分段只是給人挑的建議，不是精確的切點。"""
    env = envelope(x, sr, win_ms)
    peak = float(env.max()) if len(env) else 0.0
    if peak < EPS:
        return []
    loud = env > peak * from_db(threshold_db)
    runs: list[list[int]] = []
    for i, is_loud in enumerate(loud):
        if not is_loud:
            continue
        if runs and i - runs[-1][1] <= max(1, int(min_gap_ms / win_ms)):
            runs[-1][1] = i
        else:
            runs.append([i, i])
    total = len(x) / sr
    segments = []
    for first, last in runs:
        start, end = first * win_ms / 1000.0, (last + 1) * win_ms / 1000.0
        if (end - start) * 1000.0 < min_len_ms:
            continue
        segments.append((round(max(0.0, start - pad_ms / 1000.0), 4), round(min(total, end + pad_ms / 1000.0), 4)))
    return segments


def peaks(x: np.ndarray, bins: int) -> list[list[float]]:
    """波形顯示用：把音訊分成 bins 格，每格 [最小, 最大]（取到小數 3 位）。"""
    mono = x if x.ndim == 1 else x.mean(axis=1)
    if len(mono) == 0 or bins <= 0:
        return []
    edges = np.linspace(0, len(mono), min(bins, len(mono)) + 1).astype(int)
    return [[round(float(mono[a:b].min()), 3), round(float(mono[a:b].max()), 3)] for a, b in zip(edges[:-1], edges[1:]) if b > a]


def trim_silence(x: np.ndarray, sr: int = SR, threshold_db: float = -48.0, tail_ms: float = 30.0) -> np.ndarray:
    """修掉頭尾低於門檻（相對峰值）的靜音。"""
    env = envelope(x, sr, 4.0)
    if len(env) == 0 or env.max() < EPS:
        return x
    loud = np.where(env > env.max() * from_db(threshold_db))[0]
    win = int(sr * 4.0 / 1000.0)
    start = max(0, int(loud[0]) * win - win)
    end = min(len(x), (int(loud[-1]) + 1) * win + int(sr * tail_ms / 1000.0))
    return x[start:end]


def fade(x: np.ndarray, sr: int = SR, fade_in_ms: float = 0.0, fade_out_ms: float = 0.0) -> np.ndarray:
    y = x.copy()
    n_in = min(len(y), int(sr * fade_in_ms / 1000.0))
    n_out = min(len(y), int(sr * fade_out_ms / 1000.0))
    if n_in > 1:
        ramp = np.linspace(0.0, 1.0, n_in, dtype=np.float32)
        y[:n_in] *= ramp if y.ndim == 1 else ramp[:, None]
    if n_out > 1:
        ramp = np.linspace(1.0, 0.0, n_out, dtype=np.float32)
        y[-n_out:] *= ramp if y.ndim == 1 else ramp[:, None]
    return y


def active_rms_db(x: np.ndarray, sr: int = SR) -> float:
    """有聲部分（包絡高於峰值 -30 dB）的 RMS，單位 dBFS；用來讓長短不同的音效聽起來一樣大。"""
    mono = x if x.ndim == 1 else x.mean(axis=1)
    env = envelope(mono, sr, 4.0)
    if env.max() < EPS:
        return -120.0
    win = int(sr * 4.0 / 1000.0)
    mask = np.repeat(env > env.max() * from_db(-30.0), win)[: len(mono)]
    active = mono[: len(mask)][mask]
    return db(float(np.sqrt(np.mean(active ** 2)))) if len(active) else -120.0


def normalize_rms(x: np.ndarray, target_db: float, peak_db: float = -1.0, sr: int = SR) -> np.ndarray:
    """增益到目標有聲 RMS，但峰值不超過 peak_db（超過就降低增益，不削波）。"""
    gain = target_db - active_rms_db(x, sr)
    peak = float(np.max(np.abs(x))) if len(x) else 0.0
    if peak > EPS:
        gain = min(gain, peak_db - db(peak))
    return (x * from_db(gain)).astype(np.float32)


def filter_band(x: np.ndarray, sr: int = SR, lowpass: float | None = None, highpass: float | None = None) -> np.ndarray:
    y = x
    if highpass:
        y = signal.sosfilt(signal.butter(2, highpass, "highpass", fs=sr, output="sos"), y, axis=0)
    if lowpass:
        y = signal.sosfilt(signal.butter(2, lowpass, "lowpass", fs=sr, output="sos"), y, axis=0)
    return y.astype(np.float32)


def change_rate(x: np.ndarray, rate: float) -> np.ndarray:
    """改變播放速度（音高與長度一起變），rate > 1 變高變短。"""
    if abs(rate - 1.0) < 1e-3:
        return x
    num, den = int(round(1000.0)), int(round(1000.0 * rate))
    return signal.resample_poly(x, num, den, axis=0).astype(np.float32)


def loop_blend(x: np.ndarray, sr: int = SR, blend_ms: float = 400.0) -> np.ndarray:
    """做成無縫迴圈：把尾端淡出的一段疊到開頭淡入的一段上，結果比原本短一個 blend。"""
    n = min(int(sr * blend_ms / 1000.0), len(x) // 3)
    if n < 2:
        return x
    ramp = np.linspace(0.0, 1.0, n, dtype=np.float32)
    ramp = ramp if x.ndim == 1 else ramp[:, None]
    head = x[:n] * ramp + x[-n:] * (1.0 - ramp)
    return np.concatenate([head, x[n:-n]]).astype(np.float32)


def measure_lufs(x: np.ndarray, sr: int = SR) -> float:
    """整合響度（LUFS），用 ffmpeg 的 ebur128 量。"""
    cmd = ["ffmpeg", "-nostats", "-v", "info", "-f", "f32le", "-ar", str(sr), "-ac", str(1 if x.ndim == 1 else 2), "-i", "-", "-filter_complex", "ebur128", "-f", "null", "-"]
    err = subprocess.run(cmd, input=np.ascontiguousarray(x, dtype=np.float32).tobytes(), capture_output=True).stderr.decode("utf-8", "replace")
    marker = err.rfind("I:")
    if marker < 0:
        return -70.0
    return float(err[marker + 2:].split("LUFS")[0].strip())


def normalize_lufs(x: np.ndarray, target_lufs: float, peak_db: float = -1.5, sr: int = SR) -> np.ndarray:
    gain = target_lufs - measure_lufs(x, sr)
    peak = float(np.max(np.abs(x))) if len(x) else 0.0
    if peak > EPS:
        gain = min(gain, peak_db - db(peak))
    return (x * from_db(gain)).astype(np.float32)
