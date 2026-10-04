"""產生位置登記 data/audio/slots.json 與位置清單 design/16-audio/PLACEMENTS.md、素材清單 design/16-audio/CATALOG.md（NE-163）。

用法：python tools/audio/build_slots.py [--min-candidates 10] [--max-candidates 30] [--rerank]

位置編號 `P-<域>-<三位數>` 只增不改（已有的位置以目標 id 認）；每個位置列出目前用的素材編號（從加工清單反查素材目錄）
與備選素材編號（目前素材 → 調查報告建議的 → 同類別其他 → 額外可選的類別；已有的備選順序保留，新的接在後面）。
位置清單文件重新產生時，使用者填的「預計使用」與「手動放入」會保留。
"""
import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import slot_table  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
AUDIO_SRC = ROOT / "assets_src" / "audio"
CATALOG = AUDIO_SRC / "catalog.json"
HINTS = AUDIO_SRC / "hints.json"
PIPELINE = AUDIO_SRC / "pipeline.json"
SLOTS = ROOT / "data" / "audio" / "slots.json"
PLACEMENTS = ROOT / "design" / "16-audio" / "PLACEMENTS.md"
CATALOG_MD = ROOT / "design" / "16-audio" / "CATALOG.md"

# 這些域的備選上限比 --max-candidates 高（槍聲與背景音樂的來源多，挑的空間要夠）；已有的備選保留，新素材接在後面。
DOMAIN_MAX = {"WPN": 60, "BGM": 60}
DOMAINS = {"WPN": "武器", "HIT": "命中與材質", "CHR": "角色", "MOV": "移動與腳步", "ENV": "機關與場景互動", "UIS": "介面", "AMB": "環境音", "BGM": "背景音樂"}
ROW = re.compile(r"^\|\s*(P-[A-Z]+-\d{3})\s*\|")


def load(path: Path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def lookup_factory(assets: dict):
    exact = {(a["pack"], a["file"]): aid for aid, a in assets.items()}
    by_stem = {}
    for aid, a in assets.items():
        p = Path(a["file"])
        by_stem[(a["pack"], p.parent.as_posix(), p.stem.lower())] = aid

    def lookup(pack: str, file: str):
        if (pack, file) in exact:
            return exact[(pack, file)]
        p = Path(file)
        return by_stem.get((pack, p.parent.as_posix(), p.stem.lower()))
    return lookup


def current_sfx(pipeline: dict, target: str, lookup) -> list:
    item = pipeline.get("sfx", {}).get(target)
    ids = []
    for variant in (item or {}).get("variants", []):
        for part in variant.get("layers", [variant]):
            aid = lookup(part["pack"], part["file"])
            if aid and aid not in ids:
                ids.append(aid)
    return ids


STOP_TOKENS = {"shot", "gunshot", "loop", "amb", "hit", "mat", "sound", "sfx", "land", "step", "grunt", "death", "hurt", "break", "ding", "game", "main", "wood"}


def tokens_for(slot: dict) -> set:
    """位置的關鍵字：從調查建議的類別名稱與音效 id 拆出來（例如 gunshot_shotgun → shotgun），用來給備選排序。"""
    words = set()
    words.update(w.lower() for w in slot.get("kw", []))
    for name in list(slot.get("hint", [])) + [slot["target"]]:
        for word in name.lower().split("_"):
            if len(word) >= 4 and word not in STOP_TOKENS:
                words.add(word)
    return words


def candidates_for(slot: dict, assets: dict, hints: dict, current: list, previous: list, max_count: int) -> list:
    result = [aid for aid in previous if aid in assets]
    for aid in current:
        if aid not in result:
            result.insert(len(current) and min(len(result), current.index(aid)), aid)
    primary, also = slot["category"], slot.get("also", [])
    dur = slot.get("dur")
    wanted_hint = set(slot.get("hint", []))
    music_use = set(slot.get("use", []))

    def ok(aid: str) -> bool:
        a = assets[aid]
        if dur and not (dur[0] <= a["dur"] <= dur[1]):
            return False
        if slot["kind"] == "music" and not dur and a["dur"] < 40.0:
            return False
        return True

    def hinted(aid: str) -> bool:
        a = assets[aid]
        key = f'{a["pack"]}/{a["file"]}'
        if slot["kind"] == "music":
            return bool(music_use & set(hints.get("music", {}).get(key, {}).get("best_for", [])))
        return bool(wanted_hint & set(hints.get("sfx", {}).get(key, [])))

    words = tokens_for(slot)

    def score(aid: str) -> int:
        a = assets[aid]
        text = f'{a["pack"]} {a["file"]} {a.get("desc", "")}'.lower()
        return sum(1 for w in words if re.search(r"(?<![a-z])" + re.escape(w), text))

    def pool(category: str, only_hinted: bool) -> list:
        ids = [aid for aid in assets if aid.startswith(category + "-") and (hinted(aid) or not only_hinted)]
        return sorted(ids, key=lambda aid: (-score(aid), aid))

    # 關鍵字明確對得上的素材（不分類別）排在最前面：例如電話亭的撥號、話筒，常被歸在機械或其他類。
    cross = sorted((aid for aid in assets if not aid.startswith("MUS-") and slot["kind"] != "music" and score(aid) >= (1 if slot.get("kw") else 3)),
                   key=lambda aid: (-score(aid), aid))[:12]
    pools = [cross, pool(primary, True), pool(primary, False)]
    for category in also:
        pools.append(pool(category, True))
    for category in also:
        pools.append(pool(category, False))
    for pool in pools:
        for aid in pool:
            if len(result) >= max_count:
                return result
            if aid not in result and ok(aid):
                result.append(aid)
    return result


def write_md(slots: list, assets: dict) -> None:
    old = {}
    if PLACEMENTS.exists():
        for line in PLACEMENTS.read_text(encoding="utf-8").splitlines():
            m = ROW.match(line)
            if m:
                cells = [c.strip() for c in line.strip().strip("|").split("|")]
                if len(cells) >= 6:
                    old[m.group(1)] = (cells[4], cells[5])
    lines = [
        "# 音訊位置清單", "",
        "遊戲裡每一個會響的**位置**（`P-` 開頭）目前用哪些**素材**（`GUN-0001` 這種編號，見 [CATALOG.md](CATALOG.md)）。",
        "兩套編號各自獨立：位置編號是「放在哪裡」，素材編號是「放進去什麼」；素材的類別前綴：",
        "GUN 槍聲、RLD 槍械操作、IMP 撞擊與命中、EXP 爆炸、MLE 近戰揮擊、MOV 移動與衣物、VOX 人聲與生物、ITM 物品與拾取、MEC 機械與機關、ELC 電子與能量、UIS 介面、AMB 環境循環、MUS 音樂、OTH 其他。", "",
        "**怎麼用**", "",
        "- 在「預計使用」填你想用的素材編號（可以多個，用逗號或頓號分開；可以跨類別，任何編號都行）。音效實驗室也能直接挑，挑了會寫回這裡。",
        "- 「手動放入」打勾 `[x]` 代表你自己已經把檔案放進遊戲，套用工具會略過這個位置。",
        "- 「備選素材」是依位置挑好的候選，不是限制。",
        "- 填好後執行 `python tools/audio/apply_placements.py` 套用；重新產生本文件（`python tools/audio/build_slots.py`）會保留你填的兩欄。", "",
    ]
    for domain, label in DOMAINS.items():
        rows = [s for s in slots if s["domain"] == domain]
        if not rows:
            continue
        lines += [f"## {label}（{domain}）", "", "| 位置 | 名稱 | 遊戲裡的位置 | 目前素材 | 預計使用 | 手動放入 | 備選素材 |", "|---|---|---|---|---|---|---|"]
        for s in rows:
            planned, manual = old.get(s["id"], ("", "[ ]"))
            current = "、".join(s["current"]) if s["current"] else "（合成音）" if s["kind"] == "sfx" else "（無）"
            cell = lambda text: str(text).replace("|", "／")
            lines.append(f'| {s["id"]} | {cell(s["name"])} | {cell(s["where"])} | {current} | {planned} | {manual or "[ ]"} | {"、".join(s["candidates"])} |')
        lines.append("")
    PLACEMENTS.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_catalog_md(assets: dict, categories: dict, used: dict) -> None:
    lines = ["# 音訊素材清單", "", "每個已下載的 CC0 素材一個編號（只增不改）。完整資料在 `assets_src/audio/catalog.json`；試聽用音效實驗室。", "",
             "欄位：編號｜時長（秒）｜素材包／檔案｜說明｜目前用在哪些位置", ""]
    by_cat: dict = {}
    for aid, a in assets.items():
        by_cat.setdefault(aid.split("-")[0], []).append(aid)
    for cat in sorted(by_cat):
        lines += [f"## {cat} {categories.get(cat, '')}（{len(by_cat[cat])}）", "", "| 編號 | 時長 | 素材包／檔案 | 說明 | 位置 |", "|---|---|---|---|---|"]
        for aid in sorted(by_cat[cat]):
            a = assets[aid]
            lines.append(f'| {aid} | {a["dur"]:.1f} | {a["pack"]}／{a["file"].replace("|", "／")} | {a.get("desc", "").replace("|", "／")} | {"、".join(used.get(aid, []))} |')
        lines.append("")
    CATALOG_MD.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--min-candidates", type=int, default=10)
    parser.add_argument("--max-candidates", type=int, default=30)
    parser.add_argument("--rerank", action="store_true", help="丟掉原本的備選順序，依目前的素材目錄重新排（新增素材後用）")
    args = parser.parse_args()
    catalog = load(CATALOG, {"assets": {}})
    assets, categories = catalog["assets"], catalog.get("categories", {})
    hints, pipeline = load(HINTS, {}), load(PIPELINE, {})
    previous = {s["target"]: s for s in load(SLOTS, {"slots": []})["slots"]}
    lookup = lookup_factory(assets)
    counters = {}
    for s in previous.values():
        counters[s["domain"]] = max(counters.get(s["domain"], 0), int(s["id"].split("-")[-1]))
    entries = []
    for target, domain, name, where, category, also, extra in slot_table.SFX:
        entries.append({"target": target, "domain": domain, "kind": "sfx", "name": name, "where": where, "category": category, "also": also, **extra})
    for target, name, where, extra in slot_table.MUSIC:
        entries.append({"target": target, "domain": "BGM", "kind": "music", "name": name, "where": where, "category": "MUS", "also": [], **extra})
    slots, used, short = [], {}, []
    for e in entries:
        old = previous.get(e["target"])
        if old:
            sid = old["id"]
        else:
            counters[e["domain"]] = counters.get(e["domain"], 0) + 1
            sid = f'P-{e["domain"]}-{counters[e["domain"]]:03d}'
        if e["kind"] == "music":
            item = pipeline.get("music", {}).get(e["target"])
            aid = lookup(item["pack"], item["file"]) if item else None
            current = [aid] if aid else []
        else:
            current = current_sfx(pipeline, e["target"], lookup)
        candidates = candidates_for(e, assets, hints, current, [] if args.rerank or not old else old["candidates"], max(args.max_candidates, DOMAIN_MAX.get(e["domain"], 0)))
        slot = {"id": sid, **{k: e[k] for k in ("domain", "kind", "target", "name", "where", "category")}, "also": e["also"]}
        for key in ("dur", "proc", "hint", "use"):
            if key in e:
                slot[key] = e[key]
        slot["current"], slot["candidates"] = current, candidates
        slots.append(slot)
        for aid in current:
            used.setdefault(aid, []).append(sid)
        if len(candidates) < args.min_candidates:
            short.append((sid, e["target"], len(candidates)))
    slots.sort(key=lambda s: s["id"])
    SLOTS.write_text(json.dumps({"_說明": "位置登記：遊戲裡每一個會響的位置。id 是位置編號（只增不改）；target 是音效庫 id（kind=sfx）或音樂曲目 id（kind=music）；current 是目前用的素材編號、candidates 是備選素材編號（先目前、再依調查建議與同類別排序）。由 tools/audio/build_slots.py 依 tools/audio/slot_table.py 產生，請改表再重跑。",
                                  "domains": DOMAINS, "slots": slots}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    write_md(slots, assets)
    write_catalog_md(assets, categories, used)
    print(f"位置 {len(slots)} 個，素材 {len(assets)} 個；備選不足 {args.min_candidates} 個的位置 {len(short)} 個")
    for sid, target, count in short:
        print(f"  {sid} {target}: {count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
