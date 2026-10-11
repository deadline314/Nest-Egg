#!/usr/bin/env python3
"""章節驗收閘門：檢查驗收票的擋路票（Blocked by）是否都已完成。

唯讀工具：只讀 pm/ 下的票，不寫入任何檔案。
用法：python3 tools/release/chapter_gate.py NE-233 [NE-234 ...] [--root PATH] [--json]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

DEFAULT_ROOT = Path(__file__).resolve().parents[2]  # tools/release/ -> repo 根目錄

# 票代號前綴 -> pm/ 下的專案資料夾
PROJECT_DIRS = {"NE": "Nest-Egg", "BG": "Nest-Egg-BG", "ST": "ST"}
# 視為「已完成」的擋路票狀態（括號內的備註不影響判斷）
DONE_STATUSES = {"完成", "審查中", "取消"}

CODE_RE = re.compile(r"^[A-Z]+-\d+$")
TICKET_CODE_RE = re.compile(r"[A-Z]+-\d+")
STATUS_PREFIX = "> 狀態："
BLOCKED_PREFIX = "- Blocked by："
ACCEPTANCE_HEADING = "### 驗收條件"
CHECKBOX_RE = re.compile(r"^\s*- \[( |x|X)\]")


def normalize_code(code: str) -> str:
    """統一成大寫並檢查格式，例如 ne-233 -> NE-233。"""
    norm = code.strip().upper()
    if not CODE_RE.match(norm):
        raise ValueError(f"票代號格式錯誤：{code!r}（應為 NE-233 這種格式）")
    return norm


def find_tickets(root: Path, code: str) -> list[Path]:
    """回傳檔名以 [code] 開頭的票；整段比對，所以 NE-23 不會命中 NE-233。"""
    code = normalize_code(code)
    prefix = code.split("-")[0]
    if prefix not in PROJECT_DIRS:
        return []
    folder = root / "pm" / PROJECT_DIRS[prefix]
    if not folder.is_dir():
        return []
    return sorted(p for p in folder.glob("*.md") if p.name.startswith(f"[{code}]"))


def parse_ticket(path: Path, root: Path | None = None) -> dict:
    """讀出票的狀態、第一條 Blocked by、驗收條件的勾選數。路徑相對 root 以 posix 格式表示。"""
    lines = path.read_text(encoding="utf-8").splitlines()

    # 第一行以「> 狀態：」開頭的為準
    status = "未知"
    for line in lines:
        if line.startswith(STATUS_PREFIX):
            status = line[len(STATUS_PREFIX):].strip()
            break

    # 第一條 Blocked by 為準；「無」代表沒有擋路票
    blocked_by: list[str] = []
    for line in lines:
        text = line.strip()
        if text.startswith(BLOCKED_PREFIX):
            value = text[len(BLOCKED_PREFIX):].strip()
            if not value.startswith("無"):
                blocked_by = list(dict.fromkeys(TICKET_CODE_RE.findall(value)))
            break

    # 只數「### 驗收條件」區段內的勾選框，遇到下一行 # 開頭的標題就結束
    checked = unchecked = 0
    in_section = False
    for line in lines:
        if not in_section:
            in_section = line.strip() == ACCEPTANCE_HEADING
            continue
        if line.startswith("#"):
            break
        m = CHECKBOX_RE.match(line)
        if m:
            if m.group(1) == " ":
                unchecked += 1
            else:
                checked += 1

    rel = path.relative_to(root).as_posix() if root is not None else path.as_posix()
    return {
        "path": rel,
        "status": status,
        "blocked_by": blocked_by,
        "checked": checked,
        "unchecked": unchecked,
    }


def is_done(status: str) -> bool:
    """狀態去掉括號備註後，是否屬於已完成類。"""
    base = re.split(r"[（(]", status, maxsplit=1)[0].strip()
    return base in DONE_STATUSES


def _rel(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def _unique_ticket(root: Path, code: str) -> Path:
    """找到唯一一張票；找不到或重複都丟 ValueError。"""
    paths = find_tickets(root, code)
    if not paths:
        raise ValueError(f"找不到票 {code}（請確認 pm/ 下有 [{code}] 開頭的檔案）")
    if len(paths) > 1:
        names = "、".join(_rel(p, root) for p in paths)
        raise ValueError(f"票 {code} 有 {len(paths)} 個同號檔案，無法判斷：{names}")
    return paths[0]


def _blocker(root: Path, code: str) -> dict:
    paths = find_tickets(root, code)
    if not paths:
        return {"code": code, "state": "missing", "status": "", "checked": 0, "unchecked": 0, "paths": []}
    rels = [_rel(p, root) for p in paths]
    if len(paths) > 1:
        return {"code": code, "state": "ambiguous", "status": "", "checked": 0, "unchecked": 0, "paths": rels}
    info = parse_ticket(paths[0], root)
    return {
        "code": code,
        "state": "done" if is_done(info["status"]) else "open",
        "status": info["status"],
        "checked": info["checked"],
        "unchecked": info["unchecked"],
        "paths": rels,
    }


def gate(root: Path, code: str) -> dict:
    """計算一張驗收票的擋路票狀態；ready_to_verify 表示所有擋路票都已完成。"""
    code = normalize_code(code)
    ticket = parse_ticket(_unique_ticket(root, code), root)
    blockers = [_blocker(root, b) for b in ticket["blocked_by"]]
    return {
        "ticket": code,
        "status": ticket["status"],
        "checked": ticket["checked"],
        "unchecked": ticket["unchecked"],
        "blockers": blockers,
        "ready_to_verify": all(b["state"] == "done" for b in blockers),
    }


def format_gate(g: dict) -> list[str]:
    """產生給人看的精簡中文摘要：一行表頭，加上每張未完成的擋路票一行。"""
    total = g["checked"] + g["unchecked"]
    pending = [b for b in g["blockers"] if b["state"] != "done"]
    verdict = "可開始驗收" if g["ready_to_verify"] else f"還有 {len(pending)} 張擋住"
    lines = [f"{g['ticket']} {g['status']} {g['checked']}/{total}：{verdict}"]
    for b in pending:
        if b["state"] == "missing":
            lines.append(f"  {b['code']} 找不到票")
        elif b["state"] == "ambiguous":
            lines.append(f"  {b['code']} 票號重複：{' '.join(b['paths'])}")
        else:
            lines.append(
                f"  {b['code']} {b['status']} {b['checked']}/{b['checked'] + b['unchecked']} {b['paths'][0]}"
            )
    return lines


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="檢查章節驗收票的擋路票是否都已完成（唯讀）")
    ap.add_argument("codes", nargs="+", metavar="CODE", help="驗收票代號，例如 NE-233")
    ap.add_argument("--root", type=Path, default=DEFAULT_ROOT, help="repo 根目錄（預設：本工具所在 repo）")
    ap.add_argument("--json", action="store_true", help="以 JSON 輸出")
    args = ap.parse_args(argv)

    root = args.root.resolve()
    results: list[dict] = []
    errors: list[str] = []
    for code in args.codes:
        try:
            results.append(gate(root, code))
        except ValueError as exc:
            errors.append(str(exc))

    if args.json:
        print(json.dumps(results, ensure_ascii=False, indent=2))
    else:
        for g in results:
            for line in format_gate(g):
                print(line)
    for msg in errors:
        print(f"錯誤：{msg}", file=sys.stderr)
    return 2 if errors else 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
