"""Read-only scoped NE-90 inventory; no generation or source modification."""
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/comfyui"))
from check_parts import check_character
from check_spec import check

SKINS = ["trooper", "trooper_elite", "grenadier", "sniper", "slasher", "stalker", "flamer", "reclaimer"]

def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))

def image_record(path: Path) -> dict:
    image = Image.open(path)
    rgba = image.convert("RGBA")
    alpha = np.asarray(rgba)[..., 3]
    return {"path": path.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "size": list(image.size), "mode": image.mode, "alpha_bbox": rgba.getbbox(), "transparent_px": int((alpha == 0).sum()), "solid_px": int((alpha > 127).sum())}

def main() -> None:
    output = ROOT / "pm/Nest-Egg/attachments/NE-90-humanoid-subagent"
    pictures = ROOT / "pm/Nest-Egg/images/NE-90-humanoid-subagent"
    output.mkdir(parents=True, exist_ok=True)
    pictures.mkdir(parents=True, exist_ok=True)
    mappings = []
    for path in sorted((ROOT / "data/enemies").rglob("*.tres")):
        text = path.read_text(encoding="utf-8")
        def field(name: str, default="") -> str:
            found = re.search(rf"^{name} = (.+)$", text, re.M)
            return found.group(1).strip('"') if found else default
        mappings.append({"enemy": path.relative_to(ROOT).as_posix(), "skin": field("rig_skin"), "weapon": field("rig_weapon"), "speed": float(field("move_speed", "0")), "two_handed": field("rig_two_handed", "true") == "true", "creature": field("creature_skin"), "in_scope": field("rig_skin") in SKINS})
    sheets = Image.new("RGB", (8 * 300, 470), "#596376")
    draw = ImageDraw.Draw(sheets)
    ledger = []
    for column, skin in enumerate(SKINS):
        directory = ROOT / "art/characters" / skin
        definition = read(directory / "character.json")
        rig = read(ROOT / definition["rig"].removeprefix("res://"))
        recipe = read(ROOT / f"tools/comfyui/recipes/{skin}.json")
        spec = read(ROOT / recipe["spec"])
        errors, warnings = check(recipe, spec, True)
        original = ROOT / recipe["work"] / "base_rgba.png"
        part_records = []
        for name, texture in definition["textures"].items():
            record = {"name": name, "definition": texture, "image": image_record(directory / texture["file"])}
            if "glow" in texture: record["glow"] = image_record(directory / texture["glow"])
            normal = directory / texture["file"]
            normal = normal.with_name(normal.stem + "_n.png")
            if normal.exists(): record["normal"] = image_record(normal)
            record["slots"] = [part for part in definition["parts"] if part.get("texture") == name]
            part_records.append(record)
        source = Image.open(original).convert("RGBA")
        source.thumbnail((280, 420), Image.Resampling.LANCZOS)
        sheets.paste(source, (column * 300 + (300 - source.width) // 2, 35), source)
        draw.text((column * 300 + 5, 6), skin, fill="white")
        ledger.append({"skin": skin, "source": image_record(original), "spec_errors": errors, "spec_warnings": warnings, "part_warnings": check_character(skin, True), "texture_scale": definition["texture_scale"], "scale": definition["scale"], "bones": rig["bones"], "parts": part_records, "weapon_anchor": rig.get("weapon_anchor"), "source_recipe": recipe, "motion": read(ROOT / f"art/motion/{skin}.json")})
        # Every texture at native size, each shown against light and dark backgrounds.
        textures = [(name, Image.open(directory / texture["file"]).convert("RGBA")) for name, texture in definition["textures"].items()]
        widths = [max(220, image.width + 20) for _, image in textures]
        height = max(image.height for _, image in textures) + 40
        sheet = Image.new("RGB", (sum(widths), height * 2), "#eeeef0")
        painter = ImageDraw.Draw(sheet)
        x = 0
        for (name, image), width in zip(textures, widths):
            painter.rectangle((x, height, x + width, 2 * height), fill="#222634")
            for row in range(2):
                sheet.paste(image, (x + 10, row * height + 25), image)
                painter.text((x + 10, row * height + 5), name, fill="black" if row == 0 else "white")
            x += width
        sheet.save(pictures / f"{skin}-parts-native.png")
    sheets.save(pictures / "source-contact-sheet.png")
    (output / "asset-ledger.json").write_text(json.dumps({"scope": SKINS, "enemy_mapping": mappings, "characters": ledger}, ensure_ascii=False, indent=2), encoding="utf-8")
    # Keep distinct skin + actual weapon modes, including borrowed aliases.
    configs = {}
    for row in mappings:
        if row["in_scope"]:
            key = (row["skin"], row["weapon"], row["two_handed"])
            if key not in configs or configs[key]["speed"] < row["speed"]: configs[key] = row
    (output / "capture-config.json").write_text(json.dumps(list(configs.values()), indent=2), encoding="utf-8")
    for row in ledger:
        print(row["skin"], "spec errors", len(row["spec_errors"]), "part warnings", len(row["part_warnings"]), "textures", len(row["parts"]))
    print("mapped", sum(row["in_scope"] for row in mappings), "enemies;", len(configs), "distinct skin/weapon modes")

if __name__ == "__main__":
    main()
