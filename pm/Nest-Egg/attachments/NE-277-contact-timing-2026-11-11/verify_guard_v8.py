"""Offline finite-contact evidence. --raw-root additionally verifies the full private manifests."""
from pathlib import Path,PurePosixPath
import argparse,hashlib,json,sys,zipfile

HERE=Path(__file__).resolve().parent
def sha(data):return hashlib.sha256(data).hexdigest()

def verify(raw_root=None):
 assert not sys.flags.optimize
 index=json.loads((HERE/'guard-v8-index.json').read_bytes());selected=index['selected'];path=HERE/selected['file']
 assert path.stat().st_size==selected['bytes'] and sha(path.read_bytes())==selected['sha256']
 data={}
 with zipfile.ZipFile(path) as archive:
  assert archive.testzip() is None and set(archive.namelist())==set(selected['members'])
  for name in archive.namelist():
   assert not PurePosixPath(name).is_absolute() and '..' not in PurePosixPath(name).parts and '\\' not in name and ':' not in name
   data[name]=archive.read(name);assert sha(data[name])==index['members'][name]
 complete=False
 if raw_root is not None:
  raw=Path(raw_root)/index['raw'];assert raw.stat().st_size==index['bytes'] and sha(raw.read_bytes())==index['sha256']
  with zipfile.ZipFile(raw) as archive:
   assert archive.testzip() is None and set(archive.namelist())==set(index['members'])
   for name,digest in index['members'].items():assert sha(archive.read(name))==digest
  complete=True
 read=lambda name:json.loads(data[name])
 original=read('vertex-and-transform-controls/original/result.json');guarded=read('vertex-and-transform-controls/guarded/result.json')
 assert len(original['rows'])==len(guarded['rows'])==7 and original['failures']==3 and guarded['failures']==0
 assert {r['case'] for r in original['rows'] if r['finite']!=r['expected_finite']}=={'nan-a','inf-b','nan-c'}
 assert all(r['finite']==r['expected_finite'] for r in guarded['rows'])
 original_log=data['vertex-and-transform-controls/original/engine.log'].decode()
 assert original_log.count('ERROR: Condition "det == 0" is true.')==2 and 'SCRIPT ERROR' not in original_log
 assert read('vertex-and-transform-controls/original/exit.json')['exit']==1
 assert read('vertex-and-transform-controls/guarded/exit.json')['exit']==0
 old=read('v7-shape-size-red/result.json');new=read('v8-final-controls/sizes/result.json')
 assert old['failures']==1 and new['failures']==0
 assert old['rows'][0]['stored_nonfinite'] and old['rows'][0]['finite_return'] and old['rows'][0]['point']=='(100.0, 100.0)'
 assert all(r['stored_nonfinite'] and not r['finite_return'] for r in new['rows'][:2])
 assert old['rows'][2]['finite_return'] and new['rows'][2]['finite_return'] and new['rows'][2]['point']=='(0.0, 0.0)'
 for folder,marker in [('v7-full-geometry','FINITE_PROPOSAL_DONE checks=110 failures=0'),('v8-final-controls/geometry','FINITE_PROPOSAL_DONE checks=113 failures=0'),('v8-final-controls/sizes','SIZE_API_DONE failures=0'),('vertex-and-transform-controls/guarded','FINITE_API_DONE failures=0')]:
  log=data[folder+'/engine.log'].decode()
  assert marker in log and not any(m in log for m in ['ERROR:','SCRIPT ERROR','ObjectDB instances leaked','resources still in use'])
  assert read(folder+'/exit.json')['exit']==0
 for name,digest in index['final_source_sha256'].items():assert sha(data['final-source/'+name])==digest
 candidate=read('candidate-v8.json')
 assert all(candidate['source_sha256'][name]==digest for name,digest in index['final_source_sha256'].items())
 return {'selected_members_verified':len(data),'full_raw_verified':complete,'vertex_transform':'original three false hits/two API errors -> guarded 7/0','shape_sizes':'v7 one false hit -> v8 3/0, zero-size positive retained','final_geometry':'113/0','engine_started':False,'performance':False}

if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--raw-root',type=Path);args=parser.parse_args()
 print(json.dumps(verify(args.raw_root)))
