"""Plot actual log summaries; this is an evidence table, never a gameplay screenshot."""
from pathlib import Path
import hashlib,json,re,zipfile
from PIL import Image,ImageDraw,ImageFont
HERE=Path(__file__).resolve().parent
def main():
 raw=HERE/'controlled-raw.zip';index=json.loads((HERE/'controlled-index.json').read_bytes())
 assert hashlib.sha256(raw.read_bytes()).hexdigest()==index['raw_sha256']
 labels=[('original-stack-red','Original Shift / actual put-down stack','Original symptoms'),('neutral-key-only','Only Shift -> CapsLock','Carry symptoms removed'),('final-seven-grid','Final fixture / seven schedules','Pass'),('formal-path-original-carry','Formal helper path / original Carry','Pass'),('missing-mouse-negative','Omit the mouse event','Expected rejection'),('bound-shift-negative','Use gameplay-bound Shift again','Expected rejection'),('stopped-carry-negative','Stop real lift updates','Expected rejection'),('stopped-visual-negative','Stop normal pose updates','Expected rejection')]
 rows=[]
 with zipfile.ZipFile(raw) as z:
  for name,label,purpose in labels:
   log=z.read(name+'/process.log').decode('utf-8');match=re.search(r'checks: (\d+), failures: (\d+)',log)
   receipt=json.loads(z.read(name+'/receipt.json'))
   rows.append([label,match[1],match[2],str(receipt['exit']),purpose])
 image=Image.new('RGB',(1400,720),'#f4f5f8');draw=ImageDraw.Draw(image)
 font=lambda size,bold=False:ImageFont.truetype('C:/Windows/Fonts/'+('arialbd.ttf' if bold else 'arial.ttf'),size)
 draw.text((40,25),'NE-288 / recorded fixture results',font=font(30,True),fill='#202b3d')
 draw.text((40,75),'Headless source-fixed logs. This is a result table, not a gameplay screenshot or performance measurement.',font=font(20),fill='#435067')
 columns=[40,620,720,830,920,1360]
 for row,values in enumerate([['Actual case','Checks','Failures','Exit','Meaning']]+rows):
  top=125+row*50
  color='#26364d' if row==0 else ('#e5f3e9' if row in [3,4] else ('#fff1d9' if row>=5 else '#f7e8e8'))
  for column,value in enumerate(values):
   draw.rectangle((columns[column],top,columns[column+1],top+50),fill=color,outline='#d3d9e3')
   draw.text((columns[column]+10,top+13),value,font=font(20,row==0),fill='white' if row==0 else '#202b3d')
 draw.text((40,610),'The neutral-key run retains separate choice/death publication failures; only the final fixture is fully green.',font=font(20),fill='#435067')
 draw.text((40,655),'Raw ZIP SHA256: '+index['raw_sha256'],font=font(17),fill='#435067')
 output=HERE.parents[1]/'images/NE-288-input-publication.png';image.save(output)
 provenance={'scope':'Data visualization of original log summaries only; not gameplay, human evaluation or performance evidence.','raw_sha256':index['raw_sha256'],'output_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'rows':rows}
 (HERE/'plot-provenance.json').write_bytes((json.dumps(provenance,indent=2)+'\n').encode())
 print(output)
if __name__=='__main__':main()
