"""One handed-off native window: real one-pixel negative, full captures, deferred CPU analysis."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs"
ANIMATOR = "2236b4d7dfdb948542672a5cc3797c6bb7d51e0a1fd230336a9b932fb1a758cf"


def main():
    runner = Path(__file__).with_name("run_native.py")
    control = OUT / "material-negative-v1/hand-true-hole.png"
    negative = "material-true-hole-native-v2"
    command = [sys.executable, "-X", "utf8", str(runner), "performance", "--tag", negative,
               "--expected-animator-sha", ANIMATOR, "--frames=1", "--zooms=3.4", "--npc-pose=sit",
               "--alpha-only", "--joint-context", "--trace-joint=wrist_back",
               "--diagnostic-part-texture=hand_back:" + control.as_posix()]
    result = subprocess.run(command, cwd=ROOT)
    run = json.loads((OUT / (negative + "-run.json")).read_text(encoding="utf8"))
    hashes = json.loads((OUT / (negative + "-source-hashes.json")).read_text(encoding="utf8"))
    report = json.loads((OUT / negative / "scope-report.json").read_text(encoding="utf8"))
    if (result.returncode != 1 or run["exit_code"] or run["engine_errors"] or not hashes["unchanged"] or
            report["failed_samples"] != 2 or
            any(f["joint"] != "wrist_back" or f["raw"]["enclosed_pixels"] != 1 for f in report["failures"])):
        raise RuntimeError("True one-native-pixel negative was not rejected exactly; preserve and diagnose this run")
    for phase, tag in (("performance", "npc-performance-material-v2"),
                       ("transitions", "npc-transitions-material-v2")):
        command = [sys.executable, "-X", "utf8", str(runner), phase, "--tag", tag,
                   "--expected-animator-sha", ANIMATOR, "--alpha-only", "--joint-context",
                   "--trace-joint=wrist_back", "--capture-only"]
        result = subprocess.run(command, cwd=ROOT)
        if result.returncode:
            raise RuntimeError("Invalid native capture; preserve evidence and stop: " + tag)
    (OUT / "material-capture-window-v2.json").write_text(json.dumps({
        "classification": "full native captures only; acceptance pending deferred raw/context CPU checks",
        "one_pixel_negative_rejected": True,
        "captures": ["npc-performance-material-v2", "npc-transitions-material-v2"]}, indent=2) + "\n",
        encoding="utf8", newline="\n")
    print("All Godot processes exited; shared GPU window released; full acceptance still pending", flush=True)


if __name__ == "__main__":
    main()
