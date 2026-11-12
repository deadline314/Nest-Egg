"""Read-only independent baseline/candidate Cutscene receipt and archive reader."""
import collections
import hashlib
import json
from pathlib import Path
import re
import zipfile

P=Path(__file__).resolve().parent
index=json.loads((P/'raw-index.json').read_text(encoding='utf8'))
path=P/index['zip']
assert path.stat().st_size==index['bytes']
assert hashlib.sha256(path.read_bytes()).hexdigest()==index['sha256']
with zipfile.ZipFile(path) as z:
    assert z.testzip() is None and set(z.namelist())==set(index['members'])
    raw={}
    for name,item in index['members'].items():
        b=z.read(name)
        assert len(b)==item['bytes'] and hashlib.sha256(b).hexdigest()==item['sha256']
        raw[name]=b
def j(n):return json.loads(raw[n])
plan=j('plan.json')
assert plan['base']=='896d3e8a7fb1b0018df0aec47ed8c5a37bb881c0'
counts=[];messages=[]
for condition in ['A_baseline','B_candidate']:
    before=j(condition+'-before.json');after=j(condition+'-after.json')
    assert len(before)==27674 and before==after
    proc=j(condition+'-process.json')
    log=raw[condition+'.log']
    assert hashlib.sha256(log).hexdigest()==proc['log_sha256']
    assert proc['exit_code']==0 and proc['source_fixed'] and proc['script_errors']==0
    assert not proc['exit_leaks'] and not proc['failure_lines']
    text=log.decode('utf8',errors='replace')
    summary=re.findall(r'^checks: (\d+), failures: (\d+)',text,re.M)
    assert summary and list(summary[-1])==proc['summary']
    assert not re.search(r'SCRIPT ERROR|ObjectDB.*leak|were leaked|resources still in use',text)
    counts.append(int(summary[-1][0]))
    messages.append(collections.Counter(d['text'] for d in proc['diagnostics']))
    for name,expected in (plan['baseline_sha256'] if condition=='A_baseline' else plan['candidate_sha256']).items():
        assert before[name]==expected
assert counts==[1821,1829] and counts[1]-counts[0]==8
assert messages[0]==messages[1]
a=j('A_baseline-after.json');b=j('B_candidate-before.json')
assert {name for name in a if a[name]!=b[name]}==set(plan['baseline_sha256'])
restored=j('candidate-restored.json')
assert restored['all_27674_exact'] and restored['uid_exact'] and restored['candidate']==plan['candidate_sha256']
for name,expected in plan['baseline_sha256'].items():
    assert hashlib.sha256(raw['baseline_sources/'+name]).hexdigest()==expected
print('A 1821/0; B 1829/0; precisely 8 new checks; both process exit0')
print('Both: 0 SCRIPT ERROR, 0 exit leak. Deliberately expected ERROR texts/counts identical:',sum(messages[0].values()))
print('Both 27,674-source epochs fixed; candidate3+UID and full candidate source restored exact.')
print('This does not attribute or erase the original 26-group filtered exit diagnostics.')
