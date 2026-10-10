import sys,json,re
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,'C:/tmp/scenery-wall-independent');import audit as a
rec=[]
for p in sorted((a.R/'data/levels').glob('*_map.json')):
 d=json.loads(p.read_text(encoding='utf8'));rows=[''.join(s[y] for s in d['segments']) for y in range(len(d['segments'][0]))]
 lev=p.stem.removesuffix('_map');lp=a.R/'data/levels'/f'{lev}.tres'
 if not lp.exists():continue
 t=lp.read_text(encoding='utf8');match=re.search(r'^decor = .*?\{(.*?)\}',t,re.M|re.S)
 if not match:continue
 mapping=dict(re.findall(r'"(.)": "([^"]+)"',match[1]));texts=a.strings(a.field(t,'sign_texts')) or ['拉麵','薬','酒場','義体','電腦'];walls,details=a.guaranteed_wall(rows,a.parse_theme(a.respath(t,'environment')))
 for y,row in enumerate(rows):
  for x,ch in enumerate(row):
   kind=mapping.get(ch)
   if kind not in ['neon_sign','neon_sign_h','billboard']:continue
   text=texts[abs(x*73856093 ^ y*19349663)%len(texts)]
   size=[21,len(text)*12+10] if kind=='neon_sign' else [len(text)*12+10,21]
   if kind=='billboard':size=[112,64]
   r=[x*16,y*16,*size];expanded=[r[0]-3.75,r[1]-.75,r[2]+7.5,r[3]+1.5] if kind=='billboard' else r
   rec.append({'level':lev,'kind':kind,'cell':[x,y],'text':text,'rect':r,'size_H':[v/56 for v in size],'base_guarantee':not a.uncov(r,walls),'jitter_frame_guarantee':not a.uncov(expanded,walls),'jitter_frame_rect':expanded})
(a.O/'decor-audit.json').write_text(json.dumps(rec,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
print('decor count',len(rec),'base uncertified',[r for r in rec if not r['base_guarantee']],'jitter uncertified',[r for r in rec if not r['jitter_frame_guarantee']])
