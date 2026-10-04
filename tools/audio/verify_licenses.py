"""重新抓取 manifest.json 裡每個素材包的來源頁面，確認授權欄位真的是 CC0（NE-155 的複查工具）。

用法：python tools/audio/verify_licenses.py [--jobs 6] [--only ID ...]
OpenGameArt 頁面的「License(s):」欄只能有 CC0；Kenney 頁面要寫 CC0。抓不到頁面的列為「未能確認」，不算通過。
結果印在畫面並寫到 assets_src/audio/license_check.json（時間、通過／失敗清單）。
"""
import argparse
import json
import re
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "assets_src" / "audio" / "manifest.json"
REPORT = ROOT / "assets_src" / "audio" / "license_check.json"
UA = {"User-Agent": "NestEgg-license-check/1.0 (personal game project)"}


def fetch(url: str) -> str:
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=40) as response:
                return response.read().decode("utf-8", "replace")
        except Exception:  # noqa: BLE001 重試
            time.sleep(1.5 * (attempt + 1))
    return ""


def check(pack: dict) -> dict:
    html = fetch(pack["page"])
    if not html:
        return {"id": pack["id"], "page": pack["page"], "result": "unverified", "detail": "頁面抓不到"}
    if "opengameart.org" in pack["page"]:
        match = re.search(r"License\(s\):.*?</div>\s*</div>|License\(s\):(.*?)<(?:/section|h2|div class=\"field field-name-field-art-tags)", html, re.S)
        block = html[html.find("License(s):"): html.find("License(s):") + 1500] if "License(s):" in html else ""
        licenses = re.findall(r'<a href="https?://creativecommons\.org/[^"]+"[^>]*>([^<]+)</a>|<a href="/content/[^"]*license[^"]*"[^>]*>([^<]+)</a>', block)
        names = [a or b for a, b in licenses]
        if not names:
            names = re.findall(r"(CC0[^<\n]*|CC-BY[^<\n]*|GPL[^<\n]*|OGA-BY[^<\n]*)", block)
        text = " | ".join(n.strip() for n in names) or "（找不到授權欄位）"
        ok = bool(names) and all(n.strip().upper().startswith("CC0") for n in names)
        return {"id": pack["id"], "page": pack["page"], "result": "ok" if ok else "FAIL", "detail": text}
    ok = "CC0" in html or "Creative Commons CC0" in html
    return {"id": pack["id"], "page": pack["page"], "result": "ok" if ok else "FAIL", "detail": "Kenney 頁面" + ("寫 CC0" if ok else "沒看到 CC0")}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--jobs", type=int, default=6)
    parser.add_argument("--only", nargs="*", default=[])
    args = parser.parse_args()
    packs = [p for p in json.loads(MANIFEST.read_text(encoding="utf-8"))["packs"] if not args.only or p["id"] in args.only]
    seen, unique = set(), []
    for pack in packs:  # 同一個頁面（例如同一張專輯的多首）只查一次
        if pack["page"] not in seen:
            seen.add(pack["page"])
            unique.append(pack)
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(check, unique))
    bad = [r for r in results if r["result"] != "ok"]
    REPORT.write_text(json.dumps({"checked_at": time.strftime("%Y-%m-%d %H:%M:%S"), "pages": len(results), "ok": len(results) - len(bad), "problems": bad}, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"檢查 {len(results)} 個頁面：通過 {len(results) - len(bad)}，有問題或未能確認 {len(bad)}")
    for r in bad:
        print(f"  {r['result']:10} {r['id']}  {r['detail']}  {r['page']}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
