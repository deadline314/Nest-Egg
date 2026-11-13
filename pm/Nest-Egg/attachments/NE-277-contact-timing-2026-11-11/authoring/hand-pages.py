"""Unscaled consecutive native hand crops for human review; never replaces raw frames."""
from pathlib import Path
import argparse,json,hashlib
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser();p.add_argument('weapons',nargs='+');a=p.parse_args()
 out=ROOT/'work/ne277-hand-review-v6';out.mkdir(exist_ok=True)
 font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',15)
 for weapon in a.weapons:
  folder=ROOT/f'work/ne277-contact-native-{weapon}-final-v6'
  rows=json.loads((folder/'contact-result.json').read_bytes())['rows']
  groups=[]
  for row in rows:
   frames=row['frames']
   if row['held']:
    at=next(i for i,f in enumerate(frames) if f['phase']==3)
    start=max(0,at-2)
   else:
    tick=row['contact_hits'][0]['tick']
    at=next(i for i,f in enumerate(frames) if f['tick']>=tick)
    start=max(0,at-5)
   selected=frames[start:start+6]
   assert len(selected)==6 and all(b['tick']==a['tick']+1 for a,b in zip(selected,selected[1:]))
   pictures=[]
   for frame in selected:
    path=folder/frame['image'];path=path.with_name(path.stem+'-hands.png')
    with Image.open(path) as im:pictures.append((im.convert('RGB').copy(),path,frame))
   groups.append((row,pictures))
  cell_w=max(im.width for _,group in groups for im,_,_ in group)+8
  heights=[max(im.height for im,_,_ in group)+44 for _,group in groups]
  canvas=Image.new('RGB',(cell_w*6,sum(heights)+35),'#171922');draw=ImageDraw.Draw(canvas)
  draw.text((8,8),weapon+' / original native hand pixels / six consecutive physics steps',font=font,fill='white')
  metadata=[];top=35
  for (row,group),height in zip(groups,heights):
   draw.text((8,top),row['name']+(' / release' if row['held'] else ' / first contact'),font=font,fill='white')
   facts=[]
   for i,(im,path,frame) in enumerate(group):
    draw.text((i*cell_w+4,top+18),f"tick {frame['tick']} / {frame['progress']:.3f}",font=font,fill='#b9c1ce')
    canvas.paste(im,(i*cell_w+4,top+38))
    facts.append({'path':path.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'tick':frame['tick'],'phase':frame['phase'],'progress':frame['progress']})
   metadata.append({'name':row['name'],'frames':facts});top+=height
  canvas.save(out/f'{weapon}-hands.png')
  (out/f'{weapon}-hands.json').write_bytes((json.dumps({'scope':'selected six consecutive unscaled original native hand crops, not all-frame manual review','rows':metadata},indent=2)+'\n').encode())
  print(weapon,canvas.size)
if __name__=='__main__':main()
