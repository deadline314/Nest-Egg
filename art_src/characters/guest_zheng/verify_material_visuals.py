"""Record the individually viewed native pages and final formal scene measurements."""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs"


def main():
    folder = OUT / "npc-colour-material-v2"
    expected = {f"{pose}-{zoom}-{facing}.png" for pose in ("sit-entry", "sit-converse", "sit-exit", "wave-entry", "wave-exit")
                for zoom in ("2.2", "3.4", "3.7") for facing in (-1, 1)}
    assert {path.name for path in folder.glob("*.png")} == expected
    pages = []
    for name in sorted(expected):
        path = folder / name
        pixels = np.array(Image.open(path).convert("RGBA"))
        assert pixels.shape == (720, 1280, 4)
        foreground = np.any(pixels[:690, :, :3] != pixels[0, 0, :3], axis=2)
        assert not foreground[:, 0].any() and not foreground[:, -1].any() and not foreground[0].any()
        counts = [int(foreground[:, column * 320:(column + 1) * 320].sum()) for column in range(4)]
        assert min(counts) > 100
        pages.append(dict(file=name, sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                          size=[1280, 720], four_nonempty_body_regions=counts,
                          no_body_on_outer_left_right_top_edge=True, individually_viewed_by_agent=True))
    scenes = json.loads((OUT / "scene-material-lf-v8/scenes.json").read_text(encoding="utf8"))
    assert not scenes["failures"]
    snapshots = [snapshot for scene in scenes["scenes"] for snapshot in scene["snapshots"]]
    feet = [foot["delta_stage_pixels"] for snapshot in snapshots for foot in snapshot["feet"]]
    seats = [snapshot["seat"]["delta"] for snapshot in snapshots if snapshot["pose"] != "idle"]
    contacts = [contact["distance"] for scene in scenes["scenes"] for contact in scene["held_contacts"]]
    assert all(len(snapshot["texture_bindings"]) == 15 for snapshot in snapshots)
    assert all(binding["normal"] != "missing" and binding["normal_size"] == binding["diffuse_size"]
               for snapshot in snapshots for binding in snapshot["texture_bindings"])
    transitions = {state: sum(scene["transition_samples"][state] for scene in scenes["scenes"]) for state in ("sit", "idle")}
    assert min(transitions.values()) > 0 and max(map(abs, feet)) <= 1 and max(map(abs, seats)) <= 1
    result = dict(classification="agent visual review of all 30 native colour pages and selected formal scene snapshots; not human/playtest approval",
                  findings="Both directions retain complete bodies, hands and feet. Cloth folds replace the flat underarm patch. No extra limbs, disconnected joints or visibly cropped targets in these pages.",
                  pages=pages, scene=dict(snapshots=len(snapshots), actual_diffuse_normal_bindings=15,
                                         actual_transition_samples=transitions, foot_delta_range=[min(feet), max(feet)],
                                         seated_pelvis_delta_range=[min(seats), max(seats)],
                                         held_frames=len(contacts), held_contact_max=max(contacts),
                                         selected_native_snapshots_viewed=["ch2_t_s18_ticket-slip-held.png", "ch2_t_s18_ticket-slip-rest.png", "ch2_t_s18_ticket-idle.png"]),
                  source_scope="Frozen working-tree union with recorded source ZIP/SHA; not asserted to be a published HEAD")
    (OUT / "material-visual-review-v2.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf8", newline="\n")
    print(json.dumps(result["scene"], indent=2))


if __name__ == "__main__":
    main()
