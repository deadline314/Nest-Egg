"""建立素材目錄 assets_src/audio/catalog.json：每個已下載的 CC0 音訊檔一個永久編號（NE-163）。

用法：python tools/audio/build_catalog.py [--sfx-report 音效報告.json] [--music-report 音樂報告.json] [--stats]

編號格式 `<類>-<四位數>`（類見 CATEGORIES），只增不改：已經有編號的檔案（以素材包＋相對路徑認）不會被重編，
也不會因為分類規則改了而換編號；新找到的檔案接在該類目前最大號碼後面。同一個聲音有多種格式（wav、mp3、ogg）時只收一份。
--sfx-report／--music-report 把調查報告裡的「建議用途」（音效類別、音樂用途與情緒）寫進 assets_src/audio/hints.json，之後挑備選時當排序依據。
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AUDIO_SRC = ROOT / "assets_src" / "audio"
RAW = ROOT / "assets_src" / "raw" / "audio"
MANIFEST = AUDIO_SRC / "manifest.json"
CATALOG = AUDIO_SRC / "catalog.json"
HINTS = AUDIO_SRC / "hints.json"
EXTENSIONS = {".ogg": 0, ".wav": 1, ".flac": 2, ".mp3": 3}

CATEGORIES = {
    "GUN": "槍聲", "RLD": "槍械操作", "IMP": "撞擊與命中", "EXP": "爆炸", "MLE": "近戰揮擊", "MOV": "移動與衣物",
    "VOX": "人聲與生物", "ITM": "物品與拾取", "MEC": "機械與機關", "ELC": "電子與能量", "UIS": "介面", "AMB": "環境循環", "MUS": "音樂", "OTH": "其他",
}

# 依序比對「素材包 id／相對路徑」（小寫），第一個命中的類別為準。
# 這些檔案是整句語音（比賽播報員等），專案不收語音。
EXCLUDE = r"announcer|arenacombat"

RULES: list[tuple[str, str]] = [
    # Freesound 專題素材包（add_freesound.py）：檔名只有編號，靠素材包名稱歸類
    ("ELC", r"^fs_cc0-(emp|overload|ability-ready)/"),
    ("ITM", r"^fs_cc0-pickup/"),
    ("MEC", r"^fs_cc0-phone-(ring|handset)/"),
    ("ELC", r"^fs_cc0-phone-dial/"),
    ("IMP", r"^fs_cc0-(headshot|shield-break|kill-burst)/"),
    ("MLE", r"^fs_cc0-sword-(ring|cut)/"),
    ("UIS", r"interface-sounds|ui-audio|ui-sound|/ui_|menu_|rollover|confirmation_|_ui\b|buttons-switches|button-sfx"),
    ("RLD", r"reload|clipload|singlebullet|shotguncock|shotgun-reload|magazine|dryfire|equipment-click|lock-or-click|\brack\b|shell in chamber|gunreload|cocking|\bcock\b|loading|\bclip\b|eject|breech|pulling back hammer|cylinder|gun movement|handling"),
    ("GUN", r"firearm|gunshot|gun-shot|gun_shot|cannon-fire|cannon_fire|bigshot|smallshot|silencer|shotgun|rifle|pistol|handgun|\bsmg\b|bullet|/gun|-gun|gun-|/shot|_shot"),
    ("EXP", r"explo|bang|blast|boom|firework|detonat|cannon_hit|cannon-hit"),
    ("MLE", r"swish|swosh|whoosh|sword|blade|slash|swing|clash|weapon-sw|machete|thwack|chop|knifeslice|drawknife|melee"),
    ("MOV", r"footstep|metal_steps|\bsteps?\b|jump|landing|cloth|belt|leather|rustle|run(ning)?\b|scorchers-foley"),
    ("ITM", r"coin|gem|item|book|paper|\bcup\b|_cup|dishes|bell|gong|key_open|\bpot\b|metalpot|toilet|plop|craft|hammer|plug-"),
    ("VOX", r"pain|scream|grunt|dead|death|\bdie\b|voice|monster|growl|creature|creture|alien|breath|bite|chomp|\beat_|roar|bark|vocal|cough|hurt|moan|zombie|snore|ghoul|human|slime|\bbug|attack|stomp"),
    ("AMB", r"ambien|ambience|amb[_-]|loop|rain|wind|thunder|drip|crackling|steam|generator|crowd|background|noise|hum\b|hiss|helicopter|traffic|rumbl|gas-leak|gas_leak|\bair\b|_air|fire|flame|ignition|flare"),
    ("ELC", r"electric|spark|zap|laser|sci-?fi|power|charge|shield|force|thruster|phaser|computer|terminal|digital|beep|tone|alarm|siren|hover|space|robot|wobble|spell"),
    ("IMP", r"impact|hit|punch|thud|crash|break|breaking|smash|slam|glass|wood|metal-dings|ding|clang|crack|crunch|slap|splash|fall|collision|meat"),
    ("MEC", r"door|gate|winch|chain|motor|machine|mechanic|switch|lever|button|click|servo|lock|latch|clank|rattle|gear|pump|fan|typewriter|workshop|tool|drill|engine|squeak|creak|metal|spring|interaction"),
]


def classify(pack: str, relative: str, kind: str) -> str:
    if kind == "music":
        return "MUS"
    text = f"{pack}/{relative}".lower()
    for category, pattern in RULES:
        if re.search(pattern, text):
            return category
    return "OTH"


def probe_duration(path: Path) -> float:
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", str(path)],
                             capture_output=True, text=True, timeout=60).stdout.strip()
        return round(float(out), 2)
    except (ValueError, subprocess.SubprocessError):
        return 0.0


def list_audio(folder: Path) -> list[Path]:
    """資料夾內所有音訊檔；同一個資料夾、同樣檔名（不含副檔名）的多種格式只留優先格式。"""
    best: dict = {}
    for path in sorted(folder.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in EXTENSIONS or "__MACOSX" in path.parts:
            continue
        key = (path.parent, path.stem.lower())
        if key not in best or EXTENSIONS[path.suffix.lower()] < EXTENSIONS[best[key].suffix.lower()]:
            best[key] = path
    return sorted(best.values())


def import_reports(sfx_path: Path | None, music_path: Path | None) -> None:
    """把調查報告的建議用途合併進 hints.json（已有的保留，同一個檔案的類別取聯集）。"""
    sfx = json.loads(sfx_path.read_text(encoding="utf-8")) if sfx_path else {}
    music = json.loads(music_path.read_text(encoding="utf-8")) if music_path else {}
    hints = json.loads(HINTS.read_text(encoding="utf-8")) if HINTS.exists() else {}
    for key in ("sfx", "music", "notes"):
        hints.setdefault(key, {})
    for category, items in sfx.get("category_candidates", {}).items():
        for item in items:
            if item.get("why"):
                hints["notes"][f'{item["pack"]}/{item["file"]}'] = item["why"]
            hints["sfx"].setdefault(f'{item["pack"]}/{item["file"]}', [])
            if category not in hints["sfx"][f'{item["pack"]}/{item["file"]}']:
                hints["sfx"][f'{item["pack"]}/{item["file"]}'].append(category)
    for track in music.get("tracks", []):
        local = Path(track["local_file"])
        key = f'{local.parent.name}/{local.name}'
        hints["music"][key] = {"best_for": track.get("best_for", []), "mood": track.get("mood", ""), "loopable": track.get("loopable", ""),
                               "lufs": track.get("lufs"), "title": track.get("title", ""), "author": track.get("author", "")}
    HINTS.write_text(json.dumps(hints, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"提示：{len(hints['sfx'])} 個音效檔、{len(hints['music'])} 首曲目 → {HINTS.relative_to(ROOT)}")


def firearm_descriptions() -> dict:
    """Firearm Library 的檔名只有代號（A_42P.wav），說明在它自己的 csv 裡：回傳 {相對路徑: 說明}。"""
    result = {}
    folder = RAW / "oga_the-free-firearm-sound-library" / "Prepared SFX Library"
    sheet = folder / "Prepared Master Sheet.csv"
    if not sheet.exists():
        return result
    import csv
    names = {}
    for path in folder.rglob("*.wav"):
        names[path.name] = path.relative_to(RAW / "oga_the-free-firearm-sound-library").as_posix()
    with sheet.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            if row.get("Filename") in names:
                result[names[row["Filename"]]] = re.sub(r"\s+", " ", row.get("Description", "")).strip()
    return result


def describe(pack: str, relative: str, hints: dict, firearm: dict) -> str:
    key = f"{pack}/{relative}"
    if pack == "oga_the-free-firearm-sound-library" and relative in firearm:
        return firearm[relative][:160]
    if key in hints.get("music", {}):
        return str(hints["music"][key].get("mood", ""))[:160]
    return str(hints.get("notes", {}).get(key, ""))[:160]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sfx-report", type=Path, help="音效調查報告（合併進 hints.json）")
    parser.add_argument("--music-report", type=Path, help="音樂調查報告（合併進 hints.json）")
    parser.add_argument("--stats", action="store_true")
    args = parser.parse_args()
    if shutil.which("ffprobe") is None:
        print("找不到 ffprobe：量時長需要 ffmpeg（Windows：scoop install ffmpeg），裝好後重開終端機再跑。", file=sys.stderr)
        return 1
    if args.sfx_report or args.music_report:
        import_reports(args.sfx_report, args.music_report)
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))["packs"]
    existing = json.loads(CATALOG.read_text(encoding="utf-8")) if CATALOG.exists() else {"assets": {}}
    live_packs = {pack["id"] for pack in manifest}
    assets: dict = {aid: a for aid, a in existing["assets"].items() if a["pack"] in live_packs}
    dropped = len(existing["assets"]) - len(assets)
    known = {(a["pack"], a["file"]): aid for aid, a in assets.items()}
    counters = {}
    for aid in existing["assets"]:  # 剔除的編號也不重用
        category, number = aid.split("-")
        counters[category] = max(counters.get(category, 0), int(number))
    pending = []
    for pack in manifest:
        folder = RAW / pack["dir"]
        if not folder.is_dir() or pack.get("local"):  # 本機產生的片段素材包由 clip_tool.py 登記編號
            continue
        for path in list_audio(folder):
            relative = path.relative_to(folder).as_posix()
            if re.search(EXCLUDE, f'{pack["id"]}/{relative}'.lower()):
                continue
            if (pack["id"], relative) not in known:
                pending.append((pack, relative, path))
    with ThreadPoolExecutor(max_workers=8) as pool:
        durations = list(pool.map(lambda item: probe_duration(item[2]), pending))
    added = 0
    for (pack, relative, _path), duration in zip(pending, durations):
        category = classify(pack["id"], relative, pack["kind"])
        counters[category] = counters.get(category, 0) + 1
        aid = f"{category}-{counters[category]:04d}"
        assets[aid] = {"pack": pack["id"], "file": relative, "dur": duration}
        added += 1
    hints = json.loads(HINTS.read_text(encoding="utf-8")) if HINTS.exists() else {}
    firearm = firearm_descriptions()
    for aid, a in assets.items():
        text = describe(a["pack"], a["file"], hints, firearm)
        if text:
            a["desc"] = text
    ordered = dict(sorted(assets.items()))
    CATALOG.write_text(json.dumps({"_說明": "素材目錄：素材編號 → 素材包、檔案、時長（秒）。編號只增不改，由 tools/audio/build_catalog.py 維護；類別前綴見 design/16-audio/DESIGN.md 5.1。", "categories": CATEGORIES, "assets": ordered}, ensure_ascii=False, indent=0) + "\n", encoding="utf-8")
    print(f"素材目錄：共 {len(ordered)} 筆，新增 {added} 筆，剔除 {dropped} 筆（素材包已不在 manifest）")
    if args.stats or added:
        by = {}
        for aid in ordered:
            by[aid.split("-")[0]] = by.get(aid.split("-")[0], 0) + 1
        print("  ".join(f"{c}:{n}" for c, n in sorted(by.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
