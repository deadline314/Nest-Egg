"""Which joint-audit failures are cracks a player can see: the samples that fail BOTH ways of drawing the joint.

    python tools/joint_audit_both.py <pair-only audit dir> <as-worn audit dir> [--top N]

rig_joint_audit draws a joint two ways:
  --pair-only  only the two adjoining parts. Finds a gap between them, but also fails wherever the joint is covered by a third part the
               audit does not draw (a sleeve over an elbow, a wrist guard, a collar).
  (default)    the two parts plus everything else that is visible on their bones. What the player sees with all gear on, but an armour
               plate standing off a limb encloses a pocket of background that is the drawing's own shape, not a crack.
A sample that fails only one way is one of those two false alarms. A sample that fails both ways is a gap between the two parts that
nothing covers. The threshold of check_joint_frames.py is not changed; both directories must hold its report.json for the same characters.
What gear hides is still open when the gear is shot off: look at rig_preview --damage --bare for that.
"""
import collections
import json
import sys
from pathlib import Path


def real(report: dict) -> dict:
    out = {}
    for f in report["failures"]:
        if f["center_alpha"] >= 128 and not f["enclosed_pixels"] and not f["loose_pieces"]:
            continue  # outline notch or the band cutting a bent limb
        kind = ("loose" if f["loose_pieces"] else "") + ("encl" if f["enclosed_pixels"] else "") + ("center" if f["center_alpha"] < 128 else "")
        out[(f["char"], f["facing"], f["joint"], f["pose"], f["zoom"], f["frame"])] = kind
    return out


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    top = int(next((a.split("=")[1] for a in sys.argv[1:] if a.startswith("--top=")), 12))
    pair = json.loads((Path(args[0]) / "report.json").read_text(encoding="utf8"))
    worn = json.loads((Path(args[1]) / "report.json").read_text(encoding="utf8"))
    a, b = real(pair), real(worn)
    both = {k: b[k] for k in a.keys() & b.keys()}
    per, kinds = collections.Counter(k[0] for k in both), collections.Counter((k[0], k[2], v) for k, v in both.items())
    print(f"samples {worn['samples']}: pair-only {len(a)}, as-worn {len(b)}, both {len(both)}")
    print(" ", dict(per))
    for key, count in kinds.most_common(top):
        print(" ", key, count)


if __name__ == "__main__":
    main()
