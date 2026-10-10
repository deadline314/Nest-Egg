"""Bounded, streaming integrity checks for unencrypted Godot 4.7 PCKs.

Format reference: Godot 4.7.2-stable core/io/file_access_pack.cpp and
editor/export/editor_export_platform.cpp. Unknown/encrypted/delta packs fail closed.
This checks bytes and packaging, never native Windows launch or chapter acceptance.
"""
from __future__ import annotations

import hashlib
import struct
from pathlib import Path, PurePosixPath

from campaign_release import AuditError, digest

MAGIC = b"GDPC"
WINDOWS_EXE_LIMIT = 1 << 32  # 4.7.2 fixup_embedded_pck rejects >= 4 GiB.
MAX_ENTRIES = 100_000
MAX_PATH = 4096
BLOCK = 1024 * 1024
FORBIDDEN_ROOTS = {"tools", "tests", "pm", "design", "art_src", "assets_src", "Cyberpunk_Edgerunners_Subs"}


def exact(stream, count: int) -> bytes:
    value = stream.read(count)
    if len(value) != count:
        raise AuditError("truncated PCK structure")
    return value


def pack_path(raw: bytes) -> str:
    try:
        path = raw.rstrip(b"\x00").decode("utf-8")
    except UnicodeError as exc:
        raise AuditError("non UTF-8 PCK path") from exc
    path = path.removeprefix("res://")
    if not path or "\\" in path or "\x00" in path or ":" in path or path.startswith("/"):
        raise AuditError(f"unsafe PCK path: {path!r}")
    parts = path.split("/")
    if any(p in {"", ".", ".."} for p in parts):
        raise AuditError(f"unsafe PCK path: {path!r}")
    if any(p.startswith(".") for p in parts) and parts[0] != ".godot":
        raise AuditError(f"unexpected hidden PCK file: {path}")
    if parts[0] in FORBIDDEN_ROOTS or PurePosixPath(path).suffix in {".py", ".md", ".psd", ".blend", ".srt", ".ass"}:
        raise AuditError(f"development file in PCK: {path}")
    return path


def inspect_pack(path: Path, expected_version=(4, 7, 2), required: dict[str, str] | None = None) -> dict:
    """Check every payload's MD5 with bounded reads and report SHA-256 of artifact.

    `required` maps raw runtime paths (e.g. JSON) to the committed input SHA-256.
    Imported resources are represented by .import/.remap and generated cache paths;
    callers must separately verify those mappings, not demand source PNG bytes.
    """
    if path.is_symlink() or not path.is_file():
        raise AuditError("artifact must be a regular file")
    total = path.stat().st_size
    with path.open("rb") as stream:
        signature = exact(stream, 4)
        target = "pck"
        if signature == MAGIC:
            start, end = 0, total
        else:
            if signature == b"\x7fELF":
                target = "linux"
                stream.seek(18)
                if struct.unpack("<H", exact(stream, 2))[0] != 62:
                    raise AuditError("Linux template is not x86_64")
            elif signature[:2] == b"MZ":
                target = "windows"
                if total >= WINDOWS_EXE_LIMIT:
                    raise AuditError("Windows executable is >= 4 GiB")
                stream.seek(0x3C)
                pe_offset = struct.unpack("<I", exact(stream, 4))[0]
                if pe_offset > total - 26:
                    raise AuditError("invalid PE header offset")
                stream.seek(pe_offset)
                if exact(stream, 4) != b"PE\x00\x00" or struct.unpack("<H", exact(stream, 2))[0] != 0x8664:
                    raise AuditError("invalid Windows x86_64 PE header")
            else:
                raise AuditError("unknown artifact executable signature")
            if total < 12:
                raise AuditError("missing embedded PCK footer")
            stream.seek(total - 12)
            pack_bytes, footer = struct.unpack("<Q4s", exact(stream, 12))
            if footer != MAGIC or pack_bytes < 104 or pack_bytes > total - 12:
                raise AuditError("invalid embedded PCK footer")
            start, end = total - 12 - pack_bytes, total - 12
        stream.seek(start)
        if exact(stream, 4) != MAGIC:
            raise AuditError("embedded PCK header missing")
        version, major, minor, patch, flags = struct.unpack("<IIIII", exact(stream, 20))
        if version not in {2, 3, 4} or (major, minor, patch) != tuple(expected_version):
            raise AuditError(f"unsupported PCK/engine version: {version}, {major}.{minor}.{patch}")
        if flags not in {0, 2} or (version >= 3 and flags != 2):
            raise AuditError("encrypted/sparse/unknown PCK flags are unsupported")
        header_bytes = 104 if version >= 3 else 96
        file_base = struct.unpack("<Q", exact(stream, 8))[0]
        if version >= 3 or flags & 2:
            file_base += start
        if version >= 3:
            directory = start + struct.unpack("<Q", exact(stream, 8))[0]
            if not start + 104 <= directory <= end - 4:
                raise AuditError("PCK directory offset out of bounds")
            stream.seek(directory)
        else:
            exact(stream, 64)
            directory = stream.tell()
        count = struct.unpack("<I", exact(stream, 4))[0]
        if not 0 < count <= MAX_ENTRIES:
            raise AuditError("invalid PCK file count")
        entries, seen = [], set()
        for _ in range(count):
            length = struct.unpack("<I", exact(stream, 4))[0]
            if not 0 < length <= MAX_PATH or stream.tell() + length + 36 > end:
                raise AuditError("PCK directory entry out of bounds")
            name = pack_path(exact(stream, length))
            offset, size = struct.unpack("<QQ", exact(stream, 16))
            md5 = exact(stream, 16).hex()
            entry_flags = struct.unpack("<I", exact(stream, 4))[0]
            if entry_flags or name in seen:
                raise AuditError(f"unsupported flags or duplicate PCK entry: {name}")
            seen.add(name)
            offset += file_base
            if offset < file_base or offset + size > end or offset < start + header_bytes:
                raise AuditError(f"PCK payload out of bounds: {name}")
            entries.append({"path": name, "offset": offset, "bytes": size, "md5": md5})
        directory_end = stream.tell()
        previous_end = start + header_bytes
        for item in sorted(entries, key=lambda e: e["offset"]):
            begin, stop = item["offset"], item["offset"] + item["bytes"]
            if item["bytes"] and (begin < previous_end or begin < directory_end and stop > directory):
                raise AuditError(f"overlapping PCK payload/directory: {item['path']}")
            previous_end = max(previous_end, stop)
            stream.seek(begin)
            md5 = hashlib.md5(usedforsecurity=False)
            sha = hashlib.sha256()
            remaining = item["bytes"]
            while remaining:
                chunk = exact(stream, min(BLOCK, remaining))
                md5.update(chunk)
                sha.update(chunk)
                remaining -= len(chunk)
            if md5.hexdigest() != item["md5"]:
                raise AuditError(f"PCK payload checksum mismatch: {item['path']}")
            item["sha256"] = sha.hexdigest()
        by_path = {item["path"]: item for item in entries}
        for name, sha in (required or {}).items():
            if name not in by_path or by_path[name]["sha256"] != sha:
                raise AuditError(f"committed raw resource missing or changed in PCK: {name}")
    return {"target": target, "bytes": total, "sha256": digest(path), "pck_bytes": end - start,
            "pck_format": version, "engine_version": f"{major}.{minor}.{patch}",
            "embedded": target != "pck", "files": entries,
            "integrity_verified": True, "native_windows_launch_verified": False}
