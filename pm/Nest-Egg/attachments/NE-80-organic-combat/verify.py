"""Verify archived combat evidence, or a fresh public replay against its inputs."""
import argparse
import hashlib
import json
import struct
import subprocess
from pathlib import Path

from combat_checks import validate, self_test

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def verify_sources(report, index, historical, archived_fixture=True):
    errors = []
    paths = dict(index['source_paths'])
    paths['fixture_script'] = str(HERE / ('archive-fixture.gd' if archived_fixture else 'replay.gd'))
    paths['fixture_scene'] = str(HERE / ('archive-fixture.tscn' if archived_fixture else 'replay.tscn'))
    entries = [(paths[key], value) for key, value in report['source_sha256'].items()]
    entries += list(report['character_texture_sha256'].items())
    for path, expected in entries:
        try:
            if path.startswith('res://'):
                relative = path.removeprefix('res://')
                data = subprocess.check_output(['git', 'show', f"{index['head']}:{relative}"], cwd=ROOT) if historical else (ROOT/relative).read_bytes()
            else:
                data = Path(path).read_bytes()
            if sha(data) != expected:
                errors.append(f'actual source bytes differ: {path}')
        except (OSError, subprocess.CalledProcessError) as exc:
            errors.append(f'missing source: {path}: {exc}')
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--replay-report', type=Path)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    index = json.loads((HERE/'evidence-index.json').read_text(encoding='utf-8'))
    errors = []
    if args.replay_report:
        report = json.loads(args.replay_report.read_text(encoding='utf-8'))
        head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
        errors += validate(report, head)
        errors += verify_sources(report, index, False, False)
        self_test(report, head)
    else:
        for relative, expected in index['files'].items():
            try:
                if sha((ROOT/relative).read_bytes()) != expected:
                    errors.append(f'archive file bytes changed: {relative}')
            except OSError:
                errors.append(f'archive file missing: {relative}')
        for name, native, checks in [('native-report.json', True, 13), ('archive-cpu-report.json', False, 10), ('public-cpu-report.json', False, 10)]:
            report = json.loads((HERE/name).read_text(encoding='utf-8'))
            errors += validate(report, index['head'], native)
            if report['checks'] != checks:
                errors.append(f'{name}: expected {checks} checks')
            errors += verify_sources(report, index, True, name != 'public-cpu-report.json')
            if not native:
                self_test(report, index['head'])
            else:
                captures = [e['data'] for e in report['events'] if e['event']=='native_capture']
                expected = {'NE80_heavy_spin_up_armor_closed', 'NE80_heavy_vent_after_natural_fire', 'NE80_heavy_vent_player_hit'}
                if {c['name'] for c in captures} != expected or len(captures) != 3:
                    errors.append('expected three native captures')
                for capture in captures:
                    image = ROOT/'pm/Nest-Egg/images/NE-80-organic-combat'/(capture['name']+'.png')
                    data = image.read_bytes()
                    if data[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II',data[16:24]) != (1280,720):
                        errors.append(f'invalid native PNG: {image.name}')
                    if capture['size'] != [1280,720] or not capture['simulation_frozen'] or capture['simulation_before'] != capture['simulation_after']:
                        errors.append(f'readback advanced simulation: {image.name}')
        for log in HERE.glob('*.log'):
            content = log.read_bytes()
            if b'SCRIPT ERROR' in content or b'ERROR:' in content:
                errors.append(f'Godot error in {log.name}')
        if args.self_test:
            native = json.loads((HERE/'native-report.json').read_text(encoding='utf-8'))
            native['source_sha256']['enemy_data'] = '0'*64
            assert verify_sources(native, index, True), 'actual source byte negative escaped'
            path = next(ROOT/relative for relative in index['files'] if relative.endswith('.png'))
            data = bytearray(path.read_bytes())
            data[-1] ^= 1
            assert sha(data) != index['files'][path.relative_to(ROOT).as_posix()], 'image corruption escaped'
            print('NEGATIVE actual-source-byte corruption and one-byte PNG corruption rejected')
    if errors:
        raise SystemExit('\n'.join(errors))
    print('PASS NE80 bounded combat evidence; CPU 10/0, native 13/0; all recorded source bytes verified')


if __name__ == '__main__':
    main()
