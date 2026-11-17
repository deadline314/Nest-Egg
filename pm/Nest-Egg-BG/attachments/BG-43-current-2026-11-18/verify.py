from pathlib import Path,PurePosixPath
import hashlib,json,re,sys,tempfile,zipfile
from PIL import Image
from verify_bg43_current_20261118 import verify as verify_case
def verify(folder):
 folder=folder.resolve();m=json.loads((folder/'manifest.json').read_text());archives={}
 for name,digest in m['readers'].items():assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==digest
 try:
  for name,digest in m['archives'].items():
   assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==digest,'Archive digest mismatch'
   archives[name]=zipfile.ZipFile(folder/name)
  for name,z in archives.items():
   expected={f['member'] for f in m['files'].values() if f['archive']==name};assert set(z.namelist())==expected and len(z.namelist())==len(expected)
  with tempfile.TemporaryDirectory(prefix='.ne-bg43-verify-',dir=folder) as temporary:
   root=Path(temporary).resolve();assert root.parent==folder and root.name.startswith('.ne-bg43-verify-')
   for name,e in m['files'].items():
    rel=PurePosixPath(name);assert not rel.is_absolute() and '..' not in rel.parts
    p=(root/name).resolve();assert p.is_relative_to(root) and p!=root
    value=archives[e['archive']].read(e['member']);assert hashlib.sha256(value).hexdigest()==e['sha256'],name
    p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(value)
   def data(n):return json.loads((root/n).read_text(encoding='utf-8'))
   before,after=data('source-base.json'),data('source-v2.json');assert len(before)==10088 and len(after)==10090
   changes={'data/audio/ambience.json','data/audio/music.json','data/audio/footsteps.json','tools/level/build_ch3.py','data/environment/themes/ch3_plaza.tres','data/levels/ch3_plaza.tres'}
   added={'data/lighting/plaza.tres','data/environment/materials/plaza_asphalt.tres'}
   assert set(after)-set(before)==added and {p for p in before if before[p]!=after[p]}==changes
   for phase in ['formal-v2','flat-v2','states-v4','checks-v2']:assert data(phase+'/source-before.json')==data(phase+'/source-after.json')==after
   for phase in ['formal-v2','flat-v2']:assert data(phase+'/result.json')['native_engine_gates_passed']
   assert data('states-v4/result.json')['passed'] and data('checks-v2/result.json')['all_passed']
   for rel in changes|added:assert hashlib.sha256((root/'source'/rel).read_bytes()).hexdigest()==after[rel]
   assert hashlib.sha256((root/'replay/before-profile.tres').read_bytes()).hexdigest()==before['data/lighting/market.tres']
   assert data('source/data/audio/footsteps.json')['materials']['plaza_asphalt']=='wet'
   assert data('source/data/audio/ambience.json')['profiles']['plaza']==data('source/data/audio/ambience.json')['profiles']['market']
   assert data('source/data/audio/music.json')['map']['zones']['plaza']==data('source/data/audio/music.json')['map']['zones']['market']
   proof=data('baseline-proof.json');assert proof['original_bg43']=='245fa0d563336de8e351c41675843f053b0ed140' and proof['old_props']==5 and len(proof['added'])==3 and not proof['removed']
   delta=data('replay/prop-delta.json')['ch3_plaza'];assert delta['added']==proof['added'] and delta['original_doors']==['plaza_lift','plaza_ladder']
   for name in ['map','level']:assert hashlib.sha256((root/('original-'+name+('.json' if name=='map' else '.tres'))).read_bytes()).hexdigest()==proof['original_sha256'][name]
   pipeline=data('pipeline-extract.json');assert len(pipeline['props'])==4 and {p['seed'] for p in pipeline['props']}==set(range(7501,7505))
   for p in pipeline['props']:
    ident=p['id'];tres=(root/'assets'/(ident+'.tres')).read_text();size=re.search(r'^size = Vector2\(([^,]+),\s*([^)]+)\)',tres,re.M)
    assert size and abs(float(size[2])-p['height_m']*30)<.11
    with Image.open(root/'assets'/(ident+'.png')) as im:assert im.mode=='RGBA' and im.getchannel('A').getextrema()[0]==0
   cases=[verify_case(root/'formal-v2'/r['name']) for r in data('formal-v2/runs.json')];assert len(cases)==2 and all(r['passed'] for r in cases)
   assert sum(r['cells'] for r in cases)==40 and sum(r['standable'] for r in cases)==12 and sum(r['enemy_observations'] for r in cases)==0
   raw_records=0
   for phase,key,expected in [('formal-v2','bg43',9),('flat-v2','bg43_flat',3)]:
    runs=data(phase+'/runs.json');assert len(runs)==2
    for run in runs:
     assert run['exit']==run['script_errors']==0 and not run['engine_error'] and run['source_held']
     quality=run['name'].rsplit('-',1)[1];f=root/phase/run['name']/'ch3_plaza';index=json.loads((f/'bg43-index.json').read_text())
     assert index['probe']['adapter']=='AMD Radeon RX 9070 XT' and index['probe']['engine'].startswith('4.7.2') and index['probe']['quality']==(0 if quality=='low' else 2)
     assert len(index['shots'])==int(index['columns'])*int(index['rows'])==20
     for shot in index['shots']:
      group=shot[key];assert group['controls_valid'] and len(group['records'])==expected
      if phase=='flat-v2':assert group['records'][0]['raw_sha256']==group['records'][2]['raw_sha256']
      for r in group['records']:
       assert hashlib.sha256((f/r['files']['raw']).read_bytes()).hexdigest()==r['raw_sha256']
       with Image.open(f/r['files']['png']) as im:assert im.size==(640,360)
       raw_records+=1
   assert raw_records==480
   for q in ['low','high']:
    states=data('states-v4/'+q+'/states.json');assert states['actual_npc_talks'] and not states['seeded_story_flags'] and len(states['rows'])==22 and len(states['routes'])==6
    assert [r['option'] for r in states['selected_choices']]==['drain','branch','power']
    for row in states['rows']:
     assert row['quality']==(0 if q=='low' else 2)
     with Image.open(root/'states-v4'/q/(row['name']+'.png')) as im:assert im.size==(640,360)
     if 'npc' in row:assert row['in_range'] and row['prompt_visible']
     for r in row.get('reactions',[]):
      if r['reaction']=='plaza_outer_ladder':assert abs(r['down_top'][1]+r['down_size'][1]-r['floor'])<.01
   log=(root/'checks-v2/changed/raw.log').read_text(encoding='utf-8');match=re.search(r'checks: (\d+), new failures: (\d+), known failures \(tests/known_failures.txt\): (\d+)',log)
   assert match and int(match[1])>0 and match.groups()[1:]==('0','0')
   assert '總計：0 錯誤、0 警告' in (root/'checks-v2/scene-report/raw.log').read_text(encoding='utf-8')
   assert root.parent==folder and root.name.startswith('.ne-bg43-verify-')
   return {'passed':True,'cases':2,'normal_cells':40,'standable':12,'enemy_observations':0,'normal_hdr':360,'flat_hdr':120,'state_png':44,'point_decreases':sum(len(r['point_decreases']) for r in cases),'changed_checks':int(match[1]),'logical_members':len(m['files'])}
 finally:
  for z in archives.values():z.close()
if __name__=='__main__':print(json.dumps(verify(Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).parent),indent=2))
