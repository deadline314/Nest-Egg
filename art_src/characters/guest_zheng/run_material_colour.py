"""One handed-off serial window for complete colour pages and the LF formal scene."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
ANIMATOR = "2236b4d7dfdb948542672a5cc3797c6bb7d51e0a1fd230336a9b932fb1a758cf"


def main():
    for phase, tag in (("colour", "npc-colour-material-v2"), ("scene", "scene-material-lf-v8")):
        command = [sys.executable, "-X", "utf8", str(Path(__file__).with_name("run_native.py")),
                   phase, "--tag", tag, "--expected-animator-sha", ANIMATOR]
        result = subprocess.run(command, cwd=ROOT)
        if result.returncode:
            raise RuntimeError("Invalid colour/scene batch; preserve and stop: " + tag)
    print("Colour and formal LF scene Godot processes exited; GPU/C released", flush=True)


if __name__ == "__main__":
    main()
