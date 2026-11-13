"""Offline NE295 replay: original ZIP/member bytes, source/queue gates, five native readers."""
import argparse,hashlib,json,os,re,subprocess,sys,zipfile
from pathlib import Path,PurePosixPath
HERE=Path(__file__).resolve().parent
C_GUARD_SHA='a3df1f1a2c27952545453a3d1b8a422a42755deddcc86088a70c1dc62e1d81d0'
def sha(b):return hashlib.sha256(b).hexdigest()
def read(p):return json.loads(p.read_bytes())
def verify(extract,result):
 index=read(HERE/'index.json');extract=extract.resolve();assert not extract.exists() or not any(extract.iterdir()),'use a fresh owned extraction directory'
 extract.mkdir(parents=True,exist_ok=True);objects={};members={}
 for item in index['archives']:
  path=HERE/item['file'];assert path.stat().st_size==item['bytes'] and sha(path.read_bytes())==item['sha256'];assert item['bytes']<90_000_000
  with zipfile.ZipFile(path) as z:
   assert z.testzip() is None and len(z.infolist())==len(item['members'])
   for row in z.infolist():
    name=row.filename;bits=PurePosixPath(name);assert not bits.is_absolute() and '..' not in bits.parts and '\\' not in name
    body=z.read(row);expected=item['members'][name];assert len(body)==expected['bytes'] and sha(body)==expected['sha256'];target=extract.joinpath(*bits.parts)
    if name in members:assert members[name]==expected['sha256'],'conflicting duplicate archive path'
    else:target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(body);members[name]=expected['sha256']
    objects.setdefault(expected['sha256'],target)
 for name,row in index['selected'].items():assert (HERE/name).stat().st_size==row['bytes'] and sha((HERE/name).read_bytes())==row['sha256']==members[row['source']]
 manifest=read(extract/'delivery-manifest-v2.json');assert sha((extract/'delivery-manifest-v2.json').read_bytes())==index['product_manifest_sha256'] and len(manifest['files'])==22
 for name,row in manifest['files'].items():
  assert sha((extract/'final'/name).read_bytes())==row['sha256']
  if row['base_sha256'] is not None:assert sha((extract/'base'/name).read_bytes())==row['base_sha256']
 outputs=extract/'_independent-results';outputs.mkdir();results={}
 for role,entry in index['final_epochs'].items():
  ep=extract/entry['epoch'];receipt=read(ep/'exit.json');assert receipt['exit']==0 and receipt['strict_clean'] and receipt['source_fixed'] and receipt['c_fixed'] and receipt['all_four_queues_clear'] and not receipt['diagnostics'] and not receipt['owned_after']
  before=read(ep/'source-before.json');assert before==read(ep/'source-after.json') and len(before)==receipt['before_count']==receipt['after_count']
  assert sha((ep/'c-guard-original.json').read_bytes())==C_GUARD_SHA
  guard=read(ep/'c-guard-original.json')['files'];assert len(guard)==receipt['c_count']==463 and guard==read(ep/'c-before.json')==read(ep/'c-after.json')
  for name,row in manifest['files'].items():assert before[name]['sha256']==row['sha256']
  for label in ['outer-before','inner-before','inner-after','outer-after']:
   q=read(ep/(label+'.json'));assert [r['port'] for r in q]==[8188,8189];assert q[0]['state']=='empty' and q[0]['running']==q[0]['pending']==0
   assert (q[1]['state']=='empty' and q[1]['running']==q[1]['pending']==0) or (q[1]['state']=='refused' and q[1]['winerror']==10061)
  log=(ep/'engine.log').read_text(encoding='utf-8');assert not re.search(r'ERROR:|SCRIPT ERROR|WARNING:|^FAIL|leaked at exit|resources still in use|RID allocations.*leaked',log,re.M)
  scene=next(a.removeprefix('res://') for a in read(ep/'command.json')['argv'] if a.startswith('res://') and a.endswith('.tscn'))
  # Executed native scene/producer and recursive private base bytes must exist as exact source objects.
  pending=[scene];seen=set()
  while pending:
   name=pending.pop()
   if name in seen:continue
   seen.add(name);assert name in before and before[name]['sha256'] in objects,'missing exact executed source object: '+name
   code=objects[before[name]['sha256']].read_text(encoding='utf-8-sig')
   pending += re.findall(r'(?:extends\s+|path=)"res://(work/[^"\n]+\.(?:gd|tscn))"',code)
  command=[sys.executable,str(extract/entry['reader']),str(ep/'captures'),'--out',str(outputs/(role+'.json'))]
  env=os.environ.copy();env['PYTHONIOENCODING']='utf-8';run=subprocess.run(command,capture_output=True,env=env);(outputs/(role+'.log')).write_bytes(run.stdout+run.stderr);assert run.returncode==0,(role,run.returncode,(run.stdout+run.stderr).decode('utf-8',errors='replace'))
  results[role]={'reader_exit':run.returncode,'records':entry['records'],'executed_source_objects':sorted(seen),'source_count':len(before),'native_wall_seconds':receipt['wall_seconds']}
 controls=[('clone-flags', ['work/ne295-final-renderers-v1/read_final_cause.py','--self-test']),('death-negatives',['work/ne295-final-renderers-v1/death_negative_controls.py',str(extract/index['final_epochs']['death']['epoch']/'captures')]),('normal-oracle',['work/ne295-renderer-coverage-v1/read_basis.py','--self-test'])]
 for role,args in controls:
  command=[sys.executable,str(extract/args[0]),*args[1:],'--out',str(outputs/(role+'.json'))];run=subprocess.run(command,capture_output=True);(outputs/(role+'.log')).write_bytes(run.stdout+run.stderr);assert run.returncode==0,(role,run.stdout,run.stderr);v=read(outputs/(role+'.json'));assert v['failures']==0
  results[role]={'checks':v['checks'],'reader_exit':run.returncode}
 out={'passed':True,'archive_count':len(index['archives']),'zip_file_entries':index['zip_file_entries'],'archive_bytes':index['archive_bytes'],'selected_originals':len(index['selected']),'final_source_paths':22,'results':results,'scope':'Offline original bytes and actual renderer data; no new Godot, gameplay or performance run'};result.write_bytes((json.dumps(out,indent=2)+'\n').encode());print(json.dumps(out,indent=2))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--extract-to',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args();verify(a.extract_to,a.out)
