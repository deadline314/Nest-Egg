"""Memory-only negative controls; never edits native evidence files."""
import argparse
import hashlib
import json
from pathlib import Path
from unittest.mock import patch

import verify_bg55_readability as verifier


def run(folder: Path) -> dict:
    verifier.verify(folder, True, True)
    original_loads = json.loads
    rejected = []
    cases = ("contrast", "geometry", "control-verdict", "caster-camera", "support-gap", "physics-space", "contact-shadow")
    for case in cases:
        def changed_loads(raw, *args, **kwargs):
            data = original_loads(raw, *args, **kwargs)
            if isinstance(data, dict) and "shots" in data:
                probe = next(s["bg55"] for s in data["shots"] if any(r["enemies"] for r in s["bg55"]["records"]))
                record = next(r for r in probe["records"] if r["enemies"])
                if case == "contrast": record["enemies"][0]["contrast"] += 0.1
                elif case == "geometry": record["enemies"][0]["screen_rect"][2] += 1
                elif case == "control-verdict": probe["controls_valid"] = not probe["controls_valid"]
                elif case == "caster-camera":
                    wall = next(w for w in record["held"]["lighting_owners"]["wall_shadows"] if w["enabled"])
                    wall["caster_transform_values"][4] += 10
                elif case == "support-gap": record["held"]["player_support"]["gap"] += 1
                elif case == "physics-space": record["held"]["lighting_owners"]["physics_bodies"][0]["space_valid"] = False
                else: record["player_contact_shadow"]["cast"] = False
            return data
        try:
            with patch.object(verifier.json, "loads", changed_loads): verifier.verify(folder, True, True)
        except AssertionError:
            rejected.append(case)
        else:
            raise AssertionError("corruption was accepted: " + case)
    original_read = Path.read_bytes
    def changed_read(path):
        raw = original_read(path)
        return bytes([raw[0] ^ 1]) + raw[1:] if path.suffix == ".bin" else raw
    try:
        with patch.object(Path, "read_bytes", changed_read): verifier.verify(folder, True, True)
    except AssertionError:
        rejected.append("raw-byte")
    else:
        raise AssertionError("corrupt raw byte was accepted")
    return dict(rejected=rejected, failures=0, originals_modified=False, unmodified_baseline_passed=True,
                verifier_sha256=hashlib.sha256(Path(verifier.__file__).read_bytes()).hexdigest(),
                negative_control_source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    report = run(args.folder)
    args.out.write_bytes((json.dumps(report, indent=2) + "\n").encode())
    print(json.dumps(report))
