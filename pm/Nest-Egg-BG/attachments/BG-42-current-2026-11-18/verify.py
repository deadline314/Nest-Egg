from pathlib import Path,PurePosixPath
import hashlib,json,re,sys,tempfile,zipfile
from PIL import Image
from verify_bg42_final_20261118 import verify as verify_case

def verify(folder):
    folder=folder.resolve();packet_folder=folder;manifest=json.loads((folder/'manifest.json').read_text(encoding='utf-8'));archives={}
    for name,digest in manifest['readers'].items():assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==digest,name
    try:
        for name,digest in manifest['archives'].items():
            assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==digest,'Archive digest mismatch'
            archives[name]=zipfile.ZipFile(folder/name)
        for name,z in archives.items():
            expected={f['member'] for f in manifest['files'].values() if f['archive']==name}
            assert set(z.namelist())==expected and len(z.namelist())==len(expected)
        # Cleanup is confined to this verified, newly owned child of the packet directory.
        with tempfile.TemporaryDirectory(prefix='.ne-bg42-verify-',dir=folder) as temporary:
            root=Path(temporary).resolve();assert root.parent==folder and root.name.startswith('.ne-bg42-verify-')
            for name,entry in manifest['files'].items():
                rel=PurePosixPath(name);assert not rel.is_absolute() and '..' not in rel.parts
                path=(root/name).resolve();assert path.is_relative_to(root) and path!=root
                value=archives[entry['archive']].read(entry['member']);assert hashlib.sha256(value).hexdigest()==entry['sha256'],name
                path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(value)
            def data(name):return json.loads((root/name).read_text(encoding='utf-8'))
            source=data('source-final.json');baseline=data('source-base.json')
            assert len(source)==len(baseline)==10088
            assert {p for p in source if source[p]!=baseline[p]}=={'data/lighting/ledger_office_interior.tres','data/lighting/lounge_front.tres'}
            for phase in ['formal-final','flat-final','states-final','checks-final']:assert data(phase+'/source-before.json')==data(phase+'/source-after.json')==source
            assert data('formal-final/result.json')['native_engine_gates_passed'] and data('flat-final/result.json')['native_engine_gates_passed'] and data('states-final/result.json')['passed'] and data('checks-final/result.json')['all_passed']
            for rel in ['data/lighting/ledger_office_interior.tres','data/lighting/lounge_front.tres']:
                assert hashlib.sha256((root/'source'/Path(rel).name).read_bytes()).hexdigest()==source[rel]
            proof=data('baseline-proof.json');delta=data('replay/prop-delta.json');assert len(proof)==3
            for row in proof:
                level=row['level'];current=data('source/'+level+'_map.json');old=data(level+'-historical-before-map.json');then=data(level+'-original-authored-map.json')
                assert row['removed']==delta[level]['removed'] and row['added']==delta[level]['added']
                assert all(p in old['props'] for p in row['removed']) and all(p in then['props'] and p in current['props'] for p in row['added'])
            cfg=data('pipeline-extract.json');assert len(cfg['props'])==4 and {p['seed'] for p in cfg['props']}=={7401,7403,7404,7412}
            for p in cfg['props']:
                ident=p['id'];tres=(root/'assets'/(ident+'.tres')).read_text();size=re.search(r'^size = Vector2\(([^,]+),\s*([^)]+)\)',tres,re.M)
                assert size and abs(float(size[2])-p['height_m']*30)<.11
                with Image.open(root/'assets'/(ident+'.png')) as im:assert im.mode=='RGBA' and im.getchannel('A').getextrema()[0]==0
            results=[]
            for run in data('formal-final/runs.json'):
                result=verify_case(root/'formal-final'/run['name']);assert result['absolute_pass'] and result['no_worse'];results.append(result)
            assert len(results)==6 and sum(r['cells'] for r in results)==60 and sum(r['standable'] for r in results)==42 and sum(r['enemy_observations'] for r in results)==4
            png_slots=0;raw_slots=0
            for phase,key,expected_records in [('formal-final','bg42',9),('flat-final','bg42_flat',3)]:
                runs=data(phase+'/runs.json');assert len(runs)==6
                for run in runs:
                    assert run['exit']==run['script_errors']==0 and not run['engine_error'] and run['source_held']
                    level=run['name'].rsplit('-',1)[0];quality=run['name'].rsplit('-',1)[1];folder=root/phase/run['name']/level;index=json.loads((folder/'bg42-index.json').read_text())
                    assert index['probe']['adapter']=='AMD Radeon RX 9070 XT' and index['probe']['engine'].startswith('4.7.2') and index['probe']['quality']==(0 if quality=='low' else 2)
                    assert len(index['shots'])==int(index['rows'])*int(index['columns'])
                    for shot in index['shots']:
                        group=shot[key];records=group['records'];assert group['controls_valid'] and len(records)==expected_records
                        if phase=='flat-final':assert records[0]['raw_sha256']==records[2]['raw_sha256']
                        for record in records:
                            assert record['width']==640 and record['height']==360
                            with Image.open(folder/record['files']['png']) as im:assert im.size==(640,360)
                            assert hashlib.sha256((folder/record['files']['raw']).read_bytes()).hexdigest()==record['raw_sha256'];raw_slots+=1
                        png_slots+=1
            assert png_slots==120 and raw_slots==720
            for quality in ['low','high']:
                states=data('states-final/'+quality+'/states.json');assert len(states['rows'])==5 and states['actual_npc_talks'] and states['ledger_taken'] and states['ledger_owned'] and states['audit_submitted']
                assert states['seeded_preconditions']==['ch2_yong_subdued','ch2_egret_returned','ch2_market_reconciled']
                for row in states['rows']:
                    assert row['quality']==(0 if quality=='low' else 2)
                    with Image.open(root/'states-final'/quality/(row['name']+'.png')) as im:assert im.size==(640,360)
                    if row['name'] in ['isolation-diagram-and-box','cabinet-before','terminal-before']:assert row['in_range'] and row['prompt_visible']
            log=(root/'checks-final/changed/raw.log').read_text(encoding='utf-8');m=re.search(r'checks: (\d+), new failures: (\d+), known failures \(tests/known_failures.txt\): (\d+)',log)
            assert m and tuple(map(int,m.groups()))==(45331,0,0)
            assert '總計：0 錯誤、0 警告' in (root/'checks-final/scene-report/raw.log').read_text(encoding='utf-8')
            assert root.parent==packet_folder and root.name.startswith('.ne-bg42-verify-')
            return {'passed':True,'cases':6,'normal_cells':60,'standable':42,'enemy_view_observations':4,'normal_logical_hdr_records':540,'flat_logical_hdr_records':180,'staging_cells':120,'interaction_png':10,'changed_checks':45331,'logical_members':len(manifest['files'])}
    finally:
        for z in archives.values():z.close()
if __name__=='__main__':print(json.dumps(verify(Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).parent),indent=2))
