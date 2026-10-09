"""Validate published evidence references and hashes; not a visual acceptance gate."""
import hashlib
import json
import re
from pathlib import Path
from PIL import Image

out = Path(__file__).parent
root = out.resolve().parents[3]
errors = []
equivalence = json.loads((out / "source-equivalence.json").read_text(encoding="utf-8"))
if len(equivalence["items"]) != 174 or equivalence["changed"]:
    errors.append("expected the 174 pinned source/resource hashes to be unchanged")
for entry in equivalence["items"]:
    path = root / entry["path"]
    if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != entry["current_sha256"]:
        errors.append("source no longer matches pinned evidence: " + entry["path"])

inventory = json.loads((out / "inventory.json").read_text(encoding="utf-8"))
formal = [m for m in inventory["models"] if m["id"] != "test_creature"]
if len(formal) != 16 or len(inventory["mounts"]) != 38:
    errors.append("empty/incomplete registry coverage")
for model in formal:
    if model["structural_errors"]:
        errors.append("structural errors: " + model["id"])
    for face in [-1, 1]:
        state = model["states"][0]
        if not (root / f"pm/Nest-Egg/images/NE-90-creature-subagent/{model['id']}-{state}-frame119-face{face}-zoom3.4.png").exists():
            errors.append(f"missing native snapshot: {model['id']} {face}")

index = json.loads((out / "image-index.json").read_text(encoding="utf-8"))
native = [i for i in index if i["kind"] == "native-Godot-capture"]
if len(native) != 34:
    errors.append(f"expected 34 native captures, got {len(native)}")
for entry in index:
    path = root / entry["path"]
    if hashlib.sha256(path.read_bytes()).hexdigest() != entry["sha256"]:
        errors.append("PNG changed after indexing: " + entry["path"])
    with Image.open(path) as image:
        if list(image.size) != entry["native_size"]:
            errors.append("PNG size mismatch: " + entry["path"])
    if entry["kind"] == "native-Godot-capture" and entry["native_size"] != [1280, 720]:
        errors.append("native capture was resized: " + entry["path"])

report = (out / "REPORT.md").read_text(encoding="utf-8")
for link in re.findall(r"\]\(([^)]+)\)", report):
    if "://" in link:
        continue
    target = (out / link.split("#")[0]).resolve()
    # Existing cloud evidence is intentionally excluded from this sparse worktree.
    if "NE-90-cloud-creatures" not in link and not target.exists():
        errors.append("broken report link: " + link)

result = {"formal_models": len(formal), "enemy_resources": len(inventory["mounts"]),
          "source_resource_hashes": len(equivalence["items"]), "native_pngs": len(native),
          "errors": errors, "visual_acceptance": "NOT_CERTIFIED_BY_THIS_VALIDATOR"}
(out / "evidence-validation.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
print(json.dumps(result))
raise SystemExit(1 if errors else 0)
