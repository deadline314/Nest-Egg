"""把位置清單裡「預計使用」的素材套用到遊戲（NE-163）。

用法：python tools/audio/apply_placements.py [--dry-run] [--no-build] [--doc 清單檔] [--slots P-WPN-001 ...] [--json] [--result 結果檔]
  --slots   只套用這幾個位置（實驗室的「套用到遊戲」讓使用者勾選）
  --json    結果印成一行 JSON：{"changes": [...], "problems": [...]}，給實驗室讀；--dry-run 時只列出會改什麼
  --result  最後把結果（ok、套用了哪些、錯誤）寫成 JSON 檔，給在背景執行這個工具的實驗室輪詢

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
WEAPONS = ROOT / "data" / "weapons"
FIRE_SOUND = re.compile(r'^fire_sound\s*=\s*&"([^"]+)"', re.M)
## 武器的射擊音效至少要有幾個變體（連射才不會重複；AudioSuite 有同樣的檢查）。
MIN_WEAPON_VARIANTS = 2
## 通關與死亡短曲的長度上限（秒）；音樂測試要求短曲不超過 30 秒。
STING_SECONDS = 12.0


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


def weapon_fire_sounds() -> set:
    """所有武器資料引用的射擊音效 id（data/weapons/**/*.tres 的 fire_sound）。"""
    names = set()
    for path in WEAPONS.rglob("*.tres"):
        names.update(FIRE_SOUND.findall(path.read_text(encoding="utf-8")))
    return names


def plan(doc: Path, only: list | None = None) -> tuple:
    """讀位置清單與素材目錄，算出要套用的位置。回傳（變更清單, 問題, 改過的 pipeline）；不寫任何檔案。警告（仍會套用但可能出問題）放在各變更的 warnings，不算問題。"""
    slots = {s["id"]: s for s in json.loads(SLOTS.read_text(encoding="utf-8"))["slots"]}
    assets = json.loads(CATALOG.read_text(encoding="utf-8"))["assets"]
    pipeline = json.loads(PIPELINE.read_text(encoding="utf-8"))
    fire_sounds = weapon_fire_sounds()
    problems, changes = [], []
    for slot_id, row in parse_rows(doc).items():
        if only is not None and slot_id not in only:
            continue
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
        warnings = []
        if slot["kind"] == "music":
            asset = assets[planned[0]]
            old = pipeline.get("music", {}).get(slot["target"], {})
            entry = {"pack": asset["pack"], "file": asset["file"]}
            if slot["target"].endswith("_sting"):
                # 短曲（通關、死亡）：只取開頭 STING_SECONDS 秒並淡出，不循環
                if asset["dur"] > STING_SECONDS:
                    entry.update({"end": STING_SECONDS, "fade_out_ms": 1500.0})
                    warnings.append(f"短曲只取開頭 {STING_SECONDS:.0f} 秒並淡出（原曲 {asset['dur']:.0f} 秒）")
            elif asset["dur"] > 150.0:
                entry.update({"end": 150.0, "loop_blend_ms": 1500.0})
            elif asset["dur"] > 30.0:
                entry["loop_blend_ms"] = old.get("loop_blend_ms", 1500.0)
            pipeline.setdefault("music", {})[slot["target"]] = entry
            if len(planned) > 1:
                warnings.append(f"音樂位置只用第一個編號（{planned[0]}），其餘忽略")
        else:
            item = pipeline.setdefault("sfx", {}).setdefault(slot["target"], {})
            item.setdefault("category", PIPELINE_CATEGORY.get(slot["category"], "foley"))
            proc = dict(slot.get("proc", {}))
            if slot["category"] == "AMB" or planned[0].startswith("AMB"):
                item["category"] = "ambience"
                proc.setdefault("max_len", 30.0)
            item["variants"] = [{"pack": assets[a]["pack"], "file": assets[a]["file"], **proc} for a in planned]
            if slot["target"] in fire_sounds:
                item["min_variants"] = MIN_WEAPON_VARIANTS
                if len(planned) < MIN_WEAPON_VARIANTS:
                    warnings.append(f"武器射擊音效至少要有 {MIN_WEAPON_VARIANTS} 個變體（連射才不會重複，音訊測試也這樣要求），現在只挑了 {len(planned)} 個素材；一個素材切不出足夠的發數時，會複製並微調音高補到 {MIN_WEAPON_VARIANTS} 個")
        changes.append({"slot": slot_id, "name": slot["name"], "kind": slot["kind"], "target": slot["target"], "current": list(slot["current"]), "planned": planned, "warnings": warnings})
    return changes, problems, pipeline


def run_build() -> int:
    for command in (["build_audio.py"], ["build_slots.py"]):
        result = subprocess.run([sys.executable, str(Path(__file__).resolve().parent / command[0])])
        if result.returncode != 0:
            print(f"{command[0]} 失敗，請看上面的訊息", file=sys.stderr)
            return result.returncode
    return 0


def write_result(path: Path | None, result: dict) -> None:
    if path is not None:
        path.write_text(json.dumps(result, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--doc", type=Path, default=PLACEMENTS, help="改用另一份位置清單（測試用）")
    parser.add_argument("--slots", nargs="*", default=None, help="只套用這幾個位置")
    parser.add_argument("--json", action="store_true", help="結果印成一行 JSON（給實驗室讀）")
    parser.add_argument("--result", type=Path, help="結果寫成 JSON 檔（給在背景執行的實驗室輪詢）")
    args = parser.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    try:
        changes, problems, pipeline = plan(args.doc, args.slots)
    except (OSError, ValueError, KeyError) as error:
        message = f"讀取位置清單或素材目錄失敗：{error}"
        print(json.dumps({"error": message}) if args.json else message, file=sys.stdout if args.json else sys.stderr)
        write_result(args.result, {"ok": False, "applied": [], "problems": [], "error": message})
        return 1
    # --json 的輸出一律只含 ASCII（中文用 \u 跳脫）：Windows 上 Godot 讀工具輸出時用系統碼頁解碼，UTF-8 的中文會變亂碼甚至讓 JSON 讀不出來。
    if args.json and args.dry_run:
        print(json.dumps({"changes": changes, "problems": problems}))
        return 0
    if not args.json:
        for change in changes:
            print(f'套用  {change["slot"]} {change["name"]}：{"、".join(change["current"]) or "（合成音）"} → {"、".join(change["planned"])}')
        for line in problems + [f'{c["slot"]}：{w}' for c in changes for w in c["warnings"]]:
            print("注意  " + line, file=sys.stderr)
    if not changes:
        if not args.json:
            print("沒有需要套用的位置。")
        write_result(args.result, {"ok": not problems, "applied": [], "problems": problems, "error": ""})
        return 1 if problems else 0
    if args.dry_run:
        return 0
    PIPELINE.write_text(json.dumps(pipeline, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    code = 0 if args.no_build else run_build()
    result = {"ok": code == 0, "applied": [c["slot"] for c in changes], "problems": problems, "error": "" if code == 0 else "重建音訊失敗，請看終端機的訊息（pipeline.json 已經改好，修好問題後執行 build_audio.py 與 build_slots.py）"}
    write_result(args.result, result)
    if args.json:
        print(json.dumps({**result, "changes": changes}))
    return code if code != 0 else (1 if problems and not args.json else 0)


if __name__ == "__main__":
    sys.exit(main())
