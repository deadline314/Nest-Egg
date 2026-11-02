#!/usr/bin/env python3
"""Real normal audio, deferred terminal playback and strict exit diagnostics."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import time

from runtime_probe import run_case, write_json

PROJECT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=os.environ.get('GODOT'))
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.godot is None or not args.godot.is_file():
        parser.error('provide an existing Godot engine')
    engine, output = args.godot.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    (output / '.gdignore').touch()
    (output / '.gitignore').write_text('*\n')
    names = ['game/main.gd', 'autoload/sfx.gd', 'autoload/music.gd', 'autoload/ambience.gd',
             'core/audio/audio_release.gd', 'core/audio/crossfade_player.gd',
             'data/audio/sound_bank.json', 'data/audio/music.json', 'data/audio/ambience.json',
             'audio/sfx/beep_02.ogg', 'tests/probes/audio_shutdown.gd',
             'tests/probes/audio_shutdown.tscn', 'tools/run_audio_shutdown.py', 'tools/runtime_probe.py']
    hashes = {}
    for name in names:
        target = output / 'source' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PROJECT / name, target)
        with target.open('rb') as stream:
            hashes[name] = hashlib.file_digest(stream, 'sha256').hexdigest()
    with engine.open('rb') as stream:
        engine_sha = hashlib.file_digest(stream, 'sha256').hexdigest()
    receipt = {'source_sha256': hashes, 'engine_sha256': engine_sha, 'cases': []}
    started = time.monotonic()

    def run(mode):
        slot = output / (mode + '-slot')
        slot.mkdir()
        return run_case(mode, engine, output, 120, project=PROJECT,
                        scene='res://tests/probes/audio_shutdown.tscn', slot=slot, verbose=True)

    modes = [f'{owner}_{fps}' for owner in ('main', 'settle') for fps in (0, 5, 20, 60)]
    with ThreadPoolExecutor(max_workers=3) as pool:
        for case in pool.map(run, modes):
            receipt['cases'].append(case)
            receipt['wall_seconds'] = round(time.monotonic() - started, 3)
            write_json(output / 'receipt.json', receipt)
            print(case['mode'], 'PASS' if case['passed'] else 'FAIL', case.get('result'), flush=True)
            if not case['passed']:
                print(json.dumps(case['diagnostics']), flush=True)
    return int(any(not case['passed'] for case in receipt['cases']))


if __name__ == '__main__':
    raise SystemExit(main())
