"""Portable CPU verification; run python verify.py beside this evidence packet."""
from pathlib import Path
import hashlib
import json
import math
import re
import zipfile

ROOT = Path(__file__).resolve().parent
count = 0

def check(value, message):
    global count
    count += 1
    if not value:
        raise RuntimeError(message)

def read(rel):
    return json.loads((ROOT / rel).read_text(encoding='utf-8'))

def digest(data):
    return hashlib.sha256(data).hexdigest()

def payload(row):
    textures = row['textures']
    check(len({t['path'] for t in textures}) == len(textures), 'Duplicate residency path')
    check(all(t['bytes'] > 0 and t['owners'] for t in textures), 'Missing payload/owner')
    check(sum(t['bytes'] for t in textures) == row['payload_bytes'], 'Payload total differs')

def main():
    # Original PNG bytes remain portable, including every rejected epoch.
    archives = {}
    try:
        aliases = {x['path']: x for x in read('raw-image-aliases.json')}
        for row in read('original-outputs.json'):
            if row['kind'] == 'archived-image':
                alias = aliases[row['path']]
                if alias['archive'] not in archives:
                    archives[alias['archive']] = zipfile.ZipFile(ROOT / alias['archive'])
                data = archives[alias['archive']].read(alias['member'])
            else:
                data = (ROOT / 'raw' / row['path']).read_bytes()
            check(len(data) == row['bytes'] and digest(data) == row['sha256'], row['path'])
    finally:
        for archive in archives.values():
            archive.close()

    sources = {digest(p.read_bytes()) for folder in ['work', 'frozen-candidate', 'native-support', 'raw/isolation-work-sources']
               for p in (ROOT / folder).rglob('*') if p.is_file()}
    for name in ['A1', 'B1', 'C1', 'A2', 'C2', 'D1', 'D2', 'D3', 'D4', 'A3', 'E1', 'A4', 'E2']:
        report = read(f'raw/isolated-{name}/report.json')
        check(report['tool_sha256'] in sources, f'{name}: exact tool source missing')
        check(report['source_shas']['core/asset_prefetch.gd'] in sources, f'{name}: exact core source missing')
        for row in report['records']:
            payload(row)
            check(row['prefetch']['queued'] == 0 and row['prefetch']['inflight'] == 0, f'{name}: unsettled')
        calculated = report['records'][-1]['payload_bytes'] / report['records'][0]['payload_bytes']
        check(math.isclose(calculated, report['ratio'], rel_tol=1e-13), f'{name}: ratio')
        check(sum(len(r['built_stages']) for r in report['records']) == 15, f'{name}: stage coverage')
        for owner in report['owner_runs']:
            check(bool(owner['held']['stage_residents']), f'{name}: actual owner never held stage')
            check(not owner['after']['stage_residents'], f'{name}: actual owner leaked stage')
            check(owner['cancelled'] != owner['finished_signal'], f'{name}: finish/cancel result')
    for name in ['A3', 'A4']:
        r = read(f'raw/isolated-{name}/report.json')
        check(len(r['failures']) == 4 and r['ratio'] > 1.10, f'{name}: original stopped failing')
        check((ROOT / f'work/exit-{name}.txt').read_text().strip() == '1', f'{name}: exit')
    for name in ['E1', 'E2']:
        r = read(f'raw/isolated-{name}/report.json')
        check(not r['failures'] and r['observer']['count'] == 0 and r['ratio'] <= 1.10, f'{name}: gates')
        check(all(not x['stage_residents'] and not x['unexpected_backdrop'] and x['white_share'] <= .05
                  for x in r['records']), f'{name}: residency/white')
        check((ROOT / f'work/exit-{name}.txt').read_text().strip() == '0', f'{name}: exit')

    mapping = read('work/comment-mapping.json')
    old = ROOT / 'work/candidate-512-theme-backdrop-only-prefetch.gd.txt'
    final = ROOT / 'frozen-candidate/core/asset_prefetch.gd'
    check(digest(old.read_bytes()) == mapping['native_E_sha256'], 'Native E hash')
    check(digest(final.read_bytes()) == mapping['final_comment_only_sha256'], 'Final core hash')
    uncomment = lambda p: [line for line in p.read_text(encoding='utf-8').splitlines()
                          if line.strip() and not line.lstrip().startswith('#')]
    check(uncomment(old) == uncomment(final), 'Final executable lines differ from native E')
    # All failed Main fixtures keep their exact tool sources and screenshots.
    for epoch in ['main-D', 'main-E1', 'main-E2', 'main-E3']:
        r = read(f'raw/{epoch}/record-summary.json')
        check(r['failures'] == 1 and r['tool_sha256'] in sources, f'{epoch}: failure history/source')
        check(any(x.startswith(epoch + '/') for x in aliases), f'{epoch}: failure images missing')
    record = read('raw/main-E4/record-summary.json')
    cold = read('raw/main-E4/cold-summary.json')
    check(record['checks'] + cold['checks'] == 252 and record['failures'] == cold['failures'] == 0, 'Main 252/0')
    check(record['pid'] != cold['pid'] and cold['cold_record_pid'] == record['pid'], 'Independent cold process')
    check(record['complete_authored_lines_accepted'] == 6 and record['npc_talks'] and cold['npc_talks'], 'Actual opening/NPC dialogue')
    for r in [record, cold]:
        check(r['tool_sha256'] in sources and r['prefetch_sha256'] == mapping['native_E_sha256'], 'Main exact sources')
        menus = [x for x in r['events'] if x['stage'] == 'menu-settled']
        check(len(menus) == 4, 'Three returns plus terminal menu')
        check(len({x['render_texture_bytes'] for x in menus}) == 1, 'Renderer menu growth')
        check({x['environment_residency']['payload_bytes'] for x in menus} == {46474208}, 'Environment menu growth')
        for menu in menus:
            payload(menu['environment_residency'])
            check(menu['prefetch']['queued'] == 0 and menu['prefetch']['inflight'] == 0, 'Unsettled menu')
        check(r['events'][-1]['stage'] == 'pre-real-main-quit', 'Main did not reach natural quit')
    slot = read('raw/main-E4/slot.json')
    check(digest(slot['payload'].encode()) == slot['checksum'], 'Actual slot checksum')
    for name in ['main-E-record-04.log', 'main-E-cold-04.log']:
        log = (ROOT / 'work' / name).read_text(encoding='utf-8', errors='replace')
        check(not re.search(r'(?:SCRIPT ERROR|^ERROR:|Parse Error|Compile Error|ObjectDB instances leaked)', log, re.M), name)

    before = read('work/official-source-before.json')
    after = read('work/official-source-after.json')
    check(before == after, 'Official source guard changed')
    check((ROOT / 'raw/official-3713/exit.txt').read_text().strip() == '0', 'Official affected exit')
    check('failures: 0' in (ROOT / 'raw/official-3713/console.log').read_text(encoding='utf-8'), 'Official summary missing')
    result = read('official-result.json')
    check(result['same_eof_diagnostics'] is False, 'Original unequal exit numbers were rewritten')
    check(result['baseline_shard_checks'] + 18 == 3453, 'Baseline/candidate new checks differ')
    check(result['candidate_eof_diagnostics'] != result['baseline_eof_diagnostics'], 'Original EOF comparison was hidden')
    for case in result['original_drop_reproduction']:
        check(case['prefetch_sha'] == '9e6e6ecfe8faf1ef80eaf2655321843ca0b6df1a704cac74380910fc78d341b8', 'Drop reproduction was not original prefetch')
        expected = (2 if case['case'] == 'box' else 1) if case['retire'] else 0
        check(case['before'] == 0 and case['added'] == expected and case['after'] == expected, 'Actual original drop owner reproduction')
        check(case['natural_exit'] == (1 if case['retire'] else 0), 'Actual drop probe exit')
        check(len(case['stray_nodes']) == expected, 'Actual orphan identities missing')
    check(read('baseline-shutdown-control/source-before.json') == read('baseline-shutdown-control/source-after.json'), 'Baseline source guard')
    check(read('baseline-shutdown-control/candidate-restored.json') == before, 'Candidate restoration')
    for row in read('manifest.json'):
        path = ROOT / row['path']
        with path.open('rb') as source:
            hashed = hashlib.file_digest(source, 'sha256').hexdigest()
        check(path.stat().st_size == row['bytes'] and hashed == row['sha256'], 'Packet manifest: ' + row['path'])
    print(f'BG32 portable checks: {count}, failures: 0')

if __name__ == '__main__':
    main()
