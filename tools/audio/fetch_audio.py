"""下載 assets_src/audio/manifest.json 列出的 CC0 音效與音樂來源（NE-155）。

用法：python tools/audio/fetch_audio.py [--only ID ...] [--kind sfx|music] [--jobs N] [--list] [--manifest FILE]

原始檔放 assets_src/raw/audio/<dir>/（git-ignored，可重抓，全部約 3 GB）。來源只有 Kenney、OpenGameArt 與 archive.org，授權都是 CC0；
manifest 的每一筆都記錄作者、網址與下載連結。多個素材包同時下載，單項失敗會重試、仍失敗只記錄不中斷其他項目；
已經下載過的資料夾會略過，所以中途斷線後重跑就會接著補。每個素材包先下載到暫存資料夾、完整解壓後才改名，不會留下殘缺的資料夾。
授權登記（assets_src/audio/LICENSES.json）由 build_audio.py 依實際用到的素材產生，不在這裡寫。
"""
import argparse
import json
import shutil
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "assets_src" / "audio" / "manifest.json"
RAW = ROOT / "assets_src" / "raw" / "audio"
UA = {"User-Agent": "NestEgg-audio-fetch/1.0 (personal game project)"}
AUDIO_EXTENSIONS = {".ogg", ".wav", ".mp3", ".flac"}


def download(url: str, dest: Path, attempts: int = 3) -> None:
    """下載一個檔案；網路錯誤最多重試 attempts 次（間隔 2、4 秒）。"""
    dest.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url.replace(" ", "%20"), headers=UA)
    for attempt in range(1, attempts + 1):
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                dest.write_bytes(response.read())
            return
        except OSError:  # URLError、逾時、連線中斷都是 OSError
            if attempt == attempts:
                raise
            time.sleep(2 * attempt)


def has_audio(folder: Path) -> bool:
    return folder.is_dir() and any(p.suffix.lower() in AUDIO_EXTENSIONS for p in folder.rglob("*"))


def fetch_entry(entry: dict) -> None:
    """先在 <dir>.part 裡下載並解壓，確認有音訊檔才改名為正式資料夾。"""
    folder = RAW / entry["dir"]
    staging = folder.with_name(folder.name + ".part")
    shutil.rmtree(staging, ignore_errors=True)
    urls = entry["download"] if isinstance(entry["download"], list) else [entry["download"]]
    try:
        for url in urls:
            name = Path(urllib.parse.unquote(urllib.parse.urlparse(url).path)).name
            dest = staging / name
            download(url, dest)
            if dest.suffix.lower() == ".zip":
                with zipfile.ZipFile(dest) as archive:
                    archive.extractall(staging)
                dest.unlink()
        if not has_audio(staging):
            raise IOError("下載完成但資料夾裡沒有音訊檔")
        shutil.rmtree(folder, ignore_errors=True)
        staging.rename(folder)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="*", default=[])
    parser.add_argument("--kind", choices=["sfx", "music"])
    parser.add_argument("--jobs", type=int, default=4, help="同時下載的素材包數")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--manifest", type=Path, default=MANIFEST, help="改用另一份來源目錄（測試用）")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    pending = []
    skipped = 0
    for entry in manifest["packs"]:
        if (args.only and entry["id"] not in args.only) or (args.kind and entry["kind"] != args.kind):
            continue
        if args.list:
            print(f'{entry["id"]:56} {entry["kind"]:6} {entry["author"][:24]:24} {entry["license"]}')
        elif has_audio(RAW / entry["dir"]):
            skipped += 1
        else:
            pending.append(entry)
    if args.list:
        return 0
    print(f"要下載 {len(pending)} 個素材包，略過已下載的 {skipped} 個 → {RAW.relative_to(ROOT)}")
    failed = 0
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futures = {pool.submit(fetch_entry, entry): entry for entry in pending}
        for done, future in enumerate(as_completed(futures), start=1):
            entry = futures[future]
            try:
                future.result()
                print(f'[{done}/{len(pending)}] ok    {entry["id"]}')
            except Exception as error:  # 單項失敗不阻擋其他項目
                failed += 1
                print(f'[{done}/{len(pending)}] FAIL  {entry["id"]}: {error}（{entry["page"]}）', file=sys.stderr)
    if failed:
        print(f"{failed} 個素材包失敗；重跑同一個指令會只補下載失敗的。", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
