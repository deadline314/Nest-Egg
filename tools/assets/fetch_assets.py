"""Download free CC0 environment assets listed in assets_src/manifest.json (NE-56).

Usage:  python tools/assets/fetch_assets.py [--only ID ...] [--list]

Sources: Poly Haven (api.polyhaven.com) and ambientCG (ambientcg.com/api/v2), both CC0.
Raw files go to assets_src/raw/<id>/ (git-ignored, re-downloadable). Every download appends an entry to
assets_src/LICENSES.json (committed) with author, license and source URL, so provenance is never lost.
Failures are logged per asset and never abort the batch.
"""
import argparse
import hashlib
import json
import sys
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets_src"
MANIFEST = SRC / "manifest.json"
LICENSES = SRC / "LICENSES.json"
UA = {"User-Agent": "NestEgg-asset-fetch/1.0 (personal game project)"}
PH_TEXTURE_MAPS = ["Diffuse", "nor_gl", "Rough", "AO", "Displacement"]


def get_json(url: str):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.load(r)


def download(url: str, dest: Path, md5: str = "", sha256: str = "") -> None:
    if dest.exists() and dest.stat().st_size > 0:
        if sha256 and hashlib.sha256(dest.read_bytes()).hexdigest() != sha256:
            raise IOError(f"cached sha256 mismatch: {dest}")
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300) as r:
        data = r.read()
    if md5 and hashlib.md5(data).hexdigest() != md5:
        raise IOError(f"md5 mismatch for {url}")
    if sha256 and hashlib.sha256(data).hexdigest() != sha256:
        raise IOError(f"sha256 mismatch for {url}")
    dest.write_bytes(data)


def fetch_polyhaven(entry: dict, out: Path) -> dict:
    asset, kind, res = entry["asset"], entry["kind"], entry.get("res", "2k")
    info = get_json(f"https://api.polyhaven.com/info/{asset}")
    files = get_json(f"https://api.polyhaven.com/files/{asset}")
    if kind == "hdri":
        node = files["tonemapped"]
        download(node["url"], out / f"{asset}.jpg", node.get("md5", ""))
    elif kind == "texture":
        for m in PH_TEXTURE_MAPS:
            node = files.get(m, {}).get(res, {}).get("jpg")
            if node:
                download(node["url"], out / f"{asset}_{m}.jpg", node.get("md5", ""))
    elif kind == "model":
        node = files["gltf"][res]["gltf"]
        download(node["url"], out / f"{asset}.gltf", node.get("md5", ""))
        for rel, inc in node["include"].items():
            download(inc["url"], out / rel, inc.get("md5", ""))
    else:
        raise ValueError(f"unknown kind {kind}")
    return {
        "author": ", ".join(info.get("authors", {}).keys()),
        "license": "CC0-1.0",
        "page": f"https://polyhaven.com/a/{asset}",
        "name": info.get("name", asset),
    }


def fetch_ambientcg(entry: dict, out: Path) -> dict:
    asset, res = entry["asset"], entry.get("res", "2K").upper()
    d = get_json("https://ambientcg.com/api/v2/full_json?" + urllib.parse.urlencode(
        {"id": asset, "include": "downloadData"}))
    found = d["foundAssets"][0]
    zip_name = f"{asset}_{res}-JPG.zip"
    dest = out / zip_name
    download(f"https://ambientcg.com/get?file={zip_name}", dest)
    with zipfile.ZipFile(dest) as z:
        z.extractall(out)
    return {
        "author": "ambientCG (Lennart Demes)",
        "license": "CC0-1.0",
        "page": f"https://ambientcg.com/view?id={asset}",
        "name": found.get("displayName", asset),
    }


def fetch_kenney(entry: dict, out: Path) -> dict:
    """Official Kenney repository, pinned revision and verified asset hashes."""
    import re
    from pathlib import PurePosixPath
    repo, revision = entry['repo'], entry['revision']
    if not re.fullmatch(r'KenneyNL/[A-Za-z0-9_.-]+', repo) or not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('Kenney source must use the official owner and a full commit hash')
    def safe(path):
        parts = PurePosixPath(path)
        if parts.is_absolute() or '..' in parts.parts or not re.fullmatch(r'[A-Za-z0-9_.\-/]+', path):
            raise ValueError(f'unsafe source path: {path}')
        return path
    for file in entry['files']:
        safe(file['path']); safe(file['dest'])
        if not re.fullmatch(r'[0-9a-f]{64}', file['sha256']):
            raise ValueError('each source file needs a SHA-256')
    base = f'https://raw.githubusercontent.com/{repo}/{revision}'
    evidence = out / 'SOURCE_README.md'
    download(base + '/README.md', evidence)
    readme = evidence.read_text(encoding='utf-8')
    statement = 'Assets included in this package (2D sprites, 3D models and sound effects) are [CC0 licensed](https://creativecommons.org/publicdomain/zero/1.0/)'
    if statement not in readme:
        raise ValueError('pinned README does not explicitly license these assets as CC0')
    for file in entry['files']:
        download(base + '/' + file['path'], out / file['dest'], sha256=file['sha256'])
    return {'author': 'Kenney', 'license': 'CC0-1.0',
            'page': f'https://github.com/{repo}/tree/{revision}',
            'name': entry['asset'], 'license_statement': statement,
            'license_evidence': base + '/README.md',
            'license_evidence_sha256': hashlib.sha256(evidence.read_bytes()).hexdigest()}


FETCHERS = {"kenney": fetch_kenney, "polyhaven": fetch_polyhaven, "ambientcg": fetch_ambientcg}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=[])
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    licenses = json.loads(LICENSES.read_text(encoding="utf-8")) if LICENSES.exists() else {}
    failed = 0
    for entry in manifest:
        eid = entry["id"]
        if args.only and eid not in args.only:
            continue
        if args.list:
            print(f'{eid:32} {entry["source"]:10} {entry["kind"]:8} {entry["asset"]}')
            continue
        try:
            meta = FETCHERS[entry["source"]](entry, SRC / "raw" / eid)
            licenses[eid] = {**entry, **meta}
            print(f"ok    {eid}")
        except Exception as e:  # keep going: one bad asset must not block the batch
            failed += 1
            print(f"FAIL  {eid}: {e}", file=sys.stderr)
    if not args.list:
        LICENSES.write_text(json.dumps(licenses, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
