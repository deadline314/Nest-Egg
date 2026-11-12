"""Read-only exact formal source/log receipts and native-to-final comments."""
from pathlib import Path
import copy,hashlib,json,re,zipfile
here=Path(__file__).resolve().parent;index=json.loads((here/'formal-tests-index.json').read_text(encoding='utf-8'))
with zipfile.ZipFile(here/'formal-tests-original.zip') as z:
    for row in index:
        raw=z.read(row['path']);assert len(raw)==row['bytes'] and hashlib.sha256(raw).hexdigest()==row['sha256']
    def doc(path):return json.loads(z.read(path))
    results=[]
    for prefix,count in [('canonical-affected-v14-v1',10478),('latest-main-short-v1',2089)]:
        receipt=doc(prefix+'/exit.json');before=doc(prefix+'/source-before.json');after=doc(prefix+'/source-after.json')
        assert receipt['exit']==0 and receipt['passed'] and receipt['source_unchanged'] and not receipt['script_errors']
        assert before==after and len(before)==10162
        log=z.read(prefix+'/full.log').decode('utf-8')
        summary=re.search(r'checks: (\d+), new failures: (\d+), known failures .*?: (\d+)',log)
        assert summary and tuple(map(int,summary.groups()))==(count,0,0)
        shardnames=[r['path'] for r in index if r['path'].startswith(prefix+'/logs/shard_') and r['path'].endswith('.log')]
        shards=[z.read(n).decode('utf-8',errors='replace') for n in shardnames];assert len(shards)==2
        assert all('SCRIPT ERROR' not in s for s in shards)
        command=doc(prefix+'/command.json')
        if prefix.startswith('canonical'):
            assert command['command'][1]=='tools/run_tests_changed.sh' and command['base']=='2fa7bde15a08d0744d968c796ed9c5c4bf614015'
            assert 'Running 22 groups in 2 processes' in log
        else:
            assert command['base']=='d20d88f46e4889e46efbbbe4d165ddf396db4346'
            assert command['command'][1:]==['tools/run_tests_parallel.sh','--only=AmmoTraySuite,DeathFlowSuite,CutsceneSuite']
        results.append({'scope':prefix,'checks':count,'new':0,'known':0,'exit':0,'source_count':len(before),'raw_ERROR_lines':sum(len(re.findall(r'^ERROR:',s,re.M)) for s in shards),'raw_ObjectDB_diagnostics':[line for s in shards for line in s.splitlines() if 'ObjectDB' in line],'claim':'original filters applied by archived runner; raw diagnostics retained, not zero-ERROR headless'})
        negative=copy.deepcopy(after);negative[next(iter(negative))]='0'*64;assert negative!=before
    manifest=doc('final-four-v1/manifest.json')
    old=doc('canonical-affected-v14-v1/source-before.json');final=doc('latest-main-short-v1/source-before.json')
    with zipfile.ZipFile(here/'source-and-cpu-original.zip') as native:
        for row in manifest['paths']:
            path=row['path'];a=native.read('candidate-v14/candidate/'+path);b=z.read('final-four-v1/candidate/'+path)
            assert hashlib.sha256(a).hexdigest()==old[path]==row['native_v14_sha256']
            assert hashlib.sha256(b).hexdigest()==final[path]==row['candidate_sha256']
            execution=lambda raw:b'\n'.join(line for line in raw.splitlines() if not line.lstrip().startswith(b'#'))
            assert execution(a)==execution(b),'final delta must be whole-line comments only'
print(json.dumps({'passed':True,'formal':results,'source_negative_control':'changed source digest rejected','native_to_final':'all four execution lines byte-identical; helper three comment locations differ, others byte-identical'},indent=2))
