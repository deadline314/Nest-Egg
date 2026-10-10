import sys,json,re,math,hashlib
from pathlib import Path
from PIL import Image
sys.dont_write_bytecode=True
R=Path('C:/Github/Nest-Egg'); O=Path('C:/tmp/scenery-wall-independent')
contacts=json.loads((R/'data/environment/scenery_contacts.json').read_text(encoding='utf8'))
wallmeta=json.loads((R/'data/environment/facade_wall_support.json').read_text(encoding='utf8'))
policy=json.loads((R/'assets_src/pipeline/scenery_placement.json').read_text(encoding='utf8'))
def field(t,k,default=None):
 m=re.search(r'^'+re.escape(k)+r' = (.*)$',t,re.M); return m[1] if m else default
def refs(t): return {m[2]:m[1] for m in re.finditer(r'\[ext_resource [^\]]*path="res://([^"]+)" id="([^"]+)"\]',t)}
def respath(t,k):
 v=field(t,k,'');m=re.search(r'ExtResource\("([^"]+)"\)',v);return refs(t).get(m[1]) if m else None
def strings(v): return re.findall(r'"([^"]+)"',v or '')
props={}
for p in (R/'data/environment').rglob('*.tres'):
 t=p.read_text(encoding='utf8');idv=field(t,'id');sv=field(t,'size');tex=field(t,'texture')
 if idv and sv and tex:
  ident=strings(idv)[0];size=list(map(float,re.findall(r'[-\d.]+',sv)[1:]))
  if ident in props: raise ValueError(('duplicate',ident))
  props[ident]={'size':size,'texture':strings(tex)[0],'resource':p.relative_to(R).as_posix(),'sway':float(field(t,'sway','0')),'scale_exempt':field(t,'scale_exempt','false')}
alpha={}
def alpha_info(path):
 if path not in alpha:
  with Image.open(R/path.removeprefix('res://')) as im:
   a=im.convert('RGBA').getchannel('A');bb=a.getbbox(); w,h=im.size
   top=h
   for y in range(h-1,-1,-1):
    if a.crop((0,y,w,y+1)).getextrema()[0]<128: break
    top=y
   alpha[path]={'size':[w,h],'bbox':list(bb) if bb else None,'min_alpha':a.getextrema()[0],'fullwidth_opaque_start':top/h}
 return alpha[path]
metadata_errors=[]
for path,f in wallmeta.items():
 a=alpha_info(path)
 if abs(f-a['fullwidth_opaque_start'])>1e-10: metadata_errors.append({'path':path,'declared':f,'actual':a['fullwidth_opaque_start']})
def parse_theme(path):
 if not path: return []
 t=(R/path).read_text(encoding='utf8');ex=refs(t);zs=[]
 for b in re.split(r'(?=\[sub_resource)',t)[1:]:
  if field(b,'from_tile') is None: continue
  z={'from':int(field(b,'from_tile')),'holes':float(field(b,'hole_chance','.22')),'interior':strings(field(b,'interior','')),'facades':[]}
  for rid in re.findall(r'ExtResource\("([^"]+)"\)',field(b,'facades','')):
   if rid not in ex:continue
   ft=(R/ex[rid]).read_text(encoding='utf8'); f={k:strings(field(ft,k,'')) for k in ('ground','body','cap')}
   if f['ground']:z['facades'].append(f)
  zs.append(z)
 return zs
# Intersections of all legal seeds, rather than a guessed Godot RNG seed.
def guaranteed_wall(rows,zones):
 width=len(rows[0]);height=len(rows);cols=math.ceil(width/4);ground=[];out=[]
 for c in range(cols):
  xs=range(c*4,min((c+1)*4,width));covered=sum(rows[0][x]=='#' for x in xs)
  surfaces=[]
  for x in xs:
   s=next((y*16 for y in range(height) if rows[y][x] in '#='),math.inf)
   if s>0:surfaces.append(s)
  ground.append(min(surfaces) if surfaces and min(surfaces)!=math.inf else height*16)
  out.append(covered*2<4)
 result=[];details=[]
 for c in range(cols):
  z=max((z for z in zones if z['from']<=c*4),key=lambda z:z['from'],default={'from':0,'holes':.22,'interior':[],'facades':[]})
  x=c*64
  if not out[c]:
   interioropaque=not z['interior'] or alpha_info(z['interior'][0])['min_alpha']>=128
   for row in range(math.ceil(height/4)):
    y=row*64
    if interioropaque and (z['holes']==0 or not(y>64 and y<height*16-128)):
     result.append([x,y,min(64,width*16-x),min(64,height*16-y)])
   details.append({'column':c,'outdoor':False,'hole_chance':z['holes'],'interior_opaque':interioropaque})
  else:
   # even random top = ground_even-[64,144]; odd reuses prior top then clamps.
   pg=ground[c-c%2]; depmin=max(32,ground[c]-pg+64); depmax=max(32,ground[c]-pg+144)
   fmin=max(1,int((depmin-48)/32));fmax=max(1,int((depmax-48)/32))
   if z['facades']:
    # guarantee base/body fullwidth opacity for every possible facade/variant.
    fractions={k:max(wallmeta.get(p,1) for f in z['facades'] for p in f[k]) for k in ('ground','body','cap')}
    if fractions['ground']<1:result.append([x,ground[c]-40+40*fractions['ground'],64,40*(1-fractions['ground'])])
    for i in range(fmin):
     result.append([x,ground[c]-40-32*(i+1)+32*fractions['body'],64,32*(1-fractions['body'])])
    if fmin==fmax:result.append([x,ground[c]-40-32*fmin-8+8*fractions['cap'],64,8*(1-fractions['cap'])])
   else:result.append([x,ground[c]-depmin,64,depmin])
   details.append({'column':c,'outdoor':True,'ground':ground[c],'possible_floors':[fmin,fmax]})
 return result,details
def subtract(a,b):
 x,y,w,h=a;u,v,j,k=b;ix=max(x,u);iy=max(y,v);ex=min(x+w,u+j);ey=min(y+h,v+k)
 if ex<=ix or ey<=iy:return [a]
 return [r for r in [[x,y,w,iy-y],[x,ey,w,y+h-ey],[x,iy,ix-x,ey-iy],[ex,iy,x+w-ex,ey-iy]] if r[2]>0 and r[3]>0]
def uncov(a,bs):
 cur=[a]
 for b in bs:cur=[r for x in cur for r in subtract(x,b)]
 return cur
records=[];other=[]
for p in sorted((R/'data/levels').glob('*_map.json')):
 d=json.loads(p.read_text(encoding='utf8'));rows=[''.join(seg[y] for seg in d['segments']) for y in range(len(d['segments'][0]))]
 lev=p.stem.removesuffix('_map');lp=R/'data/levels'/f'{lev}.tres';lt=lp.read_text(encoding='utf8') if lp.exists() else ''
 zones=parse_theme(respath(lt,'environment'));walls,details=guaranteed_wall(rows,zones)
 for e in d.get('props',[]):
  if e['id'] not in props: continue
  q=props[e['id']];w,h=q['size'];bottom=(e.get('y',0)+1)*16
  if e.get('ground'):
   center=min(max(e['x']+int(w/32),0),len(rows[0])-1)
   floor=next((yy*16 for yy in range(1,len(rows)) if rows[yy][center] in '#=~' and rows[yy-1][center]!='#'),None)
   if floor is None:continue
   bottom=floor+h*contacts.get(e['id'],{}).get('bottom_margin',0)
  if 'ceiling_row' in e:bottom=e['ceiling_row']*16+h
  rect=[e['x']*16+e.get('dx',0),bottom+e.get('dy',0)-h,w,h]
  b=contacts.get(e['id'],{}).get('bounds',[0,0,1,1]);b=list(b)
  if e.get('flip'):b[0],b[2]=1-b[2],1-b[0]
  vis=[rect[0]+w*b[0],rect[1]+h*b[1],w*(b[2]-b[0]),h*(b[3]-b[1])]
  a=alpha_info(q['texture']);actual=[a['bbox'][0]/a['size'][0],a['bbox'][1]/a['size'][1],a['bbox'][2]/a['size'][0],a['bbox'][3]/a['size'][1]]
  rec={'level':lev,'entry':e,'resource':q['resource'],'rect':rect,'visible_rect':vis,'size_H':[w/56,h/56],'all_seed_wall_covered':not uncov(vis,walls),'uncovered_all_seed_guarantee':uncov(vis,walls),'columns':[z for z in details if z['column']*64<vis[0]+vis[2] and (z['column']+1)*64>vis[0]],'sway':q['sway'],'contact_bbox_correct':all(abs(x-y)<1e-7 for x,y in zip(contacts.get(e['id'],{}).get('bounds',[0,0,1,1]),actual))}
  if e.get('support')=='wall':records.append(rec)
  elif e['id'] in policy['wall'] or re.search('sign|billboard|hook|lantern|lamp|shelf|calendar|hanging|pipe|camera|window|graffiti|instruments',e['id']):other.append(rec)
result={'root':str(R),'method':'Source-translated guaranteed wall region common to all legal seeds. Not exact seed/native renderer execution. Uncovered does not imply actual-seed failure. Pillow >=128 base texture alpha; no glow as structural support. H=56 authoring reference.', 'wall_count':len(records),'wall_records':records,'other_mount_style_records':other,'facade_alpha_metadata_mismatch':metadata_errors,'alpha_files':alpha}
(O/'wall-audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
lines=['|Level|Prop x,y|Logical rect|W/H, h/H|Wall covering guaranteed all seeds?|','|---|---|---|---|---|']
for v in records:
 e=v['entry'];lines.append(f"|{v['level']}|{e['id']} {e['x']},{e.get('y')}|{v['rect']}|{v['size_H'][0]:.3f}, {v['size_H'][1]:.3f}|{'yes' if v['all_seed_wall_covered'] else 'not certified: '+str(v['columns'])}|")
(O/'wall-inventory.md').write_text('\n'.join(lines)+'\n',encoding='utf8')
print('wall_count',len(records),'unresolved',[(v['level'],v['entry']['id'],v['entry']['x']) for v in records if not v['all_seed_wall_covered']]);print('facade_metadata_mismatches',metadata_errors);print('bad_contactbbox',[(v['level'],v['entry']['id']) for v in records if not v['contact_bbox_correct']]);print('othercount',len(other));print('CH1',[(v['level'],v['entry']['id'],v['rect'],v['size_H']) for v in records if v['level'].startswith('ch1_')])


