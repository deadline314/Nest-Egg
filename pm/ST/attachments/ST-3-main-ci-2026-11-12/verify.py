from pathlib import Path
import hashlib, json, re, zipfile

root = Path(__file__).resolve().parent
index = json.loads((root / 'index.json').read_bytes())
digest = lambda b: hashlib.sha256(b).hexdigest()
assert digest((root / 'original.zip').read_bytes()) == index['archive_sha256']
with zipfile.ZipFile(root / 'original.zip') as z:
    assert z.testzip() is None and set(z.namelist()) == set(index['files'])
    for name, wanted in index['files'].items():
        assert digest(z.read(name)) == wanted, name
    for run, event, seconds in [('43220021833', 'push', 507), ('43221750729', 'schedule', 681)]:
        meta = json.loads(z.read(run + '/run.json'))
        assert meta['headSha'] == index['head']
        assert meta['status'] == 'completed' and meta['conclusion'] == 'success'
        assert meta['event'] == event
        log = z.read(run + '/gh-displayed.log').decode('utf-8')
        assert 'Running 88 groups in 6 processes' in log
        assert f'checks: 99000, new failures: 0, known failures (tests/known_failures.txt): 0  (wall time {seconds} s)' in log
        assert 'DUMMY_TEXTURE_EXIT_CHECK logs=6 diagnostics=0' in log
        jobs = meta['jobs']
        assert len(jobs) == 1 and jobs[0]['conclusion'] == 'success'
        steps = {s['name']: s for s in jobs[0]['steps']}
        for step in ('Run all tests (parallel)', 'Reject DummyTexture exit leaks in complete game logs', 'Check durable handoff NPC completion and cold read', 'Check first-clinic results and original pending cold reads'):
            assert steps[step]['conclusion'] == 'success', step
        print(run, event, '88 groups / 99000 checks / 0 new / 0 known; archive PASS')
