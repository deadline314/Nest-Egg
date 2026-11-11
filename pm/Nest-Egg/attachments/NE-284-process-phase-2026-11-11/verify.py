"""Read-only verification of retained test-phase evidence (standard library)."""
from pathlib import Path
import hashlib
import json
import re
import zipfile


def sha(data):
    return hashlib.sha256(data).hexdigest()


def verify_archive(folder, name):
    receipt = json.loads((folder / (name + '.json')).read_bytes())
    path = folder / receipt['archive']
    assert path.stat().st_size == receipt['bytes']
    assert sha(path.read_bytes()) == receipt['sha256']
    with zipfile.ZipFile(path) as archive:
        manifest = json.loads(archive.read('manifest.json'))
        assert set(archive.namelist()) == set(manifest) | {'manifest.json'}
        contents = {}
        for member, metadata in manifest.items():
            data = archive.read(member)
            assert len(data) == metadata['bytes'] and sha(data) == metadata['sha256'], member
            contents[member] = data
    return receipt, contents


def main():
    folder = Path(__file__).resolve().parent
    diagnostic, raw = verify_archive(folder, 'diagnostic-and-red')
    results = json.loads(raw['diagnostic/results.json'])
    outcomes = {item['case']: item['exit'] for item in results}
    outcomes['red-catchup'] = json.loads(raw['diagnostic/red-result.json'])['exit']
    assert outcomes == {'red-catchup': 1, 'green-catchup': 0, 'green-normal': 0,
                        'negative-stopped-clock': 1}
    for case, failures in [('red-catchup', 20), ('green-catchup', 0),
                           ('green-normal', 0), ('negative-stopped-clock', 20)]:
        text = raw['diagnostic/' + case + '.log'].decode('utf8')
        assert f'checks: 260, failures: {failures}' in text
        assert text.count('NE284_TRIAL ') == 20
        assert text.count('FAIL: an on-screen drip advances') == failures
        assert not re.search(r'(?m)^(?:SCRIPT ERROR|ERROR):', text)
    green = raw['diagnostic/green-catchup-test-source.gd']
    assert green == raw['diagnostic/green-normal-test-source.gd']
    assert green == raw['diagnostic/negative-stopped-clock-test-source.gd']
    original_clock = raw['diagnostic/green-catchup-drip-source.gd']
    assert original_clock == raw['diagnostic/green-normal-drip-source.gd']
    assert original_clock.replace(b'clock = fmod(clock + delta, _period)',
                                  b'clock = fmod(clock + delta * 0.0, _period)') == raw[
                                      'diagnostic/negative-stopped-clock-drip-source.gd']
    assert json.loads(raw['affected-red/exit.json'])['exit'] == 1
    assert 'checks: 71186, new failures: 1' in raw['affected-red/full.log'].decode('utf8')
    final, clean = verify_archive(folder, 'affected-green')
    exit_data = json.loads(clean['exit.json'])
    candidate = json.loads(clean['candidate.json'])
    assert exit_data['exit'] == 0 and exit_data['sources_unchanged']
    assert candidate['source_sha256'] == exit_data['source_after']
    assert len(candidate['source_sha256']) == 20
    for path, expected in candidate['source_sha256'].items():
        assert sha(clean['source/' + path]) == expected, path
    assert clean['source/tests/suite/test_environment.gd'] == green
    log = clean['full.log'].decode('utf8')
    assert 'Running 70 groups in 4 processes' in log
    assert re.search(r'checks: \d+, new failures: 0, known failures .*: 0', log)
    for name, data in clean.items():
        if name.startswith('logs/'):
            assert not re.search(rb'(?m)^(?:SCRIPT ERROR|Parse Error):', data), name
    print(json.dumps({'verified_archives': 2, 'diagnostic_cases': 4,
                      'diagnostic_trials': 80, 'frozen_candidate_sources': 20,
                      'affected_groups': 70, 'new_failures': 0}))


if __name__ == '__main__':
    main()
