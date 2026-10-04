"""下載 assets_src/audio/manifest.json 列出的 CC0 音效與音樂來源（NE-155）。

用法：python tools/audio/fetch_audio.py [--only ID ...] [--kind sfx|music] [--list] [--manifest FILE]

原始檔放 assets_src/raw/audio/<dir>/（git-ignored，可重抓）。來源只有 Kenney 與 OpenGameArt，授權都是 CC0；
manifest 的每一筆都記錄作者、網址與下載連結。單項失敗只記錄、不中斷其他項目；已經下載過的資料夾會略過。
授權登記（assets_src/audio/LICENSES.json）由 build_audio.py 依實際用到的素材產生，不在這裡寫。
"""
import argparse
import json
import sys
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "assets_src" / "audio" / "manifest.json"
RAW = ROOT / "assets_src" / "raw" / "audio"
UA = {"User-Agent": "NestEgg-audio-fetch/1.0 (personal game project)"}
AUDIO_EXTENSIONS = {".ogg", ".wav", ".mp3", ".flac"}


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url.replace(" ", "%20"), headers=UA)
    with urllib.request.urlopen(request, timeout=120) as response:
        dest.write_bytes(response.read())


def has_audio(folder: Path) -> bool:
    return folder.is_dir() and any(p.suffix.lower() in AUDIO_EXTENSIONS for p in folder.rglob("*"))


def fetch_entry(entry: dict) -> None:
    folder = RAW / entry["dir"]
    urls = entry["download"] if isinstance(entry["download"], list) else [entry["download"]]
    for url in urls:
        name = Path(urllib.parse.unquote(urllib.parse.urlparse(url).path)).name
        dest = folder / name
        download(url, dest)
        if dest.suffix.lower() == ".zip":
            with zipfile.ZipFile(dest) as archive:
                archive.extractall(folder)
            dest.unlink()
    if not has_audio(folder):
        raise IOError("下載完成但資料夾裡沒有音訊檔")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="*", default=[])
    parser.add_argument("--kind", choices=["sfx", "music"])
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--manifest", type=Path, default=MANIFEST, help="改用另一份來源目錄（測試用）")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    failed = 0
    for entry in manifest["packs"]:
        if (args.only and entry["id"] not in args.only) or (args.kind and entry["kind"] != args.kind):
            continue
        if args.list:
            print(f'{entry["id"]:56} {entry["kind"]:6} {entry["author"][:24]:24} {entry["license"]}')
            continue
        if has_audio(RAW / entry["dir"]):
            print(f'skip  {entry["id"]}（已下載）')
            continue
        try:
            fetch_entry(entry)
            print(f'ok    {entry["id"]}')
        except Exception as error:  # 單項失敗不阻擋其他項目
            failed += 1
            print(f'FAIL  {entry["id"]}: {error}（{entry["page"]}）', file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
