#!/usr/bin/env python3
"""Build and verify the pinned Godot audio lifetime repair (NE-280)."""

import argparse
import hashlib
import json
import os
import pathlib
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import venv
import zipfile

HERE = pathlib.Path(__file__).resolve().parent


def digest_file(path):
    with pathlib.Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def recipe():
    raw = (HERE / "manifest.json").read_bytes()
    spec = json.loads(raw)
    patch = (HERE / "audio-bus-lifetime.patch").read_bytes()
    if hashlib.sha256(patch).hexdigest() != spec["patch_sha256"]:
        raise ValueError("audio patch does not match its pinned digest")
    fingerprint = hashlib.sha256(raw + patch + pathlib.Path(__file__).read_bytes()).hexdigest()
    return spec, patch.decode("utf-8"), fingerprint


def download(url, destination, expected, limit):
    if destination.exists():
        if digest_file(destination) != expected:
            raise ValueError(f"cached download has the wrong digest: {destination}")
        return destination
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".part")
    total = 0
    digest = hashlib.sha256()
    # One request: permission failures must remain visible, without mirror retries.
    with urllib.request.urlopen(url, timeout=60) as response, temporary.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            total += len(chunk)
            if total > limit:
                raise ValueError(f"download exceeds its size limit: {url}")
            digest.update(chunk)
            output.write(chunk)
    if digest.hexdigest() != expected:
        raise ValueError(f"download digest mismatch: {url}")
    temporary.replace(destination)
    return destination


def apply_exact_patch(source, patch, spec):
    before = source.read_bytes()
    digest = hashlib.sha256(before).hexdigest()
    if digest == spec["audio_after_sha256"]:
        return
    if digest != spec["audio_before_sha256"]:
        raise ValueError("audio source differs from the pinned version; refusing a fuzzy patch")
    lines = patch.splitlines(keepends=True)
    headers = [i for i, line in enumerate(lines) if line.startswith("@@ ")]
    if len(headers) != 1:
        raise ValueError("the versioned audio repair requires exactly one patch hunk")
    body = lines[headers[0] + 1:]
    old = "".join(line[1:] for line in body if line.startswith((" ", "-"))).encode()
    new = "".join(line[1:] for line in body if line.startswith((" ", "+"))).encode()
    if before.count(old) != 1:
        raise ValueError("audio patch context is not unique")
    after = before.replace(old, new, 1)
    if hashlib.sha256(after).hexdigest() != spec["audio_after_sha256"]:
        raise ValueError("patched audio source has the wrong digest")
    source.write_bytes(after)


def prepare_source(root, archive, spec, patch):
    source = root / ("godot-" + spec["source_commit"])
    if source.is_symlink():
        raise ValueError("source directory is a link; refusing to modify another checkout")
    with tarfile.open(archive) as package:
        members = package.getmembers()
        for member in members:
            relative = pathlib.PurePosixPath(member.name)
            if not relative.parts or relative.parts[0] != source.name or ".." in relative.parts:
                raise ValueError("unexpected source archive path")
        if not source.exists():
            package.extractall(root, filter="data")
        verified = 0
        for member in members:
            if not member.isfile():
                continue
            relative = pathlib.PurePosixPath(member.name)
            if relative.parts[0] != source.name or ".." in relative.parts:
                raise ValueError("unexpected source archive path")
            target = root.joinpath(*relative.parts)
            if target.is_symlink() or not target.is_file():
                raise ValueError(f"source file missing or replaced by a link: {relative}")
            actual = digest_file(target)
            if relative.as_posix() == source.name + "/" + spec["audio_source_path"]:
                if actual not in [spec["audio_before_sha256"], spec["audio_after_sha256"]]:
                    raise ValueError("audio source differs from both pinned states")
            else:
                with package.extractfile(member) as stream:
                    expected = hashlib.file_digest(stream, "sha256").hexdigest()
                if actual != expected:
                    raise ValueError(f"source changed outside the audio patch: {relative}")
            verified += 1
    apply_exact_patch(source / spec["audio_source_path"], patch, spec)
    return source, verified


def prepare_accesskit(root, source, spec):
    asset = spec["accesskit"]
    archive = download(asset["browser_download_url"], root / "downloads" / asset["name"],
                       asset["digest"].removeprefix("sha256:"), 512 * 1024 * 1024)
    destination = source / "bin/build_deps/accesskit"
    prefix = "accesskit-c-0.22.3/"
    with zipfile.ZipFile(archive) as package:
        for member in package.infolist():
            if member.is_dir():
                continue
            if not member.filename.startswith(prefix):
                raise ValueError("unexpected AccessKit archive layout")
            relative = pathlib.PurePosixPath(member.filename[len(prefix):])
            if ".." in relative.parts or relative.is_absolute():
                raise ValueError("unsafe AccessKit archive path")
            target = destination.joinpath(*relative.parts)
            if target.is_symlink():
                raise ValueError("AccessKit file was replaced by a link")
            if target.exists():
                with package.open(member) as stream:
                    expected = hashlib.file_digest(stream, "sha256").hexdigest()
                if digest_file(target) != expected:
                    raise ValueError(f"AccessKit cache differs: {relative}")
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with package.open(member) as stream, target.open("wb") as output:
                    shutil.copyfileobj(stream, output, 1024 * 1024)
    return destination


def verify_cached(root, fingerprint, spec):
    binary = root / "dist/godot"
    receipt = root / "dist/receipt.json"
    if binary.is_symlink() or receipt.is_symlink() or not binary.is_file() or not receipt.is_file():
        return None
    try:
        data = json.loads(receipt.read_text())
        if not isinstance(data, dict):
            return None
        if data["recipe_sha256"] != fingerprint or data["binary_sha256"] != digest_file(binary):
            return None
        for key in ["source_commit", "source_archive_sha256", "patch_sha256", "audio_after_sha256"]:
            if data.get(key) != spec[key]:
                return None
        version = data.get("engine_version", "")
        if data.get("binary_bytes") != binary.stat().st_size or not version.startswith("4.7.2.stable.") or ".official" in version:
            return None
        if data.get("features") != {"wayland": True, "x11": True, "accesskit": True, "renderers": ["vulkan", "opengl3"]}:
            return None
    except (ValueError, KeyError, OSError):
        return None
    return binary


def scons_python(root, provided, version):
    python = pathlib.Path(provided).resolve() if provided else root / "venv/bin/python"
    if provided and not python.is_file():
        raise ValueError("provided SCons Python does not exist")
    if not python.exists():
        venv.EnvBuilder(with_pip=True).create(root / "venv")
    check = subprocess.run([str(python), "-c", "import SCons; print(SCons.__version__)"],
                           capture_output=True, text=True)
    if check.returncode != 0 or check.stdout.strip() != version:
        if provided:
            raise ValueError("provided Python does not contain the pinned SCons version")
        subprocess.run([str(python), "-m", "pip", "install", "--no-cache-dir", "scons==" + version], check=True)
    return python


def compiled_features(source):
    database = source / "compile_commands.json"
    entries = json.loads(database.read_text())
    required = {"WAYLAND_ENABLED", "X11_ENABLED", "ACCESSKIT_ENABLED", "VULKAN_ENABLED", "GLES3_ENABLED"}
    found = set()
    for entry in entries:
        command = entry.get("command", " ".join(entry.get("arguments", [])))
        for name in required - found:
            if re.search(r"(?:-D|/D)" + name + r"(?:[=\s]|$)", command):
                found.add(name)
    if found != required:
        raise ValueError("required engine features were not compiled: " + ", ".join(sorted(required - found)))
    return digest_file(database)


def publish(source, root, spec, fingerprint, command, source_files, compiler):
    built = source / "bin/godot.linuxbsd.editor.x86_64"
    if not built.is_file():
        raise ValueError("the expected editor binary was not produced")
    compile_database = compiled_features(source)
    dist = root / "dist"
    if dist.is_symlink():
        raise ValueError("distribution directory is a link; use an owned build directory")
    dist.mkdir(exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=dist, prefix=".godot-", delete=False) as pending:
        temporary = pathlib.Path(pending.name)
    try:
        shutil.copy2(built, temporary)
        temporary.chmod(temporary.stat().st_mode | 0o111)
        version = subprocess.run([str(temporary), "--headless", "--version"], check=True,
                                 capture_output=True, text=True).stdout.strip()
        if not version.startswith("4.7.2.stable.") or ".official" in version:
            raise ValueError("the repaired engine must identify itself as a custom 4.7.2 build")
        receipt = {"schema": 1, "recipe_sha256": fingerprint, "source_commit": spec["source_commit"],
                   "source_archive_sha256": spec["source_archive_sha256"], "source_files_verified": source_files,
                   "patch_sha256": spec["patch_sha256"], "audio_after_sha256": spec["audio_after_sha256"],
                   "accesskit_sha256": spec["accesskit"]["digest"], "command": command,
                   "compiler": compiler, "engine_version": version, "binary_sha256": digest_file(temporary),
                   "compile_commands_sha256": compile_database,
                   "binary_bytes": temporary.stat().st_size,
                   "features": {"wayland": True, "x11": True, "accesskit": True, "renderers": ["vulkan", "opengl3"]}}
        temporary.replace(dist / "godot")
    finally:
        temporary.unlink(missing_ok=True)
    (dist / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    shutil.copyfile(source / "LICENSE.txt", dist / "LICENSE.txt")
    shutil.copyfile(source / "COPYRIGHT.txt", dist / "COPYRIGHT.txt")
    return dist / "godot"


def emit(binary, environment_file):
    if environment_file:
        value = str(binary.resolve())
        if "\n" in value or "\r" in value:
            raise ValueError("engine path contains a newline")
        with pathlib.Path(environment_file).open("a") as output:
            output.write("GODOT=" + value + "\n")
    print(binary.resolve())


def main():
    if sys.version_info < (3, 12):
        raise ValueError("Python 3.12 or newer is required")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=pathlib.Path, default=pathlib.Path("work/godot-audio-safe"))
    parser.add_argument("--archive", type=pathlib.Path)
    parser.add_argument("--scons-python")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--github-env")
    args = parser.parse_args()
    if not 1 <= args.jobs <= 16:
        raise ValueError("jobs must be 1..16")
    spec, patch, fingerprint = recipe()
    root = args.work_dir.resolve()
    if not args.prepare_only and (not sys.platform.startswith("linux") or platform.machine() not in ["x86_64", "AMD64"]):
        raise ValueError("automatic build supports Linux x86_64; use --prepare-only and the platform build guide")
    binary = verify_cached(root, fingerprint, spec)
    if binary and not args.prepare_only:
        emit(binary, args.github_env)
        return
    if args.verify_only:
        raise ValueError("cached engine is absent or its source/patch/binary receipt does not match")
    if root.joinpath(".git").exists():
        raise ValueError("use a dedicated build directory")
    root.mkdir(parents=True, exist_ok=True)
    (root / ".gdignore").touch()
    archive = args.archive.resolve() if args.archive else root / "downloads/godot.tar.gz"
    archive = download(spec["source_url"], archive, spec["source_archive_sha256"], 300 * 1024 * 1024)
    source, source_files = prepare_source(root, archive, spec, patch)
    prepare_accesskit(root, source, spec)
    if args.prepare_only:
        print(source)
        return
    if shutil.which("wayland-scanner") is None:
        raise ValueError("wayland-scanner is required; install libwayland-bin to retain Wayland support")
    python = scons_python(root, args.scons_python, spec["scons_version"])
    command = [str(python), "-m", "SCons", "-j" + str(args.jobs), *spec["build_options"]]
    environment = os.environ.copy()
    environment["LOCALAPPDATA"] = ""
    environment.pop("SCONS_CACHE", None)
    subprocess.run(command, cwd=source, env=environment, check=True)
    compiler = subprocess.run(["g++", "--version"], check=True, capture_output=True, text=True).stdout.splitlines()[0]
    binary = publish(source, root, spec, fingerprint, command, source_files, compiler)
    emit(binary, args.github_env)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError, tarfile.TarError, zipfile.BadZipFile) as error:
        raise SystemExit(f"Godot audio build failed: {error}") from error
