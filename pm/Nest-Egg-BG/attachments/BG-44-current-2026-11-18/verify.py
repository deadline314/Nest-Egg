from pathlib import Path,PurePosixPath
import hashlib,json,re,sys,tempfile,zipfile
from PIL import Image
from verify_bg44_current_20261118 import verify as verify_case
def verify(folder):
 folder=folder.resolve();m=json.loads((folder/'manifest.json').read_text());archives={}
 for name,digest in m['readers'].items():assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==digest
 try:
  for name,digest in m['archives'].items():
   assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==digest,'Archive digest mismatch'
   archives[name]=zipfile.ZipFile(folder/name)
  for name,z in archives.items():
   expected={f['member'] for f in m['files'].values() if f['archive']==name};assert set(z.namelist())==expected and len(z.namelist())==len(expected)
  with tempfile.TemporaryDirectory(prefix='.ne-bg44-verify-',dir=folder) as temporary:
   root=Path(temporary).resolve();assert root.parent==folder and root.name.startswith('.ne-bg44-verify-')
   for name,e in m['files'].items():
    rel=PurePosixPath(name);assert not rel.is_absolute() and '..' not in rel.parts
    p=(root/name).resolve();assert p.is_relative_to(root) and p!=root
    value=archives[e['archive']].read(e['member']);assert hashlib.sha256(value).hexdigest()==e['sha256'],name
    p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(value)
   def data(n):return json.loads((root/n).read_text(encoding='utf-8'))
   before,after=data('source-base.json'),data('source-v2.json');assert len(before)==10090 and len(after)==10092
   changes={'data/audio/ambience.json','data/audio/music.json','data/audio/footsteps.json','tools/level/build_ch3.py','data/environment/themes/ch3_mezzanine.tres','data/levels/ch3_pump.tres','data/levels/ch3_layout_v2.json','data/levels/ch3_mezzanine_map.json','tools/level/test_ch3_layout.py'}
   added={'data/lighting/pump_room.tres','data/environment/materials/mezzanine_steel_plate.tres'}
   assert set(after)-set(before)==added and {p for p in before if before[p]!=after[p]}==changes
   for phase in ['formal-v2','flat-v2','states-v3','checks-v2']:assert data(phase+'/source-before.json')==data(phase+'/source-after.json')==after
   for phase in ['formal-v2','flat-v2']:assert data(phase+'/result.json')['native_engine_gates_passed']
   assert data('states-v3/result.json')['passed'] and data('checks-v2/result.json')['all_passed']
   generator=data('generator-tests.json');assert generator['actual_exit']==0 and generator['tests']==6 and generator['source_sha256']==after['tools/level/test_ch3_layout.py']
   for rel in changes|added:assert hashlib.sha256((root/'source'/rel).read_bytes()).hexdigest()==after[rel]
   for name,profile in [('power_room-before','power_room'),('transfer-before','transfer')]:
    assert hashlib.sha256((root/'replay'/(name+'.tres')).read_bytes()).hexdigest()==before['data/lighting/'+profile+'.tres']
   assert hashlib.sha256((root/'replay/mezzanine-before-theme.tres').read_bytes()).hexdigest()==before['data/environment/themes/ch3_mezzanine.tres']
   assert data('source/data/audio/footsteps.json')['materials']['mezzanine_steel_plate']=='metal'
   assert data('source/data/audio/ambience.json')['profiles']['pump_room']==data('source/data/audio/ambience.json')['profiles']['power_room']
   assert data('source/data/audio/music.json')['map']['zones']['pump_room']==data('source/data/audio/music.json')['map']['zones']['power_room']
   proof=data('baseline-proof.json');assert proof['original_bg44']=='c80f5483fbb56f0f7f3feb15c782cb5625af0f5a' and len(proof['rows'])==2
   delta=data('replay/prop-delta.json')
   for row in proof['rows']:
    level=row['level'];assert delta[level]['added']==row['added'] and not row['removed']
    assert hashlib.sha256((root/(('pump' if level=='ch3_pump' else 'mezzanine')+'-original-map.json')).read_bytes()).hexdigest()==row['original_map_sha256']
   pipeline=data('pipeline-extract.json');assert len(pipeline['props'])==4 and {p['seed'] for p in pipeline['props']}==set(range(7601,7605))
   for p in pipeline['props']:
    ident=p['id'];tres=(root/'assets'/(ident+'.tres')).read_text();size=re.search(r'^size = Vector2\(([^,]+),\s*([^)]+)\)',tres,re.M)
    assert size and abs(float(size[2])-p['height_m']*30)<.11
    with Image.open(root/'assets'/(ident+'.png')) as im:assert im.mode=='RGBA' and im.getchannel('A').getextrema()[0]==0
   cases=[verify_case(root/'formal-v2'/r['name']) for r in data('formal-v2/runs.json')];assert len(cases)==4 and all(r['passed'] for r in cases)
   assert sum(r['cells'] for r in cases)==80 and sum(r['standable'] for r in cases)==54 and sum(r['enemy_observations'] for r in cases)==14
   raw_records=0
   for phase,key,expected in [('formal-v2','bg44',9),('flat-v2','bg44_flat',3)]:
    runs=data(phase+'/runs.json');assert len(runs)==4
    for run in runs:
     assert run['exit']==run['script_errors']==0 and not run['engine_error'] and run['source_held']
     quality=run['name'].rsplit('-',1)[1];f=root/phase/run['name']/run['name'].rsplit('-',1)[0];index=json.loads((f/'bg44-index.json').read_text())
     assert index['probe']['adapter']=='AMD Radeon RX 9070 XT' and index['probe']['engine'].startswith('4.7.2') and index['probe']['quality']==(0 if quality=='low' else 2)
     assert len(index['shots'])==int(index['columns'])*int(index['rows'])==20
     for shot in index['shots']:
      group=shot[key];assert group['controls_valid'] and len(group['records'])==expected
      if phase=='flat-v2':assert group['records'][0]['raw_sha256']==group['records'][2]['raw_sha256']
      for r in group['records']:
       assert hashlib.sha256((f/r['files']['raw']).read_bytes()).hexdigest()==r['raw_sha256']
       with Image.open(f/r['files']['png']) as im:assert im.size==(640,360)
       raw_records+=1
   assert raw_records==960
   for q in ['low','high']:
    states=data('states-v3/'+q+'/states.json');assert states['actual_talks'] and states['hand_captured'] and len(states['rows'])==11
    assert [r['option'] for r in states['selected']]==['drain','branch','power']
    for row in states['rows']:
     assert row['quality']==(0 if q=='low' else 2)
     with Image.open(root/'states-v3'/q/(row['name']+'.png')) as im:assert im.size==(640,360)
     if 'npc' in row:assert row['in_range'] and row['prompt_visible']
    rows={r['name']:r for r in states['rows']}
    assert rows['wheel-hand-turn']['phase']=='turn' and rows['wheel-hand-turn']['contact_error']<=.25
    assert rows['wheel-before']['progress']==0 and 0<rows['wheel-dial-mid']['progress']<1 and abs(rows['wheel-drained']['progress']-1)<1e-12
    assert rows['panel-open']['swapped'] and abs(rows['panel-open']['closed_bottom']-rows['panel-open']['open_bottom'])<.01
    assert rows['notice-after']['notice_seen']
    aligned=rows['notice-aligned'];assert abs(aligned['prop'][1]+aligned['size'][1]-aligned['npc_position'][1])<.01 and abs(aligned['prop'][0]-aligned['npc_position'][0])<16
   log=(root/'checks-v2/changed/raw.log').read_text(encoding='utf-8');match=re.search(r'checks: (\d+), new failures: (\d+), known failures \(tests/known_failures.txt\): (\d+)',log)
   assert match and int(match[1])>0 and match.groups()[1:]==('0','0')
   assert '總計：0 錯誤、0 警告' in (root/'checks-v2/scene-report/raw.log').read_text(encoding='utf-8')
   assert root.parent==folder and root.name.startswith('.ne-bg44-verify-')
   return {'passed':True,'cases':4,'normal_cells':80,'standable':54,'enemy_observations':14,'normal_hdr':720,'flat_hdr':240,'state_png':22,'point_decreases':sum(len(r['point_decreases']) for r in cases),'changed_checks':int(match[1]),'logical_members':len(m['files'])}
 finally:
  for z in archives.values():z.close()
if __name__=='__main__':print(json.dumps(verify(Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).parent),indent=2))
