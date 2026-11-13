"""Native same-source controls; request the team's GPU/C-project handoff first."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs"
SHA = "2236b4d7dfdb948542672a5cc3797c6bb7d51e0a1fd230336a9b932fb1a758cf"


def main():
    shoulder = ["--frames=23", "--zooms=1", "--joints=shoulder_front", "--npc-pose=wave",
                "--trace-joint=shoulder_front", "--trace-frame=22"]
    wrist = ["--frames=137", "--zooms=2.2", "--joints=wrist_front", "--npc-pose=sit_listen",
             "--trace-joint=wrist_front", "--trace-frame=136"]
    knee = ["--frames=43", "--zooms=2.2", "--joints=knee_front"]
    cases = [
        ("performance", "shoulder-base", shoulder),
        ("performance", "shoulder-head", shoulder + ["--diagnostic-include-part=head"]),
        ("performance", "shoulder-forearm", shoulder + ["--diagnostic-include-part=arm_front_lower"]),
        ("performance", "shoulder-whole", shoulder + ["--diagnostic-whole-rig"]),
        ("performance", "wrist-base", wrist),
        ("performance", "wrist-upperarm", wrist + ["--diagnostic-include-part=arm_front_upper"]),
        ("transitions", "knee-base", knee),
        ("transitions", "knee-pelvis", knee + ["--diagnostic-include-part=pelvis"]),
    ]
    results = []
    for phase, label, args in cases:
        tag = "context-" + label + "-v1"
        command = [sys.executable, "-X", "utf8", str(Path(__file__).with_name("run_native.py")),
                   phase, "--tag", tag, "--expected-animator-sha", SHA, *args]
        process = subprocess.run(command, cwd=ROOT)
        run = json.loads((OUT / (tag + "-run.json")).read_text(encoding="utf8"))
        hashes = json.loads((OUT / (tag + "-source-hashes.json")).read_text(encoding="utf8"))
        if run["exit_code"] or run["engine_errors"] or not hashes["unchanged"]:
            raise RuntimeError("Native control was invalid; stop the batch: " + label)
        report = json.loads((OUT / tag / "report.json").read_text(encoding="utf8"))
        results.append(dict(label=label, runner_exit=process.returncode, samples=report["samples"],
                            failures=report["failed_samples"], summary=report["summary"]))
        print(label, report["failed_samples"], "/", report["samples"], flush=True)
    (OUT / "context-controls-v1.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    main()
