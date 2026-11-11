from pathlib import Path
import argparse,hashlib,json,re,subprocess,zipfile

RESTORE='通訊結束後拾取紀錄回來'
EXPIRY='時間到後全部淡出，閒置時不再每影格更新'
TEST='tests/suite/test_combat_hud.gd'
SIX={'ui/settings_screen.gd','ui/kit/ui_theme.gd','ui/codex_screen.gd','ui/death_screen.gd',
     'tests/helpers/settings_device_checks.gd','tests/suite/test_ui_screens.gd'}
def require(value,message):
    if not value: raise ValueError(message)

def main():
    p=argparse.ArgumentParser();p.add_argument('--index',type=Path,default=Path(__file__).with_name('index.json'))
    p.add_argument('--repo',type=Path);p.add_argument('--raw-root',type=Path);a=p.parse_args()
    index=json.loads(a.index.read_bytes());path=a.index.parent/index['proof']['path']
    require(path.stat().st_size==index['proof']['bytes'] and hashlib.sha256(path.read_bytes()).hexdigest()==index['proof']['sha256'],'proof archive mismatch')
    z=zipfile.ZipFile(path)
    require(set(z.namelist())==set(index['proof']['members']),'proof member set')
    for name,sha in index['proof']['members'].items(): require(hashlib.sha256(z.read(name)).hexdigest()==sha,'member hash: '+name)
    related=json.loads(z.read('source-eligibility.json'))
    require(len(related)==9 and all(e['same_bytes'] and e['published_sha256']==e['shadow_sha256'] for e in related),'published nine mismatch')
    if a.repo:
        for e in related:
            raw=subprocess.check_output(['git','show',index['base']+':'+e['path']],cwd=a.repo)
            require(hashlib.sha256(raw).hexdigest()==e['published_sha256'],'git published source: '+e['path'])
    m=json.loads(z.read('candidate/manifest.json'));old=z.read('candidate/test_combat_hud-before.gd');new=z.read('candidate/test_combat_hud-candidate.gd')
    require(hashlib.sha256(old).hexdigest()==m['before_sha256'] and hashlib.sha256(new).hexdigest()==m['candidate_sha256'],'candidate bytes')
    before=b'\tStory._layer.cancel_radio()\n\tawait frames(2)\n\tcheck(feed.visible'
    after=b'\tStory._layer.cancel_radio()\n\t# Feed visibility is published by _process; physics ticks can finish before any UI update.\n\tawait runner.get_tree().create_timer(0.0, true, false, true).timeout\n\tcheck(feed.visible'
    require(old.count(before)==1 and old.replace(before,after,1)==new and new.replace(after,before,1)==old,'more than single reversible wait change')
    sources={};reports={}
    for case in index['cases']:
        prefix='cases/'+case+'/'
        report=json.loads(z.read(prefix+'observations.json'));receipt=json.loads(z.read(prefix+'exit.json'))
        source=json.loads(z.read(prefix+'source-before.json'));sources[case]=source;reports[case]=report
        require(receipt['sources_unchanged'] and source==receipt['source_after'],'source changed: '+case)
        for _,sha in source.items(): require(hashlib.sha256(z.read('source-objects/'+sha+'.bytes')).hexdigest()==sha,'actual source bytes: '+case)
        log=z.read(prefix+'run.log').decode('utf8',errors='replace')
        require('SCRIPT ERROR' not in log and not any(l.startswith('ERROR:') for l in log.splitlines()),'engine error: '+case)
        require(not re.search(r'ObjectDB.*leak|RID.*leak|resources still in use',log,re.I),'cleanup leak: '+case)
        require(report['checks']==12,'assertion count: '+case)
        rows=report['observations'];checks=[r for r in rows if r['event']=='assertion']
        restore=next(r for r in checks if r['message']==RESTORE)
        close=[r for r in rows if r['event']=='radio_visibility_changed' and not r['radio_visible'] and r.get('feed_lines') and r['time_usec']<=restore['time_usec']][-1]
        require(len(restore['feed_lines'])==4 and not restore['radio_visible'],'restoration data: '+case)
        fixed=case.endswith('-v4');negative='frozen-negative' in case;slow=not fixed and '-60-60-' not in case
        if fixed:
            require(report['test_variant']=='restore-post-process' and report['test_source_sha256']==m['candidate_sha256'] and source[TEST]==m['candidate_sha256'],'incorrect final metadata/source')
            require('incorrectly' in report['metadata_correction'] and 'post-process' in report['restore_wait'],'metadata correction not explicit')
            require(restore['process_signals']>close['process_signals'],'post-process publication absent')
            require(report['negative_freeze_feed']==negative and report['freeze_applied']==negative,'fault-control declaration')
            expected=[RESTORE,EXPIRY] if negative else []
            require(report['failures']==expected and receipt['exit']==(1 if negative else 0),'fixed original assertions: '+case)
            require(restore['condition']==(not negative) and restore['feed_visible']==(not negative) and restore['feed_processing']==(not negative),'fault control bypassed')
        else:
            require(source[TEST]==m['before_sha256'],'baseline assertion source')
            require(report['failures']==([RESTORE] if slow else []) and receipt['exit']==(1 if slow else 0),'original clock result: '+case)
            if slow:
                require(restore['process_signals']==close['process_signals'] and restore['physics_frame']==close['physics_frame']+2,'physics/process cause absent')
                require(not restore['condition'] and not restore['feed_visible'] and restore['feed_processing'] and restore['feed_can_process'],'not the observed publication race')
    for hz,cap in [(60,60),(240,30),(120,30)]:
        left=sources[f'baseline-{hz}-{cap}-v2'];right=sources[f'candidate-{hz}-{cap}-v2']
        require({key for key in left if left[key]!=right[key]}==SIX,'baseline/six changed more than six')
    fixed=[sources[c] for c in index['cases'] if c.endswith('-v4')]
    require(all(s==fixed[0] for s in fixed),'positive/negative source changed')
    if a.raw_root:
        raw=a.raw_root/index['external_raw']['path']
        require(raw.stat().st_size==index['external_raw']['bytes'] and hashlib.sha256(raw.read_bytes()).hexdigest()==index['external_raw']['sha256'],'external complete raw')
        manifest=json.loads((a.raw_root/index['external_full_index']['path']).read_bytes())
        require(hashlib.sha256((a.raw_root/index['external_full_index']['path']).read_bytes()).hexdigest()==index['external_full_index']['sha256'],'external full index')
        with zipfile.ZipFile(raw) as all_raw:
            require(set(all_raw.namelist())==set(manifest['members']),'external member set')
            for name,sha in manifest['members'].items(): require(hashlib.sha256(all_raw.read(name)).hexdigest()==sha,'external raw member: '+name)
    print('NE291_READER: published nine/source objects verified; six-only control 60/60 green and two faster-physics modes red; corrected V4 36/0; frozen-feed negative 12/2 rejected; single reversible wait; original assertions/expiry retained.')

if __name__=='__main__': main()
