"""Preserve completed native outputs without claiming the formal regression is green."""
from pathlib import Path
import hashlib,json,shutil,zipfile
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'pm/Nest-Egg/attachments/NE-277-contact-timing-2026-11-11'
def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def copy(p,q):
 q.parent.mkdir(parents=True,exist_ok=True)
 if q.exists():assert sha(p)==sha(q),str(q)
 else:shutil.copyfile(p,q)
 assert sha(p)==sha(q)
def main():
 for weapon in ['blade','dagger','glaive','maul','whip']:
  for suffix in ['png','json']:
   copy(ROOT/f'work/ne277-hand-review-v6/{weapon}-hands.{suffix}',OUT/f'hand-review/{weapon}-hands.{suffix}')
 for name in ['build-packet.py','derive-feedback-audio.py','hand-pages.py','archive-current.py']:
  copy(Path(__file__).with_name(name),OUT/'authoring'/name)
 copy(ROOT/'work/ne277-timing-isolated/candidate-v6.json',OUT/'candidate-v6.json')
 candidate=json.loads((OUT/'candidate-v6.json').read_bytes())
 assert all(sha(ROOT/n)==value for n,value in candidate['source_sha256'].items())
 rows=[]
 for path in sorted(OUT.glob('*.zip')):
  with zipfile.ZipFile(path) as z:assert z.testzip() is None
  rows.append({'file':path.name,'bytes':path.stat().st_size,'sha256':sha(path)})
 (OUT/'native-archive-index.json').write_bytes((json.dumps({'scope':'Native five-weapon 42-row matrix and 36 feedback recordings complete. Formal affected65 v6 remains red: 88643 checks/2 new failures in reading/carry fixture, under diagnosis. This archive index is not a completed-ticket claim.','archives':rows},indent=2)+'\n').encode())
 print(json.dumps({'archives':len(rows),'candidate_sources':len(candidate['source_sha256'])}))
if __name__=='__main__':main()
