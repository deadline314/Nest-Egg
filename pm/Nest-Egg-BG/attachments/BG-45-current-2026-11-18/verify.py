from pathlib import Path,PurePosixPath
import hashlib,json,re,shutil,sys,tempfile,zipfile
from PIL import Image
from verify_bg45_current_20261118 import verify as verify_case
from verify_bg45_sun_20261118 import verify as verify_sun
LEVELS=['ch3_clinic','ch3_glass_edge','ch3_showroom','ch3_office_hall']
def verify(folder):
 folder=folder.resolve();m=json.loads((folder/'manifest.json').read_text());archives={}
 for name,digest in m['readers'].items():assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==digest
 try:
  for name,digest in m['archives'].items():
   assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==digest,'Archive digest mismatch'
   archives[name]=zipfile.ZipFile(folder/name)
  for name,z in archives.items():
   members={f['member'] for f in m['files'].values() if f['archive']==name};assert set(z.namelist())==members and len(z.namelist())==len(members)
  with tempfile.TemporaryDirectory(prefix='.ne-bg45-verify-',dir=folder) as temporary:
   root=Path(temporary).resolve();assert root.parent==folder and root.name.startswith('.ne-bg45-verify-')
   for name,e in m['files'].items():
    rel=PurePosixPath(name);assert not rel.is_absolute() and '..' not in rel.parts
    p=(root/name).resolve();assert p.is_relative_to(root) and p!=root
    data=archives[e['archive']].read(e['member']);assert hashlib.sha256(data).hexdigest()==e['sha256'],name
    p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
   def data(name):return json.loads((root/name).read_text(encoding='utf-8'))
   before,after=data('source-base.json'),data('source-v2.json');assert len(before)==10092 and len(after)==10094
   changes={'data/audio/ambience.json','data/levels/ch3_office_hall.tres','data/levels/ch3_showroom.tres','tools/level/build_ch3.py','data/levels/ch3_showroom_map.json','tools/level/test_ch3_layout.py'}
   added={'data/lighting/showroom_day.tres','data/lighting/reception_white.tres'}
   assert set(after)-set(before)==added and {p for p in before if before[p]!=after[p]}==changes
   for phase in ['formal-v2','flat-v2','states-v3','sun-v3','checks-v2']:assert data(phase+'/source-before.json')==data(phase+'/source-after.json')==after
   for phase in ['formal-v2','flat-v2']:assert data(phase+'/result.json')['native_engine_gates_passed']
   for phase in ['states-v3','sun-v3']:assert data(phase+'/result.json')['passed']
   assert data('checks-v2/result.json')['all_passed']
   for rel in changes|added:assert hashlib.sha256((root/'source'/rel).read_bytes()).hexdigest()==after[rel]
   generator=data('generator-tests.json');assert generator['actual_exit']==0 and generator['tests']==7 and generator['source_sha256']==after['tools/level/test_ch3_layout.py']
   assert 'Ran 7 tests' in (root/'generator-tests.log').read_text() and '\nOK' in (root/'generator-tests.log').read_text()
   for name in ['clinic_ward','sunlit_edge','sunny_day','tower_white']:
    assert hashlib.sha256((root/'replay/bg45-current'/(name+'-before.tres')).read_bytes()).hexdigest()==before['data/lighting/'+name+'.tres']
   ambience=data('source/data/audio/ambience.json')['profiles'];zones=data('source/data/audio/music.json')['map']['zones']
   for old,new in [('sunny_day','showroom_day'),('tower_white','reception_white')]:assert ambience[old]==ambience[new] and old not in zones and new not in zones
   assert hashlib.sha256((root/'source/data/audio/music.json').read_bytes()).hexdigest()==before['data/audio/music.json']
   proof=data('baseline-proof.json');assert proof['original_bg45']=='02015266ca88f23e0774620359d7045f460b8f6d' and len(proof['rows'])==4
   delta=data('replay/bg45-current/prop-delta.json')
   for row in proof['rows']:
    level=row['level'];assert level in LEVELS and delta[level]['added']==row['added'] and delta[level]['removed']==row['removed']
    assert hashlib.sha256((root/(level.removeprefix('ch3_')+'-original-map.json')).read_bytes()).hexdigest()==row['original_map_sha256']
   pipeline=data('pipeline-extract.json');assert len(pipeline['props'])==3 and {p['seed'] for p in pipeline['props']}==set(range(7701,7704))
   for p in pipeline['props']:
    ident=p['id'];text=(root/'assets'/(ident+'.tres')).read_text();size=re.search(r'^size = Vector2\(([^,]+),\s*([^)]+)\)',text,re.M);assert size and abs(float(size[2])-p['height_m']*30)<.11
    with Image.open(root/'assets'/(ident+'.png')) as im:assert im.mode=='RGBA' and im.getchannel('A').getextrema()[0]==0
   cases=[verify_case(root/'formal-v2'/r['name']) for r in data('formal-v2/runs.json')];assert len(cases)==8 and all(r['passed'] for r in cases)
   assert sum(r['cells'] for r in cases)==108 and sum(r['standable'] for r in cases)==72 and sum(r['enemy_observations'] for r in cases)==0
   raw_count=0
   for phase,key,count in [('formal-v2','bg45',9),('flat-v2','bg45_flat',3)]:
    runs=data(phase+'/runs.json');assert len(runs)==8
    for run in runs:
     assert run['exit']==run['script_errors']==0 and not run['engine_error'] and run['source_held']
     level,quality=run['name'].rsplit('-',1);assert level in LEVELS;f=root/phase/run['name']/level;index=json.loads((f/'bg45-index.json').read_text())
     assert index['probe']['adapter']=='AMD Radeon RX 9070 XT' and index['probe']['engine'].startswith('4.7.2') and index['probe']['quality']==(0 if quality=='low' else 2)
     assert len(index['shots'])==int(index['columns'])*int(index['rows'])==(15 if level in ['ch3_clinic','ch3_showroom'] else 12)
     for shot in index['shots']:
      group=shot[key];assert group['controls_valid'] and len(group['records'])==count
      if phase=='flat-v2':assert group['records'][0]['raw_sha256']==group['records'][2]['raw_sha256']
      for r in group['records']:
       assert hashlib.sha256((f/r['files']['raw']).read_bytes()).hexdigest()==r['raw_sha256']
       with Image.open(f/r['files']['png']) as im:assert im.size==(640,360)
       raw_count+=1
   assert raw_count==1296
   for q in ['low','high']:
    states=data('states-v3/'+q+'/states.json');assert states['actual_talks'] and not states['seeded_result_flags'] and len(states['rows'])==19 and len(states['alignments'])==13
    assert [x['option'] for x in states['selected']]==['go','save','eleven','save','hundred','eleven','tracked','leave','post','finish','leave']
    for row in states['rows']:
     assert row['quality']==(0 if q=='low' else 2)
     with Image.open(root/'states-v3'/q/(row['name']+'.png')) as im:assert im.size==(640,360)
     if 'npc' in row:assert row['in_range'] and row['prompt_visible']
    for row in states['alignments']:
     x,y,w,h=row['rect'];nx,ny=row['npc_world'];gap=max(0,x-nx,nx-x-w);assert abs(gap-row['gap'])<1e-5 and gap<=row['limit']
     assert row['limit']==(32 if row['prop']=='clinic__reading_desk' else 16)
     props=data('source/data/levels/'+row['level']+'_map.json')['props'];entry=next(x for x in props if x['id']==row['prop']);assert abs(x-entry['x']*16-entry.get('dx',0))<1e-5
     size=re.search(r'^size = Vector2\(([^,]+),\s*([^)]+)\)',(root/'props'/(row['prop']+'.tres')).read_text(),re.M);assert size and abs(float(size[1])-w)<1e-5 and abs(float(size[2])-h)<1e-5
     if row['grounded']:assert abs(y+h-ny-row['ground_offset'])<.02
    rows={r['name']:r for r in states['rows']};assert rows['clinic-results']['reconciled'] and rows['clinic-results']['earned']==180 and not rows['clinic-results']['borrowed_tape']
    for name in ['petition-after','petition-repeat']:assert rows[name]['receipt_taken'] and rows[name]['receipt_held']
   sunlight=[verify_sun(root/'sun-v3'/q) for q in ['low','high']];assert all(r['passed'] for r in sunlight)
   # Run the same reader against an actual empty-alpha file in an owned temporary copy.
   negative=root/'empty-alpha';negative.mkdir();assert negative.resolve().is_relative_to(root)
   for name in ['runs.json','source-before.json','source-after.json']:shutil.copyfile(root/'sun-v3'/name,negative/name)
   shutil.copytree(root/'sun-v3/low',negative/'low');f=negative/'low';sun=json.loads((f/'sun.json').read_text());mask=f/sun['alpha']['raw'];mask.write_bytes(bytes(mask.stat().st_size));sun['alpha']['sha256']=hashlib.sha256(mask.read_bytes()).hexdigest();(f/'sun.json').write_text(json.dumps(sun))
   rejected=False
   try:verify_sun(f)
   except AssertionError as error:rejected='Opaque body mask is empty or too small' in str(error)
   assert rejected
   log=(root/'checks-v2/changed/raw.log').read_text(encoding='utf-8');match=re.search(r'checks: (\d+), new failures: (\d+), known failures \(tests/known_failures.txt\): (\d+)',log);assert match and match.groups()[1:]==('0','0')
   assert '總計：0 錯誤、0 警告' in (root/'checks-v2/scene-report/raw.log').read_text(encoding='utf-8')
   assert root.parent==folder and root.name.startswith('.ne-bg45-verify-')
   return {'passed':True,'cases':8,'normal_cells':108,'standable':72,'enemy_observations':0,'normal_hdr':972,'flat_hdr':324,'state_png':38,'point_decreases':sum(len(r['point_decreases']) for r in cases),'sunlight':sunlight,'empty_alpha_rejected':True,'changed_checks':int(match[1]),'logical_members':len(m['files'])}
 finally:
  for z in archives.values():z.close()
if __name__=='__main__':print(json.dumps(verify(Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).parent),indent=2))
