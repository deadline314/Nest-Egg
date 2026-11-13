"""Keep original RGBA locally; publish complete lossless alpha and failed RGBA evidence."""
import hashlib
import argparse
import io
import json
from pathlib import Path
import shutil
import zipfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs"
ARCHIVES = Path("D:/NestEggVerification/archives/NE-267")
LIMIT = 42 * 1024 * 1024  # leave directory overhead below root's 45 MiB limit


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


class Volumes:
    def __init__(self, folder, prefix):
        self.folder, self.prefix = folder, prefix
        self.archive = None
        self.names = []
        self.size = 0

    def add(self, name, data):
        if self.archive is None or self.size + len(data) > LIMIT:
            if self.archive is not None:
                self.archive.close()
            path = self.folder / f"{self.prefix}-{len(self.names) + 1:02d}.zip"
            if path.exists():
                raise ValueError("Refuse to overwrite an evidence volume: " + str(path))
            self.names.append(path)
            self.archive = zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED, compresslevel=6)
            self.size = 0
        self.archive.writestr(name, data)
        self.size += len(data)

    def close(self):
        if self.archive is not None:
            self.archive.close()
        for path in self.names:
            if path.stat().st_size >= 45 * 1024 * 1024:
                raise ValueError("Evidence volume exceeded the chosen remote limit")
        return [dict(file=p.name, sha256=digest(p), bytes=p.stat().st_size) for p in self.names]


def ensure_native_archive(folder):
    manifest = folder / "native-frames-manifest.json"
    archive_path = folder / "native-frames.zip"
    if manifest.exists() or archive_path.exists():
        if not manifest.exists() or not archive_path.exists():
            raise ValueError("Incomplete prior raw package; preserve it and diagnose first")
        return
    groups = json.loads((folder / "frames.json").read_text(encoding="utf8"))
    names = [sample["file"] for group in groups for sample in group["samples"]]
    if len(names) != len(set(names)):
        raise ValueError("Duplicated native frame names")
    members = []
    with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for name in names:
            if Path(name).name != name or "/" in name or "\\" in name:
                raise ValueError("Unexpected native frame path: " + name)
            data = (folder / name).read_bytes()
            archive.writestr(name, data)
            members.append(dict(member=name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
    only_alpha = all(cell.get("alpha_only_rgb") for group in groups for cell in group["cells"])
    receipt = dict(classification="original native RGBA frame bytes; alpha-only RGB sensor shader" if only_alpha else "original native RGBA frame bytes",
                   archive_sha256=digest(archive_path), members=members)
    manifest.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8", newline="\n")


def package(run):
    folder = OUT / run
    (folder / ".gitignore").write_text(
        "# Originals stay here and in the persistent D archive; remote evidence is explicit below.\n"
        "*.png\nnative-frames.zip\n", encoding="utf8", newline="\n")
    ensure_native_archive(folder)
    prior = json.loads((folder / "native-frames-manifest.json").read_text(encoding="utf8"))
    archive = folder / "native-frames.zip"
    original_sha = digest(archive)
    assert original_sha == prior["archive_sha256"]
    ARCHIVES.mkdir(parents=True, exist_ok=True)
    target = ARCHIVES / (run + "-native-rgba.zip")
    if target.exists():
        if digest(target) != original_sha:
            raise ValueError("Persistent original archive already exists with different bytes")
    else:
        shutil.copyfile(archive, target)
    assert digest(target) == original_sha
    shutil.copyfile(folder / "native-frames-manifest.json", ARCHIVES / (run + "-members.json"))
    failed = set(f["file"] for f in json.loads((folder / "report.json").read_text(encoding="utf8"))["failures"])
    alpha = Volumes(folder, "alpha-derived")
    originals = Volumes(folder, "failed-native-rgba")
    alpha.add("frames.json", (folder / "frames.json").read_bytes())
    records = []
    for index, member in enumerate(prior["members"]):
        path = folder / member["member"]
        raw = path.read_bytes()
        assert hashlib.sha256(raw).hexdigest() == member["sha256"]
        image = Image.open(io.BytesIO(raw)).convert("RGBA")
        channel = image.getchannel("A")
        derived = Image.merge("LA", (Image.new("L", image.size, 255), channel))
        encoded = io.BytesIO()
        derived.save(encoded, format="PNG", compress_level=9)
        data = encoded.getvalue()
        assert Image.open(io.BytesIO(data)).convert("RGBA").getchannel("A").tobytes() == channel.tobytes()
        alpha.add(path.name, data)
        records.append(dict(member=path.name, original_rgba_sha256=member["sha256"],
                            derived_la_sha256=hashlib.sha256(data).hexdigest(),
                            alpha_sha256=hashlib.sha256(channel.tobytes()).hexdigest(),
                            size=list(image.size), included_failed_rgba=path.name in failed))
        if path.name in failed:
            originals.add(path.name, raw)
        if (index + 1) % 500 == 0:
            print(run, index + 1, "frames packed", flush=True)
    receipt = dict(classification="Derived LA PNGs preserve every original native alpha pixel; they are not original RGBA captures",
                   original_rgba_archive=dict(persistent_path=target.as_posix(), sha256=original_sha,
                                              original_local_path=archive.relative_to(ROOT).as_posix(),
                                              bytes=archive.stat().st_size, originals_deleted=False),
                   frames=len(records), failed_unique_frames=len(failed), alpha_volumes=alpha.close(),
                   failed_rgba_volumes=originals.close(), members=records,
                   reader="Extract all alpha-derived volumes together, then run unchanged tools/check_joint_frames.py on that folder")
    (folder / "remote-evidence-manifest.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8")
    (folder / ".gitignore").write_text(
        "# Originals stay here and in the persistent D archive; remote evidence is explicit below.\n"
        "*.png\nnative-frames.zip\n", encoding="utf8")
    print(run, "complete", len(records), "alpha frames;", len(failed), "original failed RGBA frames", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("runs", nargs="+")
    for name in parser.parse_args().runs:
        if Path(name).name != name or "/" in name or "\\" in name:
            raise ValueError("Each run must be one evidence folder name")
        package(name)
