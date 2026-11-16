"""Native matrix runner with one shared GPU lock, private settings/profile and immutable outputs."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
out = Path(sys.argv[1])
assert out.is_absolute() and not out.exists()
(out / "profile").mkdir(parents=True)
quality = sys.argv[2]
weapons = sys.argv[3] if len(sys.argv) > 3 else "rifle"
phase = sys.argv[4] if len(sys.argv) > 4 else "visual"
paths = list(json.loads((HERE / "freeze-wall-v4.json").read_text(encoding="utf8")))
paths += ["tools/weapon_light_probe.gd", "tools/weapon_light_probe.tscn", "tools/weapon_head_probe.gd", "tools/contrast_probe.gd", "tools/viewport_capture.gd",
          "tools/scenarios/scenario_base.gd", "data/levels/ch1_warehouse.tres", "data/lighting/blackout.tres",
          "game/player/loadout.gd", "autoload/projectile_pool.gd", "game/projectiles/projectile.gd", "core/weapon_system.gd"]
paths += ["data/weapons/" + name + ".tres" for name in ["pistol", "rifle", "smg", "spread", "launcher", "laser", "railgun"]]
paths += [path.relative_to(ROOT).as_posix() for folder in ["core", "autoload", "game", "ui"] for path in (ROOT / folder).rglob("*.gd")]
paths = sorted(set(paths))
def hashes():
    return {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in paths}
before = hashes()
head_before = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
env = os.environ.copy()
overrides = {"APPDATA": str(out / "profile"), "LOCALAPPDATA": str(out / "profile")}
env.update(overrides)
command = [sys.executable, "-B", str(ROOT / "tools/comfyui/gpu_lock.py"), "--",
           "C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe", "--path", str(ROOT),
           "--rendering-method", "forward_plus", "--rendering-driver", "vulkan", "res://tools/weapon_light_probe.tscn", "--",
           "--out=" + str(out), "--weapons=" + weapons, "--phase=" + phase, "--tag=matrix"]
if quality != "current":
    command += ["--quality=" + quality]
command += sys.argv[5:]
started = datetime.datetime.now(datetime.timezone.utc).isoformat()
with (out / "console.log").open("wb") as log:
    process = subprocess.run(command, env=env, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
after = hashes()
diagnostics = [line for line in (out / "console.log").read_text(encoding="utf8").splitlines()
               if any(marker in line for marker in ["ERROR:", "SCRIPT ERROR", "orphan", "leaked", "Leaked"])]
receipt = {"command": command, "cwd": str(ROOT), "environment_overrides": overrides,
           "started_utc": started, "finished_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
           "exit_code": process.returncode, "source_before_sha256": before, "source_after_sha256": after,
           "source_unchanged": before == after, "diagnostics": diagnostics, "git_head_before": head_before,
           "git_head_after": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()}
(out / "process-receipt.json").write_text(json.dumps(receipt, indent=2), encoding="utf8")
print(json.dumps({"exit_code": process.returncode, "source_unchanged": before == after, "diagnostics": diagnostics}))
sys.exit(1 if process.returncode or before != after or diagnostics else 0)
