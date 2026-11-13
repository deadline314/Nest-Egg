"""Keep exact provider/job bytes in a new archive; never rewrite earlier receipts."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs"


def main():
    destination = OUT / "torso-local-job-raw-v1.zip"
    if destination.exists():
        raise ValueError("Keep the previous job archive; choose a new version")
    files = list((WORK / "torso_underlayer").rglob("*"))
    found = []
    for folder in (WORK / "03_generation_jobs").iterdir():
        receipt = folder / "generation.json"
        if receipt.exists():
            data = json.loads(receipt.read_text(encoding="utf8"))
            if data.get("pipeline_step") == "torso_underlayer":
                found.append(folder)
    if len(found) != 1:
        raise ValueError("Expected the one completed local torso job")
    files += list(found[0].rglob("*"))
    files += [WORK / name for name in ("make_torso_underlayer.py", "run_parts.py", "review_torso_candidate.py")]
    files = sorted({p for p in files if p.is_file() and p.name != ".gdignore"})
    manifest = []
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in files:
            data = path.read_bytes()
            member = path.relative_to(ROOT).as_posix()
            archive.writestr(member, data)
            manifest.append(dict(member=member, bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
    with zipfile.ZipFile(destination) as archive:
        for item in manifest:
            assert hashlib.sha256(archive.read(item["member"])).hexdigest() == item["sha256"]
    result = dict(classification="exact job and source bytes; local RGB candidate, not native acceptance",
                  shared_existing_service=True, lifecycle_disabled=True, graph_retries=0,
                  archive=destination.name, sha256=hashlib.sha256(destination.read_bytes()).hexdigest(), members=manifest)
    (OUT / "torso-local-job-raw-v1-manifest.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf8")
    print(destination.name, len(manifest), destination.stat().st_size, result["sha256"])


if __name__ == "__main__":
    main()
