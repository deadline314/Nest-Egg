from pathlib import Path,PurePosixPath
import hashlib,io,json,sys,zipfile
from PIL import Image
def verify(folder):
 m=json.loads((folder/'manifest.json').read_text());archive=folder/'evidence.zip';assert hashlib.sha256(archive.read_bytes()).hexdigest()==m['archive_sha256'],'Archive digest mismatch'
 assert hashlib.sha256((folder/'verify.py').read_bytes()).hexdigest()==m['reader_sha256']
 with zipfile.ZipFile(archive) as z:
  assert set(z.namelist())==set(m['files']) and len(z.namelist())<=200 and sum(i.file_size for i in z.infolist())<64*1024*1024
  for n,h in m['files'].items():
   assert not PurePosixPath(n).is_absolute() and '..' not in PurePosixPath(n).parts and hashlib.sha256(z.read(n)).hexdigest()==h
  data=lambda n:json.loads(z.read(n));source=data('native/source-before.json');assert len(source)==10094 and source==data('native/source-after.json')
  final_source=data('source-v4.json');assert len(final_source)==10094 and [n for n in source if source[n]!=final_source[n]]==['tools/ch2_flow_probe.gd']
  original=z.read('diagnostics/original-flow-probe.gd');assert hashlib.sha256(original).hexdigest()==source['tools/ch2_flow_probe.gd']
  actual=z.read('source/tools/ch2_flow_probe.gd');assert actual.count(b'await AudioRelease.settle(get_tree())')==2 and actual.replace(b'\tawait AudioRelease.settle(get_tree())\n',b'')==original
  assert data('checks/result.json')['only_probe_shutdown_changed'] and data('checks/result.json')['root_matches_final_native_source'] and data('checks/result.json')['exit']==0
  assert 'ERROR:' not in z.read('checks/raw.log').decode('utf-8')
  for n,h in final_source.items():
   if 'source/'+n in m['files']:assert hashlib.sha256(z.read('source/'+n)).hexdigest()==h
  scenes=data('source/data/story/ch2_heron.json')['scenes'];selected={k:v for k,v in scenes.items() if any(s.get('do')=='scene' and s.get('id')=='ch2_guest_book_room' for s in v.get('steps',[]))};assert len(selected)==18 and selected==data('native/scene-sources.json')
  stage=data('source/data/cutscene/stages/ch2_guest_book_room.json');proportions=data('source/data/cutscene/stage_proportions.json');assert stage['floor']==265.5 and len(stage['furniture'])==3
  for f in stage['furniture']:
   x,y,w,h=f['rect'];lo,hi=proportions['kinds'][f['kind']];ratio=h/(proportions['actor_height']*3.9);assert lo-proportions['tolerance']<=ratio<=hi+proportions['tolerance'] and abs(y+h-stage['floor'])<=2
  background=next(l for l in stage['layers'] if l.get('path','').endswith('guest_book_seating.png'));assert background['source_width']==1843 and background['scale']==.5
  with Image.open(io.BytesIO(z.read('source/art/environment/scenes/guest_book_seating.png'))) as im:assert im.size==(1843,853)
  stage_run=data('native/runs.json')[0];assert stage_run['name']=='stage-scenes' and stage_run['exit']==stage_run['script_errors']==0 and not stage_run['engine_error'] and stage_run['source_held']
  for k,v in selected.items():
   meta=data('native/stage-scenes/'+k+'.json');assert meta['saved'] and meta['flags_unchanged'] and not meta['framing_problems'] and meta['adapter']=='AMD Radeon RX 9070 XT' and meta['godot'].startswith('4.7.2')
   actor=v['steps'][1];assert actor['id']=='ali' and actor['pos'][1]==265.5 and actor['scale']==3.9
   seated=int(k[7:9]) in [18,19,20];assert actor['pose']==('sit' if seated else 'idle') and actor['pos'][0]==(232 if seated else 150)
   if seated:assert actor['seat_sag']==.5 and actor['pose_support']
  final=data('flow/result.json');assert final['passed'] and final['runs']==2 and final['only_probe_audio_shutdown_changed']
  for row in data('flow/runs.json'):
   assert row['exit']==row['script_errors']==0 and not row['engine_error'] and row['source_held']
   name=row['name'];result=data('flow/'+name+'/guest-book-result.json');assert result['failures']==0 and result['credit_delta']==100 and result['book_complete'] and not result['paused']
   raw=z.read('flow/'+name+'/raw.log').decode('utf-8');assert 'ERROR:' not in raw and 'FAIL ' not in raw and 'CH2_GUEST_BOOK_PROBE failures=0' in raw and 'AMD Radeon RX 9070 XT' in raw
   for text in ['skip does not invent a completed guest or payment','one completed guest pays exactly twenty','the completed first guest is not paid twice','the finished book revisit never pays again','returning to Rin releases the story pause']:assert 'PASS '+text in raw
  pngs=[n for n in z.namelist() if n.endswith('.png') and (n.startswith('native/stage-scenes/') or n.startswith('flow/'))]
  for n in pngs:
   with Image.open(io.BytesIO(z.read(n))) as im:assert im.size==(640,360)
  return {'passed':True,'connected_scenes':18,'clean_final_flows':2,'source_count':len(source),'native_png':len(pngs),'only_probe_shutdown_changed':True,'historical_exit_failure_preserved':True}
if __name__=='__main__':print(json.dumps(verify(Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).parent),indent=2))
