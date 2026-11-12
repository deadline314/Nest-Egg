"""Read-only original2fa affected proof. Latest81 joint is a separate scope."""
import hashlib,json,pathlib,re,zipfile
R=pathlib.Path(__file__).resolve().parent
index=json.loads((R/'affected-2fa-index.json').read_text(encoding='utf8'))
def sha(f):
    h=hashlib.sha256()
    for b in iter(lambda:f.read(1048576),b''):h.update(b)
    return h.hexdigest()
with (R/index['archive']['name']).open('rb') as f:assert sha(f)==index['archive']['sha256']
with zipfile.ZipFile(R/index['archive']['name']) as z:
    assert set(z.namelist())==set(index['members'])
    for name,v in index['members'].items():
        i=z.getinfo(name);assert i.file_size==v['bytes'] and i.CRC==v['crc32'],name
        with z.open(name) as f:assert sha(f)==v['sha256'],name
    data=lambda name:json.loads(z.read(name))
    before=data('source-before.json');assert before==data('source-after.json')
    receipt=data('exit.json');assert receipt['exit']==0 and receipt['script_errors']==0 and receipt['source_fixed'] and receipt['source_count']==13157 and receipt['shards']==2
    cmd=data('command.json');assert cmd['base']==cmd['head']=='2fa7bde15a08d0744d968c796ed9c5c4bf614015'
    assert cmd['env']['SHARDS']=='2' and cmd['argv'][1:] == ['tools/run_tests_changed.sh',cmd['base']]
    assert hashlib.sha256(z.read('executed-runner.py')).hexdigest()==cmd['runner_sha256']
    manifest=json.loads((R/'manifest.json').read_text(encoding='utf8'))
    for name,v in manifest['files'].items():assert before[name]==v['sha256']==hashlib.sha256((R/'source'/name).read_bytes()).hexdigest()
    output=z.read('full.log').decode('utf8');assert 'Running 22 groups in 2 processes' in output and 'checks: 45566, new failures: 0, known failures (tests/known_failures.txt): 0' in output
    total=0
    for name in ['logs/shard_0.log','logs/shard_1.log']:
        text=z.read(name).decode('utf8');assert 'SCRIPT ERROR' not in text
        matches=re.findall(r'^checks: (\d+), failures: (\d+)',text,re.M);assert len(matches)==1 and int(matches[0][1])==0
        total+=int(matches[0][0])
    assert total==45566
    diagnostics=data('diagnostics.json')['shards'];assert all(not v['unexpected_diagnostic_lines'] for v in diagnostics.values())
    assert sum(v['error_lines'] for v in diagnostics.values())==147
    print('PASS: exact2fa/default-headless original22;45566/0;13157 fixed;0SCRIPT.147 preserved ERROR lines include original allowed shutdown diagnostics; no zero-leak claim. Latest81 integration is separate.')
