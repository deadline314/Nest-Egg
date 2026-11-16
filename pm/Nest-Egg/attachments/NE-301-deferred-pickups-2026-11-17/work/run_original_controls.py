from pathlib import Path
import hashlib
import json
import os
import subprocess

iso = Path('C:/NE/bg32-20261117')
out = Path('D:/NestEggVerification/evidence-20261117/ne301/corrected-original-controls')
out.mkdir(exist_ok=False)
paths = ['game/pickups/pickup.gd', 'game/enemies/enemy.gd', 'game/level/level.gd']
saved = {rel: (iso / rel).read_bytes() for rel in paths}
rows = []
try:
    for rel in paths:
        data = subprocess.check_output(['git', 'show', 'HEAD:' + rel], cwd=iso)
        (iso / rel).write_bytes(data)
        snap = out / 'source' / rel
        snap.parent.mkdir(parents=True, exist_ok=True)
        snap.write_bytes(data)
    for kind in ['credit', 'health', 'box']:
        for retire in [False, True]:
            for quit_early in [False, True]:
                name = kind + ('-retire' if retire else '-alive') + ('-quit' if quit_early else '-settle')
                env = os.environ.copy()
                env['APPDATA'] = env['LOCALAPPDATA'] = env['XDG_DATA_HOME'] = str(out / name / 'profile')
                args = ['C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe', '--headless',
                        'res://work/ne301-lifetime-probe/probe.tscn', '--', '--case=' + kind]
                if not retire: args.append('--keep-owner')
                if quit_early: args.append('--quit-before-deferred')
                with (out / (name + '.log')).open('wb') as log:
                    result = subprocess.run(args, cwd=iso, env=env, stdout=log, stderr=subprocess.STDOUT)
                row = {'case': kind, 'retire': retire, 'quit_early': quit_early,
                       'natural_exit': result.returncode, 'log': name + '.log'}
                rows.append(row)
                print(row, flush=True)
finally:
    for rel, data in saved.items():
        (iso / rel).write_bytes(data)
        assert hashlib.sha256((iso / rel).read_bytes()).digest() == hashlib.sha256(data).digest()
    (out / 'candidate-restored-shas.json').write_text(json.dumps({rel: hashlib.sha256(data).hexdigest() for rel, data in saved.items()}, indent=2) + '\n', encoding='utf-8')
(out / 'results.json').write_text(json.dumps(rows, indent=2) + '\n', encoding='utf-8')
