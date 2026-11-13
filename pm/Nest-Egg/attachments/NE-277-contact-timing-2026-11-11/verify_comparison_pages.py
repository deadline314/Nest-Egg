"""Independently compare every pasted body/hand pixel and readback with sealed native inputs."""
from pathlib import Path
import argparse
import hashlib,io,json,zipfile
from PIL import Image,ImageChops
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
def sha(data):return hashlib.sha256(data).hexdigest()
def file_sha(path):
 with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def image(data):
 with Image.open(io.BytesIO(data)) as im:return im.convert('RGB').copy()
def exact_crop(page,source,rect):
 x,y,w,h=rect
 assert source.size==(w,h) and 0<=x<x+w<=page.width and 0<=y<y+h<=page.height
 assert ImageChops.difference(page.crop((x,y,x+w,y+h)),source).getbbox() is None,'source pixels changed'
def contiguous(frames):
 assert len(frames)==6 and all(b['readback']['tick']==a['readback']['tick']+1 for a,b in zip(frames,frames[1:])),'six consecutive original ticks required'
def main(raw_root=None):
 raw_root=Path(raw_root) if raw_root is not None else HERE
 provenance=json.loads((HERE/'motion-comparison-provenance.json').read_bytes());pages=cases=pixels=checks=0
 for part in provenance['parts']:
  path=raw_root/part['file'];assert file_sha(path)==part['sha256'] and path.stat().st_size==part['bytes']<100_000_000;checks+=3
  with zipfile.ZipFile(path) as output:
   assert output.testzip() is None;checks+=1
   index=json.loads(output.read('index.json'));sources={};results={}
   try:
    for name,archive in index['archives'].items():
     source=ROOT/archive['path']
     if Path(archive['path']).parent==HERE.relative_to(ROOT):source=raw_root/Path(archive['path']).name
     assert file_sha(source)==archive['sha256'];checks+=1
     sources[name]=zipfile.ZipFile(source);raw=sources[name].read('result.json');assert sha(raw)==archive['result_sha256'];checks+=1
     results[name]={row['name']:row for row in json.loads(raw)['rows']}
    names={entry['case'] for entry in index['pages']};cases+=len(names)
    assert len(names)==part['cases'] and len(index['pages'])==part['pages'];checks+=2
    for name in names:assert {entry['stage'] for entry in index['pages'] if entry['case']==name}=={'windup','active-entry','recovery-entry','return'};checks+=1
    for entry in index['pages']:
     raw=output.read(entry['image']);assert sha(raw)==entry['image_sha256'];page=image(raw)
     raw=output.read(entry['metadata']);assert sha(raw)==entry['metadata_sha256'];meta=json.loads(raw);checks+=2
     assert meta['case']==entry['case'] and meta['stage_anchor']==entry['stage'];checks+=2
     for version in ['before','after']:
      group=meta['versions'][version];row=results[group['archive']][meta['case']]
      assert all(row[key]==meta[alias] for key,alias in [('weapon','weapon'),('move','move'),('side','facing'),('held','held')]);checks+=4
      contiguous(group['frames']);checks+=1
      assert any(fact['readback']['phase']==meta['nominal_phase'] for fact in group['frames']);checks+=1
      for fact in group['frames']:
       assert fact['readback']==row['frames'][fact['original_frame_index']];checks+=1
       for original in fact['images']:
        raw=sources[group['archive']].read(original['path']);assert sha(raw)==original['sha256'];checks+=1
        exact_crop(page,image(raw),original['destination']);checks+=1;pixels+=1
     pages+=1
   finally:
    for source in sources.values():source.close()
 assert pages==168 and cases==42 and pixels==4032
 result={'checks':checks,'failures':0,'pages':pages,'matched_cases':cases,'source_body_and_hand_images_compared_pixel_exactly':pixels,'scope':'Derived review pages only. Different original contexts/timing are retained; no all-frame manual review, pixel A/A, recognition, feel or performance claim.'}
 print(json.dumps(result));return result
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--raw-root',type=Path,help='Directory holding the new motion/native ZIPs; older published before ZIPs stay in the repository.')
 main(parser.parse_args().raw_root)
