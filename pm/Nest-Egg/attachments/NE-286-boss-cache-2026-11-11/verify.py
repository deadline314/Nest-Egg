"""Verify the shipped raw receipts, source hashes and native RGBH screenshot.

Run: python verify.py [artifact-directory]
Requires numpy and Pillow for independent HDR-to-PNG verification.
"""
from pathlib import Path
import hashlib
import io
import json
import re
import sys
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_json(archive, member):
    with zipfile.ZipFile(archive) as stream:
        return json.loads(stream.read(member))


def read_member(archive, member):
    with zipfile.ZipFile(archive) as stream:
        return stream.read(member)


def verify_archive(root, row):
    path = root / row['file']
    require(path.parent == root and path.suffix == '.zip', 'unsafe archive path')
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    require(path.stat().st_size == row['bytes'] and digest == row['sha256'], f'{path.name}: archive changed')
    with zipfile.ZipFile(path) as stream:
        manifest = json.loads(stream.read('manifest.json'))
        require(len(manifest) == row['members'], f'{path.name}: member count')
        names = stream.namelist()
        require(len(names) == len(manifest) + 1 and set(names) == set(manifest) | {'manifest.json'}, f'{path.name}: unlisted/duplicate member')
        for member, expected in manifest.items():
            require(not member.startswith('/') and '..' not in Path(member).parts, f'{path.name}: unsafe member')
            with stream.open(member) as source:
                digest = hashlib.file_digest(source, 'sha256').hexdigest()
            require(stream.getinfo(member).file_size == expected['bytes'] and digest == expected['sha256'],
                    f'{path.name}: changed member {member}')


def edition_report(data):
    lines = data.decode('utf-8', errors='replace').splitlines()
    matches = [json.loads(line.split('EDITION_INFO ', 1)[1]) for line in lines if line.startswith('EDITION_INFO ')]
    require(len(matches) == 1 and len(matches[0]) == 14, 'missing or ambiguous edition report')
    return matches[0]


def check_native(metadata, receipt):
    require(receipt['exit'] == 0 and not receipt['error_lines'] and receipt['sources_unchanged'], 'native process not clean')
    require(metadata['raw_format'] == 14 and metadata['renderer'] == 'forward_plus' and metadata['hdr_2d'], 'wrong capture format')
    require(metadata['fixture'] and metadata['not_human_boss_fight'], 'fixture scope lost')
    require(metadata['boss_visible'] and metadata['both_behavior_scripts_held'] == 2, 'missing boss/script coverage')


def verify(root):
    import numpy as np
    from PIL import Image

    rows = json.loads((root / 'archives.json').read_bytes())
    require(len({row['file'] for row in rows}) == len(rows), 'duplicate archive entry')
    for row in rows:
        verify_archive(root, row)
    diagnostic = root / 'diagnostics-and-native-leaf-cases-raw.zip'
    cases = read_json(diagnostic, 'leaf-cases/summary.json')
    require({case['case'] for case in cases} == {
        'scripts-yong-first', 'scripts-janus-first', 'data-yong-first',
        'data-janus-first', 'cache-reuse', 'cache-disabled-negative'}, 'incomplete leaf cases')
    for case in cases:
        expected_exit = 1 if case['case'] == 'cache-disabled-negative' else 0
        require(case['exit'] == case['expected_exit'] == expected_exit and not case['errors'], f"leaf case failed: {case['case']}")
        for source in ['game/main.gd', 'game/enemies/boss/janus_config.gd']:
            data = read_member(diagnostic, f"leaf-cases/{case['case']}/{Path(source).name}")
            require(hashlib.sha256(data).hexdigest() == case['source_sha256'][source], f"leaf source mismatch: {case['case']}")
        boss = read_member(diagnostic, 'candidate/janus_boss.gd')
        require(hashlib.sha256(boss).hexdigest() == case['source_sha256']['game/enemies/janus_boss.gd'], 'boss source mismatch')
    require(next(c for c in cases if c['case'] == 'cache-disabled-negative')['exit'] == 1, 'cache negative did not reject')
    require(edition_report(read_member(diagnostic, 'verbose.log')) ==
            edition_report(read_member(diagnostic, 'leaf-full-scope.log')), 'edition report changed')
    full = read_json(diagnostic, 'leaf-controls.json')['leaf-full-scope']
    require(full['exit'] == 0 and not full['errors'], 'full edition cleanup failed')
    red = read_json(root / 'combined-55-red-receipts-raw.zip', 'exit.json')
    require(red['exit'] == 1 and red['sources_unchanged'] and not red['changed_sources'], 'original red run lost')
    overlay = {}
    for name in ['combined-55-red-inputs-part01-raw.zip', 'combined-55-red-inputs-part02-raw.zip']:
        for member, item in read_json(root / name, 'manifest.json').items():
            require(member.startswith('source/') and member[7:] not in overlay, 'duplicate original source')
            overlay[member[7:]] = item['sha256']
    require(overlay == red['source_after'], 'original 322-source archive mismatch')
    for prefix, count in [('combined-64-v3', 328), ('combined-77-v4', 360)]:
        for member, item in read_json(root / f'{prefix}-red-source-delta-raw.zip', 'manifest.json').items():
            require(member.startswith('source/'), 'unexpected source delta member')
            overlay[member[7:]] = item['sha256']
        result = read_json(root / f'{prefix}-red-receipts-raw.zip', 'exit.json')
        require(result['exit'] == 1 and result['sources_unchanged'] and len(overlay) == count and overlay == result['source_after'], f'{prefix}: original source overlay mismatch')
    verified_archive = root / 'root-tickets-v5-verified-receipts-raw.zip'
    initial = read_json(verified_archive, 'initial52/exit.json')
    recheck = read_json(verified_archive, 'recheck/exit.json')
    acceptance = read_json(verified_archive, 'initial52/acceptance.json')
    frozen = read_json(verified_archive, 'initial52/test-source-before.json')
    require(initial['exit'] == 1 and initial['sources_unchanged'] and not initial['changed_sources'], 'original environment failure lost')
    require(recheck['exit'] == 0 and recheck['sources_unchanged'], 'full failed-suite recheck failed')
    require(initial['source_after'] == recheck['source_after'] == frozen, 'code changed during environment correction')
    members = read_json(root / 'root-tickets-v5-inputs-raw.zip', 'manifest.json')
    source_records = {name[len('source/'):]: item['sha256'] for name, item in members.items()}
    require(all(name.startswith('source/') for name in members) and source_records == frozen, 'proposed source archives do not match')
    cleanup = read_json(verified_archive, 'initial52/owned-empty-directory-cleanup.json')
    require(cleanup['code_sources_unchanged'] and len(cleanup['removed_empty_owned_directories']) == 2, 'unexplained environment change')
    require(all(row['empty'] and row['not_in_base_commit'] for row in cleanup['removed_empty_owned_directories']), 'deleted directory was not owned/empty')
    log = read_member(verified_archive, 'initial52/full.log').decode('utf-8', errors='replace')
    failure = 'guest_zheng has its own motion data (art/motion/guest_zheng.json)'
    require(log.count('NEW FAILURE: ') == 1 and f'NEW FAILURE: {failure}' in log, 'unexpected initial failure')
    require('checks: 64668, new failures: 1, known failures (tests/known_failures.txt): 0' in log, 'initial totals changed')
    completed = set()
    for index in range(4):
        shard = read_member(verified_archive, f'initial52/logs/shard_{index}.log').decode('utf-8', errors='replace')
        require(not re.search(r'SCRIPT ERROR|Script Error|Parse Error', shard), f'affected shard {index} has script errors')
        completed.update(re.findall(r'^SUITE_TIME (\S+) ', shard, re.M))
    rerun_log = read_member(verified_archive, 'recheck/full.log').decode('utf-8', errors='replace')
    rerun_shard = read_member(verified_archive, 'recheck/logs/shard_0.log').decode('utf-8', errors='replace')
    require('checks: 5835, new failures: 0, known failures (tests/known_failures.txt): 0' in rerun_log, 'recheck totals changed')
    require('SUITE_TIME RigActionsSuite ' in rerun_shard and not re.search(r'SCRIPT ERROR|Parse Error', rerun_shard), 'wrong rechecked suite')
    require(len(completed) == 52 and completed == set(acceptance['selected_groups']), 'incomplete affected coverage')
    require(acceptance['not_a_single_green_full_run'] and acceptance['all_selected_suites_verified'], 'verification scope misreported')
    snapshot = root / 'native-snapshot-and-producers-raw.zip'
    meta = read_json(snapshot, 'v2/janus-level.png.json')
    receipt = read_json(snapshot, 'v2/exit.json')
    check_native(meta, receipt)
    command = read_json(snapshot, 'v2/command.json')
    require(command['source_before'] == red['source_after'] == receipt['source_after'], 'native snapshot context changed')
    native_log = read_member(snapshot, 'v2/run.log').decode('utf-8', errors='replace')
    require('Forward+' in native_log and '9070 XT' in native_log, 'native renderer/device receipt missing')
    require(not re.search(r'SCRIPT ERROR|ERROR:|leaked at exit', native_log, re.I), 'native log is not clean')
    width, height = meta['image_size']
    raw = np.frombuffer(read_member(snapshot, 'v2/janus-level.png.bin'), dtype='<f2').reshape(height, width, 3).astype(np.float64)
    require(np.isfinite(raw).all(), 'nonfinite HDR input')
    linear = np.maximum(raw, 0)
    srgb = np.where(linear < 0.0031308, linear * 12.92, 1.055 * linear ** (1 / 2.4) - 0.055)
    expected = (np.clip(np.concatenate((srgb, np.ones((height, width, 1))), axis=2), 0, 1) * 255).astype(np.uint8)
    actual = np.asarray(Image.open(io.BytesIO(read_member(snapshot, 'v2/janus-level.png'))).convert('RGBA'))
    delta = np.abs(actual.astype(int) - expected.astype(int))
    require(delta.max() <= 1, 'PNG does not match original RGBH readback')
    return dict(archives=len(rows), leaf_cases=len(cases), edition_fields=14, affected_groups=len(completed),
                original_red_preserved=True, original52_exit=initial['exit'], failed_suite_recheck_exit=recheck['exit'],
                same_code_environment_only_correction=True, not_single_full_green=True,
                native_exit=receipt['exit'], max_png_channel_error=int(delta.max()), fixture_only=True)


if __name__ == '__main__':
    directory = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent
    try:
        print(json.dumps(verify(directory), indent=2))
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        raise SystemExit(f'[NE286 evidence] {error}')
