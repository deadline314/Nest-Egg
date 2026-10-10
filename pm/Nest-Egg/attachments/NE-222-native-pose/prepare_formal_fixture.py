from __future__ import annotations
import json
from pathlib import Path

BUNDLE = Path(__file__).resolve().parent
PROJECT = BUNDLE.parents[3]
TEMPLATE = BUNDLE / "generated/formal_pose_data.template.json"
OUTPUT = BUNDLE / "formal_pose_data.json"
TEXTURES = ("front_thigh_common_bbox.png", "front_calf_common_bbox.png")
PREFIX = "../../../pm/Nest-Egg/attachments/NE-222-native-pose/generated/shared_mesh/"

def main() -> None:
    data = json.loads(TEMPLATE.read_text(encoding="utf-8"))
    definitions = data.get("textures", {})
    if set(definitions) != {"probe_front_thigh", "probe_front_calf"}:
        raise SystemExit("expected exactly the two reviewed front-knee source owners")
    for key, filename in zip(("probe_front_thigh", "probe_front_calf"), TEXTURES):
        definitions[key]["file"] = PREFIX + filename
        definitions[key]["size"] = [535, 331]
        definitions[key]["pivot"] = [0, 0]
        atlas = BUNDLE / "generated/shared_mesh" / filename
        normal = atlas.with_name(atlas.stem + "_n.png")
        if not atlas.is_file() or not normal.is_file():
            raise SystemExit(f"missing diffuse/normal pair: {atlas}")
    OUTPUT.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status":"prepared_not_rendered", "path":OUTPUT.relative_to(PROJECT).as_posix(), "owners":list(definitions), "size":[535,331], "acceptance":False}, indent=2))

if __name__ == "__main__":
    main()