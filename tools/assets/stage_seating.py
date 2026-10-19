"""BG-46: restore the reviewed seating background from its retained, hash-verified source."""
import hashlib
import json
import os
from pathlib import Path

from texture_import import apply_policy

ROOT = Path(__file__).resolve().parents[2]


def main():
    spec = json.loads((ROOT / "assets_src/pipeline/guest_book_seating.json").read_text())
    source = ROOT / spec["source"]
    data = source.read_bytes()
    if hashlib.sha256(data).hexdigest() != spec["sha256"]:
        raise ValueError(f"{source}: source hash differs; existing runtime image retained")
    output = ROOT / spec["output"]
    pending = output.with_suffix(output.suffix + ".pending")
    pending.write_bytes(data)
    os.replace(pending, output)
    apply_policy()
    print(f"{output.relative_to(ROOT)}: {len(data)} bytes, exact source SHA-256")


if __name__ == "__main__":
    main()
