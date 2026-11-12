from pathlib import Path
import hashlib,json,re,zipfile
HERE=Path(__file__).resolve().parent
def sha(b):return hashlib.sha256(b).hexdigest()
i=json.loads((HERE/'official-codex-final-v1-index.json').read_bytes());p=HERE/i['archive']
assert p.stat().st_size==i['bytes']and sha(p.read_bytes())==i['sha256']
with zipfile.ZipFile(p)as z:
 assert z.testzip()is None and set(z.namelist())==set(i['entries'])
 for n,v in i['entries'].items():
  b=z.read(n);assert len(b)==v['bytes']and sha(b)==v['sha256'],n
 r=json.loads(z.read('official/exit.json'));c=json.loads(z.read('official/candidate.json'));before=json.loads(z.read('official/source-before.json'))
 assert r['exit']==i['new_failures'] and r['sources_unchanged']and not r['changed_sources']and c['base']==i['base']
 assert r['command']==['C:/Program Files/Git/bin/bash.exe','tools/run_tests_changed.sh',i['base']]
 assert len(c['changed_source_sha256'])==i['changed_count'] and len(c['source_sha256'])==i['source_count'] and before==c['source_sha256']
 for n,v in before.items():assert sha(z.read('source/'+n))==v==r['source_after'][n]
 for n,v in c['changed_source_sha256'].items():assert before[n]==v
 imported=json.loads(z.read('official/import.json'));assert imported['exit']==0 and not imported['error_lines']and imported['sources_unchanged']
 assert sha(z.read('executed-runner.py'))==json.loads(z.read('official/runner-before.json'))['sha256']
 summary=z.read('official/full.log').decode();assert f"Running {i['groups']} groups in 4 processes"in summary
 assert f"checks: {i['checks']}, new failures: {i['new_failures']}, known failures (tests/known_failures.txt): 0"in summary
 total=0;suites=[];diagnostics=0;failures=[];failure_count=0
 for shard in range(4):
  log=z.read(f'official/logs/shard_{shard}.log').decode();assert 'SCRIPT ERROR'not in log
  rows=re.findall(r'^checks: (\d+), failures: (\d+)',log,re.M);assert len(rows)==1;total+=int(rows[0][0]);failure_count+=int(rows[0][1])
  failures+=[line.rstrip('\r')for line in re.findall(r'^FAIL: (.*)',log,re.M)]
  suites+=re.findall(r'^SUITE_TIME (\S+) ',log,re.M);diagnostics+=len(re.findall(r'^ERROR:',log,re.M))
 assert total==i['checks']and len(suites)==len(set(suites))==i['groups'] and failure_count==i['new_failures']and failures==i['failure_lines']
print(json.dumps(dict(groups=i['groups'],checks=total,new_failures=failure_count,known_failures=0,exit=r['exit'],expected_or_filtered_error_lines=diagnostics,scope=i['scope'])))
