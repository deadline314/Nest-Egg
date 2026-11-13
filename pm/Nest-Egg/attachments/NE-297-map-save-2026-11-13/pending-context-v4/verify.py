"""Read-only NE297 candidate-v4/pending supplement verifier. No engine or managed tree."""
from pathlib import Path
import argparse,hashlib,json,re,tempfile,zipfile,importlib.util,copy

def sha(data):return hashlib.sha256(data).hexdigest()
def load(path):return json.loads(path.read_text(encoding='utf8'))
def verify(root,require_official=False):
    index=load(root/'index.json')
    for name,entry in index['files'].items():
        raw=(root/name).read_bytes();assert len(raw)==entry['bytes'] and sha(raw)==entry['sha256'],name
    with tempfile.TemporaryDirectory(prefix='ne297-portable-') as folder:
        dest=Path(folder)
        for name,members in index['archives'].items():
            with zipfile.ZipFile(root/name) as z:
                assert z.testzip() is None
                assert set(z.namelist())==set(members)
                for key,entry in members.items():
                    path=Path(key);assert not path.is_absolute() and '..' not in path.parts
                    raw=z.read(key);assert len(raw)==entry['bytes'] and sha(raw)==entry['sha256'],(name,key)
                    q=dest/key;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes(raw)
        source=load(dest/'sources/candidate-v4.json');assert len(source['files'])==13
        for name,digest in source['files'].items():assert sha((dest/'sources/final'/name).read_bytes())==digest
        for tag in ['value-parser-old-v4','value-parser-new-v5','value-continue-v5','old-write-v1']:
            epoch=dest/'evidence/pending/epochs'/tag
            receipt=load(epoch/'completion.json');assert receipt['accepted'] and receipt['owned_empty'] and receipt['engine_exited'] and receipt['main_lock_released'] and receipt['four_queue_gate_passed']
            proc=load(epoch/'process.json');assert proc['exit_code']==0 and proc['diagnostics']==[]
            assert sha((epoch/'process.log').read_bytes())==proc['log_sha256']
            assert load(epoch/'source-before.json')==load(epoch/'source-after.json')
            for q in ['queue-before-lock.json','queue-inside-before.json','queue-inside-after.json','queue-after-unlock.json']:assert load(epoch/q)['clear']
        for tag in ['value-parser-new-v5','value-continue-v5']:
            before=load(dest/'evidence/pending/epochs'/tag/'source-before.json');assert before['candidate13']==source['files'] and len(before['primary_C'])==463
        parser_log=(dest/'evidence/pending/epochs/value-parser-new-v5/process.log').read_text(encoding='utf8')
        line=next(s for s in parser_log.splitlines() if s.startswith('NE297_VALUE_DOMAIN_CONTROL '))
        controls=json.loads(line.split(' ',1)[1]);assert controls['raw_equality'] is False
        for k in ['same_save_value','changed_item_rejected','transfer_rejected','changed_version_rejected','missing_rejected','extra_rejected']:assert controls[k] is True
        assert (controls['original_item_type'],controls['parsed_item_type'],controls['original_version_type'],controls['parsed_version_type'])==(21,4,2,3)
        helper=dest/'evidence/focused-v5';original=load(helper/'receipt.json');review=load(helper/'independent-review.json')
        assert original['accepted'] is False and original['exit_code']==0 and original['source_exact'] and original['c_unchanged'] and original['all_four_queue_gates']
        assert review['accepted'] and review['checks']==152 and review['failures']==0 and review['migration_checks']==38 and review['pure_story_plan_checks']==114 and review['new_schema_controls']==19
        assert original['diagnostics']==review['expected_warnings'] and len(original['diagnostics'])==2
        log=(helper/'engine.log').read_text(encoding='utf8');assert 'checks: 152, failures: 0' in log and not re.search(r'SCRIPT ERROR|Parse Error|^ERROR:|ObjectDB.*leak|were leaked|resources still in use|RID.*leak',log,re.M)
        # All historical failures retain their actual exit/log/diagnostic and source receipts.
        history={}
        for tag in ['new-continue-v1','state-continue-v2','final-continue-v3']:
            epoch=dest/'evidence/pending/epochs'/tag;r=load(epoch/'completion.json');p=load(epoch/'process.json');assert not r['accepted'];history[tag]={'exit':p['exit_code'],'diagnostics':p['diagnostics']}
        module_spec=importlib.util.spec_from_file_location('pending_reader',root/'read_pending.py');module=importlib.util.module_from_spec(module_spec);module_spec.loader.exec_module(module)
        expected=load(root/'expected.json');rawroot=dest/'raw/final-save-v4';result=module.verify(rawroot,expected)
        assert (root/'pending-first-line.png').read_bytes()==(rawroot/'pending-first-line.png').read_bytes()
        assert (rawroot/'pending-original.json').read_bytes()==(dest/'raw/original-old-slot/slot.json').read_bytes()
        old=load(rawroot/'pending-old-proof.json');new=load(rawroot/'pending-new-proof.json')
        mutations=[lambda x:x.update(starts=2),lambda x:x.update(talks=2),lambda x:x.update(credits=18),lambda x:x.update(source_id='npc:ch1_egret@54,17'),lambda x:x.update(pending_cleared=False),lambda x:x['items']['held'].append('counterfeit'),lambda x:x['read_lines'][0].update(text='changed')]
        rejected=0
        for mutate in mutations:
            changed=copy.deepcopy(new);mutate(changed)
            try:module.validate(old,changed,expected)
            except AssertionError:rejected+=1
        assert rejected==len(mutations)
        equality=load(rawroot/'pending-equality-witness.json');assert equality['raw_items_equal'] is False and all(equality[k] for k in ['credits_equal','saved_value_items_equal','claims_equal'])
    assert index['official_accepted'] is False and index['second_canonical_cold_accepted'] is False and index['region_world_UI_accepted'] is False
    if require_official:raise AssertionError('Official87, same-canonical second cold and region/world UI not supplied; intentionally not accepted')
    return {'accepted':True,'candidate13':13,'focused_checks':152,'expected_atomic_refusal_warnings':2,'seven_dialogue_lines':7,'independent_semantic_negatives_rejected':rejected,'typed_domain_controls':controls,'raw_and_PNG':result,'historical_reds_preserved':history,'official_accepted':False,'second_canonical_cold_accepted':False,'region_world_UI_accepted':False}
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('root',type=Path,nargs='?',default=Path(__file__).resolve().parent);parser.add_argument('--require-official',action='store_true');args=parser.parse_args();print(json.dumps(verify(args.root,args.require_official),indent=2,ensure_ascii=True))
