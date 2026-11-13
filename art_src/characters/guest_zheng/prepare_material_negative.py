"""Move the preserved true one-pixel wrist-hole control onto the retained pixel grid."""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs/material-negative-v1"


def main():
    OUT.mkdir(exist_ok=False)
    current = ROOT / "art/characters/guest_zheng/parts/hand.png"
    original = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs/one-pixel-control/hand-without-local-underlap.png"
    result = np.array(Image.open(current))
    previous = np.array(Image.open(original))
    assert result.shape == (100, 180, 4) and previous.shape == (100, 171, 4)
    result[:, 9:180] = previous
    path = OUT / "hand-true-hole.png"
    Image.fromarray(result).save(path)
    # The original finger material remains the same; only a demonstrated missing
    # cuff overlap is restored as a deliberate failure, not an accepted repair.
    np.testing.assert_array_equal(result[:, 69:], np.array(Image.open(current))[:, 69:])
    receipt = dict(classification="deliberate native material failure control, not product art",
                   integer_reference_translation=[9, 0], source_size=[171, 100], output_size=[180, 100],
                   source_sha256=hashlib.sha256(original.read_bytes()).hexdigest(),
                   current_sha256=hashlib.sha256(current.read_bytes()).hexdigest(),
                   output_sha256=hashlib.sha256(path.read_bytes()).hexdigest(), fingers_rgba_exact=True)
    (OUT / "source.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8", newline="\n")
    print(path)


if __name__ == "__main__":
    main()
