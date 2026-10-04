"""依 assets_src/audio/pipeline.json 把原始 CC0 素材加工成遊戲用的音訊檔（NE-155）。

用法：python tools/audio/build_audio.py [--only ID ...] [--check] [--report]
  --only    只重建指定的音效 id／曲目 id
  --check   只檢查（來源檔存在、授權已登記、輸出規格），不寫任何檔案
  --report  列出每個輸出的時長、峰值、有聲 RMS
  --scratch DIR  試做：輸出寫到 DIR（不動 audio/、音效庫與授權登記），用來試聽或比對參數
  --pipeline FILE  改用另一份加工清單（搭配 --scratch 試做新分類）

輸出：
  audio/sfx/<id>_<nn>.ogg        音效：單聲道 44.1 kHz，有聲部分 RMS 對齊 target_db，峰值不超過 -1 dBFS
  audio/music/<id>.ogg           音樂：立體聲 44.1 kHz，整合響度對齊 target_lufs
  data/audio/sound_bank.json     音效庫：只更新 files／pack，保留已調整的 volume_db、pitch、note
  assets_src/audio/LICENSES.json 授權登記：只列實際用到的素材包與檔案

加工全部是確定性的，同樣的輸入重跑得到同樣的輸出；原始檔放 assets_src/raw/audio/（fetch_audio.py 下載）。
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audio_lib as lib  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
AUDIO_SRC = ROOT / "assets_src" / "audio"
RAW = ROOT / "assets_src" / "raw" / "audio"
PIPELINE = AUDIO_SRC / "pipeline.json"
MANIFEST = AUDIO_SRC / "manifest.json"
LICENSES = AUDIO_SRC / "LICENSES.json"
BANK = ROOT / "data" / "audio" / "sound_bank.json"
SFX_DIR = ROOT / "audio" / "sfx"
MUSIC_DIR = ROOT / "audio" / "music"
SFX_RES = "res://audio/sfx/"
MUSIC_RES = "res://audio/music/"

SFX_DEFAULT = {"mode": "whole", "max_len": 3.0, "target_db": -16.0, "fade_in_ms": 1.0, "fade_out_ms": 20.0,
               "gain_db": 0.0, "rate": 1.0, "single": True, "stereo": False, "quality": 4.0}
MUSIC_DEFAULT = {"target_lufs": -18.0, "peak_db": -1.5, "quality": 4.0, "fade_in_ms": 0.0, "fade_out_ms": 0.0,
                 "loop_blend_ms": 0.0, "start": 0.0, "end": None}


class BuildError(Exception):
    pass


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def source_path(manifest_dirs: dict, pack: str, file: str) -> Path:
    if pack not in manifest_dirs:
        raise BuildError(f"素材包「{pack}」不在 manifest.json")
    path = RAW / manifest_dirs[pack] / file
    if not path.is_file():
        raise BuildError(f"找不到原始檔：{path.relative_to(ROOT)}（先執行 tools/audio/fetch_audio.py --only {pack}）")
    return path


def spec_for(pipeline: dict, category: str, variant: dict) -> dict:
    spec = dict(SFX_DEFAULT)
    spec.update(pipeline.get("defaults", {}).get("sfx", {}).get(category, {}))
    spec.update({k: v for k, v in variant.items() if k not in ("pack", "file")})
    return spec


def render_sfx(path: Path, spec: dict) -> np.ndarray:
    stereo = bool(spec["stereo"])
    x = lib.decode(path, mono=not stereo)
    if "start" in spec or "end" in spec:
        first = int(float(spec.get("start", 0.0)) * lib.SR)
        last = int(float(spec["end"]) * lib.SR) if spec.get("end") is not None else len(x)
        x = x[first:last]
    if spec["mode"] == "shot":
        start, end = lib.find_shot(x, max_len=float(spec["max_len"]), single=bool(spec["single"]))
        x = x[start:end]
    elif spec["mode"] == "loop":
        x = lib.trim_silence(x, threshold_db=-60.0, tail_ms=0.0)
    else:
        x = lib.trim_silence(x)
    max_samples = int(float(spec["max_len"]) * lib.SR)
    if spec["mode"] != "loop" and len(x) > max_samples:
        x = x[:max_samples]
    x = lib.change_rate(x, float(spec["rate"]))
    if spec.get("lowpass") or spec.get("highpass"):
        x = lib.filter_band(x, lowpass=spec.get("lowpass"), highpass=spec.get("highpass"))
    if spec["mode"] == "loop":
        x = lib.loop_blend(x, blend_ms=float(spec.get("loop_blend_ms", 400.0)))
    else:
        x = lib.fade(x, fade_in_ms=float(spec["fade_in_ms"]), fade_out_ms=float(spec["fade_out_ms"]))
    x = lib.normalize_rms(x, float(spec["target_db"]) + float(spec["gain_db"]))
    return x


def render_music(path: Path, spec: dict) -> np.ndarray:
    x = lib.decode(path, mono=False)
    first = int(float(spec["start"]) * lib.SR)
    last = int(float(spec["end"]) * lib.SR) if spec["end"] is not None else len(x)
    x = x[first:last]
    if float(spec["loop_blend_ms"]) > 0:
        x = lib.loop_blend(x, blend_ms=float(spec["loop_blend_ms"]))
    x = lib.fade(x, fade_in_ms=float(spec["fade_in_ms"]), fade_out_ms=float(spec["fade_out_ms"]))
    return lib.normalize_lufs(x, float(spec["target_lufs"]), float(spec["peak_db"]))


def describe(x: np.ndarray) -> str:
    peak = lib.db(float(np.max(np.abs(x)))) if len(x) else -120.0
    return f"{len(x) / lib.SR:6.2f}s  peak {peak:6.1f} dBFS  rms {lib.active_rms_db(x):6.1f} dB"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="*", default=[])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--report", action="store_true")
    parser.add_argument("--scratch", type=Path)
    parser.add_argument("--pipeline", type=Path, default=PIPELINE)
    args = parser.parse_args()
    global SFX_DIR, MUSIC_DIR
    if args.scratch:
        SFX_DIR, MUSIC_DIR = args.scratch / "sfx", args.scratch / "music"

    pipeline = load_json(args.pipeline)
    manifest = {p["id"]: p for p in load_json(MANIFEST)["packs"]}
    dirs = {pid: p["dir"] for pid, p in manifest.items()}
    bank = load_json(BANK)
    used: dict = {}
    failures = 0

    def note_use(pack: str, file: str, output: str) -> None:
        entry = used.setdefault(pack, {"files": [], "outputs": []})
        if file not in entry["files"]:
            entry["files"].append(file)
        entry["outputs"].append(output)

    wanted_sfx, wanted_music = set(), set()
    for sound_id, item in pipeline.get("sfx", {}).items():
        outputs, packs = [], []
        for n, variant in enumerate(item["variants"], start=1):
            out_name = f"{sound_id}_{n:02d}.ogg"
            wanted_sfx.add(out_name)
            try:
                src = source_path(dirs, variant["pack"], variant["file"])
                spec = spec_for(pipeline, item.get("category", ""), variant)
                note_use(variant["pack"], variant["file"], SFX_RES + out_name)
                if args.only and sound_id not in args.only:
                    outputs.append(SFX_RES + out_name)
                    packs.append(variant["pack"])
                    continue
                x = render_sfx(src, spec)
                if len(x) < int(0.02 * lib.SR):
                    raise BuildError("加工後短於 20 ms，請檢查 mode／start／end")
                if not args.check:
                    lib.encode_ogg(x, SFX_DIR / out_name, quality=float(spec["quality"]))
                if args.report:
                    print(f"{out_name:44} {describe(x)}")
                outputs.append(SFX_RES + out_name)
                packs.append(variant["pack"])
            except (BuildError, OSError, ValueError) as error:
                failures += 1
                print(f"FAIL  {sound_id} #{n}: {error}", file=sys.stderr)
        if outputs:
            entry = bank["sounds"].get(sound_id, {})
            entry["files"] = outputs
            unique = sorted(set(packs))
            entry["pack"] = unique[0] if len(unique) == 1 else unique
            for key in ("volume_db", "pitch", "note"):
                if key in item and key not in entry:
                    entry[key] = item[key]
            bank["sounds"][sound_id] = entry

    for track_id, item in pipeline.get("music", {}).items():
        out_name = f"{track_id}.ogg"
        wanted_music.add(out_name)
        try:
            src = source_path(dirs, item["pack"], item["file"])
            spec = dict(MUSIC_DEFAULT)
            spec.update(pipeline.get("defaults", {}).get("music", {}))
            spec.update({k: v for k, v in item.items() if k not in ("pack", "file")})
            note_use(item["pack"], item["file"], MUSIC_RES + out_name)
            if args.only and track_id not in args.only:
                continue
            x = render_music(src, spec)
            if not args.check:
                lib.encode_ogg(x, MUSIC_DIR / out_name, quality=float(spec["quality"]))
            if args.report:
                print(f"{out_name:44} {describe(x)}  {lib.measure_lufs(x):.1f} LUFS")
        except (BuildError, OSError, ValueError) as error:
            failures += 1
            print(f"FAIL  {track_id}: {error}", file=sys.stderr)

    persist = not args.check and not args.scratch
    if args.check or args.only or args.scratch:
        print(f"檢查完成，{failures} 個失敗" if args.check else f"已重建指定項目，{failures} 個失敗")
        if args.check:
            return 1 if failures else 0
    else:
        # 清掉不再被 pipeline 引用的舊輸出與音效庫項目。
        for folder, wanted in ((SFX_DIR, wanted_sfx), (MUSIC_DIR, wanted_music)):
            if folder.is_dir():
                for stale in folder.glob("*.ogg"):
                    if stale.name not in wanted:
                        stale.unlink()
                        (stale.parent / (stale.name + ".import")).unlink(missing_ok=True)
                        print(f"刪除舊輸出 {stale.relative_to(ROOT)}")
        for sound_id in list(bank["sounds"]):
            files = bank["sounds"][sound_id].get("files", [])
            if sound_id not in pipeline.get("sfx", {}) and files and all(str(f).startswith(SFX_RES) for f in files):
                del bank["sounds"][sound_id]
                print(f"移除音效庫項目 {sound_id}（pipeline 已不再引用）")

    if persist:
        BANK.write_text(json.dumps(bank, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        if not args.only:
            registry = {}
            for pack, info in sorted(used.items()):
                meta = manifest[pack]
                registry[pack] = {"title": meta["title"], "author": meta["author"], "license": meta["license"],
                                  "page": meta["page"], "files_used": sorted(info["files"]), "outputs": sorted(set(info["outputs"]))}
            LICENSES.write_text(json.dumps(registry, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"完成：{len(wanted_sfx)} 個音效檔、{len(wanted_music)} 首曲目、{len(used)} 個素材包，{failures} 個失敗")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
