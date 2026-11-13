"""Verify sealed NE277 v6 native/PCM evidence. Large originals are supplied with --raw-root."""
from pathlib import Path,PurePosixPath
import argparse,hashlib,io,json,sys,tempfile,wave,zipfile
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
sys.path.insert(0,str(ROOT/'tools'))
from ne277_verify import verify_motion,verify_feedback
from ne277_contact_verify import verify_contacts

PROFILES={'blade':'thermal_blade','dagger':'mono_dagger','glaive':'ion_glaive','maul':'hydraulic_maul','whip':'mono_whip'}
def digest(data):return hashlib.sha256(data).hexdigest()
def file_digest(path):
 with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
def extract(archive,target):
 assert all(not PurePosixPath(name).is_absolute() and '..' not in PurePosixPath(name).parts for name in archive.namelist())
 archive.extractall(target)
def expected(profile,weapon,feedback=False):
 moves=profile['combo']
 if feedback:
  choices=[moves[0]]+([moves[-1]] if len(moves)>1 else [])
  return {f'{weapon}/{side}/{move}/reduced-{str(reduced).lower()}' for side in [-1,1] for reduced in [False,True] for move in choices}
 return {f'{weapon}/{side}/{move}' for side in [-1,1] for move in moves+[profile['extension']['attack']]}|{f'{weapon}/{side}/{profile["hold"]["attack"]}-held' for side in [-1,1]}
def pcm_payload(raw):
 with wave.open(io.BytesIO(raw),'rb') as stream:
  assert stream.getframerate()==48000 and stream.getnchannels()==2 and stream.getsampwidth()==2
  return stream.readframes(stream.getnframes())

def main(raw_root):
 raw_root=Path(raw_root);index=json.loads((HERE/'external-raw-index.json').read_bytes())
 checks=0
 for record in index['files']:
  path=raw_root/record['name'];assert path.stat().st_size==record['bytes'] and file_digest(path)==record['sha256'];checks+=2
  with zipfile.ZipFile(path) as archive:assert archive.testzip() is None;checks+=1
 rows=steps=0;native_checks=0
 with tempfile.TemporaryDirectory(prefix='ne277-read-') as folder:
  temporary=Path(folder).resolve();assert temporary.parent==Path(tempfile.gettempdir()).resolve() and temporary.name.startswith('ne277-read-')
  for weapon,profile_name in PROFILES.items():
   target=temporary/weapon;target.mkdir()
   with zipfile.ZipFile(raw_root/f'native-{weapon}-final.zip') as archive:extract(archive,target)
   data=json.loads((target/'result.json').read_bytes());contact=json.loads((target/'contact-result.json').read_bytes());profile=json.loads((target/f'source/data/melee/{profile_name}.json').read_bytes())
   matrix=expected(profile,weapon)
   assert not verify_motion(data,matrix,target,native=True)
   assert data['rows']==contact['rows'] and not verify_contacts(contact,matrix,target,native=True)
   log=(target/'process.log').read_text(errors='replace')
   assert 'SCRIPT ERROR' not in log and 'ERROR:' not in log
   rows+=len(data['rows']);steps+=sum(len(row['frames']) for row in data['rows']);native_checks+=contact['checks'];checks+=6
  assert (rows,steps,native_checks)==(42,2724,9069)
  for weapon,control in [('maul','early'),('whip','early'),('maul','late')]:
   target=temporary/(weapon+'-'+control);target.mkdir()
   with zipfile.ZipFile(raw_root/f'native-{weapon}-{control}-negative.zip') as archive:extract(archive,target)
   data=json.loads((target/'result.json').read_bytes());matrix={row['name'] for row in data['rows']}
   assert verify_contacts(data,matrix,target,native=True),'intentional contact-control corruption must be rejected';checks+=1
  with zipfile.ZipFile(raw_root/'native-feedback-final.zip') as archive:
   data=json.loads(archive.read('result.json'));events=json.loads(archive.read('source/data/feel/sound_events.json'))['events']
   matrix=set()
   for weapon,profile_name in PROFILES.items():matrix|=expected(json.loads(archive.read(f'source/data/melee/{profile_name}.json')),weapon,True)
   assert not verify_feedback(data,matrix,events) and len(matrix)==36 and data['checks']==362
   master=archive.read('master.wav');pcm=pcm_payload(master)
   provenance=json.loads((HERE/'feedback-audio-provenance.json').read_bytes())
   assert digest(master)==provenance['master_sha256'] and digest(pcm)==provenance['pcm_sha256'];checks+=4
   for row in provenance['rows']:
    raw=(HERE/row['file']).read_bytes();clip=pcm_payload(raw)
    start,end=row['source_start_sample'],row['source_end_sample_exclusive']
    assert 0<=start<end and clip==pcm[start*4:end*4] and digest(clip)==row['pcm_sha256'] and digest(raw)==row['wav_sha256'];checks+=4
 print(json.dumps(dict(checks=checks,failures=0,native_rows=rows,contiguous_physics_steps=steps,native_checks=native_checks,feedback_rows=36,feedback_checks=362,
  scope='Sealed v6 native/PCM evidence only. V8 finite guards and final affected/performance have separate source receipts; no human/controller/listening/performance claim.')))
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--raw-root',type=Path,required=True)
 main(parser.parse_args().raw_root)
