"""Validate and publish a retained native RGBA source without inventing a generation seed."""
from __future__ import annotations

import hashlib
import io
import json
import os
import re
import tempfile
from pathlib import Path

from PIL import Image


def read_source(root: Path, record_name: str) -> tuple[dict, Path, bytes]:
    root = root.resolve()
    record_path = (root / record_name).resolve()
    source_root = root / "art_src" / "characters"
    if not record_path.is_relative_to(source_root):
        raise ValueError(f"Source record must be inside {source_root}: {record_path}")
    record = json.loads(record_path.read_text(encoding="utf-8"))
    if not isinstance(record, dict) or not isinstance(record.get("source"), str) or not record["source"]:
        raise ValueError(f"Source record requires a source path: {record_path}")
    if not isinstance(record.get("sha256"), str) or not re.fullmatch(r"[0-9a-f]{64}", record["sha256"]):
        raise ValueError(f"Source record requires an exact SHA-256: {record_path}")
    dimensions = record.get("dimensions")
    if not isinstance(dimensions, list) or len(dimensions) != 2 or any(type(value) is not int or value <= 0 for value in dimensions):
        raise ValueError(f"Source record requires two positive native dimensions: {record_path}")
    path = (root / record["source"]).resolve()
    if not path.is_relative_to(source_root):
        raise ValueError(f"Source image must be inside {source_root}: {path}")
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != record["sha256"]:
        raise ValueError(f"Retained source SHA-256 differs: {path}")
    with Image.open(io.BytesIO(data)) as image:
        image.load()
        if image.format != "PNG" or image.mode != "RGBA" or list(image.size) != record["dimensions"]:
            raise ValueError(f"Retained source needs native RGBA PNG {record['dimensions']}: {path}")
        low, high = image.getchannel("A").getextrema()
        if low != 0 or high < 250:
            raise ValueError(f"Retained source lacks transparent background or opaque subject: {path}")
    return record, path, data


def publish_source(root: Path, record_name: str, target: Path, force: bool = False) -> Path:
    _, source, data = read_source(root, record_name)
    target = target.resolve()
    if not target.is_relative_to(root.resolve() / "art_src" / "characters"):
        raise ValueError(f"Character source target is outside art_src/characters: {target}")
    if target == source:
        raise ValueError(f"Derived source cannot replace its original: {source}")
    if target.exists():
        if target.read_bytes() == data:
            return target
        if not force:
            raise ValueError(f"Different character source already exists: {target}; select explicitly with --force")
    target.parent.mkdir(parents=True, exist_ok=True)
    staged = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix=".source-", suffix=".png", delete=False) as stream:
            staged = Path(stream.name)
            stream.write(data)
        os.replace(staged, target)
    finally:
        if staged is not None and staged.exists():
            staged.unlink()
    return target
