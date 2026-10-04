"""把 OpenGameArt 的 CC0 頁面加進來源目錄：驗證授權、取出作者與下載連結、寫 manifest 與 hints。

用法：python tools/audio/add_oga.py --kind music|sfx [--use calm,tense] 頁面代稱 [頁面代稱 ...] [--dry-run]
--use 是音樂的用途標籤（menu、victory、defeat、calm、tense、lab、underground、emotional、safe、combat、boss…，和 slot_table.py 的 use 一致），
寫進 hints.json 的 best_for，build_slots.py 挑備選時會優先列出用途相符的曲子。
頁面代稱是網址最後一段（https://opengameart.org/content/<代稱>）。授權欄不是只有 CC0 的頁面（含 CC0 加其他授權的雙授權）一律略過並印出原因。
同一個代稱已在 manifest 就略過。音樂的素材包 id 是「作者_代稱」、資料夾 music/<id>；音效是 oga_<代稱>。
說明文字（頁面描述前 160 字）寫進 hints.json，實驗室的素材清單會顯示。之後照 audio-pipeline：fetch_audio.py → build_catalog.py。
"""
import argparse
import html
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AUDIO_SRC = ROOT / "assets_src" / "audio"
MANIFEST = AUDIO_SRC / "manifest.json"
HINTS = AUDIO_SRC / "hints.json"
UA = {"User-Agent": "Mozilla/5.0 (NestEgg-audio-research)"}
FILE_PATTERN = re.compile(r"\.(ogg|mp3|wav|flac|zip|7z)$", re.I)


def get(url: str) -> str:
    error: Exception = RuntimeError("沒有嘗試")
    for attempt in range(3):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read().decode("utf-8", "replace")
        except OSError as caught:
            error = caught
            time.sleep(2 * (attempt + 1))
    raise error


def slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def read_page(slug: str) -> dict:
    page = f"https://opengameart.org/content/{slug}"
    try:
        text = get(page)
    except OSError as error:
        return {"slug": slug, "error": f"頁面打不開：{error}"}
    licenses = re.findall(r"license-name'>([^<]*)<", text)
    if not licenses or any(name != "CC0" for name in licenses):
        return {"slug": slug, "error": f"授權欄不是只有 CC0（雙授權也不收）：{licenses or '找不到授權欄'}"}
    title = re.search(r'og:title" content="([^"]*)"', text)
    description = re.search(r'og:description" content="([^"]*)"', text)
    author = re.search(r'class="username"[^>]*>([^<]*)<', text)
    files = [f for f in dict.fromkeys(re.findall(r'href="(https://opengameart.org/sites/default/files/[^"?]+)"', text)) if FILE_PATTERN.search(f) and "/css/" not in f]
    if not files:
        return {"slug": slug, "error": "頁面沒有音訊或壓縮檔下載"}
    return {"slug": slug, "page": page, "title": html.unescape(title.group(1)) if title else slug,
            "author": html.unescape(author.group(1)) if author else "", "desc": re.sub(r"\s+", " ", html.unescape(description.group(1))) if description else "",
            "files": files}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", choices=["music", "sfx"], required=True)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--use", default="", help="音樂用途標籤，逗號分隔")
    parser.add_argument("slugs", nargs="+")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    hints = json.loads(HINTS.read_text(encoding="utf-8")) if HINTS.exists() else {}
    for key in ("music", "notes"):
        hints.setdefault(key, {})
    uses = [u for u in args.use.split(",") if u]
    known_pages = {pack["page"].rstrip("/").rsplit("/", 1)[-1] for pack in manifest["packs"]}
    wanted = [s for s in dict.fromkeys(args.slugs) if s not in known_pages]
    print(f"{len(args.slugs)} 個代稱，已在目錄 {len(args.slugs) - len(wanted)} 個")
    with ThreadPoolExecutor(4) as pool:
        pages = list(pool.map(read_page, wanted))
    ids = {pack["id"] for pack in manifest["packs"]}
    added = 0
    for p in pages:
        if "error" in p:
            print(f'略過 {p["slug"]}：{p["error"]}')
            continue
        pack_id = f'{slugify(p["author"]) or "oga"}_{p["slug"]}' if args.kind == "music" else f'oga_{p["slug"]}'
        if pack_id in ids:
            print(f"略過 {p['slug']}：素材包 id {pack_id} 已存在")
            continue
        entry = {"id": pack_id, "kind": args.kind, "title": p["title"], "author": p["author"] or "?", "license": "CC0-1.0", "page": p["page"],
                 "download": p["files"][0] if len(p["files"]) == 1 else p["files"],
                 "dir": f"music/{pack_id}" if args.kind == "music" else pack_id, "notes": p["desc"][:200]}
        print(f'收 {pack_id}（{len(p["files"])} 個檔）{p["title"]}')
        if args.dry_run:
            continue
        manifest["packs"].append(entry)
        ids.add(pack_id)
        added += 1
        for url in p["files"]:
            name = Path(urllib.parse.unquote(urllib.parse.urlparse(url).path)).name
            if args.kind == "music":
                hints["music"][f"{pack_id}/{name}"] = {"best_for": uses, "mood": p["desc"][:160], "loopable": "", "lufs": None, "title": p["title"], "author": p["author"]}
            else:
                hints["notes"][f"{pack_id}/{name}"] = p["desc"][:160]
    if not args.dry_run and added:
        manifest["packs"].sort(key=lambda pack: (pack["kind"], pack["id"]))
        MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        HINTS.write_text(json.dumps(hints, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"新增 {added} 個素材包；接著跑 fetch_audio.py 與 build_catalog.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
