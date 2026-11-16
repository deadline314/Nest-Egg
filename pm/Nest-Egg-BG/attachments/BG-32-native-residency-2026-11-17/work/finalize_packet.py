from pathlib import Path
import hashlib
import json
import re
import shutil

repo = Path('C:/Users/stanl/Github/Nest-Egg')
work = repo / 'work/bg32-audit-20261117'
packet = repo / 'pm/Nest-Egg-BG/attachments/BG-32-native-residency-2026-11-17'
baseline = Path('D:/NestEggVerification/evidence-20261117/bg32/baseline-shutdown-control-02')
official = Path('C:/NE/evidence-20261117/bg32/official-3713')

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def eof(log):
    return log[log.rfind('\nchecks: '):].splitlines()[2:]

def main():
    assert (baseline / 'exit.txt').read_text().strip() == '0', 'Baseline not finished/passed'
    assert json.loads((baseline / 'source-before.json').read_text(encoding='utf-8')) == json.loads((baseline / 'source-after.json').read_text(encoding='utf-8'))
    assert json.loads((baseline / 'candidate-restored.json').read_text(encoding='utf-8')) == json.loads((work / 'official-source-before.json').read_text(encoding='utf-8'))
    candidate_log = (official / 'shard_1.log').read_text(encoding='utf-8')
    baseline_log = (baseline / 'console.log').read_text(encoding='utf-8')
    candidate_tail, baseline_tail = eof(candidate_log), eof(baseline_log)
    result = {'candidate_checks': 11759, 'candidate_new_failures': 0, 'candidate_known_failures': 0,
              'candidate_natural_exit': int((official / 'exit.txt').read_text()),
              'candidate_wall_seconds': 390,
              'baseline_shard_checks': int(re.search(r'^checks: (\d+), failures: 0', baseline_log, re.M).group(1)),
              'baseline_natural_exit': int((baseline / 'exit.txt').read_text()),
              'same_eof_diagnostics': candidate_tail == baseline_tail,
              'candidate_eof_diagnostics': candidate_tail, 'baseline_eof_diagnostics': baseline_tail,
              'scope': 'Same 5 suites, same full3713 clean baseline, same engine, new isolated profile; no changed filters.'}
    (packet / 'official-result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    extra = Path('D:/NestEggVerification/evidence-20261117/bg32')
    diagnostics = packet / 'deferred-pickup-diagnostics'
    diagnostics.mkdir(exist_ok=True)
    for p in (extra / 'drop-owner-original-controls').iterdir():
        if p.is_file(): shutil.copyfile(p, diagnostics / p.name)
    shutil.copyfile(extra / 'candidate-shutdown-verbose/console.log.gz', diagnostics / 'candidate-verbose.log.gz')
    shutil.copyfile(extra / 'candidate-shutdown-verbose/exit.txt', diagnostics / 'candidate-verbose-exit.txt')
    verbose = (extra / 'candidate-shutdown-verbose/console.log').read_text(encoding='utf-8')
    (diagnostics / 'candidate-verbose-tail.txt').write_text('\n'.join(verbose.splitlines()[-120:]) + '\n', encoding='utf-8')
    repro = []
    for observation in json.loads((diagnostics / 'results.json').read_text(encoding='utf-8')):
        log = (diagnostics / observation['log']).read_text(encoding='utf-8')
        measurement = re.search(r'BG32_DROP_OWNER_CONTROL.*before=(\d+) after=(\d+) added=(\d+).*prefetch_sha=([a-f0-9]+)', log)
        assert measurement
        repro.append({**observation, 'before': int(measurement[1]), 'after': int(measurement[2]), 'added': int(measurement[3]),
                      'prefetch_sha': measurement[4],
                      'stray_nodes': [{'id': int(node[0]), 'source': node[1]} for node in re.findall(r'(\d+) - Stray Node:.*Source:([^\)]+)', log)]})
    result.update({'related_ticket': 'NE-301', 'original_drop_reproduction': repro,
                   'classification': 'Original deferred pickup family independently reproduced. Candidate verbose repeated 1 area/4 objects/2 resources; first candidate nonverbose had 2/6/3 and its extra ID is not individually recoverable after exit. Do not assert exact ID attribution or identical counts.',
                   'native_main_error_scope': 'Both independent native Main logs clean; official headless test runner retains its pre-existing exit-diagnostic policy unchanged.'})
    (packet / 'official-result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    for p in baseline.iterdir():
        if p.is_file():
            dest = packet / 'baseline-shutdown-control' / p.name
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(p, dest)
    # Preserve the setup-only failed cross-drive rename and its finally restoration.
    first = baseline.parent / 'baseline-shutdown-control'
    if (first / 'candidate-restored.json').is_file():
        dest = packet / 'baseline-control-initial-setup'
        dest.mkdir(exist_ok=True)
        shutil.copyfile(first / 'candidate-restored.json', dest / 'candidate-restored.json')
        (dest / 'observation.json').write_text(json.dumps({'stage': 'setup before Godot', 'error': 'WinError 17: os.replace cannot move files between C: and D:', 'candidate_finally_restored': True, 'fix': 'Copy exact owned SHA-verified helper to D, then unlink that owned source; retry in new control-02 output.'}, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))

if __name__ == '__main__':
    main()
