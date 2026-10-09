"""Native crop contact sheets, no resampling; original 1280x720 captures retained."""
import hashlib,json
from pathlib import Path
from PIL import Image,ImageChops,ImageDraw
root=Path(__file__).resolve().parents[4]
pics=root/'pm/Nest-Egg/images/NE-90-creature-subagent'
for face in [-1,1]:
 files=sorted(pics.glob(f'*frame119-face{face}-zoom3.4.png'))
 for group in range(2):
  crops=[]
  for p in files[group*8:(group+1)*8]:
   with Image.open(p) as im:
    area=im.convert('RGB').crop((0,110,1280,720)); diff=ImageChops.difference(area,Image.new('RGB',area.size,area.getpixel((0,0)))); box=diff.getbbox()
    crops.append((p,area.crop(box)))
  heights=[max(im.height for _,im in crops[i:i+2])+45 for i in range(0,len(crops),2)]
  width=max(im.width for _,im in crops)+40
  sheet=Image.new('RGB',(width*2,sum(heights)),(96,96,96)); draw=ImageDraw.Draw(sheet)
  for i,(p,im) in enumerate(crops):
   row=i//2; x=(i%2)*width+(width-im.width)//2; y=sum(heights[:row])+35
   sheet.paste(im,(x,y)); draw.text(((i%2)*width+10,sum(heights[:row])+10),p.name.split('-frame119')[0],fill=(240,240,240))
  sheet.save(pics/f'review-sheet-{group+1}-face{face}-native-crops.png')
index=[]
for p in sorted(pics.glob('*.png')):
 with Image.open(p) as im:index.append({'path':p.relative_to(root).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'native_size':list(im.size),'mode':im.mode,'kind':'derived-native-crop-sheet' if p.name.startswith('review-sheet') else 'native-Godot-capture'})
(Path(__file__).parent/'image-index.json').write_text(json.dumps(index,indent=2),encoding='utf-8')
