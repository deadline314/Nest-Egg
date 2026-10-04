"""把位置清單裡「預計使用」的素材套用到遊戲（NE-163）。

用法：python tools/audio/apply_placements.py [--dry-run] [--no-build] [--doc 清單檔]

讀 design/16-audio/PLACEMENTS.md：
  - 「預計使用」有填素材編號、且「手動放入」沒打勾的位置 → 改寫 assets_src/audio/pipeline.json 該位置的來源，然後重建音訊檔與音效庫／授權登記
  - 打了勾（[x]）的位置 → 略過（使用者自己放了檔案）
  - 預計使用和目前素材一樣的位置 → 不動
新變體沿用位置登記裡的加工參數（slots.json 的 proc，例如槍聲逐發切割、最長秒數）。音樂位置只取第一個編號。
完成後重新產生位置清單，「目前素材」會更新成剛套用的編號。
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))

PLACEMENTS = ROOT / "design" / "16-audio" / "PLACEMENTS.md"
SLOTS = ROOT / "data" / "audio" / "slots.json"
CATALOG = ROOT / "assets_src" / "audio" / "catalog.json"
PIPELINE = ROOT / "assets_src" / "audio" / "pipeline.json"
ROW = re.compile(r"^\|\s*(P-[A-Z]+-\d{3})\s*\|")
ASSET_ID = re.compile(r"\b[A-Z]{3}-\d{4}\b")
PIPELINE_CATEGORY = {"GUN": "gun", "IMP": "impact", "EXP": "explosion", "UIS": "ui", "VOX": "voice", "AMB": "ambience"}


def parse_rows(doc: Path) -> dict:
    rows = {}
    for line in doc.read_text(encoding="utf-8").splitlines():
        match = ROW.match(line)
        if not match:
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) >= 6:
            rows[match.group(1)] = {"planned": ASSET_ID.findall(cells[4]), "manual": cells[5].lower().startswith("[x"), "raw_planned": cells[4]}
    return rows


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--doc", type=Path, default=PLACEMENTS, help="改用另一份位置清單（測試用）")
    args = parser.parse_args()
    slots = {s["id"]: s for s in json.loads(SLOTS.read_text(encoding="utf-8"))["slots"]}
    assets = json.loads(CATALOG.read_text(encoding="utf-8"))["assets"]
    pipeline = json.loads(PIPELINE.read_text(encoding="utf-8"))
    problems, changed = [], []
    for slot_id, row in parse_rows(args.doc).items():
        slot = slots.get(slot_id)
        if slot is None:
            problems.append(f"{slot_id}：位置登記裡沒有這個位置")
            continue
        planned = row["planned"]
        if row["raw_planned"] and not planned:
            problems.append(f"{slot_id}：預計使用「{row['raw_planned']}」看不出素材編號（格式如 GUN-0042）")
            continue
        if not planned or row["manual"] or planned == slot["current"]:
            continue
        unknown = [a for a in planned if a not in assets]
        if unknown:
            problems.append(f"{slot_id}：素材目錄沒有 {'、'.join(unknown)}")
            continue
        if slot["kind"] == "music":
            asset = assets[planned[0]]
            old = pipeline.get("music", {}).get(slot["target"], {})
            entry = {"pack": asset["pack"], "file": asset["file"]}
            if asset["dur"] > 150.0:
                entry.update({"end": 150.0, "loop_blend_ms": 1500.0})
            elif asset["dur"] > 30.0:
                entry["loop_blend_ms"] = old.get("loop_blend_ms", 1500.0)
            pipeline.setdefault("music", {})[slot["target"]] = entry
            if len(planned) > 1:
                problems.append(f"{slot_id}：音樂位置只用第一個編號（{planned[0]}），其餘忽略")
        else:
            item = pipeline.setdefault("sfx", {}).setdefault(slot["target"], {})
            item.setdefault("category", PIPELINE_CATEGORY.get(slot["category"], "foley"))
            proc = dict(slot.get("proc", {}))
            if slot["category"] == "AMB" or planned[0].startswith("AMB"):
                item["category"] = "ambience"
                proc.setdefault("max_len", 30.0)
            item["variants"] = [{"pack": assets[a]["pack"], "file": assets[a]["file"], **proc} for a in planned]
        changed.append(f'{slot_id} {slot["name"]}：{"、".join(slot["current"]) or "（合成音）"} → {"、".join(planned)}')
    for line in changed:
        print("套用  " + line)
    for line in problems:
        print("注意  " + line, file=sys.stderr)
    if not changed:
        print("沒有需要套用的位置。")
        return 1 if problems else 0
    if args.dry_run:
        return 0
    PIPELINE.write_text(json.dumps(pipeline, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    if not args.no_build:
        for command in (["build_audio.py"], ["build_slots.py"]):
            result = subprocess.run([sys.executable, str(Path(__file__).resolve().parent / command[0])])
            if result.returncode != 0:
                print(f"{command[0]} 失敗，請看上面的訊息", file=sys.stderr)
                return result.returncode
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
