"""Short native render or affected tests under the shared GPU lock and RAM guard."""
import argparse
import json
import hashlib
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[4]
out = Path(__file__).parent
sys.path.insert(0, str(root / 'tools/comfyui'))
import comfy_guard

parser = argparse.ArgumentParser()
parser.add_argument('mode', choices=['render', 'import', 'probe', 'changed', 'related', 'unit', 'mutant'])
parser.add_argument('--base', default=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip())
args = parser.parse_args()
godot = 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe'
if args.mode in ['render', 'unit', 'mutant']:
    stage = root / '.godot/worm-repair'
    stage.mkdir(parents=True, exist_ok=True)
    script = 'render' if args.mode == 'render' else 'unit'
    node = 'Node2D' if args.mode == 'render' else 'Node'
    (stage / f'{script}.gd').write_text((out / f'{script}.gd').read_text(encoding='utf-8'), encoding='utf-8')
    (stage / f'{script}.tscn').write_text(f'[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://.godot/worm-repair/{script}.gd" id="1"]\n[node name="Review" type="{node}"]\nscript = ExtResource("1")\n', encoding='utf-8')
    (root / 'pm/Nest-Egg/images/NE-90-worm-repair').mkdir(parents=True, exist_ok=True)
    command = [godot, '--audio-driver', 'Dummy', '--path', str(root)]
    command += ['--rendering-driver', 'vulkan', '--rendering-method', 'forward_plus'] if args.mode == 'render' else ['--headless']
    command += [f'res://.godot/worm-repair/{script}.tscn']
elif args.mode == 'import':
    command = [godot, '--headless', '--editor', '--path', str(root), '--quit']
elif args.mode == 'probe':
    command = [godot, '--headless', '--path', str(root), 'res://tests/smoke_test.tscn', '--', '--only=ChainCreatureSuite']
elif args.mode == 'related':
    command = ['C:/Program Files/Git/bin/bash.exe', 'tools/run_tests_parallel.sh', '--only=ChainCreatureSuite,FloodPitSuite,EnvironmentSuite']
else:
    command = ['C:/Program Files/Git/bin/bash.exe', 'tools/run_tests_changed.sh', args.base]
env = os.environ.copy()
env.update(GODOT=godot, SHARDS='2', PYTHONUTF8='1', LOG_DIR=str(out / ('related-shards' if args.mode == 'related' else 'test-shards')))
with comfy_guard.server_lock():
    available = comfy_guard.free_ram_gb()
    if available < 4:
        raise SystemExit(f'STOP: available RAM {available:.3f} GiB < 4 GiB')
    source = root / 'game/creature/worm_creature.gd'
    original = source.read_bytes()
    snapshot_paths = ['game/creature/worm_creature.gd', 'game/creature/worm_belly.gdshader', 'art/creatures/cloud_serpent.json', 'tests/suite/test_chain_creature.gd']
    snapshot = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in snapshot_paths}
    try:
        if args.mode == 'mutant':
            text = original.decode('utf-8')
            anchor = '\t_mesh.uv = _uvs'
            assert text.count(anchor) == 1
            text = text.replace(anchor, '\t# Negative control: the former whole-body head flip.\n\tfor row in _joints:\n\t\t_uvs[row * 2].y = _tex_size.y if mirrored else 0.0\n\t\t_uvs[row * 2 + 1].y = 0.0 if mirrored else _tex_size.y\n' + anchor)
            source.write_text(text, encoding='utf-8')
        with (out / f'{args.mode}.log').open('w', encoding='utf-8') as log:
            result = subprocess.run(command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT)
    finally:
        if args.mode == 'mutant':
            source.write_bytes(original)
    after = {path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in snapshot_paths}
    (out / f'command-{args.mode}.json').write_text(json.dumps(dict(command=command, base=args.base, source_head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(), source_sha256=snapshot, source_unchanged_during_run=after == snapshot, available_ram_gib=available, exit_code=result.returncode, processes=2 if args.mode in ['changed', 'related'] else 1), indent=2), encoding='utf-8')
    print(args.mode, 'exit', result.returncode, 'RAM', round(available, 3))
    raise SystemExit(result.returncode)
