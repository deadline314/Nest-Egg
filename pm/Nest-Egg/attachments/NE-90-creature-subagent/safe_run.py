"""Serial native review runner. Checks free RAM after acquiring the shared GPU lock."""
import argparse
import json
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(root / "tools/comfyui"))
import comfy_guard

parser = argparse.ArgumentParser()
parser.add_argument("scene", choices=["capture", "watchdog", "metadata", "gait"])
parser.add_argument("--godot", required=True)
parser.add_argument("--ids", default="")
args = parser.parse_args()
out = Path(__file__).parent
runner = root / ".godot/creature-subagent"
runner.mkdir(parents=True, exist_ok=True)
source = out / "runner" / f"{args.scene}.gd"
(runner / source.name).write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
node_type = "Node2D" if args.scene in ["capture", "watchdog"] else "Node"
(runner / f"{args.scene}.tscn").write_text(
    f'[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" '
    f'path="res://.godot/creature-subagent/{source.name}" id="1"]\n'
    f'[node name="Audit" type="{node_type}"]\nscript = ExtResource("1")\n',
    encoding="utf-8",
)
with comfy_guard.server_lock():
    available = comfy_guard.free_ram_gb()
    if available < 4.0:
        print(f"STOP: available RAM {available:.3f} GiB is below 4 GiB")
        raise SystemExit(2)
    command = [args.godot, "--audio-driver", "Dummy", "--path", str(root)]
    if args.scene in ["metadata", "gait"]:
        command += ["--headless"]
    else:
        command += ["--rendering-driver", "vulkan", "--rendering-method", "forward_plus"]
    command += [f"res://.godot/creature-subagent/{args.scene}.tscn"]
    if args.ids:
        command += ["--", "--ids=" + args.ids]
    log_name = "native-capture" if args.scene == "capture" else args.scene
    if args.ids:
        log_name += "-" + args.ids.replace(",", "-")
    with (out / f"{log_name}.log").open("w", encoding="utf-8") as log:
        result = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT)
    (out / f"command-{log_name}.json").write_text(json.dumps({
        "command": command, "available_ram_gib_before_start": available,
        "exit_code": result.returncode, "shared_lock": str(comfy_guard.LOCK_PATH),
    }, indent=2), encoding="utf-8")
    print(args.scene, "exit", result.returncode, "available RAM", round(available, 3))
    raise SystemExit(result.returncode)
