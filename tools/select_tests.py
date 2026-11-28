#!/usr/bin/env python3
"""依有更動的檔案，挑出受影響、需要跑的測試套件。

用法：python tools/select_tests.py [--base origin/main] [--files a b ...] [--explain] [--all] [--probes]
輸出：逗號分隔的套件名稱（可直接給 tests/smoke_test.tscn 的 --only=；main 是開頭那一大段流程測試）。沒有受影響的測試就輸出空字串。
  --probes 改為輸出受影響的探針執行器（tools/run_*.py，各自跑 tests/probes/ 底下的真實流程；CI 也逐一跑它們）。
結束代碼：0 成功（含「沒有受影響的測試」）；2 挑選失敗（git 指令失敗、基準不存在、讀不到輸出），原因寫在 stderr，呼叫端不可當成沒有測試。
git 的輸出一律用 NUL 分隔並以 UTF-8 解碼，不依賴系統編碼（繁中 Windows 的 cp950）或 core.quotePath 設定。

原理（靜態影響分析）：
  1. 為每個檔案建立相依關係：GDScript 用到另一個檔案的 class_name 或單例名稱，或字串裡出現它的 res:// 路徑（或它所在的資料夾）；
     .tres／.tscn／.json 內寫到的 res:// 路徑也算相依。GDScript 可用 # changed-test-inputs: 宣告執行時才列舉的來源。
  2. 從有更動的檔案出發，沿著「誰用到它」往外找（最多 MAX_DEPTH 層），碰到測試套件（tests/suite/*.gd）或流程測試（tests/smoke_test.gd）就收進來。
     被超過 HUB_DEPENDENTS 個檔案用到的核心（Player、Sfx、Level…）只在它自己被更動時才往外展開，
     不然改一個資料檔就會經過 Player 牽連到所有測試，失去「只跑受影響範圍」的意義。
  3. 更動的檔案本身是測試時，就是那個套件。
  4. 改一支腳本時，以它為腳本的資料檔（敵人、道具的 .tres，場景 .tscn）視同一起改了，不受核心門檻限制：
     改 grunt.gd 要挑到所有用到 grunt.tres 的關卡與測試（NE-431；之前停在 grunt.tres 只挑到 1 個）。
  5. 從資料檔（.tres／.tscn／.json）出發時，碰到用路徑引用它的程式只再往下找測試，不沿著程式之間的引用一路擴散：
     改一個關卡檔不該經過「某支程式寫了這個路徑」牽連到半個專案（NE-431；之前改 ch2_loading.tres 挑出 58 個）。
  6. 經由別的檔案被牽連到的測試套件不再往外擴散到「用了它的共用函式」的其他套件；只有測試檔本身被改時才會。
  7. 資料改動時，只是掃描整個資料夾、又被大量使用的程式（關卡目錄、索引）不算受影響；掃資料夾的專門檢查（場景稽核）
     與直接掃資料夾的測試套件照樣挑進來。
  8. 關卡檔之間的引用是出入口的目的地，不沿著它擴散；從資料走進的程式若是核心（用到它的檔案超過門檻），也不再往外找。
改動單一工具只會挑到相關套件；改到被大量使用的核心（例如 Player、Sfx）會挑到很多，接近完整測試，這是預期的。
這是保守的估計，不是證明：完整測試仍由 CI 排程負責（.github/workflows/tests.yml）。
"""
import argparse
import re
import subprocess
import sys
from collections import defaultdict, deque
from fnmatch import fnmatchcase
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {".git", ".godot", "assets_src", "pm", "design", "node_modules", "__pycache__"}
SCAN_EXT = {".gd", ".tres", ".tscn", ".json", ".gdshader", ".cfg"}
# 這些變動會影響整個專案或測試流程本身，直接跑全部。
# 往外找幾層；核心檔（被這麼多檔案用到）只有「自己被更動」時才展開。
MAX_DEPTH = 8
HUB_DEPENDENTS = 30
RUN_ALL = {"project.godot", "tests/smoke_test.gd", "tools/run_tests.sh", "tools/run_tests_parallel.sh", "tools/test_filters.sh", "tools/bounded_run.sh", "tools/select_tests.py", "tools/godot_audio/build.py", "tools/godot_audio/manifest.json"}
CLASS_RE = re.compile(r"^class_name\s+(\w+)", re.M)
PATH_RE = re.compile(r"res://[\w./\-]+")
AUTOLOAD_RE = re.compile(r'^(\w+)="\*?res://([^"]+)"', re.M)
WORD_RE = re.compile(r"[A-Za-z_]\w*")
RUNTIME_INPUT_RE = re.compile(r"^# changed-test-inputs:[ \t]*(.*)$", re.M)
# 探針場景：tests/probes 底下的流程檢查，以及 tools/chN_*_probe.tscn 的章節存檔鏈（NE-431）。
PROBE_SCENE_RE = re.compile(r"res://(tests/probes/\w+\.tscn|tools/ch\d+_\w+_probe\.tscn)")
SCRIPT_RESOURCE_RE = re.compile(r'\[ext_resource[^\]]*type="Script"[^\]]*path="res://([^"]+)"')
DATA_EXT = {".tres", ".tscn", ".json", ".cfg"}
PROBE_SHARED = {"tools/runtime_probe.py"}  # 所有探針執行器共用


class SelectionError(Exception):
    """挑不出受影響的測試（git 失敗、基準不存在等）；和「真的沒有受影響的測試」不同，呼叫端必須當成失敗。"""


def git_paths(*args):
    """執行 git 並回傳它列出的路徑。用 -z（NUL 分隔、不加引號）並自己以 UTF-8 解碼，不受系統編碼與 core.quotePath 影響。"""
    cmd = ["git", *args, "-z"]
    try:
        result = subprocess.run(cmd, cwd=ROOT, capture_output=True)
    except OSError as error:
        raise SelectionError(f"無法執行 git（{' '.join(cmd)}）：{error}") from error
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip() or f"代碼 {result.returncode}"
        raise SelectionError(f"git 指令失敗（{' '.join(cmd)}）：{detail}")
    return [name for name in result.stdout.decode("utf-8", errors="replace").split("\0") if name]


def tracked_files():
    ignored = {}
    return [line for line in git_paths("ls-files", "-co", "--exclude-standard")
            if not any(part in SKIP_DIRS for part in Path(line).parts)
            and not godot_ignored_directory(Path(line).parent, ignored)]


def godot_ignored_directory(directory, cache):
    """Mirror Godot's directory markers; cache ancestors, never snapshot contents."""
    key = directory.as_posix()
    if key not in cache:
        inherited = directory != Path(".") and godot_ignored_directory(directory.parent, cache)
        try:
            cache[key] = inherited or (ROOT / directory / ".gdignore").is_file()
        except OSError as error:
            raise SelectionError(f"無法檢查 Godot 忽略目錄 {directory}: {error}") from error
    return cache[key]


def changed_files(base):
    names = set()
    for args in (("diff", "--name-only", f"{base}...HEAD"), ("diff", "--name-only", "HEAD"), ("ls-files", "-o", "--exclude-standard")):
        names.update(git_paths(*args))
    return sorted(names)


def read_text(path):
    try:
        return (ROOT / path).read_text(encoding="utf-8", errors="ignore")
    except (OSError, ValueError):
        return ""


def strip_suite_registration(text):
    """smoke_test.gd 的 _suites() 只是登記每個套件，不算流程測試用到它們。"""
    start = text.find("func _suites()")
    if start < 0:
        return text
    end = text.find("\nfunc ", start + 1)
    return text[:start] + (text[end:] if end > 0 else "")


def build_graph(files, changed):
    texts = {f: read_text(f) for f in files if Path(f).suffix in SCAN_EXT}
    known_files = set(files)
    provides = {}  # 名稱 -> 檔案

    def provide(name, path):
        previous = provides.get(name)
        if previous is not None and previous != path:
            raise SelectionError(f"同名正式類別／單例 {name}：{previous} 與 {path}")
        provides[name] = path

    autoloads = AUTOLOAD_RE.findall(read_text("project.godot"))
    for name, rel in autoloads:
        provide(name, rel)
    for f, text in texts.items():
        if f.endswith(".gd"):
            for name in CLASS_RE.findall(text):
                provide(name, f)
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
    dir_users = defaultdict(set)  # 檔案 -> 只是掃描它所在資料夾的檔案（不是指名用到它）
    for f, text in texts.items():
        scan_text = strip_suite_registration(text) if f == "tests/smoke_test.gd" else text
        used = set()
        if f.endswith(".gd"):
            for word in set(WORD_RE.findall(scan_text)):
                target = provides.get(word)
                if target and target != f:
                    used.add(target)
            if "# changed-test-inputs:" in scan_text:
                patterns = " ".join(RUNTIME_INPUT_RE.findall(scan_text)).split()
                # Include deleted inputs and avoid expanding patterns over the whole repository.
                used.update(path for path in changed if path != f
                            and any(fnmatchcase(path, pattern) for pattern in patterns))
        for path in set(PATH_RE.findall(scan_text)):
            stripped = path.rstrip("/")
            rel = stripped[len("res://"):]
            if rel in known_files and rel != f:
                used.add(rel)
            for member in dir_members.get(stripped, []):
                if member != f:
                    used.add(member)
                    if rel != member:
                        dir_users[member].add(f)
        for target in used:
            dependents[target].add(f)
    instances = defaultdict(set)  # 腳本 -> 以它為腳本的資料檔
    for f, text in texts.items():
        if Path(f).suffix in (".tres", ".tscn"):
            for script in SCRIPT_RESOURCE_RE.findall(text):
                if script in known_files:
                    instances[script].add(f)
    # 同一個檔案若也被指名用到，就不算「只掃資料夾」。
    for target, scanners in dir_users.items():
        scanners -= {user for user in scanners if f"res://{target}" in texts.get(user, "")}
    return dependents, suite_of, instances, dir_users


def _is_data(path):
    return Path(path).suffix in DATA_EXT and not path.startswith("tests/")


def select(changed, files):
    dependents, suite_of, instances, dir_users = build_graph(files, changed)
    reasons = {}
    depth = {}
    # 怎麼走到這個檔案的：code＝程式改動往外找；data＝資料改動；data_code＝從資料檔走進來的程式（只再找測試）。
    mode = {}
    queue = deque()
    for f in changed:
        reasons[f] = "有更動"
        depth[f] = 0
        mode[f] = "data" if _is_data(f) else "code"
        queue.append(f)
    while queue:
        current = queue.popleft()
        if depth[current] > 0 and (current in suite_of or current in ("tests/smoke_test.gd", "tests/smoke_test.tscn")):
            continue  # 規則 6
        users = set(dependents.get(current, ()))
        if mode[current] != "code":
            # 規則 7：資料改動時，「只掃資料夾」的檔案只有測試本身算受影響（例如逐一檢查所有關卡的套件）。
            users -= {user for user in dir_users.get(current, ())
                      if not user.startswith("tests/") and len(dependents.get(user, ())) > HUB_DEPENDENTS}
        own_instances = instances.get(current, set()) if current.endswith(".gd") else set()
        # 核心門檻只限制程式之間的擴散；資料的擴散已經由規則 5 收住，關卡、敵人資料被很多檔案引用也照樣要找到測試。
        if depth[current] >= MAX_DEPTH or (mode[current] != "data" and depth[current] > 0 and len(users) > HUB_DEPENDENTS):
            users = own_instances  # 核心不往外展開，但自己的資料實例仍算一起改了（規則 4）
        for user in users:
            if user in reasons:
                continue
            if user in own_instances:  # 規則 4：資料實例和腳本同一層
                next_depth, next_mode = depth[current], "data"
            else:
                next_depth = depth[current] + 1
                if mode[current] == "data_code" and not user.startswith("tests/"):
                    continue  # 規則 5：從資料走進的程式只再找測試
                if mode[current] == "data" and current.startswith("data/levels/") and user.startswith("data/levels/"):
                    continue  # 規則 8：關卡之間只是出入口指向對方，不是包含
                if mode[current] == "data" and user.endswith(".gd") and not user.startswith("tests/"):
                    next_mode = "data_code"
                elif mode[current] == "data" and _is_data(user):
                    next_mode = "data"
                else:
                    next_mode = mode[current]
            reasons[user] = current
            depth[user] = next_depth
            mode[user] = next_mode
            queue.append(user)
    chosen = {}
    for f in reasons:
        if f in suite_of:
            chosen[suite_of[f]] = f
        elif f == "tests/smoke_test.gd":
            chosen["main"] = f
    return chosen, reasons


def probe_runners(files):
    """探針執行器（tools/run_*.py）-> 它跑的探針場景。沒有寫死探針場景的執行器不算。"""
    runners = {}
    for f in files:
        if f.startswith("tools/run_") and f.endswith(".py"):
            scenes = set(PROBE_SCENE_RE.findall(read_text(f)))
            if scenes:
                runners[f] = scenes
    return runners


def select_probes(changed, reasons, runners, run_all):
    """探針場景被影響、執行器本身或共用的 runtime_probe.py 有更動，就挑出那個執行器。"""
    if run_all or PROBE_SHARED & set(changed):
        return sorted(runners)
    return sorted(runner for runner, scenes in runners.items() if runner in changed or scenes & set(reasons))


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
    parser.add_argument("--probes", action="store_true")
    args = parser.parse_args()
    for stream in (sys.stdout, sys.stderr):  # 說明文字含中文；主控台編碼不支援時用替代字元，不讓輸出本身當掉
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(errors="backslashreplace")
    try:
        return run(args)
    except SelectionError as error:
        print(f"select_tests.py：挑選受影響的測試失敗：{error}", file=sys.stderr)
        return 2


def run(args):
    files = tracked_files()
    all_suites = sorted(set(re.findall(r"class_name\s+(\w+Suite)\b", "\n".join(read_text(f) for f in files if f.startswith("tests/suite/")))))
    changed = args.files if args.files is not None else changed_files(args.base)
    ignored = {}
    boundary_changed = any(Path(f).name == ".gdignore"
                           and not godot_ignored_directory(Path(f).parent.parent, ignored)
                           for f in changed)
    run_all = args.all or boundary_changed or any(f in RUN_ALL or (f.startswith("tools/godot_audio/") and f.endswith(".patch")) for f in changed)
    if run_all and not args.probes:
        print("ALL" if not args.explain else "全部（改到整個專案或測試流程本身）")
        return 0
    code_changes = [f for f in changed if not f.startswith(("pm/", "design/", "assets_src/")) and not f.endswith((".md", ".py")) or f == "tools/select_tests.py"]
    chosen, reasons = select(code_changes, files)
    if args.probes:
        runners = probe_runners(files)
        picked = select_probes(changed, reasons, runners, run_all)
        if args.explain:
            for runner in picked:
                hit = sorted(runners[runner] & set(reasons))
                print(f"{runner}: {explain_chain(reasons, hit[0]) if hit else '執行器本身或共用工具有更動'}")
            return 0
        print(",".join(picked))
        return 0
    if args.explain:
        for name, f in sorted(chosen.items()):
            print(f"{name}: {explain_chain(reasons, f)}")
        print(f"（更動 {len(changed)} 個檔案，其中 {len(code_changes)} 個會影響遊戲或工具；挑出 {len(chosen)} 個測試群組）", file=sys.stderr)
        return 0
    print(",".join(sorted(chosen)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
