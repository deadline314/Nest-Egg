"""Complete deferred raw/context checks after releasing the native GPU window."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("runs", nargs="+")
    args = parser.parse_args()
    all_passed = True
    for name in args.runs:
        if Path(name).name != name or "/" in name or "\\" in name:
            raise ValueError("run must be one evidence folder")
        destination = OUT / (name + "-acceptance-complete.json")
        if destination.exists():
            raise ValueError("Preserve prior analysis; do not overwrite it")
        pending = json.loads((OUT / (name + "-acceptance-pending.json")).read_text(encoding="utf8"))
        source = json.loads((OUT / (name + "-source-hashes.json")).read_text(encoding="utf8"))
        capture = json.loads((OUT / (name + "-run.json")).read_text(encoding="utf8"))
        assert source["unchanged"] and capture["exit_code"] == 0 and not capture["engine_errors"]
        for member in ("tools/check_joint_frames.py", "tools/check_npc_joint_scope.py", "tools/npc_joint_scope.py"):
            assert hashlib.sha256((ROOT / member).read_bytes()).hexdigest() == source["before"][member], member
        folder = ROOT / pending["folder"]
        receipt = dict(classification="complete native joint capture analysis, working-tree source bundle", checks=[])
        for label, arguments in (("raw", ["tools/check_joint_frames.py", str(folder)]),
                                  ("scope", ["tools/check_npc_joint_scope.py", str(folder),
                                             "--expected-chars=guest_zheng", "--expected-zooms=1,2.2,3.4,3.7"])):
            command = [sys.executable, "-X", "utf8", *arguments]
            started = time.monotonic()
            result = subprocess.run(command, cwd=ROOT, capture_output=True)
            log = OUT / (name + "-" + label + "-deferred.log")
            log.write_bytes(result.stdout + result.stderr)
            receipt["checks"].append(dict(checker=label, exit_code=result.returncode,
                                         seconds=time.monotonic() - started, command=command,
                                         log_sha256=hashlib.sha256(log.read_bytes()).hexdigest()))
            print(name, label, result.returncode, flush=True)
        report = json.loads((folder / "scope-report.json").read_text(encoding="utf8"))
        raw = json.loads((folder / "report.json").read_text(encoding="utf8"))
        receipt.update(samples=report["samples"], raw_failures=raw["failed_samples"],
                       scope_failures=report["failed_samples"], exterior_scope_samples=report["exterior_scope_samples"],
                       passed=receipt["checks"][-1]["exit_code"] == 0 and report["failed_samples"] == 0)
        destination.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8", newline="\n")
        all_passed &= receipt["passed"]
    return int(not all_passed)


if __name__ == "__main__":
    raise SystemExit(main())
