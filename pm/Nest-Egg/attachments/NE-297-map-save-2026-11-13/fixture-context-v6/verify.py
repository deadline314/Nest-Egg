"""Portable focused-v6 evidence replay; does not accept pending formal87/cold/UI."""
from pathlib import Path
import argparse,hashlib,json,re,tempfile,zipfile
def sha(b):return hashlib.sha256(b).hexdigest()
def load(p):return json.loads(p.read_text(encoding='utf8'))
def clear(q):return len(q)==2 and q[0]['port']==8188 and q[0]['state']=='empty' and q[1]['port']==8189 and q[1]['state'] in ['empty','refused']
def replay(root,require_official=False):
    index=load(root/'index.json')
    for n,row in index['files'].items():assert sha((root/n).read_bytes())==row['sha256'] and (root/n).stat().st_size==row['bytes']
    with tempfile.TemporaryDirectory(prefix='ne297-v6-portable-') as folder:
        d=Path(folder)
        for n,members in index['archives'].items():
            with zipfile.ZipFile(root/n) as z:
                assert z.testzip() is None and set(z.namelist())==set(members)
                for key,row in members.items():
                    p=Path(key);assert not p.is_absolute() and '..' not in p.parts
                    b=z.read(key);assert sha(b)==row['sha256'] and len(b)==row['bytes'];q=d/key;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(b)
        v6=load(d/'sources/candidate-v6.json');v5=load(d/'sources/candidate-v5.json');assert len(v6['files'])==len(v5['files'])==14
        differences=[n for n in v6['files'] if v6['files'][n]!=v5['files'][n]]
        assert differences==['tests/helpers/map_layout_migration_checks.gd']
        for n,h in v6['files'].items():assert sha((d/'sources/final14'/n).read_bytes())==h
        focused=d/'evidence/focused-v6';r=load(focused/'receipt.json');review=load(focused/'independent-review.json')
        assert r['accepted'] is False and r['started'] and r['exit_code']==0 and r['error'] is None and r['source_count']==10192 and r['source_exact'] and r['c_unchanged'] and r['all_four_queue_gates']
        assert not r['added'] and not r['changed'] and not r['removed']
        before=load(focused/'source-before.json');assert before==load(focused/'source-after.json') and load(focused/'c-before.json')==load(focused/'c-after.json') and len(load(focused/'c-before.json'))==463
        assert all(before[n]==h for n,h in v6['files'].items())
        for key in ['outer-queue-before.json','inner-queue-before.json','inner-queue-after.json','outer-queue-after.json']:assert clear(load(focused/key))
        command=load(focused/'command.json');assert len(command['environment'])>=5 and all(n in command['environment'] for n in ['APPDATA','LOCALAPPDATA','USERPROFILE','TMP','TEMP'])
        log=(focused/'engine.log').read_text(encoding='utf8')
        assert not re.search(r'SCRIPT ERROR|Parse Error|^ERROR:|ObjectDB.*leak|were leaked|resources still in use|DummyTexture',log,re.M)
        warnings=[line for line in log.splitlines() if line.startswith('WARNING:')]
        expected=[
            'WARNING: [RunSave] run/level res://data/levels/no_such_level_ne297.tres 無效，退回 res://data/levels/ch1_prologue.tres',
            'WARNING: [RunSave] run/level res://data/levels/no_such_level_ne297.tres 無效，退回 res://data/levels/ch1_prologue.tres',
            'WARNING: [Level] res://data/levels/ne297_test_only.tres area/layout_revision：不支援的版面修訂；原存檔保留；原存檔保留。',
            'WARNING: [Level] res://data/levels/ne297_test_only.tres layout migration：持久鍵衝突 gate@10,50；原存檔保留；原存檔保留。']
        assert warnings==r['diagnostics']==expected
        assert review['accepted'] and review['checks']==181 and review['failures']==0 and 'checks: 181, failures: 0' in log
        witnesses=[json.loads(line.split('] ',1)[1]) for line in log.splitlines() if line.startswith('[NE297 destination reader] ')]
        assert witnesses==review['witness'] and len(witnesses)==4
        assert {(w['source_revision'],w['target']) for w in witnesses}=={(v,p) for v in [1,2] for p in ['res://data/levels/ne297_test_only.tres','res://data/levels/level_01.tres']}
        for w in witnesses:assert w['has_data'] is True and w['error']=='' and w['position']==[-1.0,-1.0] and all(type(v) is float for v in w['position']) and w['component_types']==[3,3] and w['raw_container_equal'] is False and w['exact_coordinate_equal'] is True
        for n in ['work/ne297-probe-v1/probe.gd','work/ne297-probe-v1/probe.tscn']:assert sha((d/'sources/actual-probe'/n).read_bytes())==before[n]
        canonical=load(d/'sources/canonical80/manifest.json');assert len(canonical['files'])==80
        excluded=[n for n in canonical['files'] if n not in before];assert excluded==['design/21-metroidvania/CHAPTER1.md']
        assert all(before[n]==h for n,h in canonical['files'].items() if n in before)
        with zipfile.ZipFile(d/'sources/canonical80/source.zip') as z:assert z.testzip() is None and set(z.namelist())==set(canonical['files']) and all(sha(z.read(n))==h for n,h in canonical['files'].items())
        old=d/'evidence/changed-v2';oldr=load(old/'receipt.json');assert not oldr['accepted'] and oldr['exit_code']==1 and oldr['source_exact'] and oldr['c_unchanged'] and oldr['all_four_queue_gates']
        assert load(old/'source-before.json')==load(old/'source-after.json') and load(old/'c-before.json')==load(old/'c-after.json')
        checks=0;fails=[];suites=[]
        for i in range(6):
            t=(old/f'test-logs/shard_{i}.log').read_text(encoding='utf8');a=re.findall(r'^checks: (\d+), failures: (\d+)$',t,re.M);assert len(a)==1;checks+=int(a[0][0]);local=re.findall(r'^FAIL: (.*)$',t,re.M);assert len(local)==int(a[0][1]);fails+=local;suites+=re.findall(r'^SUITE_TIME (\S+) ',t,re.M)
        assert checks==99539 and len(fails)==4 and len(suites)==len(set(suites))==87 and all(s=='actual run reader preserves the fresh destination entry rather than applying legacy relocation' for s in fails)
        assert all(index[k] is False for k in ['official_accepted','canonical_cold_accepted','region_world_UI_accepted'])
    if require_official:raise AssertionError('Original87 changed-v3, same-canonical cold and region/world UI still pending; focused181 is not overall acceptance.')
    return {'focused_evidence_verified':True,'actual_checks':181,'failures':0,'original_strict_wrapper_accepted':False,'exact_expected_warnings_retained':4,'witness_count':4,'all_readers_have_data_and_exact_sentinel':True,'typed_container_mismatch_observed':True,'candidate14_changed_only_test_helper':True,'canonical80_archive_exact':True,'canonical_runtime_members':79,'canonical_design_document_outside_dynamic_guard':excluded,'changed_v2_historical_checks':checks,'changed_v2_historical_failures':4,'official_accepted':False,'canonical_cold_accepted':False,'region_world_UI_accepted':False,'engine_started':False}
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('root',type=Path,nargs='?',default=Path(__file__).resolve().parent);p.add_argument('--require-official',action='store_true');a=p.parse_args();print(json.dumps(replay(a.root,a.require_official),indent=2))
