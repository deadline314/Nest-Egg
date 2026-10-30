"""Immutable source staging and honest export diagnostics for NE-232.

No command supplies fake chapter acceptance or runtime capabilities. `prepare`
can stage a committed, incomplete campaign for inspection; `export` refuses it.
`export --candidate` builds the same single files for native acceptance only when
the staged version is labelled `-candidate`; the manifest keeps every readiness
blocker and never marks the build as a release.
`probe` exports a tiny, explicitly labelled tool fixture, never a chapter build.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

import campaign_release as audit
from pack_integrity import inspect_pack

POLICY = Path(__file__).with_name("build_policy.json")
DEVELOPMENT = {"core/audio/audio_catalog.gd", "core/audio/audition_player.gd",
               "core/audio/audio_data_writer.gd", "core/audio/placement_doc.gd"}
DEV_EXTENSIONS = {".py", ".md", ".psd", ".blend", ".kra", ".aseprite", ".srt", ".ass"}
DEV_DIRECTORIES = {"raw", "originals", "art_src", "assets_src", "tests", "tools", "pm", "design"}
TOKEN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}\Z")
GODOT_ERRORS = re.compile(r"SCRIPT ERROR|Script Error|ERROR:|Parse Error|Assertion failed", re.I)
# NE-230 published contract: the game reads its cumulative identity from data, so a
# build only rewrites edition.json inside the isolated stage (never the repository).
EDITION_SCRIPT = "core/campaign_edition.gd"
CAMPAIGN_DATA = "data/release/campaign.json"
EDITION_DATA = "data/release/edition.json"
OFFICIAL_ARCHIVE_SHA256 = "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011"
OFFICIAL_TEMPLATES = {
    "linux_release.x86_64": (73519416, "d9f79ab89b5ae369aeed11c6052d402e8218cd503bf85b4a235f9c30c46a7c63"),
    "windows_release_x86_64.exe": (109268480, "d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562"),
}


def git(root: Path, *args: str) -> bytes:
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True)
    if result.returncode:
        raise audit.AuditError(f"git {' '.join(args)}: {result.stderr.decode('utf-8', 'replace').strip()}")
    return result.stdout


def committed_text(root: Path, sha: str, path: str) -> str:
    safe_relative(path)
    value = git(root, "show", f"{sha}:{path}")
    if len(value) > audit.MAX_TEXT_BYTES:
        raise audit.AuditError(f"committed metadata too large: {path}")
    return value.decode("utf-8-sig")


def committed_checksum(root: Path, sha: str, path: str) -> dict:
    """Hash acceptance logs/images without loading a whole blob into RAM."""
    safe_relative(path)
    size = int(git(root, "cat-file", "-s", f"{sha}:{path}").decode())
    checksum, substantial, read = hashlib.sha256(), 0, 0
    with tempfile.TemporaryFile() as errors:
        child = subprocess.Popen(["git", "-C", str(root), "cat-file", "blob", f"{sha}:{path}"],
                                 stdout=subprocess.PIPE, stderr=errors)
        try:
            for chunk in iter(lambda: child.stdout.read(1024 * 1024), b""):
                checksum.update(chunk)
                substantial += len(chunk.strip())
                read += len(chunk)
            if child.wait() or read != size:
                raise audit.AuditError(f"acceptance blob read failed: {path}")
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
            child.stdout.close()
    return {"path": path, "bytes": size, "sha256": checksum.hexdigest(), "substantial_bytes": substantial}


def safe_relative(path: str) -> str:
    if not isinstance(path, str) or not path or "\\" in path or "\x00" in path or ":" in path:
        raise audit.AuditError(f"invalid relative path: {path!r}")
    if any(not p or p in {".", ".."} or p.startswith(".") for p in path.split("/")):
        raise audit.AuditError(f"unsafe relative path: {path!r}")
    return path


def no_links(path: Path) -> None:
    for item in (path, *path.parents):
        try:
            info = item.lstat()  # Inspect the link/reparse point, never its target.
        except FileNotFoundError:
            continue  # New output components are allowed; existing parents still checked.
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
            raise audit.AuditError(f"linked output/template path is unsupported: {item}")


def new_directory(path: Path, source_root: Path | None = None) -> Path:
    path = path.absolute()
    no_links(path)
    if source_root and path.resolve().is_relative_to(source_root.resolve()):
        raise audit.AuditError("build output must be outside the source repository")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.mkdir()  # Atomic reservation; includes dangling links and failed builds.
    return path


def write_json(path: Path, value: dict) -> None:
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def validate_policy(policy: dict) -> None:
    if not isinstance(policy, dict) or type(policy.get("schema")) is not int or policy["schema"] != 1:
        raise audit.AuditError("build policy schema must be 1")
    if policy.get("engine_version") != "4.7.2.stable":
        raise audit.AuditError("only verified Godot 4.7.2 templates are supported")
    scripts = policy.get("development_scripts")
    if not isinstance(scripts, list) or any(p not in DEVELOPMENT for p in scripts) or len(set(scripts)) != len(scripts):
        raise audit.AuditError("unexpected development script exclusion")
    for field in ("dynamic_paths", "directory_loads"):
        values = policy.get(field)
        if not isinstance(values, list):
            raise audit.AuditError(f"policy/{field} must be an array")
        seen = set()
        for value in values:
            if not isinstance(value, dict):
                raise audit.AuditError(f"invalid policy/{field} entry")
            for key in ("source", "root"):
                safe_relative(value.get(key))
            if value["root"].split("/")[0] not in audit.ALLOWED_ROOTS:
                raise audit.AuditError("dynamic directory leaves runtime roots")
            if field == "dynamic_paths":
                raw = value.get("path")
                if not isinstance(raw, str) or not raw.startswith(value["root"] + "/"):
                    raise audit.AuditError("dynamic path is outside declared directory")
            identity = (value["source"], value.get("path", value["root"]))
            if identity in seen:
                raise audit.AuditError("duplicate dynamic loader contract")
            seen.add(identity)


def tracked_paths(root: Path, sha: str) -> dict[str, str]:
    result = {}
    for entry in git(root, "ls-tree", "-r", "-z", "--full-tree", sha).split(b"\x00"):
        if not entry:
            continue
        info, raw = entry.split(b"\t", 1)
        mode, kind, _ = info.decode("ascii").split()
        name = raw.decode("utf-8")
        result[name] = mode if kind == "blob" else kind
    return result


def selected_paths(tree: dict[str, str], specs: dict, policy: dict) -> tuple[set[str], list[dict]]:
    included, excluded = set(), []
    development = set(policy["development_scripts"])
    development |= {p + ".uid" for p in development}
    for name, mode in tree.items():
        if (name not in specs["runtime_files"] and name.removesuffix(".import").removesuffix(".uid") not in specs["runtime_files"]
                and not any(name.startswith(p + "/") for p in specs["runtime_roots"])):
            continue
        safe_relative(name)
        if mode not in {"100644", "100755"}:
            raise audit.AuditError(f"linked/submodule/special runtime input: {name} ({mode})")
        if name in development:
            excluded.append({"path": name, "reason": "unreferenced development audio editor class"})
        elif Path(name).suffix in DEV_EXTENSIONS or set(name.split("/")) & DEV_DIRECTORIES:
            excluded.append({"path": name, "reason": "development source/document"})
        else:
            included.add(name)
    for name in specs["runtime_files"]:
        if name not in included:
            raise audit.AuditError(f"required committed runtime file missing: {name}")
    for folder in specs["runtime_roots"]:
        if not any(name.startswith(folder + "/") for name in included):
            raise audit.AuditError(f"required committed runtime directory empty: {folder}")
    return included, excluded


def extract_snapshot(root: Path, sha: str, specs: dict, included: set[str], stage: Path) -> None:
    with tempfile.TemporaryFile() as errors:
        process = subprocess.Popen(["git", "-C", str(root), "archive", "--format=tar", sha,
                                    *specs["runtime_roots"], *specs["runtime_files"],
                                    *sorted(p for p in included if "/" not in p and p not in specs["runtime_files"])],
                                   stdout=subprocess.PIPE, stderr=errors)
        found = set()
        try:
            with tarfile.open(fileobj=process.stdout, mode="r|") as archive:
                for member in archive:
                    if member.isdir():
                        continue
                    safe_relative(member.name)
                    if not member.isfile():
                        raise audit.AuditError(f"non-regular archive member: {member.name}")
                    if member.name not in included:
                        continue
                    if member.name in found:
                        raise audit.AuditError(f"duplicate archive entry: {member.name}")
                    destination = stage / member.name
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    with archive.extractfile(member) as source, destination.open("xb") as target:
                        shutil.copyfileobj(source, target, 1024 * 1024)
                    destination.chmod(0o644)
                    found.add(member.name)
            if process.wait() or found != included:
                errors.seek(0)
                raise audit.AuditError(f"incomplete Git archive: {errors.read(4096).decode('utf-8', 'replace')}")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stdout.close()


def script_dependencies(stage: Path, names: set[str], excluded: list[dict]) -> dict:
    """Conservative global-class and resource graph, not a main-scene-only graph.

    All data/scene/shader resources and all project autoloads are roots. Keep
    literal script paths, UID paths, extends/type/constructor references and every
    class needed transitively. Dynamic script registry lookup is unsupported.
    """
    scripts, classes, uid_scripts = {}, {}, {}
    for name in sorted(names):
        if name.endswith(".gd"):
            text = audit.without_gd_comments(audit.read_text(stage / name))
            scripts[name] = text
            match = re.search(r"^class_name\s+([A-Za-z_]\w*)", text, re.M)
            if match:
                if match[1] in classes:
                    raise audit.AuditError(f"duplicate global script class: {match[1]}")
                classes[match[1]] = name
            if name + ".uid" in names:
                uid_scripts[audit.read_text(stage / (name + ".uid")).strip()] = name
    paths = re.compile(r'''["']\*?(res://[^"'\r\n]+|uid://[a-z0-9]+)["']''')

    def direct(text: str) -> set[str]:
        result = set()
        for raw in paths.findall(text):
            name = raw[6:] if raw.startswith("res://") else uid_scripts.get(raw)
            if name in scripts:
                result.add(name)
        return result

    seeds = set()
    for name in sorted(names):
        if Path(name).suffix in audit.SOURCE_EXTENSIONS and not name.endswith(".gd"):
            seeds.update(direct(audit.read_text(stage / name)))
    pending, reachable = list(seeds), set()
    while pending:
        name = pending.pop()
        if name in reachable:
            continue
        reachable.add(name)
        text = scripts[name]
        if "get_global_class_list" in text or re.search(r"ClassDB\s*\.\s*instantiate", text):
            raise audit.AuditError(f"opaque dynamic script registry load needs an explicit contract: {name}")
        dependencies = direct(text)
        tokens = re.sub(r'''"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*' ''', "", text, flags=re.X)
        dependencies.update(classes[token] for token in re.findall(r"\b[A-Za-z_]\w*\b", tokens) if token in classes)
        pending.extend(dependencies - reachable)
    pruned = []
    for name in sorted(set(scripts) - reachable):
        record = {"path": name, "reason": "no dependency from any runtime data/scene/autoload or reachable global class"}
        match = re.search(r"^class_name\s+([A-Za-z_]\w*)", scripts[name], re.M)
        if match:
            record["global_class"] = match[1]
        excluded.append(record)
        pruned.append(name)
        for candidate in (name, name + ".uid"):
            if candidate in names:
                (stage / candidate).unlink()  # Only this freshly-created isolated stage.
                names.remove(candidate)
                if candidate != name:
                    excluded.append({"path": candidate, "reason": "UID of unreachable script"})
    return {"root_scripts": sorted(seeds), "retained_scripts": len(reachable), "pruned_scripts": pruned,
            "scope": "all committed runtime resource/data roots + autoloads + transitive global classes/UIDs; opaque registry loads refused"}


def closure(stage: Path, files: list[dict], excluded: list[dict], policy: dict) -> dict:
    refs = audit.scan_references(stage, files, ["tools/dev_tools.json"])
    names = {f["path"] for f in files}
    issues, dynamic, warnings = [], [], []
    contracts = {(c["source"], c["path"]): c for c in policy["dynamic_paths"]}
    for ref in refs["dynamic"]:
        contract = contracts.get((ref["source"], ref["path"]))
        if not contract or not any(p.startswith(contract["root"] + "/") for p in names):
            issues.append(f"uncovered dynamic load: {ref['source']}:{ref['line']} {ref['path']}")
        else:
            dynamic.append({**ref, "covered_root": contract["root"],
                            "files": sum(p.startswith(contract["root"] + "/") for p in names)})
    for contract in policy["directory_loads"]:
        source = stage / contract["source"]
        if not source.is_file():
            issues.append(f"directory loader source missing: {contract['source']}")
        else:
            text = audit.without_gd_comments(audit.read_text(source))
            if f'res://{contract["root"]}' not in text or not any(p.startswith(contract["root"] + "/") for p in names):
                issues.append(f"directory loader contract no longer matches: {contract['source']} -> {contract['root']}")
    # Excluded global classes must not leave unresolved type/constructor references.
    # Only declared, case-sensitive Godot global classes are type symbols.
    # A pruned compatibility script can legitimately share a member basename.
    symbols = {item["global_class"] for item in excluded if item.get("global_class")}
    known_uids = set()
    for file in files:
        name = file["path"]
        if name.endswith((".uid", ".import", ".tscn", ".tres")):
            text = audit.read_text(stage / name)
            declarations = text if name.endswith((".uid", ".import")) else text.split("\n", 1)[0]
            known_uids.update(re.findall(r"uid://[a-z0-9]+", declarations))
    for file in files:
        name = file["path"]
        if name.endswith((".gd", ".tscn", ".tres")):
            text = audit.read_text(stage / name)
            if name.endswith(".gd"):
                text = audit.without_gd_comments(text)
            for token in re.findall(r"\b[A-Za-z_][A-Za-z0-9_]*\b", text):
                if token in symbols:
                    issues.append(f"excluded development class referenced: {name}: {token}")
            for uid in re.findall(r'''["'](uid://[a-z0-9]+)["']''', text):
                if uid not in known_uids:
                    header = next((line for line in text.splitlines() if uid in line and line.startswith("[ext_resource ")), "")
                    fallback = re.search(r'path="res://([^\"]+)"', header)
                    if fallback and fallback[1] in names:
                        warnings.append(f"UID unresolved, committed path fallback preserved: {name}: {uid}")
                    else:
                        issues.append(f"unresolved required UID: {name}: {uid}")
        if name.endswith(".import"):
            text = audit.read_text(stage / name)
            match = re.search(r'^source_file="res://([^"\n]+)"', text, re.M)
            if not match or match[1] != name.removesuffix(".import") or match[1] not in names:
                issues.append(f"invalid import source mapping: {name}")
        if name.endswith(".gd") and name + ".uid" not in names:
            warnings.append(f"script has no committed UID; isolated editor must generate and record it: {name}.uid")
        if name.endswith(".uid") and not re.fullmatch(r"uid://[a-z0-9]+\s*", audit.read_text(stage / name)):
            issues.append(f"invalid UID sidecar: {name}")
    issues.extend(f"{kind} reference: {r['source']}:{r['line']} {r['path']}"
                  for kind in ("missing", "excluded") for r in refs[kind])
    return {"issues": sorted(set(issues)), "warnings": warnings, "references": refs, "dynamic_coverage": dynamic,
            "directory_contracts": policy["directory_loads"],
            "scope": "all committed runtime roots, explicit dynamic directories, literal references; runtime playthrough not proven"}


def edition_contract(root: Path, sha: str, tree: dict[str, str], specs: dict, end: str) -> dict:
    """Check the committed NE-230 edition contract against the release specs."""
    issues = [f"edition contract file not committed: {name}"
              for name in (EDITION_SCRIPT, CAMPAIGN_DATA, EDITION_DATA) if name not in tree]
    order: list = []
    if CAMPAIGN_DATA in tree:
        try:
            campaign = json.loads(committed_text(root, sha, CAMPAIGN_DATA))
            chapters = campaign.get("chapters", []) if isinstance(campaign, dict) else []
            order = [c.get("id") for c in chapters if isinstance(c, dict)] if isinstance(chapters, list) else []
        except ValueError as exc:
            issues.append(f"{CAMPAIGN_DATA}: invalid JSON ({exc})")
        expected = [c["id"] for c in specs["chapters"]]
        if order != expected:
            issues.append(f"{CAMPAIGN_DATA} chapter order {order} differs from campaign_specs {expected}")
    return {"issues": issues, "chapter_order": order, "edition_id": f"through-{end}",
            "save_slot": f"user://runs/through-{end}/slot-1.json"}


def terminal_chapter_issue(root: Path, sha: str, tree: dict[str, str], chapter: dict) -> str | None:
    """The edition ends where the terminal level says its chapter is; a mismatch would mis-route."""
    path = chapter["terminal"]
    if not path or path not in tree:
        return None
    match = re.search(r'^chapter = &"([^"]*)"', committed_text(root, sha, path), re.M)
    found = match[1] if match else ""
    return None if found == chapter["id"] else f"terminal level chapter is '{found}', expected '{chapter['id']}'"


def stage_edition(stage: Path, sha: str, end: str, version: str) -> dict:
    """Rewrite only the staged edition config; record committed and staged digests."""
    path = stage / EDITION_DATA
    committed = audit.digest(path)
    path.unlink()  # Regular file from the archive; write_json refuses to overwrite.
    write_json(path, {"schema": 1, "through": end, "version": version, "source_sha": sha,
                      "_note": "Generated by tools/release/campaign_build.py prepare; not a repository file."})
    return {"id": f"through-{end}", "through": end, "path": EDITION_DATA,
            "committed_sha256": committed, "staged_sha256": audit.digest(path)}


def readiness(root: Path, sha: str, specs: dict, end: str, stage: Path, tree: dict[str, str]) -> dict:
    sources = audit.story_sources(stage, set(p for p in tree if (stage / p).is_file()))
    records, blockers = [], []
    for chapter in specs["chapters"]:
        issues = []
        if chapter["status"] != "accepted":
            issues.append("chapter is draft, not accepted production")
        for key in ("entry", "terminal"):
            path = chapter[key]
            if not path or not (stage / safe_relative(path)).is_file():
                issues.append(f"production {key} missing")
        terminal_issue = terminal_chapter_issue(root, sha, tree, chapter)
        if terminal_issue:
            issues.append(terminal_issue)
        tickets = [p for p in tree if p.startswith("pm/") and f"[{chapter['acceptance_ticket']}]" in p and p.endswith(".md")]
        if len(tickets) != 1:
            issues.append("acceptance ticket missing or ambiguous")
        else:
            text = committed_text(root, sha, tickets[0])
            if not re.search(r"^> 狀態：完成\s*$", text, re.M) or "- [ ]" in text:
                issues.append("acceptance ticket is incomplete")
        evidence = []
        for path in chapter["evidence"]:
            safe_relative(path)
            if path not in tree:
                issues.append(f"acceptance evidence not committed: {path}")
            else:
                content = committed_checksum(root, sha, path)
                if content["substantial_bytes"] < 64:
                    issues.append(f"acceptance evidence empty/trivial: {path}")
                evidence.append(content)
        if not evidence:
            issues.append("no committed chapter acceptance evidence")
        matching = []
        for source in sources:
            data = json.loads(audit.read_text(stage / source["path"]))
            if data.get("chapter", {}).get("id") == chapter["id"]:
                matching.append(data)
        if not matching or not any(q.get("kind") == "main" for data in matching for q in data.get("quests", []) if isinstance(q, dict)):
            issues.append("published production main quests absent")
        records.append({"id": chapter["id"], "acceptance_ticket": chapter["acceptance_ticket"],
                        "entry": chapter["entry"], "terminal": chapter["terminal"], "evidence": evidence, "issues": issues})
        if chapter["id"] == end:
            break
    else:
        raise audit.AuditError(f"unknown cumulative terminal chapter: {end}")
    edition = edition_contract(root, sha, tree, specs, end)
    blockers.extend(f"NE-230 edition contract: {issue}" for issue in edition["issues"])
    # Product export needs every included chapter accepted with committed evidence and a valid edition contract.
    ready = not blockers and all(not record["issues"] for record in records)
    return {"ready_for_product_export": ready, "chapters": records, "loaded_story_sources": sources,
            "owner_blockers": blockers, "observed_public_source": {"edition_contract": edition}}


def preflight_stage_paths(destination: Path, names: set[str]) -> None:
    """Keep Windows stages portable without depending on machine registry settings.

    Include the longer export working copy; check UTF-16 units, not Python's
    Unicode character count. No output is created before this check succeeds.
    """
    if sys.platform != "win32":
        return
    for prefix in (destination.absolute() / "project", destination.absolute() / "export-work/project"):
        for name in sorted(names):
            path = prefix / safe_relative(name)
            for candidate, limit in ((path, 259), (path.parent, 247)):
                units = len(str(candidate).encode("utf-16-le", errors="surrogatepass")) // 2
                if units > limit:
                    raise audit.AuditError(
                        f"Windows build path too long: {units} UTF-16 units (portable limit {limit}): {candidate}; "
                        "choose a shorter --out-root (for example C:/NE) or a shorter --version; "
                        "no stage was created")


def prepare(root: Path, output: Path, source: str | None, end: str, version: str, policy: dict) -> tuple[Path, dict]:
    validate_policy(policy)
    if not TOKEN.fullmatch(version) or not TOKEN.fullmatch(end):
        raise audit.AuditError("invalid release version/chapter directory token")
    sha = git(root, "rev-parse", "HEAD").decode().strip() if source is None else source
    if not re.fullmatch(r"[0-9a-f]{40}", sha) or git(root, "rev-parse", "--verify", sha + "^{commit}").decode().strip() != sha:
        raise audit.AuditError("source must identify an existing full commit SHA")
    specs_text = committed_text(root, sha, "tools/release/campaign_specs.json")
    specs = json.loads(specs_text)
    audit.validate_specs(specs)
    if end not in {c["id"] for c in specs["chapters"]}:
        raise audit.AuditError(f"unknown last chapter: {end}")
    tree = tracked_paths(root, sha)
    names, excluded = selected_paths(tree, specs, policy)
    destination = output / f"{version}-through-{end}-{sha}"
    preflight_stage_paths(destination, names)
    destination = new_directory(destination, root)
    stage = destination / "project"
    stage.mkdir()
    try:
        extract_snapshot(root, sha, specs, names, stage)
        edition = stage_edition(stage, sha, end, version) if EDITION_DATA in names else None
        dependencies = script_dependencies(stage, names, excluded)
        files = [{"path": p, "bytes": (stage / p).stat().st_size, "sha256": audit.digest(stage / p)} for p in sorted(names)]
        resource_closure = closure(stage, files, excluded, policy)
        ready = readiness(root, sha, specs, end, stage, tree)
        manifest = {"schema": 1, "kind": "isolated-source-stage", "version": version,
                    "cumulative_terminal": end, "edition": edition,
                    "source_sha": sha, "source_mode": "immutable Git commit archive",
                    "source_worktree_dirty": bool(git(root, "status", "--porcelain").strip()),
                    "specs_sha256": hashlib.sha256(specs_text.encode()).hexdigest(),
                    "build_policy_sha256": hashlib.sha256(json.dumps(policy, sort_keys=True).encode()).hexdigest(),
                    "source_files": len(files), "source_bytes": sum(f["bytes"] for f in files),
                    "script_dependencies": dependencies,
                    "resource_closure": resource_closure, "readiness": ready, "files": files, "excluded": excluded,
                    "exported": False, "native_windows_launch_verified": False}
        write_json(destination / "source-manifest.json", manifest)
        checksum = audit.digest(destination / "source-manifest.json")
        (destination / "source-manifest.sha256").write_text(checksum + "  source-manifest.json\n", encoding="ascii")
        return destination, manifest
    except Exception as exc:
        write_json(destination / "failure.json", {"phase": "prepare", "error": str(exc), "exported": False})
        raise


def verify_stage(destination: Path) -> dict:
    no_links(destination)
    manifest = json.loads(audit.read_text(destination / "source-manifest.json"))
    expected = (destination / "source-manifest.sha256").read_text().split()[0]
    if audit.digest(destination / "source-manifest.json") != expected or manifest.get("kind") != "isolated-source-stage":
        raise audit.AuditError("stage manifest checksum/kind mismatch")
    stage = destination / "project"
    for item in manifest["files"]:
        path = stage / safe_relative(item["path"])
        no_links(path)
        if not path.is_file() or path.stat().st_size != item["bytes"] or audit.digest(path) != item["sha256"]:
            raise audit.AuditError(f"staged input changed: {item['path']}")
    expected_files = {i["path"] for i in manifest["files"]}
    integrity_path = destination / "import-integrity.json"
    if integrity_path.exists():
        integrity = json.loads(audit.read_text(integrity_path))
        if (audit.digest(integrity_path) != (destination / "import-integrity.sha256").read_text().split()[0]
                or integrity["source_manifest_sha256"] != audit.digest(destination / "source-manifest.json")
                or integrity["import_receipt_sha256"] != audit.digest(destination / "import-receipt.json")):
            raise audit.AuditError("import integrity receipt checksum mismatch")
        for item in integrity["generated_files"]:
            name = generated_path(item["path"], expected_files)
            path = stage / name
            no_links(path)
            if not path.is_file() or path.stat().st_size != item["bytes"] or audit.digest(path) != item["sha256"]:
                raise audit.AuditError(f"generated import input changed: {name}")
            expected_files.add(name)
    actual = set()
    for path in stage.rglob("*"):
        no_links(path)
        if path.is_file():
            actual.add(path.relative_to(stage).as_posix())
    if actual != expected_files:
        raise audit.AuditError("unexpected/missing staged files (including generated/ignored inputs)")
    return manifest


def generated_path(name: str, source_names: set[str]) -> str:
    if name.startswith(".godot/"):
        relative = name[len(".godot/"):]
        if (not relative or "\\" in relative or "\x00" in relative or ":" in relative
                or any(p in {"", ".", ".."} for p in relative.split("/"))):
            raise audit.AuditError(f"unsafe generated cache path: {name}")
        return name
    safe_relative(name)
    if name.endswith(".uid") and name.removesuffix(".uid") in source_names:
        return name
    if name.endswith(".import") and name.removesuffix(".import") in source_names:
        return name
    raise audit.AuditError(f"unexpected generated import file: {name}")


def seal_import(destination: Path, manifest: dict) -> dict:
    """Record generated cache/UIDs without changing or replacing source evidence."""
    stage = destination / "project"
    source_names = {i["path"] for i in manifest["files"]}
    for item in manifest["files"]:
        path = stage / safe_relative(item["path"])
        no_links(path)
        if path.stat().st_size != item["bytes"] or audit.digest(path) != item["sha256"]:
            raise audit.AuditError(f"editor changed committed input: {item['path']}")
    generated = []
    for path in sorted(stage.rglob("*")):
        no_links(path)
        if not path.is_file():
            continue
        name = path.relative_to(stage).as_posix()
        if name not in source_names:
            generated_path(name, source_names)
            generated.append({"path": name, "bytes": path.stat().st_size, "sha256": audit.digest(path)})
    receipt = {"kind": "isolated-import-integrity", "source_manifest_sha256": audit.digest(destination / "source-manifest.json"),
               "import_receipt_sha256": audit.digest(destination / "import-receipt.json"), "generated_files": generated}
    write_json(destination / "import-integrity.json", receipt)
    (destination / "import-integrity.sha256").write_text(audit.digest(destination / "import-integrity.json") + "  import-integrity.json\n", encoding="ascii")
    return receipt


def engine_templates(godot: Path, templates: Path) -> dict:
    no_links(godot)
    no_links(templates)
    result = subprocess.run([str(godot), "--version"], capture_output=True, text=True, timeout=30)
    version = result.stdout.strip()
    if result.returncode or not version.startswith("4.7.2.stable.official."):
        raise audit.AuditError(f"expected official 4.7.2 editor; got {version!r}")
    if (templates / "version.txt").read_text().strip() != "4.7.2.stable":
        raise audit.AuditError("export template version does not match editor")
    provenance = json.loads(audit.read_text(templates / "provenance.json"))
    expected_url = "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
    if provenance.get("archive_sha256") != OFFICIAL_ARCHIVE_SHA256 or provenance.get("url") != expected_url:
        raise audit.AuditError("templates lack the verified official 4.7.2 archive provenance")
    for name in ("linux_release.x86_64", "windows_release_x86_64.exe"):
        path = templates / name
        no_links(path)
        record = provenance.get("files", {}).get(name, {})
        size, checksum = OFFICIAL_TEMPLATES[name]
        if (not path.is_file() or record.get("bytes") != size or path.stat().st_size != size
                or record.get("sha256") != checksum or audit.digest(path) != checksum):
            raise audit.AuditError(f"official template checksum mismatch: {name}")
    return {"editor_version": version, "template_version": "4.7.2.stable", "provenance": provenance}


def run_logged(command: list[str], log: Path, cwd: Path, timeout: int = 900) -> dict:
    # Logs are never replaced; capture to disk, not an unbounded in-memory buffer.
    environment = os.environ.copy()  # Inherit authentication/proxy/CA without inspecting values.
    user_paths = [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]
    if sys.platform == "win32":
        # 4.7.2 OS_Windows reads these instead of XDG; override in the child only.
        user_paths.extend((("APPDATA", "roaming"), ("LOCALAPPDATA", "local")))
    for key, folder in user_paths:
        directory = log.parent / "user" / folder
        directory.mkdir(parents=True, exist_ok=True)
        environment[key] = str(directory)
    with log.open("xb") as stream:
        stream.write((json.dumps(command, ensure_ascii=False) + "\n").encode())
        stream.flush()
        try:
            result = subprocess.run(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout, env=environment)
            code = result.returncode
        except subprocess.TimeoutExpired:
            stream.write(b"\nTIMEOUT: child terminated; partial output retained\n")
            raise audit.AuditError(f"command timed out; log retained: {log}")
        stream.write(f"\nexit_code={code}\n".encode())
    has_error = False
    with log.open("r", encoding="utf-8", errors="replace") as stream:
        for line in stream:
            if GODOT_ERRORS.search(line):
                has_error = True
    if code or has_error:
        raise audit.AuditError(f"command failed (exit={code}, error_log={has_error}); log retained: {log}")
    return {"log": log.name, "exit_code": code, "sha256": audit.digest(log)}


PROBE_PRESETS = (("Linux probe", "Linux", "linux_release.x86_64"),
                 ("Windows probe", "Windows Desktop", "windows_release_x86_64.exe"))
# (target, preset name, Godot platform, official template, artifact suffix)
PRODUCT_TARGETS = (("windows", "Nest Egg Windows", "Windows Desktop", "windows_release_x86_64.exe", "exe"),
                   ("linux", "Nest Egg Linux", "Linux", "linux_release.x86_64", "x86_64"))
CANDIDATE_SUFFIX = "-candidate"


def presets(stage: Path, templates: Path, entries=PROBE_PRESETS) -> None:
    def quoted(path: Path) -> str:
        return json.dumps(str(path.resolve()).replace("\\", "/"))
    value = []
    for i, (name, platform, template) in enumerate(entries):
        value.append(f'''[preset.{i}]
name="{name}"
platform="{platform}"
runnable=false
advanced_options=true
export_filter="all_resources"
include_filter="*.json,*.txt"
exclude_filter=""
export_path=""
script_export_mode=2
[preset.{i}.options]
custom_template/release={quoted(templates / template)}
binary_format/architecture="x86_64"
binary_format/embed_pck=true
application/modify_resources=false
codesign/enable=false
''')
    with (stage / "export_presets.cfg").open("x", encoding="utf-8") as stream:
        stream.write("\n".join(value))


def import_stage(destination: Path, godot: Path, templates: Path) -> dict:
    manifest = verify_stage(destination)
    if manifest["resource_closure"]["issues"]:
        raise audit.AuditError("resource closure is incomplete; import refused")
    engine = engine_templates(godot, templates)
    stage = destination / "project"
    # Per-build user/cache directories; preserve inherited proxy, CA and rendering selectors.
    result = run_logged([str(godot), "--headless", "--path", str(stage), "--import"], destination / "import.log", stage)
    input_paths = {item["path"] for item in manifest["files"]}
    generated = [{"path": p.relative_to(stage).as_posix(), "sha256": audit.digest(p)}
                 for p in stage.rglob("*.uid") if p.relative_to(stage).as_posix() not in input_paths]
    receipt = {"kind": "source-import-diagnostic", "source_sha": manifest["source_sha"], "engine": engine,
               "generated_uid_sidecars": generated,
               "command": result, "exported": False, "native_windows_launch_verified": False}
    write_json(destination / "import-receipt.json", receipt)
    seal_import(destination, manifest)
    return receipt


def require_product_ready(destination: Path) -> dict:
    manifest = verify_stage(destination)
    if manifest["resource_closure"]["issues"] or not manifest["readiness"]["ready_for_product_export"]:
        write_json(destination / "export-blocked.json", {"kind": "product-export-blocked",
                   "source_sha": manifest["source_sha"], "readiness": manifest["readiness"],
                   "resource_closure_issues": manifest["resource_closure"]["issues"], "exported": False})
        raise audit.AuditError("formal chapter export blocked by actual readiness/owner contracts; see export-blocked.json")
    return manifest


def require_candidate(destination: Path) -> dict:
    """A candidate is for native acceptance only: complete resources, visibly labelled, blockers kept."""
    manifest = verify_stage(destination)
    if manifest["resource_closure"]["issues"]:
        raise audit.AuditError("resource closure is incomplete; candidate export refused")
    if not manifest["version"].endswith(CANDIDATE_SUFFIX) or not manifest.get("edition"):
        raise audit.AuditError(f"candidate builds need a staged edition whose version ends with '{CANDIDATE_SUFFIX}' "
                               "so the game shows it; re-run prepare with such a version")
    return manifest


def pack_scope_issues(files: list[dict], allowed: set[str]) -> list[str]:
    """Every PCK entry must be a verified staged input or Godot's export conversion of one (.remap, .import, .gdc)."""
    issues = []
    for item in files:
        name = item["path"]
        if name in allowed or name.startswith(".godot/") or name == "project.binary":
            continue
        if name.removesuffix(".remap").removesuffix(".import") in allowed:
            continue
        if name.endswith(".gdc") and name.removesuffix(".gdc") + ".gd" in allowed:
            continue  # script_export_mode=2 ships scripts as binary tokens.
        issues.append(name)
    return issues


def campaign_scope(stage: Path, end: str) -> list[dict]:
    """Chapters this build contains, in campaign order, from the staged contract."""
    campaign = json.loads(audit.read_text(stage / CAMPAIGN_DATA))
    chapters, included = [], True
    for chapter in campaign.get("chapters", []):
        chapters.append({"id": chapter.get("id"), "title": chapter.get("title", chapter.get("id")), "included": included})
        if chapter.get("id") == end:
            included = False
    if not any(c["id"] == end for c in chapters):
        raise audit.AuditError(f"{CAMPAIGN_DATA} does not list the cumulative terminal chapter {end}")
    return chapters


def edition_launch(executable: Path, log: Path, scope: list[dict], end: str, version: str) -> dict:
    """Start the exported file alone in a clean folder and read back the scope it reports."""
    record = run_logged([str(executable), "--headless", "--", "--edition-info"], log, executable.parent, 300)
    line = next((l for l in log.read_text(encoding="utf-8", errors="replace").splitlines() if l.startswith("EDITION_INFO ")), None)
    if line is None:
        raise audit.AuditError(f"exported game did not report its edition; log retained: {log}")
    report = json.loads(line[len("EDITION_INFO "):])
    expected = [c["id"] for c in scope if c["included"]]
    reported = [c["id"] for c in report.get("chapters", []) if c.get("included")]
    if report.get("through") != end or report.get("development") or reported != expected or not report.get("first_level_included"):
        raise audit.AuditError(f"exported game reports scope {reported} through {report.get('through')!r}; expected {expected}")
    if report.get("version") != version:
        raise audit.AuditError(f"exported game shows version {report.get('version')!r}; expected {version!r}")
    if report.get("issues"):
        raise audit.AuditError(f"exported game reports edition data issues: {report['issues']}")
    leaked = [c for c in report.get("included_levels", {}) if c not in expected]
    if leaked:
        raise audit.AuditError(f"exported game includes areas of chapters outside this build: {leaked}")
    return {"command": record, "edition": report}


def native_export_host() -> dict:
    """Only execute the artifact this host can run; cross exports remain inspected."""
    target = {"linux": "linux", "win32": "windows"}.get(sys.platform)
    architecture = platform.machine()
    if target is None or architecture.lower() not in {"x86_64", "amd64"}:
        raise audit.AuditError(f"unsupported native export host: {sys.platform}/{architecture}; requires Linux/Windows x86_64")
    return {"target": target, "platform": sys.platform, "architecture": architecture}


def export(destination: Path, godot: Path, templates: Path, candidate: bool) -> dict:
    """Export Windows and Linux single files from an imported stage; never overwrite an earlier export."""
    manifest = require_candidate(destination) if candidate else require_product_ready(destination)
    if not (destination / "import-integrity.json").is_file():
        raise audit.AuditError("run import-stage before export")
    if (destination / "artifacts").exists():
        raise audit.AuditError("this stage already has an export; earlier builds are never overwritten — prepare a new version")
    native = native_export_host()
    engine = engine_templates(godot, templates)
    end, version = manifest["cumulative_terminal"], manifest["version"]
    artifacts_dir = new_directory(destination / "artifacts")
    work = destination / "export-work"
    records, artifacts = [], {}
    try:
        shutil.copytree(destination / "project", work / "project", symlinks=True)
        no_links(work / "project")
        stage = work / "project"
        presets(stage, templates, [(name, platform, template) for _, name, platform, template, _ in PRODUCT_TARGETS])
        scope = campaign_scope(stage, end)
        required = {EDITION_DATA: manifest["edition"]["staged_sha256"], CAMPAIGN_DATA: audit.digest(stage / CAMPAIGN_DATA)}
        allowed = {item["path"] for item in manifest["files"]}
        for target, preset, _, _, suffix in PRODUCT_TARGETS:
            path = artifacts_dir / f"NestEgg-{version}-through-{end}.{suffix}"
            records.append(run_logged([str(godot), "--headless", "--path", str(stage), "--export-release", preset, str(path)],
                                      destination / f"export-{target}.log", stage, 3600))
            pack = inspect_pack(path, required=required)
            stray = pack_scope_issues(pack["files"], allowed)
            if stray:
                raise audit.AuditError(f"{target} pack contains entries outside the verified stage: {stray[:10]}")
            largest = sorted(pack["files"], key=lambda f: f["bytes"], reverse=True)[:15]
            artifacts[target] = {"file": path.name, "bytes": pack["bytes"], "sha256": pack["sha256"], "pck_bytes": pack["pck_bytes"],
                                 "entries": len(pack["files"]), "size_limit_ok": pack["bytes"] < (1 << 32),
                                 "largest_entries": [{"path": f["path"], "bytes": f["bytes"]} for f in largest]}
        target = native["target"]
        clean = destination / f"clean-launch-{target}"
        clean.mkdir()
        executable = clean / artifacts[target]["file"]
        shutil.copy2(artifacts_dir / executable.name, executable)
        if target == "linux":
            executable.chmod(0o755)
        launch = edition_launch(executable, destination / f"clean-launch-{target}.log", scope, end, version)
        clean_launch = {"verified": True, "host": native, "log": launch["command"]["log"],
                        "sha256": launch["command"]["sha256"],
                        "scope": "headless edition information only; not chapter acceptance",
                        "reported_endings": launch["edition"].get("endings", []),
                        "reported_levels": launch["edition"].get("included_levels", {})}
        platform_launches = {f"{platform_target}_clean_launch": clean_launch if platform_target == target else
                            {"verified": False, "reason": f"not run on {native['platform']}/{native['architecture']}"}
                            for platform_target, *_ in PRODUCT_TARGETS}
        receipt = {"schema": 1, "kind": "campaign-candidate" if candidate else "campaign-release",
                   "is_release": not candidate, "version": version, "cumulative_terminal": end,
                   "edition_id": f"through-{end}", "save_slot": f"user://runs/through-{end}/slot-1.json",
                   "source_sha": manifest["source_sha"], "engine": engine, "chapters": scope,
                   "artifacts": artifacts, "commands": records,
                   "native_clean_launch": clean_launch, **platform_launches,
                   "native_windows_launch_verified": False,
                   "native_windows_pending": "Copy only the .exe into an empty folder on Windows, start it, play to the chapter end "
                                             "and confirm the completion card and the runs/through-<chapter> save folder (NE-232 ticket).",
                   "readiness_blockers": manifest["readiness"]["owner_blockers"] + [
                       f"{c['id']}: {issue}" for c in manifest["readiness"]["chapters"] for issue in c["issues"]],
                   "chapter_acceptance_verified": False}
        write_json(destination / "export-manifest.json", receipt)
        (destination / "SHA256SUMS").write_text("".join(f"{a['sha256']}  artifacts/{a['file']}\n" for a in artifacts.values()), encoding="ascii")
        return receipt
    except Exception as exc:
        write_json(destination / "export-failure.json", {"kind": "failed-campaign-export", "error": str(exc),
                   "successful_commands": records, "is_release": False})
        raise
    finally:
        shutil.rmtree(work, ignore_errors=True)  # The verified stage remains; the working copy is only for Godot.


PROBE_SCRIPT = '''extends Node
func _ready() -> void:
    var raw = FileAccess.get_file_as_string("res://data/probe.json")
    var parsed = JSON.parse_string(raw)
    if not parsed is Dictionary or parsed.get("fixture") != "NE232_TOOL_ONLY":
        push_error("PROBE JSON missing")
        get_tree().quit(1)
        return
    var paths = DirAccess.get_files_at("res://data/dynamic")
    var found = false
    for file in paths:
        if file.trim_suffix(".remap") == "later.tres":
            var resource = load("res://data/dynamic/" + file.trim_suffix(".remap"))
            found = resource != null and resource.resource_name == "later_chapter_fixture"
    if not found:
        push_error("PROBE dynamic directory resource missing")
        get_tree().quit(1)
        return
    print("NE232_TOOL_PROBE_PASS JSON + directory + later resource; not chapter acceptance")
    get_tree().quit(0)
'''


def native_probe_host() -> dict:
    target = {"linux": "linux", "win32": "windows"}.get(sys.platform)
    architecture = platform.machine()
    if target is None or architecture.lower() not in {"x86_64", "amd64"}:
        raise audit.AuditError(f"unsupported native probe host: {sys.platform}/{architecture}; requires Linux/Windows x86_64")
    return {"target": target, "platform": sys.platform, "architecture": architecture,
            "artifact": f"NE232_TOOL_PROBE.{('exe' if target == 'windows' else 'x86_64')}",
            "log": f"native-{target}.log", "scope": "tool fixture only; not chapter acceptance"}


def probe(output: Path, godot: Path, templates: Path) -> dict:
    native = native_probe_host()
    engine = engine_templates(godot, templates)
    destination = new_directory(output)
    stage = destination / "project"
    (stage / "data/dynamic").mkdir(parents=True)
    (stage / "project.godot").write_text('[application]\nconfig/name="NE232 TOOL PROBE ONLY"\nrun/main_scene="res://main.tscn"\n', encoding="utf-8")
    (stage / "main.tscn").write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://probe.gd" id="1"]\n[node name="ToolProbe" type="Node"]\nscript=ExtResource("1")\n', encoding="utf-8")
    (stage / "probe.gd").write_text(PROBE_SCRIPT, encoding="utf-8")
    (stage / "data/probe.json").write_text('{"fixture":"NE232_TOOL_ONLY"}\n', encoding="utf-8")
    (stage / "data/dynamic/later.tres").write_text('[gd_resource type="Resource" format=3]\n[resource]\nresource_name="later_chapter_fixture"\n', encoding="utf-8")
    records, artifacts = [], {}
    try:
        presets(stage, templates)
        records.append(run_logged([str(godot), "--headless", "--path", str(stage), "--import"], destination / "import.log", stage))
        product = destination / "artifact"
        product.mkdir()
        required = {"data/probe.json": audit.digest(stage / "data/probe.json")}
        for target, preset, suffix in (("linux", "Linux probe", "x86_64"), ("windows", "Windows probe", "exe")):
            path = product / f"NE232_TOOL_PROBE.{suffix}"
            records.append(run_logged([str(godot), "--headless", "--path", str(stage), "--export-release", preset, str(path)], destination / f"export-{target}.log", stage))
            artifacts[target] = inspect_pack(path, required=required)
            if not any(p["path"] in {"data/dynamic/later.tres", "data/dynamic/later.tres.remap"} for p in artifacts[target]["files"]):
                raise audit.AuditError("dynamic later resource absent from probe PCK")
        # Run a new native process with only the executable, no project or PCK nearby.
        clean = destination / "clean-launch"
        clean.mkdir()
        executable = clean / native["artifact"]
        shutil.copy2(product / executable.name, executable)
        if native["target"] == "linux":
            executable.chmod(0o755)
        records.append(run_logged([str(executable), "--headless"], destination / native["log"], clean, 60))
        if "NE232_TOOL_PROBE_PASS" not in (destination / native["log"]).read_text(encoding="utf-8", errors="replace"):
            raise audit.AuditError("native probe exited without runtime assertions")
        receipt = {"schema": 1, "kind": "tool-fixture-export-probe", "is_campaign_product": False,
                   "engine": engine, "commands": records, "artifacts": artifacts,
                   "native_launch": native,
                   "native_linux_fixture_launch_verified": native["target"] == "linux",
                   "native_windows_fixture_launch_verified": native["target"] == "windows",
                   "native_windows_launch_verified": native["target"] == "windows",
                   "chapter_acceptance_verified": False}
        write_json(destination / "probe-manifest.json", receipt)
        (destination / "checksums.sha256").write_text("".join(f"{v['sha256']}  artifact/NE232_TOOL_PROBE.{('exe' if k == 'windows' else 'x86_64')}\n" for k, v in artifacts.items()), encoding="ascii")
        return receipt
    except Exception as exc:
        write_json(destination / "failure.json", {"kind": "failed-tool-probe", "error": str(exc),
                   "successful_commands": records, "is_campaign_product": False})
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    stage = sub.add_parser("prepare")
    stage.add_argument("--root", type=Path, default=audit.ROOT)
    stage.add_argument("--out-root", type=Path, required=True)
    stage.add_argument("--source", help="full immutable commit SHA; defaults to HEAD")
    stage.add_argument("--through", required=True)
    stage.add_argument("--version", required=True)
    stage.add_argument("--policy", type=Path, default=POLICY)
    for name in ("import-stage", "export", "verify-stage"):
        p = sub.add_parser(name)
        p.add_argument("--stage", type=Path, required=True)
        if name in ("import-stage", "export"):
            p.add_argument("--godot", type=Path, required=True)
            p.add_argument("--templates", type=Path, required=True)
        if name == "export":
            p.add_argument("--candidate", action="store_true",
                           help="build for native acceptance only; requires a version ending in -candidate")
    fixture = sub.add_parser("probe")
    fixture.add_argument("--out", type=Path, required=True)
    fixture.add_argument("--godot", type=Path, required=True)
    fixture.add_argument("--templates", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            destination, report = prepare(args.root, args.out_root, args.source, args.through, args.version, json.loads(audit.read_text(args.policy)))
            print(json.dumps({"stage": str(destination), "source_sha": report["source_sha"],
                              "source_files": report["source_files"], "source_bytes": report["source_bytes"],
                              "closure_issues": report["resource_closure"]["issues"], "readiness": report["readiness"]}, ensure_ascii=False, indent=2))
            return 2 if report["resource_closure"]["issues"] else 0
        if args.command == "export":
            report = export(args.stage, args.godot, args.templates, args.candidate)
            print(json.dumps({k: report[k] for k in ("kind", "is_release", "version", "cumulative_terminal", "source_sha",
                                                       "artifacts", "native_clean_launch", "linux_clean_launch", "windows_clean_launch", "native_windows_launch_verified")},
                             ensure_ascii=False, indent=2))
        elif args.command == "verify-stage":
            report = verify_stage(args.stage)
            print(f"verified {report['source_files']} committed inputs; exported=false")
        elif args.command == "import-stage":
            import_stage(args.stage, args.godot, args.templates)
            print("isolated source import verified; exported=false")
        elif args.command == "probe":
            report = probe(args.out, args.godot, args.templates)
            print(json.dumps({k: v for k, v in report.items() if k != "artifacts"}, ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, subprocess.SubprocessError, tarfile.TarError) as exc:
        print(f"campaign build failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
