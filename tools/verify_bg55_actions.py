"""Check native BG55 AI observations and exposure from original float pixels."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

from verify_bg55_readability import FORMATS, exposure_bound


def verify(folder: Path) -> dict:
    data = json.loads((folder / "actions.json").read_bytes())
    assert data["renderer"] == "forward_plus" and data["hdr_2d"]
    assert data["brightness"] == 0.5 and data["simulation_time_scale"] == 1
    assert data["failures"] == 0 and len(data["actors"]) == 2
    sources = json.loads((folder / "source-before.json").read_bytes())
    results = []
    for actor in data["actors"]:
        assert actor["enemy_data_sha256"] == sources[f"data/enemies/{actor['id']}.tres"]
        timeline = actor["timeline"]
        assert len(timeline) > 100 and timeline[-1]["milliseconds"] >= 7900
        assert len({tick["enemy_hp"] for tick in timeline}) == 1 and timeline[0]["enemy_hp"] > 0
        assert min(tick["player_hp"] for tick in timeline) < 999
        states = set(tick["state"] for tick in timeline)
        assert {"windup", "recover"} <= states
        assert "strike" in states if actor["id"] == "ch2_escort" else bool(actor["projectiles"])
        # Escort has authored rig action tracks. BillThrower instead draws its
        # telegraph/paper overlay from its FSM and launches real projectiles;
        # it has no authored RigInput.action track to advance.
        if actor["id"] == "ch2_escort":
            assert len({tick["action_t"] for tick in timeline}) > 5
            assert any(tick["action"].endswith(".strike") for tick in timeline)
        else:
            assert all(tick["action"] == "" for tick in timeline)
        captures = []
        for shot in actor["captures"]:
            assert "trigger_state" in shot, "old pre/post-draw ambiguity is diagnostic only"
            assert shot["world_environment_active"] and shot["glow_enabled"]
            assert shot["profile"] == "market_gate"
            # Live Player updates its beam before its visual physics pose. Keep
            # that measured render-time lag; the held fixture's exact-zero
            # synchronization contract does not apply to ordinary moving AI.
            assert np.isfinite(shot["weapon_light_origin_error_post_draw"])
            assert shot["file"].endswith("-" + shot["state"] + ".png")
            raw = (folder / shot["raw"]).read_bytes()
            dtype, channels = FORMATS[shot["format"]]
            width, height = map(int, shot["size"])
            rgb = np.frombuffer(raw, dtype=dtype).reshape(height, width, channels).astype(np.float64)[..., :3]
            assert np.isfinite(rgb).all()
            expected = np.where(rgb <= 0.0031308, rgb * 12.92, 1.055 * np.maximum(rgb, 0) ** (1 / 2.4) - 0.055)
            shown = np.asarray(Image.open(folder / shot["file"]).convert("RGB"), dtype=np.float64) / 255
            assert np.max(np.abs(shown - np.clip(expected, 0, 1))) <= 1 / 255 + 0.00001
            record = dict(shot, width=width, height=height)
            captures.append(dict(file=shot["file"], state=shot["state"], action=shot["action"],
                                 raw_sha256=hashlib.sha256(raw).hexdigest(),
                                 exposure=exposure_bound(rgb, shot, record)))
        results.append(dict(id=actor["id"], skin=actor["skin"], physics_samples=len(timeline), states=sorted(states),
                            enemy_hp=timeline[0]["enemy_hp"], player_min_hp=min(t["player_hp"] for t in timeline),
                            actual_enemy_projectiles=len(actor["projectiles"]),
                            live_beam_origin_error_max_world_pixels=max(s["weapon_light_origin_error_post_draw"] for s in actor["captures"]),
                            live_beam_note="ordinary owner update ordering retained; no post-draw pose or light correction", captures=captures))
    return dict(quality=data["quality"], adapter=data["adapter"], actors=results)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    report = verify(args.folder)
    args.out.write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps(dict(quality=report["quality"], actors=len(report["actors"]),
                          captures=sum(len(a["captures"]) for a in report["actors"]))))
