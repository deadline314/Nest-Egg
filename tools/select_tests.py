#!/usr/bin/env python3
"""依有更動的檔案，挑出受影響、需要跑的測試套件。

用法：python tools/select_tests.py [--base origin/main] [--files a b ...] [--explain] [--all]
輸出：逗號分隔的套件名稱（可直接給 tests/smoke_test.tscn 的 --only=；main 是開頭那一大段流程測試）。沒有受影響的測試就輸出空字串。

原理（靜態影響分析）：
  1. 為每個檔案建立相依關係：GDScript 用到另一個檔案的 class_name 或單例名稱，或字串裡出現它的 res:// 路徑（或它所在的資料夾）；
     .tres／.tscn／.json 內寫到的 res:// 路徑也算相依。
  2. 從有更動的檔案出發，沿著「誰用到它」往外找（最多 MAX_DEPTH 層），碰到測試套件（tests/suite/*.gd）或流程測試（tests/smoke_test.gd）就收進來。
     被超過 HUB_DEPENDENTS 個檔案用到的核心（Player、Sfx、Level…）只在它自己被更動時才往外展開，
     不然改一個資料檔就會經過 Player 牽連到所有測試，失去「只跑受影響範圍」的意義。
  3. 更動的檔案本身是測試時，就是那個套件。
改動單一工具只會挑到相關套件；改到被大量使用的核心（例如 Player、Sfx）會挑到很多，接近完整測試，這是預期的。
這是保守的估計，不是證明：完整測試仍由 CI 排程負責（.github/workflows/tests.yml）。
"""
import argparse
import re
import subprocess
import sys
from collections import defaultdict, deque
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", ".godot", "assets_src", "pm", "design", "node_modules", "__pycache__"}
SCAN_EXT = {".gd", ".tres", ".tscn", ".json", ".gdshader", ".cfg"}
# 這些變動會影響整個專案或測試流程本身，直接跑全部。
# 往外找幾層；核心檔（被這麼多檔案用到）只有「自己被更動」時才展開。
MAX_DEPTH = 8
HUB_DEPENDENTS = 30
RUN_ALL = {"project.godot", "tests/smoke_test.gd", "tools/run_tests.sh", "tools/run_tests_parallel.sh", "tools/test_filters.sh", "tools/select_tests.py"}
CLASS_RE = re.compile(r"^class_name\s+(\w+)", re.M)
PATH_RE = re.compile(r"res://[\w./\-]+")
AUTOLOAD_RE = re.compile(r'^(\w+)="\*?res://([^"]+)"', re.M)
WORD_RE = re.compile(r"[A-Za-z_]\w*")


def tracked_files():
    out = subprocess.run(["git", "ls-files", "-co", "--exclude-standard"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return [line for line in out.splitlines() if line and not any(part in SKIP_DIRS for part in Path(line).parts)]


def changed_files(base):
    names = set()
    for cmd in (["git", "diff", "--name-only", f"{base}...HEAD"], ["git", "diff", "--name-only", "HEAD"], ["git", "ls-files", "-o", "--exclude-standard"]):
        result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        if result.returncode == 0:
            names.update(line for line in result.stdout.splitlines() if line)
    return sorted(names)


def read_text(path):
    try:
        return (ROOT / path).read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return ""


def strip_suite_registration(text):
    """smoke_test.gd 的 _suites() 只是登記每個套件，不算流程測試用到它們。"""
    start = text.find("func _suites()")
    if start < 0:
        return text
    end = text.find("\nfunc ", start + 1)
    return text[:start] + (text[end:] if end > 0 else "")


def build_graph(files):
    texts = {f: read_text(f) for f in files if Path(f).suffix in SCAN_EXT}
    provides = {}  # 名稱 -> 檔案
    autoloads = AUTOLOAD_RE.findall(read_text("project.godot"))
    for name, rel in autoloads:
        provides[name] = rel
    for f, text in texts.items():
        if f.endswith(".gd"):
            for name in CLASS_RE.findall(text):
                provides[name] = f
    suite_of = {}  # 測試檔 -> 套件名稱
    for f, text in texts.items():
        if f.startswith("tests/suite/") and f.endswith(".gd"):
            names = CLASS_RE.findall(text)
            if names and names[0].endswith("Suite") and "@abstract" not in text.split("class_name")[0]:
                suite_of[f] = names[0]
    dir_members = defaultdict(list)  # 資料夾 res:// 路徑 -> 該資料夾（含子資料夾）底下的檔案
    for f in files:
        parts = Path(f).parts
        for i in range(2, len(parts)):  # 至少兩層，避免 res://art 這種太大的範圍
            dir_members["res://" + "/".join(parts[:i])].append(f)
    dependents = defaultdict(set)  # 檔案 -> 用到它的檔案
    for f, text in texts.items():
        scan_text = strip_suite_registration(text) if f == "tests/smoke_test.gd" else text
        used = set()
        if f.endswith(".gd"):
            for word in set(WORD_RE.findall(scan_text)):
                target = provides.get(word)
                if target and target != f:
                    used.add(target)
        for path in set(PATH_RE.findall(scan_text)):
            stripped = path.rstrip("/")
            rel = stripped[len("res://"):]
            if rel in files_set(files) and rel != f:
                used.add(rel)
            for member in dir_members.get(stripped, []):
                if member != f:
                    used.add(member)
        for target in used:
            dependents[target].add(f)
    return dependents, suite_of


_files_cache = None


def files_set(files):
    global _files_cache
    if _files_cache is None:
        _files_cache = set(files)
    return _files_cache


def select(changed, files):
    dependents, suite_of = build_graph(files)
    reasons = {}
    depth = {}
    queue = deque()
    for f in changed:
        reasons[f] = "有更動"
        depth[f] = 0
        queue.append(f)
    while queue:
        current = queue.popleft()
        users = dependents.get(current, ())
        if depth[current] >= MAX_DEPTH or (depth[current] > 0 and len(users) > HUB_DEPENDENTS):
            continue
        for user in users:
            if user not in reasons:
                reasons[user] = current
                depth[user] = depth[current] + 1
                queue.append(user)
    chosen = {}
    for f in reasons:
        if f in suite_of:
            chosen[suite_of[f]] = f
        elif f == "tests/smoke_test.gd":
            chosen["main"] = f
    return chosen, reasons


def explain_chain(reasons, f):
    chain = [f]
    while reasons.get(chain[-1]) not in (None, "有更動"):
        chain.append(reasons[chain[-1]])
    return " ← ".join(chain)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="origin/main")
    parser.add_argument("--files", nargs="*")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--explain", action="store_true")
    args = parser.parse_args()
    files = tracked_files()
    all_suites = sorted(set(re.findall(r"class_name\s+(\w+Suite)\b", "\n".join(read_text(f) for f in files if f.startswith("tests/suite/")))))
    changed = args.files if args.files is not None else changed_files(args.base)
    if args.all or any(f in RUN_ALL for f in changed):
        print("ALL" if not args.explain else "全部（改到整個專案或測試流程本身）")
        return 0
    code_changes = [f for f in changed if not f.startswith(("pm/", "design/", "assets_src/")) and not f.endswith((".md", ".py")) or f == "tools/select_tests.py"]
    chosen, reasons = select(code_changes, files)
    if args.explain:
        for name, f in sorted(chosen.items()):
            print(f"{name}: {explain_chain(reasons, f)}")
        print(f"（更動 {len(changed)} 個檔案，其中 {len(code_changes)} 個會影響遊戲或工具；挑出 {len(chosen)} 個測試群組）", file=sys.stderr)
        return 0
    print(",".join(sorted(chosen)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
