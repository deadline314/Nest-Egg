"""Independent CPU sums from published TRES/map/story text; no Godot or live gameplay claim."""
from __future__ import annotations
import argparse,collections,hashlib,json,math,re
from pathlib import Path
ROOT=Path('C:/Users/stanl/.codex/worktrees/ne286-boss-cache-verification/Nest-Egg')
OUT=Path(__file__).resolve().parent
def save(path,value):Path(path).write_bytes((json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode())

class TextResource:
 def __init__(self,audit,path,text,section='resource',owner=None):
  self.audit=audit;self.path=path;self.owner=owner or self
  if owner is None:
   self.ext={};self.blocks={}
   headers=list(re.finditer(r'(?m)^\[([^\n]+)\]\s*$',text))
   for i,h in enumerate(headers):
    title=h.group(1);body=text[h.end():headers[i+1].start() if i+1<len(headers) else len(text)]
    if title.startswith('ext_resource '):
     props=dict(re.findall(r'(\w+)="([^"]*)"',title));self.ext[props['id']]=props['path']
    elif title=='resource':self.blocks['resource']=body
    elif title.startswith('sub_resource '):self.blocks[re.search(r'id="([^"]+)"',title)[1]]=body
  self.body=self.owner.blocks[section]
  fields=list(re.finditer(r'(?m)^([A-Za-z_][A-Za-z0-9_/]*)\s*=\s*',self.body))
  self.fields={m[1]:self.body[m.end():fields[i+1].start() if i+1<len(fields) else len(self.body)].strip() for i,m in enumerate(fields)}
 def value(self,key,default=None):
  raw=self.fields.get(key)
  if raw is None:return default
  return json.loads(raw[1:] if raw.startswith('&') else raw)
 def resolve(self,raw):
  m=re.fullmatch(r'(Ext|Sub)Resource\("([^"]+)"\)',raw);assert m,('unsupported resource reference',self.path,raw)
  if m[1]=='Ext':return self.audit.resource(self.owner.ext[m[2]])
  return TextResource(self.audit,self.owner.path+'::'+m[2],'',m[2],self.owner)
 def refs(self,key):
  raw=self.fields.get(key,'');items=[m[0] for m in re.finditer(r'(?:Ext|Sub)Resource\("[^"]+"\)',raw)]
  if raw.startswith('Array[ExtResource('):items=items[1:] # Typed array's first reference is its Script type.
  return [self.resolve(item) for item in items]
 def kind(self):
  script=self.fields.get('script','');m=re.fullmatch(r'ExtResource\("([^"]+)"\)',script)
  assert m,('resource has no explicit script',self.path)
  text=self.audit.read(self.owner.ext[m[1]])
  name=re.search(r'(?m)^class_name (\w+)',text);assert name
  return name[1]

class Audit:
 def __init__(self,root=ROOT,overrides=None):self.root=Path(root);self.overrides=overrides or {};self.cache={};self.checks=0;self.reads=set()
 def check(self,value,message):
  self.checks+=1
  assert value,message
 def read(self,path):
  assert path.startswith('res://') and '..' not in Path(path[6:]).parts
  self.reads.add(path);return Path(self.overrides.get(path,self.root/path[6:])).read_text(encoding='utf-8')
 def resource(self,path):
  if path not in self.cache:self.cache[path]=TextResource(self,path,self.read(path))
  return self.cache[path]
 def area(self,path):
  level=self.resource(path);layout=level.value('layout_path');raw=json.loads(self.read(layout));height=level.value('height',24)
  rows=['']*height
  for segment in raw['segments']:
   self.check(len(segment)==height,'malformed map segment height '+layout)
   width=max(map(len,segment));self.check(all(len(line)==width for line in segment),'ragged map segment '+layout)
   rows=[a+b for a,b in zip(rows,segment)]
  legend={json.loads(m[1]):level.resolve(m[2]) for m in re.finditer(r'("(?:[^"\\]|\\.)+"):\s*((?:Ext|Sub)Resource\("[^"]+"\))',level.fields.get('legend',''))}
  decor={json.loads(m[1]) for m in re.finditer(r'("(?:[^"\\]|\\.)+"):',level.fields.get('decor',''))}
  totals=dict.fromkeys(['piles','crates','enemies','reinforcements'],0);spawns=[];portals=[];boss_seen=False
  for y,row in enumerate(rows):
   for x,char in enumerate(row):
    if char in '#=^|~. PCH&*B0123456789' or char in decor:continue
    self.check(char in legend,'unknown map glyph '+repr((path,x,y,char)))
    res=legend[char];kind=res.kind();money=0;category=None
    if kind=='PortalData':portals.append({'target':res.value('target_level'),'requires_flag':res.value('requires_flag',''),'resource':res.path})
    if kind=='CreditPileData':category='piles';money=res.value('value',10)
    elif kind=='BreakableData':category='crates';money=res.value('credit_drop',0)
    elif kind=='EnemyData':
     if res.value('is_boss',False):self.check(not boss_seen,'multiple legacy boss glyphs');boss_seen=True
     category='enemies';money=res.value('credit_value',0)
    elif kind=='MechanismData' and res.value('kind',2)==5:
     category='reinforcements';children=res.refs('reinforcements')
     self.check(all(e.kind()=='EnemyData' for e in children),'invalid reinforcement resource')
     money=sum(e.value('credit_value',0) for e in children)
    if category:
     totals[category]+=money;spawns.append({'cell':[x,y],'glyph':char,'resource':res.path,'class':kind,'category':category,'declared_credits':money,'actor_id':res.value('id',''),'legacy_boss':res.value('is_boss',False) if kind=='EnemyData' else False})
  totals['total']=sum(totals.values())
  return {'path':path,'layout':layout,'totals':totals,'spawns':spawns,'portals':portals,'next_level':level.value('next_level',''),'death_cap':level.value('death_credit_cap',0),'death_ratio':level.value('death_credit_penalty',.05)}

 def verify(self,ledger):
  progression=self.read('res://autoload/progression.gd');pacing=self.read('res://core/pacing_estimate.gd')
  pawn_rate=float(re.search(r'(?m)^const PAWN_RATE := ([0-9.]+)$',progression)[1])
  interest=float(re.search(r'(?m)^const PAWN_INTEREST := ([0-9.]+)$',progression)[1])
  expected_deaths=int(re.search(r'(?m)^const EXPECTED_DEATHS := (\d+)$',pacing)[1])
  economy=self.read('res://core/economy_report.gd')
  required=dict((name,int(count)) for name,count in re.findall(r'&"([^"]+)": (\d+)',re.search(r'(?m)^const REQUIRED_SUPPLIES: Dictionary = (\{[^\n]+\})$',economy)[1]))
  self.check(bool(required),'empty supply definition')
  wallet=0;chapters=[];all_levels={}
  for path in sorted((self.root/'data/levels').glob('*.tres')):
   res=self.resource('res://'+path.relative_to(self.root).as_posix())
   if res.kind()=='LevelData':all_levels[res.path]=res
  for c,plan in zip(ledger['chapters'],ledger['plan'],strict=True):
   self.check(c['id']==plan['id'],'chapter/plan ordering mismatch')
   areas=[self.area(a['path']) for a in c['areas']]
   self.check(len({a['layout'] for a in areas})==len(areas),'layout counted more than once')
   main=dict.fromkeys(['piles','crates','enemies','reinforcements','total'],0);explore=main.copy()
   for raw,official in zip(areas,c['areas'],strict=True):
    self.check(raw['totals']==official['income'],'per-area raw map income differs '+raw['path'])
    self.check(official['route']==(raw['path'] in c['route']),'route classification differs')
    dest=main if official['route'] else explore
    for key in dest:dest[key]+=raw['totals'][key]
   self.check(main==c['map_main'] and explore==c['map_explore'],'chapter subtotal differs')
   paths={p:r for p,r in all_levels.items() if r.value('chapter','')==c['id']}
   alias={};first={}
   for path,res in paths.items():alias[path]=first.setdefault(res.value('layout_path',path),path)
   self.check(set(alias.values())=={a['path'] for a in areas},'canonical area coverage differs')
   graph={a['path']:[alias.get(p['target'],p['target']) for p in a['portals']]+([alias[a['next_level']]] if a['next_level'] in alias else []) for a in areas}
   story_path='res://data/story/'+c['id']+'.json';story=json.loads(self.read(story_path))
   waypoints=[c['entry']]+[step['location']['level'] for q in story['quests'] if q.get('kind','main')=='main' for step in q.get('steps',[]) if isinstance(step.get('location'),dict) and step['location'].get('level')]+[c['terminal']]
   legs=[]
   for start,end in zip(waypoints,waypoints[1:]):
    start=alias.get(start,start);end=alias.get(end,end);visited={start};queue=collections.deque([start])
    while queue and end not in visited:
     for nxt in graph[queue.popleft()]:
      if nxt in graph and nxt not in visited:visited.add(nxt);queue.append(nxt)
     # Only reachability is independently claimed here; the ledger selects its
     # own shortest route. Locked edges remain explicit assumptions, not unlock proof.
    self.check(end in visited,'raw static portal graph cannot connect '+start+' -> '+end)
    legs.append({'from':start,'to':end,'reachable_ignoring_locks':True})
   tx_ids=set();main_tx=side_tx=payments=0;transactions=[]
   for tx in c['transactions']:
    self.check(tx['id'] not in tx_ids,'transaction counted twice');tx_ids.add(tx['id'])
    registration=story['transactions'][tx['id']];res=self.resource(registration['resource']);amount=res.value('credits_delta',0)
    self.check(amount==tx['delta'] and res.value('id')==tx['id'],'registered transaction amount/id differs')
    if amount<0:payments+=amount
    elif tx['kind']=='side':side_tx+=amount
    else:main_tx+=amount
    transactions.append({'id':tx['id'],'resource':res.path,'delta':amount,'classification_from_ledger':tx['kind'],'quest':tx['quest']})
   self.check((main_tx,side_tx,payments)==(c['quest_main'],c['quest_side'],c['payments']),'transaction subtotal differs')
   supplies=[]
   for name,count in required.items():
    res=self.resource('res://data/consumables/'+name+'.tres');price=res.value('price',0);pawn=max(1,math.floor(price*pawn_rate));redeem=math.ceil(pawn*(1+interest))
    supplies.append({'id':name,'count':count,'price':price,'pawn':pawn,'redeem':redeem,'round_trip_loss':redeem-pawn})
   cost=sum(x['count']*x['price'] for x in supplies);self.check(cost==c['supplies']==plan['supplies'],'supply cost differs')
   cap=max(r.value('death_credit_cap',0) for r in paths.values());ratio=max(r.value('death_credit_penalty',.05) for r in paths.values())
   self.check((cap,ratio)==(c['death_cap'],c['death_ratio']),'death policy differs')
   opening=wallet;wallet+=main['total']+main_tx+payments;short=max(0,cost-wallet);wallet-=cost;deaths=[]
   for _ in range(expected_deaths):
    lost=math.floor(max(0,wallet)*ratio);lost=min(lost,cap) if cap>0 else lost;deaths.append({'before':wallet,'lost':lost,'after':wallet-lost});wallet-=lost
   self.check((wallet,sum(x['lost'] for x in deaths),short)==(plan['spare'],plan['deaths'],plan['short_before_supplies']),'three-death wallet differs')
   chapters.append({'id':c['id'],'areas':areas,'route':c['route'],'static_legs':legs,'opening_wallet':opening,'main_map':main,'explore_map':explore,'transactions':transactions,'supplies_and_pawn':supplies,'pawn_policy':{'rate':pawn_rate,'interest':interest},'death_policy':{'ratio':ratio,'cap':cap,'assumed_count':expected_deaths},'deaths':deaths,'closing_wallet':wallet})
  growth=[]
  candidates={}
  for folder,field in [('upgrades','cost'),('abilities','unlock_cost'),('arm_shield','cost')]:
   for path in sorted((self.root/'data'/folder).glob('*.tres')):
    res=self.resource('res://'+path.relative_to(self.root).as_posix());candidates[res.value('id')]=(res,field)
  for item in ledger['growth']:
   res,field=candidates[item['id']];price=res.value(field,0);self.check(price==item['price'] and price>0,'growth price differs '+item['id'])
   growth.append({'id':item['id'],'resource':res.path,'price':price,'category':item['category']})
  return {'checks':self.checks,'chapters':chapters,'growth':growth,'growth_total':sum(i['price'] for i in growth),'read_sources':sorted(self.reads),'source_overrides':{k:str(v) for k,v in self.overrides.items()},'scope':'Independent text/map sums and static portal reachability. Route locks are assumed open; declared drops are not proof the live actor pays. No natural playthrough or combat balance claim.'}

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('ledger',type=Path);parser.add_argument('--out',type=Path,required=True);parser.add_argument('--candidate-manifest',type=Path);parser.add_argument('--source-root',type=Path,default=ROOT);args=parser.parse_args()
 overrides={}
 if args.candidate_manifest:
  manifest=json.loads(args.candidate_manifest.read_bytes())
  for name,item in manifest['files'].items():
   if name.endswith('.tres'):
    path=Path(item['candidate']);assert hashlib.sha256(path.read_bytes()).hexdigest()==item['after_sha256'];overrides['res://'+name]=path
 result=Audit(root=args.source_root,overrides=overrides).verify(json.loads(args.ledger.read_bytes()));save(args.out,result);print(json.dumps({'checks':result['checks'],'growth_total':result['growth_total'],'output':str(args.out)}))

if __name__=='__main__':main()
