"""Portable read-only ZIP verifier; never extracts, edits pixels or starts Godot.
Optional --raw-root points to a directory holding raw.zip kept outside Git.
"""
from pathlib import Path,PurePosixPath
from types import SimpleNamespace
import argparse,hashlib,importlib.util,json,zipfile

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('ne262_frozen_reader',HERE/'reader.py')
reader=importlib.util.module_from_spec(spec);spec.loader.exec_module(reader)

def digest(data):return hashlib.sha256(data).hexdigest()

class Member:
 def __init__(self,archive,name=''):self.archive=archive;self.member=name
 def __truediv__(self,name):
  assert PurePosixPath(str(name)).name==str(name),'unsafe child path'
  return Member(self.archive,self.member+'/'+str(name) if self.member else str(name))
 def read_bytes(self):return self.archive.read(self.member)
 def read(self,size=-1):
  data=self.read_bytes();return data if size<0 else data[:size] # Pillow wraps a non-seekable source in BytesIO.
 def stat(self):return SimpleNamespace(st_size=self.archive.getinfo(self.member).file_size)

def validate_archive(path,manifest):
 assert path.is_file(),'archive absent; use --raw-root for external raw.zip'
 assert digest(path.read_bytes())==manifest['sha256'] and path.stat().st_size==manifest['bytes'],'archive bytes drift'
 archive=zipfile.ZipFile(path)
 assert archive.testzip() is None
 assert set(archive.namelist())==set(manifest['members']) and len(archive.namelist())==len(manifest['members'])
 for name,row in manifest['members'].items():
  part=PurePosixPath(name)
  assert not part.is_absolute() and '..' not in part.parts,'unsafe archive member'
  data=archive.read(name)
  assert digest(data)==row['sha256'] and len(data)==row['bytes'],('member drift',name)
 return archive

def expect_rejected(call,label,substring=None):
 try:call()
 except AssertionError as error:
  assert substring is None or substring in str(error),(label,str(error))
  return {'case':label,'rejected':True,'reason':str(error)}
 raise AssertionError(('reader accepted a deliberately invalid case',label))

def audit(raw_root=None):
 index=json.loads((HERE/'index.json').read_bytes())
 assert digest((HERE/'reader.py').read_bytes())==index['reader_sha256'],'frozen reader drift'
 source=validate_archive(HERE/index['source']['file'],index['source'])
 raw_path=(Path(raw_root) if raw_root else HERE)/index['raw']['file']
 raw=validate_archive(raw_path,index['raw']);cases=index['cases'];results=[]
 try:
  positive=reader.check_cpu(Member(raw,cases['cpu_positive']))
  negative=reader.check_cpu(Member(raw,cases['cpu_body_negative']))
  assert positive['checks']==14 and not positive['expected_negative']
  assert negative['checks']==14 and negative['expected_negative'] and len(negative['recorded_failures'])==4
  results+=[positive,negative]
  results.append(expect_rejected(lambda:reader.check_cpu(Member(raw,cases['cpu_wrong_particle_expectation'])),'retained initial wrong6-particle expectation'))
  normal=reader.check_render(Member(raw,cases['native_normal']))
  assert [len(item['lines']) for item in normal['observations']]==[24,12]
  results.append(normal)
  results.append(expect_rejected(lambda:reader.check_render(Member(raw,cases['native_after_still'])),'native after-still-brackets','missing renderer line'))
  results.append(expect_rejected(lambda:reader.check_render(Member(raw,cases['native_debug_off'])),'native debug-off','missing renderer line'))
  results.append(expect_rejected(lambda:reader.check_render(Member(raw,cases['native_clipped_zoom3'])),'retained clipped zoom3','projected line clipped'))
  results.append(expect_rejected(lambda:reader.check_render(Member(raw,cases['native_normal']),24),'in-frame projection shifted24px','missing renderer line'))
  for name,row in index['images'].items():
   data=(HERE/'images'/name).read_bytes()
   assert digest(data)==row['sha256'] and len(data)==row['bytes'] and data==raw.read(row['raw_member'])
  sequence=index['sequence'];count=0
  for path in raw.namelist():
   if path.startswith(sequence+'/') and path.endswith('/receipt.json'):
    receipt=json.loads(raw.read(path));assert receipt['C364_same'] and receipt['frozen_leaf12_same'] and not receipt['performance']
    parent=path.rsplit('/',1)[0]
    before=json.loads(raw.read(parent+'/C-before.json'));after=json.loads(raw.read(parent+'/C-after.json'));context=json.loads(raw.read(parent+'/C-context-v14.json'))
    assert context['count']==364 and before==after==context['files']
    for name in ['queue-before.json','queue-after.json']:
     queue=json.loads(raw.read(parent+'/'+name))
     assert queue['8188']['running']==queue['8188']['pending']==0
     assert queue['8189']['status']=='absent' and queue['8189']['winerror']==10061
    count+=1
  assert count==4 # rejected zoom3 plus normal/2 faults at zoom2
  source_files=index['source']['members']
  assert source.read('final-producer/verify.py')==(HERE/'reader.py').read_bytes()
  proof=json.loads(source.read('earlier-review/feedback-leaf-comparison.json'))
  assert proof and all(v['same'] and v['original'] is not None for group in proof.values() for v in group.values())
  return {'accepted':True,'archive_members':{'raw':len(raw.namelist()),'source':len(source_files)},'normal_legacy_segments':24,'normal_debug_segments':12,'C364_and_queue_sequences_verified':count,'results':results,'engine_started':False,'raw_source':str(raw_path),'scope':index['limits']}
 finally:raw.close();source.close()

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--raw-root',type=Path);args=parser.parse_args()
 result=audit(args.raw_root)
 # Avoid dumping all per-segment data in a normal console review.
 print(json.dumps({k:v for k,v in result.items() if k!='results'},ensure_ascii=False,indent=2))

if __name__=='__main__':main()
