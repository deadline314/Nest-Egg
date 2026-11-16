from pathlib import Path
import hashlib
import json
import re
import subprocess

REPO = Path('C:/Users/stanl/Github/Nest-Egg')
WORK = REPO / 'work/ne301-deferred-pickup-20261117'
RAW = Path('D:/NestEggVerification/evidence-20261117/ne301')
PACKET = REPO / 'pm/Nest-Egg/attachments/NE-301-deferred-pickups-2026-11-17'

def sha(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()

def main():
    official = RAW / 'official-aae'
    assert (official / 'exit.txt').read_text().strip() == '0'
    console = (official / 'console.log').read_text(encoding='utf-8')
    match = re.search(r'checks: (\d+), new failures: (\d+), known failures.*?: (\d+)  \(wall time (\d+) s\)', console)
    assert match and match[2] == '0'
    result = {'groups': 76, 'processes': 2, 'checks': int(match[1]), 'new_failures': int(match[2]),
              'known_failures': int(match[3]), 'wall_seconds': int(match[4]), 'natural_exit': 0, 'shards': []}
    for number in [0, 1]:
        text = (official / f'shard_{number}.log').read_text(encoding='utf-8')
        assert not re.search(r'SCRIPT ERROR|Parse Error|Compile Error|^FAIL:', text, re.M)
        summaries = list(re.finditer(r'^checks: (\d+), failures: (\d+)', text, re.M))
        last = summaries[-1]
        result['shards'].append({'number': number, 'checks': int(last[1]), 'failures': int(last[2]),
                                  'complete_eof_after_summary': text[last.end():].strip()})
    assert sum(row['checks'] for row in result['shards']) == result['checks']
    (WORK / 'official-result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    before = json.loads((WORK / 'official-source-before.json').read_text(encoding='utf-8'))
    assert before == json.loads((WORK / 'official-source-after.json').read_text(encoding='utf-8'))
    baseline = {}
    for rel in before['source_files']:
        if rel == 'tests/helpers/deferred_pickup_checks.gd':
            baseline[rel] = None
        else:
            data = subprocess.check_output(['git', 'show', before['base'] + ':' + rel], cwd=REPO)
            baseline[rel] = hashlib.sha256(data).hexdigest()
    (WORK / 'baseline-source-shas.json').write_text(json.dumps(baseline, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))

def manifest():
    rows = [{'path': p.relative_to(PACKET).as_posix(), 'bytes': p.stat().st_size, 'sha256': sha(p)}
            for p in sorted(PACKET.rglob('*')) if p.is_file()
            and p.name not in ['manifest.json', 'verify-console.log', 'verification.json']]
    (PACKET / 'manifest.json').write_text(json.dumps(rows, indent=2) + '\n', encoding='utf-8')
    before = json.loads((WORK / 'official-source-before.json').read_text(encoding='utf-8'))
    baseline = json.loads((WORK / 'baseline-source-shas.json').read_text(encoding='utf-8'))
    targets = [*before['source_files'], 'design/09-content/DEFERRED_PICKUP_LIFETIME.md',
               'pm/Nest-Egg/[NE-301]回收延後生成的掉落物.md',
               *['pm/Nest-Egg/images/' + name for name in ['NE-301-enemy-drops.png', 'NE-301-box-drop.png', 'NE-301-collected.png']],
               *[p.relative_to(REPO).as_posix() for p in sorted(PACKET.rglob('*')) if p.is_file()]]
    # Root owns this single existing ticket's Related backlink; never stage its directory.
    related = [p for p in (REPO / 'pm/Nest-Egg').iterdir() if p.name.startswith('[NE-118]') and p.suffix == '.md']
    assert len(related) == 1 and 'NE-301' in related[0].read_text(encoding='utf-8')
    targets.append(related[0].relative_to(REPO).as_posix())
    delivery = {'files': sorted(set(targets)), 'candidate_sources': {
        path: {'source': str(WORK / 'frozen-candidate' / path), 'baseline_sha256': baseline[path], **row}
        for path, row in before['source_files'].items()},
        'note': 'Copy frozen bytes only after checking unchanged baseline targets; preserve unrelated concurrent edits. Child performed no stage/commit/push.'}
    (WORK / 'delivery-files.json').write_text(json.dumps(delivery, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Manifest {len(rows)} files, delivery {len(delivery["files"])} paths')

if __name__ == '__main__':
    import sys
    manifest() if '--manifest' in sys.argv else main()
