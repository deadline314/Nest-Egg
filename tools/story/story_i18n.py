"""劇本的三語欄位（ST-2）：中文原文寫在作者來源，日文與英文寫在 tools/story/i18n/<章節>.json 的對照表，
產生器輸出劇本時把每一句、每個選項與提示補上 ja／en 欄位。

規則（遊戲端見 core/story_locale.gd）：
- 「text」的譯文放在同一個字典的 ja／en；其他可見欄位 K（選項的 explanation 等）放在 K_ja／K_en。
- 對照表以中文原文為鍵：原文改了就視為缺譯，產生器列出具體場景與位置，遊戲退回英文，再退回中文。
- 雙關句在對照表標 "transcreate": true，輸出時保留標記（三種語言各自重寫，不逐字翻）。
- 對照表格式：{"<中文>": {"ja": "...", "en": "...", "transcreate": true?, "note": "給譯者的說明（不輸出）"}}

用法：
  python3 tools/story/story_i18n.py --missing data/story/ch1_kasa.json [--table tools/story/i18n/ch1_kasa.json]
      列出還沒有譯文的中文句子（JSON，供譯者補）。
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TABLE_DIR = ROOT / "tools/story/i18n"
LANGUAGES = ("ja", "en")
# 劇本裡玩家看得到的文字欄位（場景台詞、旁白、選項、選擇提示、章節資訊、任務）。
VISIBLE_FIELDS = ("text", "explanation", "title", "subtitle", "end_title", "teaser", "release_note", "end_card", "background", "reward",
                  "blocked_reason", "suggestion", "prompt")
# 這些子樹不是玩家看的文字（舞台參數、條件、旗標）。
SKIP_KEYS = {"when", "set_flags", "results", "routes", "flag_defaults", "derived_flags", "transactions", "runtime_facts",
             "speakers", "stages"}


def table_path(chapter: str) -> Path:
    return TABLE_DIR / f"{chapter}.json"


def load_table(path: Path) -> dict:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{path}: 對照表要是物件（中文 → 譯文）")
    for zh, entry in data.items():
        if not isinstance(entry, dict):
            raise ValueError(f"{path}: 「{zh}」的譯文要是物件")
    return data


def _localized_key(field: str, lang: str) -> str:
    return lang if field == "text" else f"{field}_{lang}"


def walk(node, path="", out=None):
    """列出 (路徑, 字典, 欄位, 中文) — 每一個玩家看得到、還是中文的欄位。"""
    if out is None:
        out = []
    if isinstance(node, dict):
        for key, value in node.items():
            if key in SKIP_KEYS:
                continue
            if key in VISIBLE_FIELDS and isinstance(value, str) and value.strip() and _has_cjk(value):
                out.append((f"{path}/{key}", node, key, value))
            elif isinstance(value, (dict, list)):
                walk(value, f"{path}/{key}", out)
    elif isinstance(node, list):
        for index, value in enumerate(node):
            walk(value, f"{path}/{index}", out)
    return out


def _has_cjk(text: str) -> bool:
    return any("㐀" <= ch <= "鿿" for ch in text)


def _speaker_names(document: dict):
    """講者的名牌（speakers.<id>.name）也是玩家看得到的字：列出 (路徑, 字典, 'name', 中文)。"""
    speakers = document.get("speakers", {})
    return [(f"/speakers/{ident}/name", entry, "name", entry["name"]) for ident, entry in speakers.items()
            if isinstance(entry, dict) and isinstance(entry.get("name"), str) and _has_cjk(entry["name"])]


def apply(document: dict, table: dict) -> list[str]:
    """把對照表的譯文補進輸出文件（只在欄位還沒有譯文時補，作者來源寫死的譯文優先）。回傳缺譯的位置。"""
    missing = []
    for path, owner, field, zh in _speaker_names(document):
        entry = table.get(zh, {})
        for lang in LANGUAGES:
            key = f"name_{lang}"
            if not owner.get(key):
                if entry.get(lang):
                    owner[key] = entry[lang]
                else:
                    missing.append(f"{path} [{lang}] {zh}")
    for path, owner, field, zh in walk(document):
        entry = table.get(zh, {})
        for lang in LANGUAGES:
            key = _localized_key(field, lang)
            if owner.get(key):
                continue
            text = entry.get(lang, "")
            if isinstance(text, str) and text.strip():
                owner[key] = text
            else:
                missing.append(f"{path} [{lang}] {zh}")
        if entry.get("transcreate") and field == "text":
            owner["transcreate"] = True
    return missing


def missing_strings(document: dict, table: dict) -> list[str]:
    seen = []
    for _path, owner, field, zh in [*_speaker_names(document), *walk(document)]:
        if zh in seen:
            continue
        entry = table.get(zh, {})
        key = (lambda lang: f"name_{lang}") if field == "name" else (lambda lang: _localized_key(field, lang))
        if all(owner.get(key(lang)) or entry.get(lang) for lang in LANGUAGES):
            continue
        seen.append(zh)
    return seen


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--missing", required=True, help="輸出的劇本 JSON")
    parser.add_argument("--table", help="對照表（預設 tools/story/i18n/<章節 id>.json）")
    args = parser.parse_args(argv)
    document = json.loads(Path(args.missing).read_text(encoding="utf-8"))
    chapter = str(document.get("chapter", {}).get("id", Path(args.missing).stem))
    table = load_table(Path(args.table) if args.table else table_path(chapter))
    print(json.dumps(missing_strings(document, table), ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
