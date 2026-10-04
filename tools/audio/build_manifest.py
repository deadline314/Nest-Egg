"""把調查報告（音效、音樂）合併進 assets_src/audio/manifest.json。

用法：python tools/audio/build_manifest.py [--sfx 音效報告.json] [--music 音樂報告.json]
只收授權寫著 CC0 的項目；其餘一律略過並印出原因。已經在目錄裡的素材包（同一個 id）不會被覆蓋，新的接在後面。
"""
import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets_src" / "audio" / "manifest.json"
RAW = ROOT / "assets_src" / "raw" / "audio"


def relative_dir(local: str) -> str:
    return Path(local).resolve().relative_to(RAW.resolve()).as_posix()


def merge_same_dir(packs: list) -> list:
    """同一個資料夾的多筆（例如同一首歌的完整版與迴圈版）合併成一筆：下載連結取聯集，id 用資料夾名稱。"""
    merged: dict = {}
    for pack in packs:
        key = pack["dir"]
        if key not in merged:
            merged[key] = {**pack, "id": key.removeprefix("music/"), "download": []}
        urls = pack["download"] if isinstance(pack["download"], list) else [pack["download"]]
        for url in urls:
            if url not in merged[key]["download"]:
                merged[key]["download"].append(url)
    for pack in merged.values():
        if len(pack["download"]) == 1:
            pack["download"] = pack["download"][0]
    return list(merged.values())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sfx", type=Path)
    parser.add_argument("--music", type=Path)
    args = parser.parse_args()
    sfx = json.loads(args.sfx.read_text(encoding="utf-8")) if args.sfx else {"packs": []}
    music = json.loads(args.music.read_text(encoding="utf-8")) if args.music else {"tracks": []}
    existing = json.loads(OUT.read_text(encoding="utf-8"))["packs"] if OUT.exists() else []
    packs = []
    for pack in sfx["packs"]:
        if pack["license"].upper() != "CC0":
            print(f'略過 {pack["slug"]}：授權 {pack["license"]}')
            continue
        packs.append({
            "id": pack["slug"], "kind": "sfx", "title": pack["title"], "author": pack["author"], "license": "CC0-1.0",
            "page": pack["page_url"], "download": pack["download_url"], "dir": relative_dir(pack["local_dir"]),
            "notes": pack.get("notes", ""),
        })
    for track in music["tracks"]:
        if track["license"].upper() != "CC0":
            print(f'略過 {track["id"]}：授權 {track["license"]}')
            continue
        folder = Path(track["local_file"]).parent
        packs.append({
            "id": track["id"], "kind": "music", "title": track["title"], "author": track["author"], "license": "CC0-1.0",
            "page": track["page_url"], "download": track["download_url"], "dir": relative_dir(str(folder)),
            "notes": track.get("mood", ""),
        })
    fresh = merge_same_dir(packs)
    known_dirs = {p["dir"] for p in existing}
    added = [p for p in fresh if p["dir"] not in known_dirs]
    packs = sorted(existing + added, key=lambda p: (p["kind"], p["id"]))
    OUT.write_text(json.dumps({"_說明": "CC0 音效與音樂來源目錄。fetch_audio.py 依此下載到 assets_src/raw/audio/；build_audio.py 依 pipeline.json 取用並寫授權登記。", "packs": packs}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"素材包目錄：共 {len(packs)} 筆，新增 {len(added)} 筆 → {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
