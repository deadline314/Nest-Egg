#!/usr/bin/env python3
"""地圖產生器重跑檢查（NE-453）：不改動工作樹，重跑第一到四章的產生器，逐檔比對輸出和目前的資料。

用法：python tools/level/check_generators.py [ch1 ch3 ...]
每章在獨立的子程序裡跑；產生器寫進 data/ 的檔案全部改寫到暫存資料夾，repo 一個字都不動。
比對：地圖 JSON 用解析後的內容比（換行、縮排、鍵順序不算差異）；.tres 把資源編號換成路徑、去掉 ext_resource 與 load_steps 後
逐行比（資源編號、行的順序、行尾逗號不算差異）。有差異時列出區域與檔名、各舉一行，結束代碼 1。
有人直接改了地圖 JSON 卻沒寫回產生器，這支會抓到：改法是把那個東西寫回 tools/level/build_ch*.py。
"""
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
CHAPTERS = ['ch1', 'ch2', 'ch3', 'ch4']

# 子程序：把對 data/ 的寫入改到暫存資料夾，寫過的檔案之後的讀取也從暫存讀（產生器寫完會讀回 JSON 驗證）。
BOOTSTRAP = r'''
import builtins, json, os, runpy, sys
root, tmp, script, report = sys.argv[1:5]
data = os.path.join(root, "data") + os.sep
written = set()
real_open = builtins.open
def redirected(file, mode="r", *args, **kwargs):
    if isinstance(file, (str, os.PathLike)):
        path = os.path.abspath(os.fspath(file))
        if path.startswith(data):
            rel = os.path.relpath(path, root)
            target = os.path.join(tmp, rel)
            if any(flag in mode for flag in "wax"):
                os.makedirs(os.path.dirname(target), exist_ok=True)
                written.add(rel)
                return real_open(target, mode, *args, **kwargs)
            if rel in written:
                return real_open(target, mode, *args, **kwargs)
    return real_open(file, mode, *args, **kwargs)
builtins.open = redirected
sys.argv = [script]
sys.path.insert(0, os.path.dirname(script))
sys.dont_write_bytecode = True
try:
    runpy.run_path(script, run_name="__main__")
finally:
    with real_open(report, "w", encoding="utf-8") as f:
        json.dump(sorted(written), f)
'''


def normalize_tres(text):
    ids = {i: p for p, i in re.findall(r'path="([^"]+)" id="([^"]+)"', text)}
    lines = []
    for line in text.replace('\r\n', '\n').split('\n'):
        if line.startswith('[ext_resource') or not line.strip():
            continue
        line = re.sub(r'load_steps=\d+ ', '', line)
        line = re.sub(r'ExtResource\("([^"]+)"\)', lambda m: f'ExtResource("{ids.get(m.group(1), m.group(1))}")', line)
        lines.append(line.rstrip().rstrip(','))
    return sorted(lines)


def compare(rel, tmp):
    """回傳 None（一樣）或一句說明。"""
    new_path = os.path.join(tmp, rel)
    old_path = os.path.join(ROOT, rel)
    if not os.path.exists(old_path):
        return '產生器會多寫出這個檔（repo 裡沒有）'
    with open(new_path, encoding='utf-8') as f:
        new = f.read()
    with open(old_path, encoding='utf-8') as f:
        old = f.read()
    if rel.endswith('.json'):
        a, b = json.loads(old), json.loads(new)
        if a == b:
            return None
        if isinstance(a, dict) and isinstance(b, dict):
            keys = sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))
            if 'segments' in keys:
                rows_a = [''.join(seg[y] for seg in a['segments']) for y in range(len(a['segments'][0]))]
                rows_b = [''.join(seg[y] for seg in b['segments']) for y in range(len(b['segments'][0]))]
                for y, (ra, rb) in enumerate(zip(rows_a, rows_b)):
                    for x, (ca, cb) in enumerate(zip(ra, rb)):
                        if ca != cb:
                            return f'地圖第 {y} 列第 {x} 欄：資料是 {ca!r}，產生器是 {cb!r}（另有其他鍵差異：{[k for k in keys if k != "segments"]}）'
                return f'地圖的列數或寬度不同（{len(rows_a)}×{len(rows_a[0])} 對 {len(rows_b)}×{len(rows_b[0])}）'
            return f'這些鍵不同：{keys}'
        return '內容不同'
    a, b = normalize_tres(old), normalize_tres(new)
    if a == b:
        return None
    only_old = [line for line in a if line not in b]
    only_new = [line for line in b if line not in a]
    sample = (only_old or only_new or [''])[0][:120]
    side = '資料有、產生器沒有' if only_old else '產生器有、資料沒有'
    return f'{side}：{sample}'


def run_chapter(chapter):
    script = os.path.join(ROOT, 'tools', 'level', f'build_{chapter}.py')
    with tempfile.TemporaryDirectory(prefix=f'gen_{chapter}_') as tmp:
        report = os.path.join(tmp, 'written.json')
        env = dict(os.environ, PYTHONIOENCODING='utf-8')
        proc = subprocess.run([sys.executable, '-c', BOOTSTRAP, ROOT, tmp, script, report],
                              cwd=ROOT, capture_output=True, text=True, encoding='utf-8', errors='replace', env=env)
        if proc.returncode != 0:
            tail = (proc.stdout + proc.stderr).strip().splitlines()[-5:]
            return [('（產生器本身）', '執行失敗：' + ' / '.join(tail))], 0
        with open(report, encoding='utf-8') as f:
            written = json.load(f)
        problems = [(rel, reason) for rel in written if (reason := compare(rel, tmp))]
        return problems, len(written)


def main():
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    chapters = sys.argv[1:] or CHAPTERS
    failed = False
    for chapter in chapters:
        problems, count = run_chapter(chapter)
        if problems:
            failed = True
            print(f'{chapter}：{len(problems)} 個檔和目前的資料不同（共寫出 {count} 個）')
            for rel, reason in problems:
                print(f'  {rel.replace(os.sep, "/")}：{reason}')
        else:
            print(f'{chapter}：通過（{count} 個檔都和目前的資料一致）')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
