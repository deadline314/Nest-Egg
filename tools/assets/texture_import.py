"""Apply built-in Godot environment import resolution settings (BG-17).

Source pixels and world dimensions are retained. Explicitly sized props
and scene-pack props import at half resolution; props keep at least four
texture pixels per world pixel. Terrain, facade modules and foreground silhouettes retain their
resolution. Parallax records source width to preserve world geometry.
Pipeline entrypoints apply the policy after writing output, including new art.
Existing UIDs and unrelated settings are preserved; no second texture library.
"""
from __future__ import annotations

import argparse
import json
import re
import math
import fnmatch
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "art" / "environment"
POLICY = ROOT / "assets_src" / "pipeline" / "texture_import.json"


def apply_policy(check: bool = False) -> int:
    policy = json.loads(POLICY.read_text(encoding="utf-8"))
    if policy["version"] != 1:
        raise ValueError(f"{POLICY}: unsupported version")
    minimum_sizes = {}
    for data in (ROOT / "data/environment").rglob("*.tres"):
        text = data.read_text(encoding="utf-8")
        texture = re.search(r'^texture = "res://([^"\n]+)"', text, re.M)
        size = re.search(r'^size = Vector2\(([-.0-9]+), ([-.0-9]+)\)', text, re.M)
        if texture and size:
            key = texture.group(1)
            minimum_sizes[key] = max(minimum_sizes.get(key, 0), math.ceil(max(map(float, size.groups())) * policy["minimum_prop_pixels_per_world_pixel"]))
    changed = 0
    # Add rendering metadata only: existing stage positions and authored scales
    # stay untouched. The renderer compensates for the imported texture width.
    def stage_sizes(value):
        count = 0
        if isinstance(value, dict):
            source = value.get("path", "")
            if value.get("kind") == "sprite" and source.startswith("res://art/environment/"):
                image_path = ROOT / source.removeprefix("res://")
                if image_path.exists():
                    with Image.open(image_path) as image:
                        width = image.width
                    if value.get("source_width") != width:
                        value["source_width"] = width
                        count += 1
            for child in value.values():
                count += stage_sizes(child)
        elif isinstance(value, list):
            for child in value:
                count += stage_sizes(child)
        return count

    for directory in [ROOT / "data/cutscene/stages", ROOT / "data/story"]:
        for path in directory.rglob("*.json"):
            original = path.read_text(encoding="utf-8")
            data = json.loads(original)
            if stage_sizes(data):
                changed += 1
                if not check:
                    indents = [len(m.group(1)) for m in re.finditer(r"^([ ]+)\S", original, re.M)]
                    path.write_text(json.dumps(data, ensure_ascii=False, indent=min(indents, default=1)) + "\n", encoding="utf-8")
    # Keep the original world dimensions of scale-based parallax, including old
    # foreground strips whose widths differ from the standard tile width.
    for path in (ROOT / "data/environment/themes").rglob("*.tres"):
        original = path.read_text(encoding="utf-8")
        sections = re.split(r"(?=^\[)", original, flags=re.M)
        for i, section in enumerate(sections):
            match = re.search(r'^texture = "res://(art/environment/backdrop/[^"\n]+)"', section, re.M)
            if not match:
                continue
            with Image.open(ROOT / match.group(1)) as image:
                line = f"source_width = {image.width}"
            if re.search(r"^source_width\s*=.*$", section, re.M):
                sections[i] = re.sub(r"^source_width\s*=.*$", line, section, flags=re.M)
            else:
                sections[i] = section.rstrip() + "\n" + line + "\n\n"
        text = "".join(sections)
        if text != original:
            changed += 1
            if not check:
                path.write_text(text, encoding="utf-8")
    for image in sorted(ART.rglob("*")):
        if image.suffix.lower() not in {".png", ".webp", ".jpg"}:
            continue
        path = image.with_name(image.name + ".import")
        original = path.read_text(encoding="utf-8") if path.exists() else (
            '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n'
            f'[deps]\n\nsource_file="res://{image.relative_to(ROOT).as_posix()}"\n\n[params]\n'
        )
        params = dict(policy["params"])
        scale = policy["resolution_scale_by_directory"].get(image.relative_to(ART).parts[0], 1.0)
        if any(fnmatch.fnmatch(image.name, pattern) for pattern in policy.get("preserve_resolution_patterns", [])):
            scale = 1.0
        with Image.open(image) as source:
            dimensions = source.size
            longest = max(dimensions)
        base = re.sub(r"_(n|glow)$", "", image.stem)
        minimum = minimum_sizes.get(image.with_name(base + image.suffix).relative_to(ROOT).as_posix(), 0)
        limit = max(int(longest * scale), minimum)
        # Godot halves dimensions until below the limit. Preserve thin images
        # if integer rounding would change their aspect by more than 1%.
        factor = 1
        while longest / factor > limit:
            factor *= 2
        while factor > 1 and longest // factor < minimum:
            factor //= 2
            limit = longest // factor
        imported = tuple(max(1, v // factor) for v in dimensions)
        if abs(imported[0] / imported[1] / (dimensions[0] / dimensions[1]) - 1) >= 0.01:
            limit = longest
        params["process/size_limit"] = str(limit if limit < longest else 0)
        text = original
        for key, value in params.items():
            pattern = rf"^{re.escape(key)}=.*$"
            if re.search(pattern, text, re.M):
                text = re.sub(pattern, f"{key}={value}", text, flags=re.M)
            else:
                text = text.rstrip() + f"\n{key}={value}\n"
        if text != original or not path.exists():
            changed += 1
            if not check:
                path.write_text(text, encoding="utf-8")
    print(f"Environment import policy: {changed} {'noncompliant' if check else 'updated'} import/metadata files")
    return changed


def finish_pipeline(result: int) -> int:
    apply_policy()
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    count = apply_policy(args.check)
    raise SystemExit(1 if args.check and count else 0)
