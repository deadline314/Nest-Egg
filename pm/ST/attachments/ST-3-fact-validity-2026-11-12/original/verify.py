"""Verify all three separately labelled proof scopes; read-only, no engine."""
import hashlib,json,pathlib,runpy,zipfile
R=pathlib.Path(__file__).resolve().parent
runpy.run_path(str(R/'verify_short.py'),run_name='__main__')
runpy.run_path(str(R/'verify_affected.py'),run_name='__main__')
index=json.loads((R/'integration-81-index.json').read_text(encoding='utf8'))
def digest(stream):
    h=hashlib.sha256()
    for b in iter(lambda:stream.read(1048576),b''):h.update(b)
    return h.hexdigest()
with (R/index['archive']['name']).open('rb') as f:assert digest(f)==index['archive']['sha256']
with zipfile.ZipFile(R/index['archive']['name']) as z:
    assert set(z.namelist())==set(index['members'])
    for name,v in index['members'].items():
        info=z.getinfo(name);assert info.file_size==v['bytes'] and info.CRC==v['crc32'],name
        with z.open(name) as f:assert digest(f)==v['sha256'],name
    data=lambda name:json.loads(z.read(name))
    before=data('source-before.json');assert before==data('source-after.json')
    cmd=data('command.json');receipt=data('exit.json');adoption=data('adoption-receipt.json')
    target='81df4b8c9cfff960d81d3c8e54bba5ebb3e86b51'
    assert cmd['base']==cmd['head']==adoption['target']==adoption['actual_origin_main']==target
    assert adoption['original_preimages']==adoption['target_preimages']
    assert receipt['exit']==0 and receipt['source_fixed'] and receipt['script_errors']==0 and receipt['groups_complete'] and receipt['source_count']==13157
    expected={'StoryLintSuite','CutsceneSuite','DeathFlowSuite','MusicSuite','UiScreensSuite'}
    assert set(receipt['expected_groups'])==set(receipt['observed_groups'])==expected and cmd['env']['SHARDS']=='2'
    assert cmd['argv'][1]=='tools/run_tests_parallel.sh' and set(cmd['argv'][2].split('=',1)[1].split(','))==expected
    assert hashlib.sha256(z.read('executed-runner.py')).hexdigest()==cmd['runner_sha256']
    m=json.loads((R/'manifest.json').read_text(encoding='utf8'))
    for name,v in m['files'].items():assert before[name]==adoption['candidate'][name]['sha256']==v['sha256']
    assert 'checks: 2927, new failures: 0, known failures (tests/known_failures.txt): 0' in z.read('full.log').decode('utf8')
    diagnostics=data('diagnostics.json')['shards']
    assert all(not d['unexpected_diagnostic_lines'] and not d['shutdown_error_lines'] and not d['shutdown_warnings'] for d in diagnostics.values())
    assert sum(d['error_lines'] for d in diagnostics.values())==79
    print('PASS: separate published81 five-suite integration;2927/0;13157 fixed;exact same source3;0SCRIPT/0shutdown diagnostics.79 original intentional ERROR preserved. No relabelling of2fa45566.')
