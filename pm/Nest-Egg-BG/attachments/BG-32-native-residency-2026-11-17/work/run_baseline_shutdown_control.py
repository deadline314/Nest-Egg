from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess

repo = Path('C:/Users/stanl/Github/Nest-Egg')
work = repo / 'work/bg32-audit-20261117'
iso = Path('C:/NE/bg32-20261117')
out = Path('D:/NestEggVerification/evidence-20261117/bg32/baseline-shutdown-control-02')
out.mkdir(parents=True, exist_ok=False)
before = json.loads((work / 'official-source-before.json').read_text(encoding='utf-8'))
for rel, row in before['source_files'].items():
    assert hashlib.sha256((iso / rel).read_bytes()).hexdigest() == row['sha256'], rel
assert subprocess.check_output(['git', 'status', '--short', '--untracked-files=all'], cwd=iso, text=True) == before['status']
tracked = ['core/asset_prefetch.gd', 'tests/suite/test_ch1_map.gd', 'tools/texture_route_probe.gd']
helper = 'tests/helpers/prefetch_scope_checks.gd'
saved = {rel: (iso / rel).read_bytes() for rel in before['source_files']}
try:
    subprocess.run(['git', 'restore', '--source=HEAD', '--', *tracked], cwd=iso, check=True)
    shutil.copyfile(iso / helper, out / 'candidate-helper.gd.txt')
    (iso / helper).unlink()  # Exact owned helper has already been saved and SHA checked.
    status = subprocess.check_output(['git', 'status', '--short', '--untracked-files=all'], cwd=iso, text=True)
    assert status == '', status
    source = {'base': before['base'], 'status': status,
              'source_files': {rel: hashlib.sha256((iso / rel).read_bytes()).hexdigest() for rel in tracked},
              'suites': 'RunSaveSuite,InputFeelSuite,EncounterSuite,Chapter2Suite,Chapter1MapSuite'}
    (out / 'source-before.json').write_text(json.dumps(source, indent=2) + '\n', encoding='utf-8')
    env = os.environ.copy()
    env.update({'APPDATA': str(out / 'profile'), 'LOCALAPPDATA': str(out / 'profile'), 'XDG_DATA_HOME': str(out / 'profile')})
    with (out / 'console.log').open('wb') as log:
        result = subprocess.run(['C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe', '--headless',
                                 'res://tests/smoke_test.tscn', '--', '--only=' + source['suites']],
                                cwd=iso, env=env, stdout=log, stderr=subprocess.STDOUT)
    (out / 'exit.txt').write_text(str(result.returncode) + '\n', encoding='utf-8')
    after = dict(source)
    after['status'] = subprocess.check_output(['git', 'status', '--short', '--untracked-files=all'], cwd=iso, text=True)
    after['source_files'] = {rel: hashlib.sha256((iso / rel).read_bytes()).hexdigest() for rel in tracked}
    (out / 'source-after.json').write_text(json.dumps(after, indent=2) + '\n', encoding='utf-8')
    assert source == after
finally:
    for rel, data in saved.items():
        (iso / rel).write_bytes(data)
    for rel, row in before['source_files'].items():
        assert hashlib.sha256((iso / rel).read_bytes()).hexdigest() == row['sha256'], rel
    assert subprocess.check_output(['git', 'status', '--short', '--untracked-files=all'], cwd=iso, text=True) == before['status']
    (out / 'candidate-restored.json').write_text(json.dumps(before, indent=2) + '\n', encoding='utf-8')
print(out)
