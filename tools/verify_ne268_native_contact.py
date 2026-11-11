"""Independently check paired NE-268 native reports and unchanged damage values."""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> None:
    root = Path(sys.argv[1])
    before, after = (json.loads((root / name / "report.json").read_text(encoding="utf-8"))
                     for name in ("before", "current"))
    checks = 0

    def check(condition: bool, message: str) -> None:
        nonlocal checks
        assert condition, message
        checks += 1

    for name, report in (("before", before), ("current", after)):
        check(report["renderer"] == "forward_plus" and report["hdr_2d"], f"{name}: Forward+/HDR")
        check(report["adapter"] == "AMD Radeon RX 9070 XT", f"{name}: native adapter")
        check(report["chapter"] == "ch1_kasa" and report["zoom"] == 3.4, f"{name}: fixed scene")
        check((root / name / "exit-code.txt").read_text().strip() == "0", f"{name}: exit")
        log = (root / name / "run.log").read_text(encoding="utf-8")
        check("ERROR" not in log and "Leaked" not in log, f"{name}: clean engine log")
    check(before["legacy_coordinates"] and not after["legacy_coordinates"], "different coordinate policies")
    check(len(before["records"]) == len(after["records"]) == 2, "both facings")
    for old, new in zip(before["records"], after["records"]):
        check(old["side"] == new["side"], "matched facing")
        check(not old["contact_checks_pass"] and new["contact_checks_pass"], "negative control detects defect")
        check(old["hit_count"] == new["hit_count"] == 1 and old["hp"] == new["hp"] == 993, "one equal damage event")
        for key in ("amount", "knockback", "part", "weak", "stagger"):
            check(old["damage"][0][key] == new["damage"][0][key], f"unchanged {key}")
        old_event, new_event = old["events"][0], new["events"][0]
        check(old_event["feedback"] == old_event["feet"], "old feedback is at feet")
        check(new_event["inside_hurtbox"] and new_event["above_feet"] > 24, "current feedback is on body")
        check(new["numbers"][0] == new_event["feedback"] == new["damage"][0]["contact"], "number, hit flash and damage contact agree")
    print(json.dumps({"checks": checks, "failures": 0, "native_cases": 2, "expected_negative_cases": 2}))


if __name__ == "__main__":
    main()
