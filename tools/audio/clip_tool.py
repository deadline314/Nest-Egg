"""音訊片段擷取（NE-179）：把某個素材的某一段輸出成獨立的新素材；也提供實驗室擷取介面（NE-180）用的「準備編輯」資料。

用法：
  python tools/audio/clip_tool.py prepare <素材編號> [--max-seconds 180] [--out 資料夾]
      解出完整長預聽 long.ogg（單聲道、不去頭尾靜音）、波形與依靜音找出的各段，寫成 info.json（預設放 assets_src/work/clip_edit/<編號>/）
  python tools/audio/clip_tool.py export <素材編號> --start 秒 --end 秒 [--note 說明] [--no-preview] [--json]
      從原始檔切出 [start, end] 存成無損 wav（保留原檔取樣率與位元深度，不調音量、不重新取樣），取得新素材編號
  python tools/audio/clip_tool.py rebuild
      照 clips.json 重做缺少的片段檔（原始下載檔重抓之後用）
  python tools/audio/clip_tool.py list [素材編號]

資料：
  assets_src/audio/clips.json      進版控的片段清單：每個片段的新編號、原檔（編號、素材包、檔名）、起訖秒數
  assets_src/raw/audio/clips_sfx|clips_music/<編號>.wav   輸出檔（不進版控，可用 rebuild 重做）
片段登記在來源目錄的「本機產生」素材包（manifest 的 local: true）：授權沿用原檔（CC0），下載與授權複查工具略過它；
新編號類別與原檔相同、接在該類最大編號後面（編號只增不重用）。同一個原檔上幾乎相同的範圍（相差不到 20 毫秒）重複擷取，回傳既有編號。
出錯時訊息指出素材與原因，不留下半成品檔案，也不會只寫一半的清單（寫入失敗會還原已寫的檔案）。
"""
import argparse
import json
import math
import os
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audio_lib as lib  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
AUDIO_SRC = ROOT / "assets_src" / "audio"
RAW = ROOT / "assets_src" / "raw" / "audio"
CATALOG = AUDIO_SRC / "catalog.json"
MANIFEST = AUDIO_SRC / "manifest.json"
CLIPS = AUDIO_SRC / "clips.json"
EDIT_DIR = ROOT / "assets_src" / "work" / "clip_edit"
LOCAL_PACKS = {"sfx": "clips_sfx", "music": "clips_music"}
LOSSY_CODECS = {"mp3", "vorbis", "opus", "aac", "wmav2", "wmapro"}
MIN_CLIP_S = 0.01
DUPLICATE_TOLERANCE_S = 0.02
DURATION_TOLERANCE_S = 0.015
DEFAULT_MAX_SECONDS = 180.0
CLIPS_NOTE = "音訊片段清單：從原始素材擷取出來的新素材。id 是新素材編號，parent* 記錄原檔，start／end 是原檔裡的秒數。由 tools/audio/clip_tool.py 維護，輸出檔可用 clip_tool.py rebuild 重做。"


class ClipError(Exception):
    """可預期的失敗（訊息直接給使用者看）。"""


# ---------------------------------------------------------------------------
# 讀寫
# ---------------------------------------------------------------------------

def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.exists() else ""


def load_catalog() -> dict:
    try:
        return json.loads(CATALOG.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ClipError(f"讀不了素材目錄 {CATALOG.relative_to(ROOT)}：{error}（先執行 python tools/audio/build_catalog.py）") from error


def load_manifest() -> dict:
    try:
        return json.loads(MANIFEST.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ClipError(f"讀不了來源目錄 {MANIFEST.relative_to(ROOT)}：{error}") from error


def load_clips() -> dict:
    if not CLIPS.exists():
        return {"_說明": CLIPS_NOTE, "clips": []}
    try:
        doc = json.loads(CLIPS.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ClipError(f"讀不了片段清單 {CLIPS.relative_to(ROOT)}：{error}") from error
    if not isinstance(doc.get("clips"), list):
        raise ClipError(f"{CLIPS.relative_to(ROOT)} 缺少 clips 陣列")
    return doc


def dump_catalog(doc: dict) -> str:
    doc["assets"] = dict(sorted(doc["assets"].items()))
    return json.dumps(doc, ensure_ascii=False, indent=0) + "\n"


def dump_indent1(doc: dict) -> str:
    return json.dumps(doc, ensure_ascii=False, indent=1) + "\n"


def write_atomic(path: Path, text: str) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8", newline="\n")
    os.replace(tmp, path)


def write_all(updates: list[tuple[Path, str]]) -> None:
    """依序寫入多個檔案；任何一個失敗就把已寫的還原成原本的內容。"""
    originals = [(path, path.read_text(encoding="utf-8") if path.exists() else None) for path, _ in updates]
    done = 0
    try:
        for path, text in updates:
            write_atomic(path, text)
            done += 1
    except OSError as error:
        for path, old in originals[:done]:
            if old is None:
                path.unlink(missing_ok=True)
            else:
                write_atomic(path, old)
        raise ClipError(f"寫入 {path.relative_to(ROOT)} 失敗：{error}（已還原其他檔案）") from error


# ---------------------------------------------------------------------------
# 來源與探測
# ---------------------------------------------------------------------------

def manifest_pack(manifest: dict, pack_id: str) -> dict:
    for pack in manifest["packs"]:
        if pack["id"] == pack_id:
            return pack
    raise ClipError(f"素材包「{pack_id}」不在 manifest.json")


def source_of(catalog: dict, manifest: dict, asset_id: str) -> tuple[dict, dict, Path]:
    asset = catalog["assets"].get(asset_id)
    if asset is None:
        raise ClipError(f"素材目錄沒有 {asset_id}")
    pack = manifest_pack(manifest, asset["pack"])
    if pack.get("local"):
        raise ClipError(f"{asset_id} 本身就是擷取出來的片段，請從它的原檔（{asset.get('parent', '?')}）擷取")
    path = RAW / pack["dir"] / asset["file"]
    if not path.is_file():
        raise ClipError(f"找不到 {asset_id} 的原始檔 {path.relative_to(ROOT)}（先執行 python tools/audio/fetch_audio.py --only {pack['id']}）")
    return asset, pack, path


def run(cmd: list[str], what: str, **kwargs) -> subprocess.CompletedProcess:
    try:
        return subprocess.run(cmd, capture_output=True, check=True, **kwargs)
    except FileNotFoundError as error:
        raise ClipError(f"找不到 {cmd[0]}：{what}需要 ffmpeg（Windows：scoop install ffmpeg）") from error
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or b"").decode("utf-8", "replace").strip().splitlines()
        raise ClipError(f"{what}失敗：{detail[-1] if detail else error}") from error


def probe(path: Path) -> dict:
    out = run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
               "stream=codec_name,sample_rate,channels,sample_fmt,bits_per_raw_sample,duration:format=duration", "-of", "json", str(path)],
              f"讀取 {path.name} 的格式").stdout
    try:
        doc = json.loads(out)
        stream = doc["streams"][0]
        duration = float(stream.get("duration") or doc["format"]["duration"])
    except (ValueError, KeyError, IndexError) as error:
        raise ClipError(f"{path.name} 讀不出音訊資訊") from error
    return {"codec": stream.get("codec_name", ""), "sample_rate": int(stream.get("sample_rate", 0)), "channels": int(stream.get("channels", 1)),
            "sample_fmt": stream.get("sample_fmt", ""), "bits": int(stream.get("bits_per_raw_sample") or 0), "duration": duration}


def pcm_codec(info: dict) -> str:
    """輸出 wav 的編碼：盡量保留原檔的位元深度；原檔是有損格式（mp3、ogg…）時解成 16 位元。"""
    if info["codec"] in LOSSY_CODECS:
        return "pcm_s16le"
    fmt = info["sample_fmt"].rstrip("p")
    if fmt in ("flt", "dbl"):
        return "pcm_f32le"
    if fmt == "s32":
        return "pcm_s24le" if info["bits"] == 24 else "pcm_s32le"
    return "pcm_s16le"


# ---------------------------------------------------------------------------
# 準備編輯
# ---------------------------------------------------------------------------

def prepare(asset_id: str, out_dir: Path | None = None, max_seconds: float = DEFAULT_MAX_SECONDS) -> dict:
    catalog, manifest = load_catalog(), load_manifest()
    asset, pack, path = source_of(catalog, manifest, asset_id)
    info = probe(path)
    out = out_dir or (EDIT_DIR / asset_id)
    out.mkdir(parents=True, exist_ok=True)
    raw = run(["ffmpeg", "-v", "error", "-t", str(max_seconds), "-i", str(path), "-vn", "-f", "f32le", "-ac", "1", "-ar", str(lib.SR), "-"],
              f"解碼 {asset_id}").stdout
    x = np.frombuffer(raw, dtype=np.float32).copy()
    if len(x) == 0:
        raise ClipError(f"{asset_id} 解不出任何聲音")
    seconds = len(x) / lib.SR
    try:
        lib.encode_ogg(x, out / "long.ogg", quality=3.0)
    except (OSError, subprocess.CalledProcessError, FileNotFoundError) as error:
        raise ClipError(f"{asset_id} 的長預聽編碼失敗：{error}") from error
    bins = int(min(40000, max(2000, math.ceil(seconds * 200))))
    doc = {"asset": asset_id, "pack": asset["pack"], "file": asset["file"], "duration": round(info["duration"], 4), "preview_duration": round(seconds, 4),
           "truncated": info["duration"] > seconds + 0.05, "sample_rate": info["sample_rate"], "channels": info["channels"], "ogg": "long.ogg",
           "peaks": lib.peaks(x, bins), "segments": [list(s) for s in lib.find_segments(x)]}
    (out / "info.json").write_text(json.dumps(doc, ensure_ascii=False) + "\n", encoding="utf-8")
    doc["dir"] = str(out)
    return doc


# ---------------------------------------------------------------------------
# 擷取
# ---------------------------------------------------------------------------

def cut(src: Path, start: float, end: float, dest: Path, info: dict, what: str) -> None:
    """從原檔切出 [start, end] 到 dest（wav，取樣精準，保留取樣率與聲道數）；驗證輸出長度。"""
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_name(dest.name + ".part")
    try:
        run(["ffmpeg", "-v", "error", "-y", "-i", str(src), "-vn", "-af", f"atrim=start={start:.6f}:end={end:.6f},asetpts=PTS-STARTPTS",
             "-c:a", pcm_codec(info), "-f", "wav", str(tmp)], f"擷取 {what}")
        got = probe(tmp)["duration"]
        if abs(got - (end - start)) > DURATION_TOLERANCE_S:
            raise ClipError(f"擷取 {what} 的輸出長度 {got:.3f} 秒和預期的 {end - start:.3f} 秒不符")
        os.replace(tmp, dest)
    finally:
        tmp.unlink(missing_ok=True)


def next_id(prefix: str, catalog: dict, clips: dict) -> str:
    numbers = [int(i.split("-")[1]) for i in list(catalog["assets"]) + [c["id"] for c in clips["clips"]] if i.startswith(prefix + "-")]
    return f"{prefix}-{(max(numbers) if numbers else 0) + 1:04d}"


def find_duplicate(clips: dict, parent: str, start: float, end: float) -> dict | None:
    for clip in clips["clips"]:
        if clip["parent"] == parent and abs(clip["start"] - start) <= DUPLICATE_TOLERANCE_S and abs(clip["end"] - end) <= DUPLICATE_TOLERANCE_S:
            return clip
    return None


def ensure_local_pack(manifest: dict, kind: str) -> bool:
    """來源目錄裡本機產生的片段素材包；沒有就加上。回傳是否有更動。"""
    pack_id = LOCAL_PACKS[kind]
    if any(p["id"] == pack_id for p in manifest["packs"]):
        return False
    manifest["packs"].append({"id": pack_id, "kind": kind, "title": "本機擷取的片段（" + ("音效" if kind == "sfx" else "音樂") + "）", "author": "衍生自各素材包，見 clips.json",
                              "license": "CC0-1.0", "page": "assets_src/audio/clips.json", "download": [], "dir": pack_id, "local": True,
                              "notes": "從原始素材擷取的片段，授權沿用原檔（CC0）；由 tools/audio/clip_tool.py 產生，不下載。"})
    manifest["packs"].sort(key=lambda p: (p["kind"], p["id"]))
    return True


def catalog_entry(clip: dict, pack_id: str, duration: float, parent: dict) -> dict:
    desc = f'擷取自 {clip["parent"]} 的 {clip["start"]:.2f}–{clip["end"]:.2f} 秒' + (f'：{clip["note"]}' if clip.get("note") else "")
    if parent.get("desc"):
        desc += f'（{parent["desc"][:80]}）'
    return {"pack": pack_id, "file": f'{clip["id"]}.wav', "dur": round(duration, 2), "desc": desc[:200], "parent": clip["parent"], "start": clip["start"], "end": clip["end"]}


def export(asset_id: str, start: float, end: float, note: str = "", preview: bool = True) -> dict:
    catalog, manifest, clips = load_catalog(), load_manifest(), load_clips()
    asset, pack, path = source_of(catalog, manifest, asset_id)
    info = probe(path)
    if not (0.0 <= start and start + MIN_CLIP_S <= end <= info["duration"] + 0.001):
        raise ClipError(f"{asset_id}：起訖 {start:.3f}–{end:.3f} 秒不合法（檔案長 {info['duration']:.3f} 秒；起點要小於終點至少 {MIN_CLIP_S} 秒，且不能超出檔案）")
    end = min(end, info["duration"])
    existing = find_duplicate(clips, asset_id, start, end)
    if existing is not None:
        return {"id": existing["id"], "existing": True, "parent": asset_id, "start": existing["start"], "end": existing["end"]}
    clip_id = next_id(asset_id.split("-")[0], catalog, clips)
    local = LOCAL_PACKS[pack["kind"]]
    dest = RAW / local / f"{clip_id}.wav"
    cut(path, start, end, dest, info, f"{asset_id} 的 {start:.3f}–{end:.3f} 秒")
    clip = {"id": clip_id, "parent": asset_id, "parent_pack": asset["pack"], "parent_file": asset["file"], "start": round(start, 4), "end": round(end, 4)}
    if note:
        clip["note"] = note
    clips["clips"].append(clip)
    catalog["assets"][clip_id] = catalog_entry(clip, local, probe(dest)["duration"], asset)
    updates = [(CLIPS, dump_indent1(clips)), (CATALOG, dump_catalog(catalog))]
    if ensure_local_pack(manifest, pack["kind"]):
        updates.append((MANIFEST, dump_indent1(manifest)))
    try:
        write_all(updates)
    except ClipError:
        dest.unlink(missing_ok=True)
        raise
    result = {"id": clip_id, "existing": False, "parent": asset_id, "start": clip["start"], "end": clip["end"], "duration": round(end - start, 4),
              "file": str(dest.relative_to(ROOT)).replace("\\", "/"), "preview": False}
    if preview:
        done = subprocess.run([sys.executable, str(Path(__file__).with_name("build_candidates.py")), "--only", clip_id], capture_output=True)
        result["preview"] = done.returncode == 0
    return result


def rebuild() -> tuple[int, list[str]]:
    """照片段清單重做缺少的輸出檔，也補回缺少的目錄與來源登記；回傳（重做幾個，錯誤訊息）。"""
    catalog, manifest, clips = load_catalog(), load_manifest(), load_clips()
    made, errors, changed = 0, [], False
    for clip in clips["clips"]:
        try:
            pack = manifest_pack(manifest, clip["parent_pack"])
            local = LOCAL_PACKS[pack["kind"]]
            changed |= ensure_local_pack(manifest, pack["kind"])
            dest = RAW / local / f'{clip["id"]}.wav'
            if not dest.is_file():
                src = RAW / pack["dir"] / clip["parent_file"]
                if not src.is_file():
                    raise ClipError(f"找不到 {clip['id']} 的原始檔 {src.relative_to(ROOT)}（先執行 python tools/audio/fetch_audio.py --only {pack['id']}）")
                cut(src, clip["start"], clip["end"], dest, probe(src), f'{clip["id"]}（{clip["parent"]}）')
                made += 1
            if clip["id"] not in catalog["assets"]:
                catalog["assets"][clip["id"]] = catalog_entry(clip, local, probe(dest)["duration"], catalog["assets"].get(clip["parent"], {}))
                changed = True
        except ClipError as error:
            errors.append(str(error))
    if changed:
        write_all([(CATALOG, dump_catalog(catalog)), (MANIFEST, dump_indent1(manifest))])
    return made, errors


# ---------------------------------------------------------------------------
# 命令列
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", help="結果與錯誤都印成一行 JSON（給實驗室呼叫）")
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("prepare", parents=[common])
    p.add_argument("asset")
    p.add_argument("--max-seconds", type=float, default=DEFAULT_MAX_SECONDS)
    p.add_argument("--out", type=Path)
    e = sub.add_parser("export", parents=[common])
    e.add_argument("asset")
    e.add_argument("--start", type=float, required=True)
    e.add_argument("--end", type=float, required=True)
    e.add_argument("--note", default="")
    e.add_argument("--no-preview", action="store_true")
    sub.add_parser("rebuild", parents=[common])
    lst = sub.add_parser("list", parents=[common])
    lst.add_argument("asset", nargs="?")
    args = parser.parse_args()
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    try:
        if args.command == "prepare":
            doc = prepare(args.asset, args.out, args.max_seconds)
            result = {k: doc[k] for k in ("asset", "dir", "duration", "preview_duration", "truncated")} | {"segments": len(doc["segments"])}
        elif args.command == "export":
            result = export(args.asset, args.start, args.end, args.note, not args.no_preview)
        elif args.command == "rebuild":
            made, errors = rebuild()
            result = {"made": made, "errors": errors}
            if errors:
                print(json.dumps(result, ensure_ascii=False) if args.json else "\n".join(errors), file=sys.stderr if not args.json else sys.stdout)
                return 1
        else:
            clips = [c for c in load_clips()["clips"] if not args.asset or c["parent"] == args.asset or c["id"] == args.asset]
            result = {"clips": clips}
    except ClipError as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False) if args.json else f"錯誤：{error}", file=sys.stdout if args.json else sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False) if args.json or args.command == "list" else "；".join(f"{k}={v}" for k, v in result.items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
