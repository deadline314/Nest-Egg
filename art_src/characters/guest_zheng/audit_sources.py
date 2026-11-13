"""Recheck retained originals, approved portraits and eye-only output without model work."""
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/comfyui"))
from character_source import read_source
from cut_layers import validate_eye_state_sources

PORTRAITS = {
    "guest_zheng": "60e02dfa76a92e59419fa00fcb4ac8de5f5d16cd402d2c6035a10b2b689d5777",
    "guest_chen": "695e5c6697e14c187ac6984a0990869841ce1faf13aceba2d018e8606d96964b",
    "guest_hong": "493cc8b3919e0b3a9962fc58f0cdad5ce4827dfe9dc31b07966a9ccc2c43c39d",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    results = {"retained_sources": [], "eyes": []}
    for ident, approved in PORTRAITS.items():
        work = ROOT / "art_src/characters" / ident
        record = work / "01_design/source.json"
        meta = json.loads(record.read_text(encoding="utf8"))
        # The shared validator also checks original PNG mode, dimensions and alpha.
        read_source(ROOT, str(record.relative_to(ROOT)))
        source = ROOT / meta["source"]
        portrait = ROOT / "art/portraits" / (ident + ".png")
        assert sha(source) == sha(work / "base_rgba.png") == meta["sha256"]
        assert sha(portrait) == approved
        results["retained_sources"].append({"id": ident, "original_sha256": sha(source),
                                             "base_sha256": sha(work / "base_rgba.png"),
                                             "portrait_sha256": sha(portrait), "seed": None})
    spec = json.loads((ROOT / "tools/comfyui/specs/guest_zheng_side.json").read_text(encoding="utf8"))
    config = spec["eye_states"]
    original, states = validate_eye_state_sources(config, ROOT / config["sources"]["original_head"]["path"], (1024, 1536))
    pixels = np.array(original)
    mask = Image.new("1", original.size)
    ImageDraw.Draw(mask).polygon([tuple(p) for p in config["eye_mask"]], fill=1)
    outside = ~np.array(mask, dtype=bool)
    for state, image in states.items():
        candidate = np.array(image)
        results["eyes"].append({"state": state, "size": image.size,
                                "changed_pixels": int(np.any(candidate != pixels, axis=2).sum()),
                                "alpha_equal": bool(np.array_equal(candidate[:, :, 3], pixels[:, :, 3])),
                                "outside_eye_equal": bool(np.array_equal(candidate[outside], pixels[outside])),
                                "sha256": config["sources"][state]["sha256"]})
    paper = ROOT / "art/items/world/document.png"
    raw_paper = ROOT / "assets_src/generated/world_items/document.png"
    paper_receipt = ROOT / "assets_src/generated/world_items/document.json"
    paper_pixels = np.asarray(Image.open(paper))
    ys, xs = np.nonzero(paper_pixels[:, :, 3] >= 128)
    receipt = json.loads(paper_receipt.read_text(encoding="utf8"))
    assert sha(raw_paper) == receipt["source_sha256"]
    assert paper_pixels[42, 72, 3] >= 128
    results["reused_paper"] = {"existing_output": str(paper.relative_to(ROOT)), "output_sha256": sha(paper),
                               "output_size": [paper_pixels.shape[1], paper_pixels.shape[0]],
                               "raw_source": str(raw_paper.relative_to(ROOT)), "raw_sha256": sha(raw_paper),
                               "raw_size": Image.open(raw_paper).size,
                               "receipt": str(paper_receipt.relative_to(ROOT)), "receipt_sha256": sha(paper_receipt),
                               "opaque_bbox_inclusive": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())],
                               "original_seed": receipt["seed"],
                               "adoption": "existing unlettered paper art reused visually as restaurant slip; no source edits or new model job"}
    target = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs/source-and-eye-verification.json"
    target.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf8")
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
