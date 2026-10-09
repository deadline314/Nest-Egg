"""Read-only cumulative release audit. Does not export or mark chapters delivered."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
SPECS = Path(__file__).with_name("campaign_specs.json")
ALLOWED_ROOTS = frozenset({"autoload", "core", "data", "game", "scenes", "ui", "art", "audio"})
ALLOWED_FILES = frozenset({"project.godot", "icon.png"})
SOURCE_EXTENSIONS = frozenset({".gd", ".gdshader", ".tres", ".tscn", ".json", ".cfg", ".godot"})
QUOTED_PATH = re.compile(r'''["'](res://[^"'\r\n]+)["']''')
CHAPTER_LIST = re.compile(r"const CHAPTER_PATHS[^=]*=\s*\[(.*?)\]", re.S)
MAX_TEXT_BYTES = 16 * 1024 * 1024


class AuditError(ValueError):
    pass


def local_path(root: Path, raw: str) -> Path:
    """Reject traversal, drive paths, hidden inputs and links leaving the project."""
    if not isinstance(raw, str) or not raw or "\\" in raw or "\x00" in raw:
        raise AuditError(f"invalid project path: {raw!r}")
    parts = PurePosixPath(raw).parts
    if PurePosixPath(raw).is_absolute() or any(p in {".", ".."} or p.startswith(".") or ":" in p for p in parts):
        raise AuditError(f"unsafe project path: {raw!r}")
    path = root.joinpath(*parts)
    if not path.resolve().is_relative_to(root.resolve()):
        raise AuditError(f"project path escapes root: {raw!r}")
    return path


def read_text(path: Path) -> str:
    if path.stat().st_size > MAX_TEXT_BYTES:
        raise AuditError(f"source text exceeds {MAX_TEXT_BYTES} bytes: {path}")
    try:
        return path.read_text(encoding="utf-8-sig")
    except UnicodeError as exc:
        raise AuditError(f"source is not UTF-8: {path}") from exc


def digest(path: Path) -> str:
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(block)
    return checksum.hexdigest()


def without_gd_comments(text: str) -> str:
    # Keep line numbers and strings containing #; avoid reading paths in prose comments.
    lines = []
    for line in text.splitlines():
        quote, escaped, end = "", False, len(line)
        for i, char in enumerate(line):
            if escaped:
                escaped = False
            elif quote and char == "\\":
                escaped = True
            elif quote and char == quote:
                quote = ""
            elif not quote and char in {'"', "'"}:
                quote = char
            elif not quote and char == "#":
                end = i
                break
        lines.append(line[:end])
    return "\n".join(lines)


def validate_specs(specs: dict) -> None:
    if not isinstance(specs, dict) or type(specs.get("schema")) is not int or specs["schema"] != 1:
        raise AuditError("specs/schema: expected 1")
    for name, allowed in (("runtime_roots", ALLOWED_ROOTS), ("runtime_files", ALLOWED_FILES)):
        values = specs.get(name)
        if not isinstance(values, list) or not values or any(not isinstance(v, str) or v not in allowed for v in values):
            raise AuditError(f"specs/{name}: unexpected runtime boundary")
        if len(values) != len(set(values)):
            raise AuditError(f"specs/{name}: duplicates")
    if specs.get("optional_missing") != ["tools/dev_tools.json"]:
        raise AuditError("specs/optional_missing: only the existing optional dev menu is supported")
    chapters = specs.get("chapters")
    if not isinstance(chapters, list) or not chapters:
        raise AuditError("specs/chapters: expected nonempty array")
    ids = set()
    for i, chapter in enumerate(chapters):
        at = f"specs/chapters/{i}"
        if not isinstance(chapter, dict) or not isinstance(chapter.get("id"), str) or not chapter["id"]:
            raise AuditError(f"{at}/id: expected nonempty string")
        if chapter["id"] in ids:
            raise AuditError(f"{at}/id: duplicate")
        ids.add(chapter["id"])
        if not isinstance(chapter.get("status"), str) or chapter["status"] not in {"draft", "accepted"}:
            raise AuditError(f"{at}/status: expected draft or accepted")
        if not isinstance(chapter.get("evidence"), list) or any(not isinstance(p, str) for p in chapter["evidence"]):
            raise AuditError(f"{at}/evidence: expected path array")
        for key in ("entry", "terminal", "acceptance_ticket"):
            if not isinstance(chapter.get(key), str):
                raise AuditError(f"{at}/{key}: expected string")


def inventory(root: Path, specs: dict) -> list[dict]:
    paths: set[str] = set()
    for name in specs["runtime_roots"]:
        folder = local_path(root, name)
        if not folder.is_dir():
            raise AuditError(f"runtime root missing: {name}")
        for path in folder.rglob("*"):
            relative = path.relative_to(root).as_posix()
            # Reparse points/symlinks are not followed, even when their target stays inside.
            if path.is_symlink() or path.is_junction():
                raise AuditError(f"runtime link is unsupported: {relative}")
            if any(part.startswith(".") or part == "__pycache__" for part in path.relative_to(root).parts):
                continue
            if path.is_file():
                local_path(root, relative)
                paths.add(relative)
    for relative in specs["runtime_files"]:
        path = local_path(root, relative)
        if not path.is_file() or path.is_symlink():
            raise AuditError(f"runtime file missing or linked: {relative}")
        paths.add(relative)
    return [{"path": relative, "bytes": local_path(root, relative).stat().st_size,
             "sha256": digest(local_path(root, relative))} for relative in sorted(paths)]


def scan_references(root: Path, files: list[dict], optional: list[str]) -> dict:
    included = {item["path"] for item in files}
    missing, excluded, dynamic = [], [], []
    for item in files:
        path = local_path(root, item["path"])
        if path.suffix not in SOURCE_EXTENSIONS:
            continue
        text = read_text(path)
        if path.suffix in {".gd", ".gdshader"}:
            text = without_gd_comments(text) if path.suffix == ".gd" else re.sub(r"//[^\n]*|/\*.*?\*/", "", text, flags=re.S)
        for match in QUOTED_PATH.finditer(text):
            raw = match.group(1)[6:]
            location = {"source": item["path"], "line": text.count("\n", 0, match.start()) + 1, "path": raw}
            if "%" in raw or "{" in raw:
                dynamic.append(location)
                continue
            if raw in optional:
                continue
            try:
                target = local_path(root, raw)
            except AuditError as exc:
                location["reason"] = str(exc)
                missing.append(location)
                continue
            if not target.exists():
                missing.append(location)
            elif target.is_dir():
                if not any(p.startswith(raw.rstrip("/") + "/") for p in included):
                    excluded.append(location)
            elif raw not in included:
                excluded.append(location)
    return {"missing": missing, "excluded": excluded, "dynamic": dynamic}


def story_sources(root: Path, included: set[str]) -> list[dict]:
    text = without_gd_comments(read_text(local_path(root, "autoload/story.gd")))
    match = CHAPTER_LIST.search(text)
    if not match:
        raise AuditError("autoload/story.gd: cannot locate explicit CHAPTER_PATHS")
    result = []
    for resource in QUOTED_PATH.findall(match.group(1)):
        relative = resource[6:]
        path = local_path(root, relative)
        if relative not in included or not path.is_file():
            raise AuditError(f"loaded story source not included: {relative}")
        data = json.loads(read_text(path))
        if not isinstance(data, dict) or not isinstance(data.get("quests", []), list) or not isinstance(data.get("scenes", {}), (dict, list)):
            raise AuditError(f"invalid story container: {relative}")
        result.append({"path": relative, "quests": len(data.get("quests", [])), "scenes": len(data.get("scenes", {}))})
    if not result:
        raise AuditError("autoload/story.gd: no story sources found")
    return result


def chapter_readiness(root: Path, chapters: list[dict], end: str) -> list[dict]:
    result = []
    for chapter in chapters:
        problems = []
        if chapter["status"] != "accepted":
            problems.append("chapter has not been accepted")
        for key in ("entry", "terminal"):
            if not chapter[key]:
                problems.append(f"{key} not supplied")
            elif not local_path(root, chapter[key]).is_file():
                problems.append(f"{key} does not exist: {chapter[key]}")
        if not chapter["evidence"]:
            problems.append("no acceptance evidence supplied")
        for relative in chapter["evidence"]:
            if not local_path(root, relative).is_file():
                problems.append(f"acceptance evidence missing: {relative}")
        result.append({"id": chapter["id"], "acceptance_ticket": chapter["acceptance_ticket"], "issues": problems})
        if chapter["id"] == end:
            return result
    raise AuditError(f"unknown last chapter: {end}")


def git_identity(root: Path) -> dict:
    def run(*args: str) -> str:
        result = subprocess.run(["git", "-C", str(root), *args], text=True, encoding="utf-8", capture_output=True)
        if result.returncode:
            raise AuditError(f"git {' '.join(args)}: {result.stderr.strip()}")
        return result.stdout.strip()
    return {"commit": run("rev-parse", "HEAD"), "dirty": bool(run("status", "--porcelain"))}


def audit(root: Path, specs: dict, end: str) -> dict:
    root = root.resolve()
    validate_specs(specs)
    files = inventory(root, specs)
    refs = scan_references(root, files, specs["optional_missing"])
    sources = story_sources(root, {item["path"] for item in files})
    chapters = chapter_readiness(root, specs["chapters"], end)
    identity = git_identity(root)
    ready = not identity["dirty"] and not refs["missing"] and not refs["excluded"] and all(not c["issues"] for c in chapters)
    return {"schema": 1, "kind": "source-audit", "last_chapter": end, **identity,
            "ready_for_export_review": ready, "exported": False, "native_launch_verified": False,
            "source_bytes": sum(item["bytes"] for item in files), "source_files": len(files),
            "reference_scope": "literal paths in all included source files; runtime reachability not proven",
            "chapters": chapters, "loaded_story_sources": sources, "references": refs, "files": files}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--specs", type=Path, default=SPECS)
    parser.add_argument("--through", required=True, help="last chapter id from campaign_specs.json")
    parser.add_argument("--out", type=Path, help="new audit JSON path; existing files are never overwritten")
    args = parser.parse_args()
    try:
        if args.out and args.out.exists():
            raise FileExistsError(f"existing audit report is preserved: {args.out}")
        report = audit(args.root, json.loads(read_text(args.specs)), args.through)
        if args.out:
            args.out.parent.mkdir(parents=True, exist_ok=True)
            with args.out.open("x", encoding="utf-8", newline="\n") as stream:
                json.dump(report, stream, ensure_ascii=False, indent=2)
                stream.write("\n")
        summary = {key: value for key, value in report.items() if key != "files"}
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 0 if report["ready_for_export_review"] else 2
    except (OSError, AuditError, ValueError) as exc:
        print(f"release audit failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
