"""Copy completed original ZIPs and make explicitly derived, unscaled comparisons."""
from pathlib import Path
import argparse,hashlib,json,shutil,zipfile
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'pm/Nest-Egg/attachments/NE-277-contact-timing-2026-11-11'
IMAGES=ROOT/'pm/Nest-Egg/images'
def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def write(p,d):p.write_bytes((json.dumps(d,ensure_ascii=False,indent=2)+'\n').encode())
def copy_exact(source,target):
 target.parent.mkdir(parents=True,exist_ok=True)
 if target.exists():assert sha(target)==sha(source),str(target)+' already has different bytes'
 else:shutil.copyfile(source,target)
 assert sha(target)==sha(source)
def pack_file(source,name):
 with zipfile.ZipFile(source) as z:
  assert z.testzip() is None
 copy_exact(source,OUT/name)
 return {'file':name,'bytes':source.stat().st_size,'sha256':sha(source)}
def main():
 p=argparse.ArgumentParser();p.add_argument('--weapons',default='blade,dagger,glaive,maul,whip');a=p.parse_args()
 OUT.mkdir(exist_ok=True);IMAGES.mkdir(exist_ok=True)
 (OUT/'.gdignore').touch()
 (OUT/'.gitignore').write_bytes(b'__pycache__/\n*.pyc\n')
 (OUT/'.gitattributes').write_bytes(b'*.zip binary\n*.png binary\n*.wav binary\n*.json text eol=lf\n*.py text eol=lf\n*.md text eol=lf\n')
 records=[]
 for weapon in a.weapons.split(','):
  folder=ROOT/f'work/ne277-contact-native-{weapon}-final-v6'
  run=json.loads((folder/'run.json').read_bytes());assert run['passed'] and run['exit']==0 and not run['diagnostics']
  assert run['source_before_sha256']==run['source_after_sha256']
  records.append(pack_file(folder/'raw.zip',f'native-{weapon}-final.zip'))
 for weapon in ['maul','whip']:
  folder=ROOT/f'work/ne277-contact-native-{weapon}-early-negative-v6'
  run=json.loads((folder/'run.json').read_bytes());assert not run['passed'] and run['exit']==1
  assert run['source_before_sha256']==run['source_after_sha256']
  records.append(pack_file(folder/'raw.zip',f'native-{weapon}-early-negative.zip'))
  old=json.loads((folder/'contact-result.json').read_bytes())['rows'][0]
  good_folder=ROOT/f'work/ne277-contact-native-{weapon}-final-v6'
  rows=json.loads((good_folder/'contact-result.json').read_bytes())['rows']
  good=next(r for r in rows if r['side']==1 and r['move']==old['move'] and not r['held'])
  inputs=[folder/old['contact_first_image'],good_folder/good['contact_first_image']]
  canvas=Image.new('RGB',(2560,760),'#171922');draw=ImageDraw.Draw(canvas)
  font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',19)
  for i,(image,row) in enumerate(zip(inputs,[old,good])):
   with Image.open(image) as im:
    assert im.size==(1280,720);canvas.paste(im.convert('RGB'),(1280*i,40))
   hit=row['contact_hits'][0]
   text=('EARLY BROADPHASE CONTROL' if i==0 else 'PUBLISHED VISIBLE CONTACT')+f" / {weapon} / move {hit['progress']:.6f} / visible {hit['visual_progress']:.6f}"
   draw.text((1280*i+12,10),text,font=font,fill='white')
  target=IMAGES/f'NE-277-contact-{weapon}-before-after.png'
  canvas.save(target)
  write(OUT/f'{weapon}-comparison-provenance.json',{'scope':'unscaled original 1280x720 pixels pasted under a separate 40px label; actual native runtime early-broad control versus formal current source, not a reconstructed game frame','inputs':[{'file':str(x.relative_to(ROOT)),'sha256':sha(x)} for x in inputs],'output':target.relative_to(ROOT).as_posix(),'output_sha256':sha(target)})
 write(OUT/'native-archive-index.json',{'scope':'completed original ZIP copies; partial until all five weapons and final feedback/official regression are present','archives':records})
 print(json.dumps(records,indent=2))
if __name__=='__main__':main()
