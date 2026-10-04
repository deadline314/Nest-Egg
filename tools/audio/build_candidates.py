"""產生預聽用小檔案 assets_src/audition/<素材編號>.ogg（NE-163）。不進版控；音效實驗室試聽用。

用法：python tools/audio/build_candidates.py [--only 編號或前綴 ...] [--force] [--jobs N]

與正式加工同一套響度標準，所以試聽到的音量就是套用後的音量：
  音效  單聲道，去掉頭尾靜音，最長 4 秒（環境循環 12 秒），有聲部分 RMS 對齊 -20 dB、峰值不超過 -1 dBFS
  音樂  立體聲，取前 60 秒，整合響度 -18 LUFS
已存在的預聽檔會略過（--force 重做）；單檔失敗只記錄、不中斷。
"""
import argparse
import json
import sys
from multiprocessing import Pool
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audio_lib as lib  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "assets_src" / "audio" / "catalog.json"
MANIFEST = ROOT / "assets_src" / "audio" / "manifest.json"
RAW = ROOT / "assets_src" / "raw" / "audio"
OUT = ROOT / "assets_src" / "audition"
SFX_MAX = 4.0
LOOP_MAX = 12.0
MUSIC_MAX = 60.0


def render(job: tuple) -> tuple:
    aid, source, out = job
    try:
        category = aid.split("-")[0]
        if category == "MUS":
            x = lib.decode(source, mono=False)[: int(MUSIC_MAX * lib.SR)]
            x = lib.fade(x, fade_in_ms=0, fade_out_ms=300)
            x = lib.normalize_lufs(x, -18.0)
            lib.encode_ogg(x, out, quality=1.0)
        else:
            looped = category == "AMB"
            x = lib.decode(source, mono=not looped)
            x = lib.trim_silence(x, threshold_db=-60.0 if looped else -48.0)
            limit = LOOP_MAX if looped else SFX_MAX
            x = x[: int(limit * lib.SR)]
            x = lib.fade(x, fade_in_ms=1.0, fade_out_ms=20.0 if len(x) < int(limit * lib.SR) else 200.0)
            x = lib.normalize_rms(x, -20.0 if not looped else -26.0)
            lib.encode_ogg(x, out, quality=3.0)
        return aid, ""
    except Exception as error:  # noqa: BLE001 單檔失敗不阻擋其他檔
        return aid, str(error)[:200]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="*", default=[])
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--jobs", type=int, default=8)
    args = parser.parse_args()
    assets = json.loads(CATALOG.read_text(encoding="utf-8"))["assets"]
    dirs = {p["id"]: p["dir"] for p in json.loads(MANIFEST.read_text(encoding="utf-8"))["packs"]}
    jobs = []
    missing_packs: set[str] = set()
    for aid, a in assets.items():
        if args.only and not any(aid == o or aid.startswith(o) for o in args.only):
            continue
        source = RAW / dirs[a["pack"]] / a["file"]
        out = OUT / f"{aid}.ogg"
        if not source.is_file():
            missing_packs.add(a["pack"])
        elif args.force or not out.exists():
            jobs.append((aid, source, out))
    OUT.mkdir(parents=True, exist_ok=True)
    failed = 0
    with Pool(args.jobs) as pool:
        for n, (aid, error) in enumerate(pool.imap_unordered(render, jobs, chunksize=8), start=1):
            if error:
                failed += 1
                print(f"FAIL  {aid}: {error}", file=sys.stderr)
            if n % 200 == 0:
                print(f"  {n}/{len(jobs)}")
    print(f"預聽檔：處理 {len(jobs)} 個，失敗 {failed} 個 → {OUT.relative_to(ROOT)}")
    if missing_packs:
        print(
            f"找不到 {len(missing_packs)} 個素材包的原始檔（{RAW.relative_to(ROOT)}，不進版控）。"
            "請先執行 python tools/audio/fetch_audio.py 下載（約 3 GB，已下載的會略過），再重跑這個工具。",
            file=sys.stderr,
        )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
