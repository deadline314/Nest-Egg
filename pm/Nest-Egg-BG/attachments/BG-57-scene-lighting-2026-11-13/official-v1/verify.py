"""Offline official append audit. No Godot, network or existing packet mutation."""
import argparse,hashlib,io,json,re,subprocess,sys,zipfile
from pathlib import Path,PurePosixPath

def sha(b):return hashlib.sha256(b).hexdigest()
def obj(z,n):return json.loads(z.read(n))
def main():
 p=argparse.ArgumentParser();p.add_argument('--extract-to',type=Path,required=True);p.add_argument('--bash',default='C:/Program Files/Git/bin/bash.exe' if sys.platform=='win32' else 'bash');a=p.parse_args();root=Path(__file__).resolve().parent;index=json.loads((root/'index.json').read_bytes());record=json.loads((root/'receipt.json').read_bytes())
 assert record['accepted'] is True and sha((root/'receipt.json').read_bytes())==index['receipt.json']['sha256']
 for name in ['README.md','verify.py']:
  bits=(root/name).read_bytes();assert len(bits)==index[name]['bytes'] and sha(bits)==index[name]['sha256']
 meta=index['raw.zip'];raw=(root/'raw.zip').read_bytes();assert len(raw)==meta['bytes']<90_000_000 and sha(raw)==meta['sha256']==record['raw_zip_sha256']
 target=a.extract_to.resolve();assert not target.exists() or not any(target.iterdir()),'fresh owned extraction path required';target.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(io.BytesIO(raw)) as z:
  assert z.testzip() is None and len(z.namelist())==len(meta['members']) and set(z.namelist())==set(meta['members'])
  for name,expected in meta['members'].items():
   bits=PurePosixPath(name);assert not bits.is_absolute() and '..' not in bits.parts and '\\' not in name;b=z.read(name);assert len(b)==expected['bytes'] and sha(b)==expected['sha256'];f=target.joinpath(*bits.parts);f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes(b)
  tags=sorted({n.split('/')[0] for n in z.namelist() if n.endswith('/candidate/manifest.json')})
  assert 'final' in tags and any(t.startswith('red-') for t in tags)
  observed={}
  for tag in tags:
   prefix=tag+'/epoch/';m=obj(z,tag+'/candidate/manifest.json');analysis=obj(z,tag+'/independent-analysis.json');r=obj(z,prefix+'receipt.json');before=obj(z,prefix+'source-before.json');after=obj(z,prefix+'source-after.json');assert before==after and r['source_exact'] and r['c_unchanged'] and r['all_four_queue_gates'];assert obj(z,prefix+'c-before.json')==obj(z,prefix+'c-after.json')
   with zipfile.ZipFile(io.BytesIO(z.read(tag+'/candidate/source.zip'))) as src:
    assert src.testzip() is None and len(src.namelist())==len(m['files']) and set(src.namelist())==set(m['files'])
    for name,h in m['files'].items():
     assert sha(src.read(name))==h
     if name in before:assert (before[name] if isinstance(before[name],str) else before[name]['sha256'])==h
     else:assert name.startswith('design/'),'unguarded runtime candidate'
   e=z.read(prefix+'engine.log').decode('utf-8');footer=re.findall(r'^checks:\s*(\d+),\s*new failures:\s*(\d+),\s*known failures\s*\([^)]*\):\s*(\d+)',e,re.M);assert len(footer)==1;checks,new,known=map(int,footer[0]);total=0;failures=0;suites=set()
   for s in analysis['shards']:
    name=prefix+'test-logs/'+s['file'];b=z.read(name);assert sha(b)==s['sha256'];text=b.decode('utf-8');f=re.findall(r'^checks:\s*(\d+),\s*failures:\s*(\d+)',text,re.M);assert len(f)==1;c,n=map(int,f[0]);total+=c;failures+=n;names=re.findall(r'^SUITE_TIME\s+(\S+)\s+',text,re.M);assert not suites.intersection(names);suites.update(names)
    policy=target/tag/'original-policy/tools/test_filters.sh';run=subprocess.run([a.bash,'-c','source "$1"; has_unexpected_errors "$2"','_',str(policy),str(target/name)],cwd=target/tag/'original-policy',capture_output=True)
    assert run.returncode in (0,1)
    if tag=='final':assert run.returncode==1 and not re.search(r'SCRIPT ERROR|Parse Error|DummyTexture|dummy/texture_storage',text)
   assert total==checks==analysis['checks'] and failures==new+known
   selection=z.read(tag+'/selector/union-selector.txt').decode('utf-8').strip().split(',');assert suites==set(selection) and len(suites)==analysis['suites']
   for name in ['tools/run_tests_changed.sh','tools/run_tests_parallel.sh','tools/select_tests.py','tools/test_filters.sh','tests/known_failures.txt','tests/smoke_test.gd','project.godot']:
    assert sha(z.read(tag+'/original-policy/'+name))==(before[name] if isinstance(before[name],str) else before[name]['sha256'])
   if tag=='final':
    assert new==0 and r['exit_code']==0 and r['accepted'] and analysis['accepted'];assert m['ticket_files'][record['ticket']]==record['ticket_files']
    assert record['ticket_count']==len(record['ticket_files']) and record['union_count']==len(m['files'])
    assert record['official_union']=={key:analysis[key] for key in ['checks','new_failures','known_failures','suites','wall_seconds','runtime_source_count']}
   else:assert new>0 and not r['accepted'] and not analysis['accepted']
   observed[tag]={'checks':checks,'new':new,'known':known,'suites':len(suites),'candidate_count':len(m['files'])}
  final_manifest=obj(z,'final/candidate/manifest.json')
  for category in ['native','cold','focused']:
   for item in record.get(category,[]):
    prefix=item['archive_prefix'];r=obj(z,prefix+'/'+item['receipt']);assert sha(z.read(prefix+'/'+item['receipt']))==item['receipt_sha256'];assert r['accepted']==item['wrapper_accepted']
    assert obj(z,prefix+'/source-before.json')==obj(z,prefix+'/source-after.json') and obj(z,prefix+'/c-before.json')==obj(z,prefix+'/c-after.json')
    assert all(r.get(k,False) for k in ['source_exact','c_unchanged','all_four_queue_gates'])
    actual_diagnostics=[line for line in z.read(prefix+'/engine.log').decode('utf-8').splitlines() if re.match(r'^(?:SCRIPT ERROR|ERROR:|WARNING:|.*Parse Error|.*DummyTexture)',line)];assert actual_diagnostics==r.get('diagnostics',[])
    if item.get('review'):
     review=obj(z,prefix+'/'+item['review']);assert review['accepted'] is True and sha(z.read(prefix+'/'+item['review']))==item['review_sha256']
    if not r['accepted']:assert r['exit_code']==0 and r['diagnostics']==item['expected_diagnostics'] and item.get('review')
    elif 'diagnostics' in r:assert not r['diagnostics']
    if category=='native':
     before=obj(z,prefix+'/source-before.json');differences={n:{'native':before[n] if isinstance(before[n],str) else before[n]['sha256'],'final':h} for n,h in final_manifest['files'].items() if n in before and (before[n] if isinstance(before[n],str) else before[n]['sha256'])!=h};assert all(n.startswith('tests/') for n in differences)
     missing=[n for n in final_manifest['files'] if n not in before];assert all(n.startswith('design/') for n in missing)
     stated=next(row for row in record['native_candidate_delta_analysis'] if row['epoch']==item['epoch']);assert differences==stated['candidate_differences'] and missing==stated['provenance_only_missing']
  assert obj(z,'native/root-readability-review.json')['accepted'] is True
  comparison=obj(z,'native/source-context-comparison.json');assert comparison==record['native_source_context_comparison']
  cfg=obj(z,'configuration-original.json')
  for extra in cfg.get('extra_files',[]):assert sha(z.read(extra['archive_path']))==extra['sha256']
  for item in record.get('cold',[]):
   prefix=item['archive_prefix'];review=obj(z,prefix+'/'+item['review'])
   for name,expected in review['capture_sha256'].items():assert sha(z.read(prefix+'/captures/'+name))==expected
   original=next(x for x in cfg['extra_files'] if x['archive_path']=='cold-inputs/original-legacy-slot.json');assert original['sha256']==review['original_legacy_slot_sha256']
  prep=obj(z,'cold-inputs/preparation/manifest.json')
  for name,expected in prep['files'].items():assert sha(z.read('cold-inputs/preparation/inputs/'+name))==expected
 print(json.dumps({'accepted':True,'ticket':record['ticket'],'zip_file_entries':len(meta['members']),'observed_original_runs':observed,'native_wrapper_vs_review_scope_preserved':True,'no_engine_started':True},indent=2))
if __name__=='__main__':main()
