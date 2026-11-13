"""Portable read-only proof for this recorded NE298 v8 high epoch."""
from pathlib import Path
import hashlib,importlib.util,io,json,re,sys,zipfile

def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def verify(root):
 root=Path(root);index=json.loads((root/'index.json').read_bytes())
 for item in [index['metadata'],index['private_source'],*index['chunks']]:
  p=root/item['path'];assert p.stat().st_size==item['bytes'] and sha(p)==item['sha256']
  with zipfile.ZipFile(p) as z:assert z.testzip() is None
 with zipfile.ZipFile(root/index['metadata']['path']) as z:
  before=json.loads(z.read('source-before.json'));after=json.loads(z.read('source-after.json'));assert before==after
  cb=json.loads(z.read('c-before.json'));ca=json.loads(z.read('c-after.json'));assert cb==ca and len(cb)==463
  receipt=json.loads(z.read('receipt.json'));assert receipt['accepted'] is True and receipt['exit']==0 and receipt['checks']==152 and receipt['failures']==0 and not receipt['diagnostics']
  log=z.read('engine.log').decode('utf8');assert not re.search(r'SCRIPT ERROR|ERROR:|WARNING:|ObjectDB.*leak|RID allocations.*leaked|resources still in use at exit',log);assert 'NE298_CAPTURE 152 checks, 0 failures' in log
  for n in ['outer-queue-before.json','inner-queue-before.json','inner-queue-after.json','outer-queue-after.json']:
   q=json.loads(z.read(n));assert q[0]['port']==8188 and q[0]['state']=='empty' and q[1]['port']==8189 and q[1]['state'] in ['empty','refused']
  result=json.loads(z.read('captures/result.json'));assert result['failures']==0 and result['checks']==152 and not result['parse_only']
  m=json.loads(z.read('runtime21-manifest.json'));assert len(m['owned'])==21
  with zipfile.ZipFile(io.BytesIO(z.read('runtime21-source.zip'))) as source:
   assert source.testzip() is None
   for n,meta in m['owned'].items():
    b=source.read(n);assert len(b)==meta['size'] and hashlib.sha256(b).hexdigest()==meta['sha256']
    if n in before:assert before[n]['sha256']==meta['sha256']
    else:assert n.startswith('design/') # documentation is outside the runtime projection
 with zipfile.ZipFile(root/index['private_source']['path']) as z:
  for n in z.namelist():assert hashlib.sha256(z.read(n)).hexdigest()==before['work/ne298-native-input-v1/'+n]['sha256']
 assert sha(root/'verify_capture_precision.py')==index['precision_verifier_sha256']
 spec=importlib.util.spec_from_file_location('original_precision',root/'verify_capture_precision.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
 pages=[];reports=[]
 for item in index['chunks']:
  report=module.verify(root/item['path']);reports.append(report);pages.extend(x['page'] for x in report['native_images'])
 expected=[c['page'] for c in result['captures']];assert len(pages)==21 and len(set(pages))==21 and set(pages)==set(expected)
 return {'PASS':True,'original_images':21,'pixels':sum(x['pixels'] for q in reports for x in q['native_images']),'runtime_projection_exact':len(before),'protected_primary_exact':len(cb),'source_owned':21,'original_diagnostics':0,'scope':index['scope']}

if __name__=='__main__':print(json.dumps(verify(Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).parent),indent=2))