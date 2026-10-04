"""依配方檔從 Freesound 的 CC0 搜尋結果挑音效，加進來源目錄與提示檔。

用法：python tools/audio/add_freesound.py [--recipes assets_src/audio/freesound_recipes.json] [--dry-run]

不需要帳號或金鑰：搜尋頁加上授權篩選（Creative Commons 0）、依下載數排序，頁面本身就帶有每個聲音的預聽 mp3（128 kbps）、
時長、作者與下載數；原檔需登入才能下載，所以素材用預聽 mp3。授權仍是 CC0，只是格式有損，對槍聲這類短音效，加工後的音質足夠。
配方檔每個素材包有：id、title、queries（搜尋字串）、match／exclude（標題的正規表示式）、min_dur／max_dur（秒）、min_downloads、max（上限）。
結果寫進 assets_src/audio/manifest.json（素材包，同 id 重跑會覆寫）與 hints.json 的 notes（逐檔標題與作者，實驗室的素材說明用）。
之後照 audio-pipeline 的流程：fetch_audio.py 下載、build_catalog.py 編號。
"""
import argparse
import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AUDIO_SRC = ROOT / "assets_src" / "audio"
MANIFEST = AUDIO_SRC / "manifest.json"
HINTS = AUDIO_SRC / "hints.json"
UA = {"User-Agent": "Mozilla/5.0 (NestEgg-audio-research)"}
PAGES_PER_QUERY = 3


def get(url: str) -> str:
    error: Exception = RuntimeError("沒有嘗試")
    for attempt in range(3):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=40).read().decode("utf-8", "replace")
        except OSError as caught:
            error = caught
            time.sleep(2 * (attempt + 1))
    raise error


def search(query: str) -> list[dict]:
    results = []
    for page in range(1, PAGES_PER_QUERY + 1):
        url = "https://freesound.org/search/?" + urllib.parse.urlencode({"q": query, "f": 'license:"Creative Commons 0"', "s": "downloads desc", "page": page})
        found = 0
        for block in get(url).split('class="bw-player"')[1:]:
            def field(name: str) -> str:
                match = re.search(name + r'="([^"]*)"', block)
                return match.group(1) if match else ""
            if not field("data-sound-id") or not field("data-mp3"):
                continue
            found += 1
            results.append({"id": field("data-sound-id"), "user": field("data-username"), "title": html.unescape(field("data-title")),
                            "dur": float(field("data-duration") or 0.0), "downloads": int(field("data-num-downloads") or 0),
                            "mp3": field("data-mp3").replace("-lq.mp3", "-hq.mp3")})
        if found == 0:
            break
    return results


def select(recipe: dict) -> list[dict]:
    chosen: dict = {}
    match = re.compile(recipe.get("match", "."), re.I)
    exclude = re.compile(recipe["exclude"], re.I) if recipe.get("exclude") else None
    for query in recipe["queries"]:
        for sound in search(query):
            if sound["id"] in chosen or not match.search(sound["title"]) or (exclude and exclude.search(sound["title"])):
                continue
            if not recipe.get("min_dur", 0.0) <= sound["dur"] <= recipe.get("max_dur", 60.0) or sound["downloads"] < recipe.get("min_downloads", 0):
                continue
            chosen[sound["id"]] = sound
    return sorted(chosen.values(), key=lambda s: -s["downloads"])[: recipe.get("max", 30)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--recipes", type=Path, default=AUDIO_SRC / "freesound_recipes.json")
    parser.add_argument("--only", nargs="*", default=[], help="只處理這些素材包 id")
    parser.add_argument("--dry-run", action="store_true", help="只列出會收哪些，不寫檔")
    args = parser.parse_args()
    recipes = [r for r in json.loads(args.recipes.read_text(encoding="utf-8"))["packs"] if not args.only or r["id"] in args.only]
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    hints = json.loads(HINTS.read_text(encoding="utf-8")) if HINTS.exists() else {}
    hints.setdefault("notes", {})
    by_id = {pack["id"]: pack for pack in manifest["packs"]}
    for recipe in recipes:
        sounds = select(recipe)
        print(f'{recipe["id"]}：{len(sounds)} 個')
        for s in sounds:
            print(f'   {s["id"]:>7} {s["downloads"]:>6} 下載 {s["dur"]:5.1f}s  {s["title"][:56]}（{s["user"]}）')
        if args.dry_run or not sounds:
            continue
        by_id[recipe["id"]] = {
            "id": recipe["id"], "kind": "sfx", "title": recipe["title"], "author": "Freesound 使用者（逐檔作者見 hints.json）", "license": "CC0-1.0",
            "page": "https://freesound.org/search/?" + urllib.parse.urlencode({"q": recipe["queries"][0], "f": 'license:"Creative Commons 0"'}),
            "download": [s["mp3"] for s in sounds], "dir": recipe["id"],
            "notes": f'Freesound CC0 預聽 mp3（128 kbps）；{recipe.get("notes", "")}',
        }
        for s in sounds:
            hints["notes"][f'{recipe["id"]}/{Path(s["mp3"]).name}'] = f'{s["title"]}（{s["user"]}，{s["dur"]:.1f} 秒）'[:160]
    if args.dry_run:
        return 0
    manifest["packs"] = sorted(by_id.values(), key=lambda p: (p["kind"], p["id"]))
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    HINTS.write_text(json.dumps(hints, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"已更新 {MANIFEST.relative_to(ROOT)}、{HINTS.relative_to(ROOT)}；接著跑 fetch_audio.py 與 build_catalog.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
