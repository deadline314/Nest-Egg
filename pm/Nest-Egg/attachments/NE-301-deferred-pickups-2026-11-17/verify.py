"""Read-only portable verification. Requires the final official result packet."""
from pathlib import Path
import hashlib
import json
import re
import struct

ROOT = Path(__file__).resolve().parent
checks = 0

def check(value, label):
    global checks
    checks += 1
    if not value:
        raise RuntimeError(label)

def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))

def log(path):
    return (ROOT / path).read_text(encoding='utf-8', errors='replace')

def sha(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()

def strict_clean(text):
    return not re.search(r'SCRIPT ERROR|^ERROR:|Parse Error|Compile Error|leaked at exit|ObjectDB instances|resources still in use', text, re.M)

def main():
    needed = ['work/official-source-after.json', 'raw/official-aae/exit.txt', 'manifest.json']
    missing = [name for name in needed if not (ROOT / name).is_file()]
    if missing:
        raise RuntimeError('Packet is not final-ready; missing: ' + ', '.join(missing))
    for row in read('manifest.json'):
        path = ROOT / row['path']
        check(path.stat().st_size == row['bytes'] and sha(path) == row['sha256'], 'Manifest: ' + row['path'])
    for row in read('original-outputs.json'):
        path = ROOT / 'raw' / row['path']
        check(path.stat().st_size == row['bytes'] and sha(path) == row['sha256'], 'Original output: ' + row['path'])
    before = read('work/official-source-before.json')
    check(before == read('work/official-source-after.json'), 'Official before/after source guard')
    check(before['base'] == 'aae101cfc85b192af9558d5b38d250aea4f1e726' and len(before['source_files']) == 5, 'Pure NE301 source epoch')
    for path, row in before['source_files'].items():
        source = ROOT / 'frozen-candidate' / path
        check(source.stat().st_size == row['bytes'] and sha(source) == row['sha256'], 'Frozen source: ' + path)
    for row in read('work/source-newlines.json'):
        data = (ROOT / 'frozen-candidate' / row['path']).read_bytes()
        check(data.count(b'\r\n') == row['CRLF_count'] == 0 and row['raw_sha256'] == row['git_canonical_lf_sha256'] == hashlib.sha256(data).hexdigest(), 'Exact Git LF source mapping: ' + row['path'])
    # Original natural exit codes are preserved: immediate quit returns zero even
    # when its complete EOF contains real leaks. The strict gate must reject it.
    original = read('raw/corrected-original-controls/results.json')
    candidate = read('raw/static-prototype-controls/results.json')
    check(len(original) == len(candidate) == 12, 'All source/retirement/quit combinations retained')
    for row in original:
        text = log('raw/corrected-original-controls/' + row['log'])
        check(not re.search(r'SCRIPT ERROR|\[EnemyVfx\]|沒有啟動狀態機', text), 'Corrected original fixture is valid')
        if row['retire']:
            check(not strict_clean(text), 'Original retired-owner case must fail strict EOF')
            check(row['natural_exit'] == (0 if row['quit_early'] else 1), 'Original natural exit was rewritten')
            if row['quit_early']:
                check('frame=0' in text and 'NE301_TRUE_TREE_QUIT' in text, 'True immediate SceneTree.quit control')
            else:
                expected = 2 if row['case'] == 'box' else 1
                check(f'before=0 after={expected} added={expected}' in text, 'Original actual source orphan delta')
        else:
            check(row['natural_exit'] == 0 and strict_clean(text), 'Original live owner normal contract')
    for row in candidate:
        text = log('raw/static-prototype-controls/' + row['log'])
        check(row['natural_exit'] == 0 and strict_clean(text), 'Candidate actual source cleanup/quit: ' + row['log'])
        if row['quit_early']:
            check('frame=0' in text and 'NE301_TRUE_TREE_QUIT' in text, 'Candidate actual immediate quit')
        else:
            check('before=0 after=0 added=0' in text, 'Candidate actual orphan count')
    restored = read('raw/corrected-original-controls/candidate-restored-shas.json')
    check(all(restored[p] == before['source_files'][p]['sha256'] for p in restored), 'Original-control finally restored candidate')
    negative = log('raw/omit-cleanup-control/console.log')
    check('checks: 87, failures: 14' in negative and (ROOT / 'raw/omit-cleanup-control/exit.txt').read_text().strip() == '1', 'Fixed omitted-cleanup negative rejects naturally')
    check((ROOT / 'raw/omit-cleanup-control/restored-sha256.txt').read_text().strip() == before['source_files']['game/pickups/pickup.gd']['sha256'], 'Negative control restored exact pickup')
    unit = log('raw/cpu-fx-pickups-third.log')
    check('checks: 87, failures: 0' in unit, 'Permanent actual source/ownership/physics/reward checks')
    check(not re.search(r'SCRIPT ERROR|Parse Error|ObjectDB instances|resources still in use|leaked at exit', unit), 'Local suite EOF is clean')
    check(all('test_no_such_attack' in line for line in unit.splitlines() if line.startswith('ERROR:')), 'Only pre-existing intentional MeleeSet error cases remain')
    native = read('raw/native-fourth/summary.json')
    check(native['checks'] == 9 and not native['failures'], 'Native nine checks')
    check(native['credits_before'] == 0 and native['credits_after'] == 17 and native['health'] == 7 and native['med_count'] == 1, 'Actual physical collection effects')
    check(native['renderer'] == 'forward_plus' and native['hdr_2d'] and native['adapter'] == 'AMD Radeon RX 9070 XT', 'Native renderer and actual GPU')
    check('native-isolated-profile' in native['appdata'] and native['user_data_dir'].startswith(native['appdata']), 'Actual isolated user-data provenance')
    check(native['tool_sha256'] == sha(ROOT / 'raw/native_scene_witness.gd'), 'Native embedded tool hash')
    check(all(digest == before['source_files'][path]['sha256'] for path, digest in native['source_shas'].items()), 'Native exact product source epoch')
    check(strict_clean(log('raw/native-fourth.log')) and (ROOT / 'raw/native-fourth-exit.txt').read_text().strip() == '0', 'Native natural EOF strict gate')
    for name in ['NE-301-enemy-drops.png', 'NE-301-box-drop.png', 'NE-301-collected.png']:
        original = ROOT / 'raw/native-fourth' / name
        data = original.read_bytes()
        check(data[:8] == b'\x89PNG\r\n\x1a\n' and struct.unpack('>II', data[16:24]) == (1280, 720), 'Original native PNG: ' + name)
        repo = ROOT.parent.parent.parent.parent
        if (repo / 'project.godot').is_file():
            public = ROOT.parent.parent / 'images' / name
            check(public.is_file() and sha(public) == sha(original), 'Public image uses isolated fourth epoch: ' + name)
    aliases = read('raw/source-epoch-aliases.json')['native-source-snapshot.json']
    for path, row in read('raw/native-source-snapshot.json')['files'].items():
        check(sha(ROOT / 'raw' / aliases.get(path, path)) == row['sha256'], 'Retained third/failed tool source epoch: ' + path)
    check((ROOT / 'raw/official-aae/exit.txt').read_text().strip() == '0', 'Official affected natural exit')
    console = log('raw/official-aae/console.log')
    check('Running 76 groups in 2 processes' in console and 'new failures: 0' in console, 'Official selected suite result')
    for shard in ['0', '1']:
        check(not re.search(r'SCRIPT ERROR|Parse Error|Compile Error', log(f'raw/official-aae/shard_{shard}.log')), 'Official no script errors: ' + shard)
    print(f'NE301 portable checks: {checks}, failures: 0')

if __name__ == '__main__':
    main()
