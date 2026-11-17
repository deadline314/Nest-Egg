from pathlib import Path,PurePosixPath
import copy,hashlib,json,re,shutil,sys,tempfile,zipfile
from PIL import Image
from verify_bg30_current_20261118 import group,verify as verify_case
from verify_bg49_held import verify_held

def verify(folder):
 folder=folder.resolve();m=json.loads((folder/'manifest.json').read_text());archives={}
 for n,h in m['readers'].items():assert hashlib.sha256((folder/n).read_bytes()).hexdigest()==h
 try:
  for n,h in m['archives'].items():
   assert re.fullmatch(r'evidence-\d\d.zip',n)
   assert hashlib.sha256((folder/n).read_bytes()).hexdigest()==h,'Archive digest mismatch'
   archives[n]=zipfile.ZipFile(folder/n)
  for n,z in archives.items():
   selected={f['member'] for f in m['files'].values() if f['archive']==n}
   assert set(z.namelist())==selected and len(z.namelist())==len(selected)
  assert len(m['files'])<20000 and sum(i.file_size for z in archives.values() for i in z.infolist())<8*1024**3
  with tempfile.TemporaryDirectory(prefix='.ne-bg30-verify-',dir=folder) as temporary:
   root=Path(temporary).resolve();assert root.parent==folder and root.name.startswith('.ne-bg30-verify-')
   for n,e in m['files'].items():
    rel=PurePosixPath(n);assert not rel.is_absolute() and '..' not in rel.parts
    p=(root/n).resolve();assert p.is_relative_to(root) and p!=root
    raw=archives[e['archive']].read(e['member']);assert hashlib.sha256(raw).hexdigest()==e['sha256'],n
    p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw)
   data=lambda n:json.loads((root/n).read_text(encoding='utf-8'))
   before,interim,after=data('source-base.json'),data('source-v2.json'),data('source-v3.json');assert len(before)==10094 and len(interim)==len(after)==10095
   adoption=data('adoption-v3.json');paths=set(adoption['product_paths']);new='data/environment/materials/prologue_concrete.tres'
   assert set(after)-set(before)=={new} and {n for n in before if before[n]!=after[n]}==paths-{new}
   assert {n for n in interim if interim[n]!=after[n]}=={'tools/contrast_probe.gd','tests/suite/test_exposure.gd'}
   metric=(root/'source/tools/contrast_probe.gd').read_text();guard='\t# Missing pixels are not a black comparison surface.\n\tif _pixel_count(edge_rect) == 0.0 or _pixel_count(below_rect) == 0.0:\n\t\treturn 0.0\n'
   assert metric.count(guard)==1 and metric.replace(guard,'')==(root/'original-source/tools/contrast_probe.gd').read_text()
   for n in paths:assert hashlib.sha256((root/'source'/n).read_bytes()).hexdigest()==after[n]
   lighting=(root/'source/data/lighting/warehouse_interior.tres').read_text();original=(root/'original-source/data/lighting/warehouse_interior.tres').read_text()
   assert lighting.replace('enemy_fill_scale = 2.0','enemy_fill_scale = 0.6').replace('creature_floor = 0.6\n','')==original
   concrete=(root/'source/data/environment/materials/concrete.tres').read_text();local=(root/'source'/new).read_text()
   assert local.replace('id = &"prologue_concrete"','id = &"concrete"').replace('0.9019608, 1.0)','0.9019608, 0.6)')==concrete
   footsteps=data('source/data/audio/footsteps.json');assert footsteps['materials']['prologue_concrete']==footsteps['materials']['concrete']=='concrete'
   profile=(root/'source/data/scripts/lighting_profile.gd').read_text();assert 'const MAX_ENEMY_FILL_SCALE := 2.0' in profile and 'not is_finite(enemy_fill_scale)' in profile
   for phase in ['formal-v5','campaign-v2']:
    assert data(phase+'/source-before.json')==data(phase+'/source-after.json')==(after if phase=='formal-v5' else interim)
    result=data(phase+'/result.json');assert result['passed'] and result['source_held'] and result['completed_producers']==2
    runs=data(phase+'/runs.json');assert [r['quality'] for r in runs]==['low','high']
    for r in runs:
     assert r['exit']==r['script_errors']==0 and not r['engine_error'] and r['source_held']
     log=(root/phase/r['quality']/'raw.log').read_text();assert 'ERROR:' not in log and 'Forward+' in log and 'AMD Radeon RX 9070 XT' in log and '4.7.2' in log
   cases=[verify_case(root/'formal-v5'/q) for q in ['low','high']]
   assert all(c['passed'] for c in cases) and sum(c['cells'] for c in cases)==576
   campaign=[verify_held(root/'campaign-v2'/q) for q in ['low','high']];assert all(c['points']==18 for c in campaign)
   states=data('states-v3/result.json');assert states['passed'] and states['source_held'] and states['completed_producers']==4
   assert 'ContrastProbe' not in (root/'replay/states-v3.gd').read_text()
   for run in data('states-v3/runs.json'):
    assert run['exit']==run['script_errors']==0 and not run['engine_error'] and run['source_held']
    name=run['quality']+'-'+run['mode'];state=data('states-v3/'+name+'/states.json');assert state['renderer']=='forward_plus' and state['hdr'] and state['adapter']=='AMD Radeon RX 9070 XT' and len(state['rows'])==10
    rows={r['name']:r for r in state['rows']};assert rows['low-health']['danger']>=.99 and rows['health-restored']['danger']<=.01
    for r in state['rows']:
     assert r['quality']==(0 if run['quality']=='low' else 2) and r['reduced_flashes']==(run['mode']=='reduced') and r['reduced_ui_motion']==(run['mode']=='reduced') and r['on_floor'] and r['tooltip_suppressed_for_body_capture']
     assert r['rain_nodes']==int(r['rain_authored'])
     if r['name'].endswith('telegraph'):assert len(r['telegraphs'])==1
     if r['level']=='ch1_warehouse':assert r['enemy_fill_scale']==2
     with Image.open(root/'states-v3'/name/(r['name']+'.png')) as im:assert im.size==(640,360)
    indoor=rows['indoor'];assert all(y<indoor['feet'][1]-60 for y in indoor['rain_surfaces'])
   assert data('checks-v3/result.json')['all_passed'] and data('checks-v3/source-before.json')==data('checks-v3/source-after.json')==after
   for r in data('checks-v3/runs.json'):assert r['exit']==r['script_errors']==0 and not r['engine_error'] and r['source_held']
   assert data('diagnostics/edge-negative/result.json')['exit']==1 and 'new failures: 2' in (root/'diagnostics/edge-negative/raw.log').read_text()
   # Mutate a real metadata file beside actual copied raw images; the same reader must reject it.
   selected=None
   for p in (root/'formal-v5/low').glob('*/formal-index.json'):
    for s in json.loads(p.read_text())['shots']:
     if s['bg30']['records'][-1]['collision_enemies']:selected=(p.parent,s['bg30']);break
    if selected:break
   assert selected is not None
   source,g=selected;negative=root/'empty-collision-negative';negative.mkdir();bad=copy.deepcopy(g)
   for r in bad['records']:
    for n in r['files'].values():shutil.copyfile(source/n,negative/n)
   bad['records'][-1]['collision_enemies'][0]['world_rect'][2]=0
   (negative/'group.json').write_text(json.dumps(bad));rejected=False
   try:group(negative,json.loads((negative/'group.json').read_text()))
   except AssertionError as error:rejected='Physical collision rectangle mismatch' in str(error)
   assert rejected,'Actual empty collision rectangle was not rejected'
   return {'passed':True,'source_count':len(after),'original_grid_cells':576,'full_framed_extra_views':sum(c['extra_views'] for c in cases),'logical_hdr':sum(c['logical_hdr'] for c in cases),'physical_collision_negative_rejected':True,'campaign_original_points':36,'state_images':40,'minima':[{k:c[k] for k in ['minimum_player','minimum_edge','minimum_full_humanoid','minimum_physical_creature']} for c in cases],'legacy_nonhuman_below':sum(len(c['legacy_nonhuman_below']) for c in cases),'white_including_background':sum(len(c['white_including_background']) for c in cases),'scope':'held scripted lighting/geometry and actual state events, original human gates plus supplementary true nonhuman collision rectangles; old legacy values retained; no natural combat, FPS, VRAM, every possible player position, or historical full-checkout claim'}
 finally:
  for z in archives.values():z.close()

if __name__=='__main__':print(json.dumps(verify(Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).parent),indent=2))
