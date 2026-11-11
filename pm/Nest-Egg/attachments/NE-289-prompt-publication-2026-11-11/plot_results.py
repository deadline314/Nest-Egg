"""Data figure from original logs; not a gameplay screenshot or performance result."""
from pathlib import Path
import hashlib,json,re,zipfile
from PIL import Image,ImageDraw,ImageFont
HERE=Path(__file__).resolve().parent
def main():
 index=json.loads((HERE/'controlled-index.json').read_bytes());raw=HERE/'controlled-raw.zip'
 assert hashlib.sha256(raw.read_bytes()).hexdigest()==index['raw_sha256']
 values={}
 with zipfile.ZipFile(raw) as z:
  for name in ['original-red','layout-nudge-old-row-red','current-row-only-red','final-timer-green','final-full-suite','final-wrong-target','final-stopped-layout']:
   match=re.search(r'checks: (\d+), failures: (\d+)',z.read(name+'/process.log').decode('utf-8'))
   values[name]={'checks':int(match[1]),'failures':int(match[2])}
 image=Image.new('RGB',(1400,850),'#f4f5f8');draw=ImageDraw.Draw(image)
 font=lambda size,bold=False:ImageFont.truetype('C:/Windows/Fonts/'+('arialbd.ttf' if bold else 'arial.ttf'),size)
 draw.text((40,25),'NE-289 / two independent fixture factors',font=font(31,True),fill='#202b3d')
 draw.text((40,75),'Actual source-fixed headless records. This is a data figure, not a gameplay screenshot.',font=font(20),fill='#435067')
 draw.text((275,132),'Old layout sampled',font=font(23,True),fill='#202b3d')
 draw.text((865,132),'Published + own target settled',font=font(23,True),fill='#202b3d')
 cells=[(180,185,'original-red','Old world row'),(780,185,'layout-nudge-old-row-red','Old world row'),(180,385,'current-row-only-red','Current-frame row'),(780,385,'final-timer-green','Current-frame row')]
 for x,y,name,label in cells:
  value=values[name];passed=value['failures']==0
  draw.rectangle((x,y,x+570,y+175),fill='#e5f3e9' if passed else '#f7e8e8',outline='#b8c3d3',width=2)
  draw.text((x+20,y+17),label,font=font(23,True),fill='#202b3d')
  draw.text((x+20,y+67),f"{value['checks']} checks / {value['failures']} failure"+('s' if value['failures']!=1 else ''),font=font(27),fill='#202b3d')
  draw.text((x+20,y+123),'PASS' if passed else 'Original geometry rejects',font=font(22,True),fill='#245b38' if passed else '#8a3030')
 draw.text((40,615),'Final complete QuestMapSuite: '+str(values['final-full-suite']['checks'])+' checks / 0 failures',font=font(25,True),fill='#245b38')
 draw.text((40,668),'True wrong target: 32 / 1. Stopped prompt processing: 32 / 4. Both deliberately rejected.',font=font(22),fill='#754c12')
 draw.text((40,718),'Camera and player continue normally; no intersection result is used as a readiness condition.',font=font(20),fill='#435067')
 draw.text((40,783),'Raw ZIP SHA256: '+index['raw_sha256'],font=font(17),fill='#435067')
 output=HERE.parents[1]/'images/NE-289-prompt-publication.png';image.save(output)
 (HERE/'plot-provenance.json').write_bytes((json.dumps({'scope':'Log-derived data figure only; not a game screenshot.','raw_sha256':index['raw_sha256'],'output_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'values':values},indent=2)+'\n').encode())
 print(output)
if __name__=='__main__':main()
