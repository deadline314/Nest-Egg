"""Immutable source staging and honest export diagnostics for NE-232.

No command supplies fake chapter acceptance or runtime capabilities. `prepare`
can stage a committed, incomplete campaign for inspection; `export` refuses it.
`probe` exports a tiny, explicitly labelled tool fixture, never a chapter build.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
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
        if item.is_symlink() or getattr(item, "is_junction", lambda: False)():
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
    symbols = {item.get("global_class", Path(item["path"]).stem).replace("_", "").lower()
               for item in excluded if item["path"].endswith(".gd")}
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
                if token.replace("_", "").lower() in symbols:
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
        # Actual owner handover is missing. Do not invent JSON keys or a capability override.
        issues.append("production entry/exit and story-result producer acceptance not handed over")
        records.append({"id": chapter["id"], "acceptance_ticket": chapter["acceptance_ticket"],
                        "entry": chapter["entry"], "terminal": chapter["terminal"], "evidence": evidence, "issues": issues})
        if chapter["id"] == end:
            break
    else:
        raise audit.AuditError(f"unknown cumulative terminal chapter: {end}")
    observed = {}
    for name in ("core/run_snapshot.gd", "tools/story/build_ch1_story.py"):
        if name in tree:
            text = committed_text(root, sha, name)
            observed[name] = {"sha256": hashlib.sha256(text.encode()).hexdigest()}
            if name.endswith("run_snapshot.gd"):
                match = re.search(r'"release":\s*"([^"]+)"', text)
                observed[name]["snapshot_release"] = match[1] if match else "not identified"
            else:
                observed[name]["backend_returns_none"] = bool(re.search(r"def production_backend\(\):(?:\n[ \t]+[^\n]*)*?\n[ \t]+return None", text))
    blockers.append("NE-230 has no published selectable cumulative release identity/terminal routing/save compatibility contract")
    blockers.append("production producer/backend handover is missing; no CLI override is supported")
    return {"ready_for_product_export": False, "chapters": records, "loaded_story_sources": sources,
            "owner_blockers": blockers, "observed_public_source": observed}


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
    destination = new_directory(output / f"{version}-through-{end}-{sha}", root)
    stage = destination / "project"
    stage.mkdir()
    try:
        extract_snapshot(root, sha, specs, names, stage)
        dependencies = script_dependencies(stage, names, excluded)
        files = [{"path": p, "bytes": (stage / p).stat().st_size, "sha256": audit.digest(stage / p)} for p in sorted(names)]
        resource_closure = closure(stage, files, excluded, policy)
        ready = readiness(root, sha, specs, end, stage, tree)
        manifest = {"schema": 1, "kind": "isolated-source-stage", "version": version,
                    "cumulative_terminal": end, "source_sha": sha, "source_mode": "immutable Git commit archive",
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
    for key, folder in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
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


def presets(stage: Path, templates: Path) -> None:
    def quoted(path: Path) -> str:
        return json.dumps(str(path.resolve()).replace("\\", "/"))
    value = []
    for i, (name, platform, template) in enumerate((
        ("Linux probe", "Linux", "linux_release.x86_64"),
        ("Windows probe", "Windows Desktop", "windows_release_x86_64.exe"))):
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


def require_product_ready(destination: Path) -> None:
    manifest = verify_stage(destination)
    if manifest["resource_closure"]["issues"] or not manifest["readiness"]["ready_for_product_export"]:
        write_json(destination / "export-blocked.json", {"kind": "product-export-blocked",
                   "source_sha": manifest["source_sha"], "readiness": manifest["readiness"],
                   "resource_closure_issues": manifest["resource_closure"]["issues"], "exported": False})
        raise audit.AuditError("formal chapter export blocked by actual readiness/owner contracts; see export-blocked.json")
    # No accepted public owner interface currently exists. Do not silently use the probe preset.
    raise audit.AuditError("product export adapter awaits the published NE-230/chapter contract")


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


def probe(output: Path, godot: Path, templates: Path) -> dict:
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
        executable = clean / "NE232_TOOL_PROBE.x86_64"
        shutil.copy2(product / executable.name, executable)
        executable.chmod(0o755)
        records.append(run_logged([str(executable), "--headless"], destination / "native-linux.log", clean, 60))
        if "NE232_TOOL_PROBE_PASS" not in (destination / "native-linux.log").read_text():
            raise audit.AuditError("native probe exited without runtime assertions")
        receipt = {"schema": 1, "kind": "tool-fixture-export-probe", "is_campaign_product": False,
                   "engine": engine, "commands": records, "artifacts": artifacts,
                   "native_linux_fixture_launch_verified": True, "native_windows_launch_verified": False,
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
        if name == "import-stage":
            p.add_argument("--godot", type=Path, required=True)
            p.add_argument("--templates", type=Path, required=True)
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
            require_product_ready(args.stage)
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
