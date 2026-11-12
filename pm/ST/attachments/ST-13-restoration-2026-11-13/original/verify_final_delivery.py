"""Read-only ST13 final-source clocks/UI/refusal replay; accepts a relocated raw root."""
import argparse,hashlib,json,re
from pathlib import Path
def load(p):return json.loads(p.read_text(encoding='utf8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def verify(root,require_official):
    manifest=load(root/'catalog-delivery-v2/stage-manifest.json')
    assert manifest['actual_base']=='20f9dddf8c57a9f8727442f661f5f7cb6236f872' and len(manifest['files'])==8
    for n,item in manifest['files'].items():assert sha(root/'catalog-delivery-v2/candidate'/n)==item['sha256']
    for name,checks,failures in [('final-hint-permanent-red-v1',19,2),('final-hint-permanent-green-v1',19,0)]:
        p=root/name;x=load(p/'measurement.json');process=load(p/'process.json')
        assert x['checks']==checks and len(x['failures'])==failures and not process['diagnostics']
        assert process['exit_code']==(1 if failures else 0)
        assert load(p/'before.json')==load(p/'after.json')
    clocks=[]
    for name,count,refusal in [('final-main-v1-count2',2,False),('final-main-v1-count3',3,False),('final-main-refusal-v1-count2',2,True)]:
        p=root/name;x=load(p/'measurement.json');process=load(p/'process.json');before=load(p/'before.json')
        assert before==load(p/'after.json') and before['base']==manifest['actual_base']
        assert all(before['tracked_source_sha256'][n]==v['sha256'] for n,v in manifest['files'].items())
        assert process['exit_code']==0 and not process['diagnostics'] and x['target_count']==count
        assert '--headless' in process['command'] and '--verbose' not in process['command']
        assert x['transition_fixture']=={'original_headless_instant':True,'enabled_original_timed_transition':True}
        m=x['measurement'];c=x['control'];zero=m['health_zero_usec']
        assert abs(c['zero_to_control_msec']-(c['first_movement_usec']-zero)/1000)<1e-7
        assert c['first_movement_usec']-zero<=3000000 and c['ST13_le_3000msec']
        assert c['new_Level_id']!=c['source_Level_id'] and len(c['load_events'])==1 and c['end'][0]>c['start'][0]
        assert c['deaths_exact'] and c['credits_exact'] and c['public_action']=='move_right' and c['synthetic']
        assert x['retry_input']['action']=='ui_accept' and not x['retry_input']['direct_handler_call']
        assert all(v==1 for v in m['raw_time_scales']) and c['clock']['max_fps']==0 and c['clock']['physics_ticks_per_second']==60
        assert x['audio_shutdown']['begin_usec']>=c['first_movement_usec']
        if refusal:
            f=x['refusal'];assert all(f[n] for n in ['real_tmp_directory','same_dead_Level','retry_only','primary_exact','backup_exact','deaths_exact','credits_exact'])
            assert f['purpose']=='respawn' and f['writer_issues']
        clocks.append(dict(case=name,complete_control_msec=c['zero_to_control_msec'],refusal=refusal))
    suites=root/'final-two-suites-v1';raw=(suites/'process.log').read_text(encoding='utf8')
    assert 'checks: 486, failures: 0' in raw and not re.search('SCRIPT ERROR|Parse Error',raw)
    errors=[l for l in raw.splitlines() if l.startswith('ERROR:')]
    assert len(errors)==1 and '沒有電話亭可登記' in errors[0]
    assert load(suites/'before.json')==load(suites/'after.json')
    old=root/'catalog-official-v1';oldgate=load(old/'source-gate.json')
    assert not oldgate['overall_accepted'] and oldgate['count_after']-oldgate['count_before']==12
    a=load(old/'source-before.json')['files'];b=load(old/'source-after.json')['files']
    assert all(b.get(n)==v for n,v in a.items())
    new=root/'catalog-official-v2';official_pending=not(new/'source-gate.json').exists()
    if require_official:
        assert not official_pending,'Final official source-after/exit gate is pending'
        gate=load(new/'source-gate.json');assert gate['overall_accepted'] and gate['all_files_exact'] and gate['original_entry_exit']==0 and not gate['SCRIPT_or_Parse_errors']
        assert load(new/'source-before.json')==load(new/'source-after.json')
    print(json.dumps(dict(scope='Read-only final eight-source proof; native pixel/readiness is independently verified by verify_native_layout_v3.py',clocks=clocks,hint_regression='19/2 ->19/0',original_two_suites='486/0,1 existing expected no-booth ERROR retained',prior_official_inventory_rejection_preserved=True,final_official_pending=official_pending),indent=2))
if __name__=='__main__':
    a=argparse.ArgumentParser();a.add_argument('--raw-root',type=Path,default=Path(__file__).resolve().parent);a.add_argument('--require-official',action='store_true');v=a.parse_args();verify(v.raw_root,v.require_official)
