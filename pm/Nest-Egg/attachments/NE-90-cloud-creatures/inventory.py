#!/usr/bin/env python3
"""Read-only creature/source inventory. Does not certify rendered seams or anatomy.
Run: python inventory.py --repo /absolute/repo --out /absolute/evidence
"""
import argparse, hashlib, json, re, subprocess, time
from pathlib import Path
from PIL import Image

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def png(p):
    with Image.open(p) as im:
        a = im.convert('RGBA').getchannel('A')
        return dict(path=str(p.relative_to(root)), sha256=sha(p), mode=im.mode,
                    native_size=list(im.size), alpha_bbox=a.getbbox(),
                    alpha_nonzero=sum(a.histogram()[1:]))

def git(*args):
    r = subprocess.run(['git','-C',str(root),*args], capture_output=True,text=True)
    return dict(command=['git',*args], code=r.returncode, stdout=r.stdout, stderr=r.stderr)

ap=argparse.ArgumentParser(); ap.add_argument('--repo',required=True); ap.add_argument('--out',required=True)
args=ap.parse_args(); root=Path(args.repo).resolve(); out=Path(args.out).resolve(); out.mkdir(parents=True,exist_ok=True)
t=time.monotonic()
mounts=[]
for p in sorted((root/'data/enemies').rglob('*.tres')):
    text=p.read_text()
    fields=dict(re.findall(r'^(rig_skin|rig_weapon|creature_skin)\s*=\s*"([^"]*)"',text,re.M))
    mounts.append(dict(path=str(p.relative_to(root)), sha256=sha(p), **fields,
                       behavior=re.findall(r'path="(res://game/enemies/[^\"]+)"',text),
                       raw=text))
models=[]
for p in sorted((root/'art/creatures').glob('*.json')):
    d=json.loads(p.read_text()); id=p.stem; parts=d.get('parts',[])
    kind='PartCreature' if parts else ('ChainCreature' if 'tentacles' in d else 'WormCreature')
    ledger=[]; seen=set(); errors=[]
    for part in parts:
        q=root/d.get('dir','res://art/creatures/'+id+'/').removeprefix('res://')/part['file']
        item=dict(part)
        if part.get('parent') and part['parent'] not in seen: errors.append('parent not earlier: '+part['name'])
        if part['name'] in seen: errors.append('duplicate part: '+part['name'])
        seen.add(part['name'])
        item['diffuse']=png(q) if q.exists() else {'missing':str(q)}
        item['auxiliary']=[png(q.with_name(q.stem+s+'.png')) for s in ['_n','_glow'] if q.with_name(q.stem+s+'.png').exists()]
        ledger.append(item)
    models.append(dict(id=id,kind=kind,data_sha256=sha(p),data=d,parts=ledger,
        native_pngs=[png(q) for q in sorted((root/'art/creatures'/id).glob('*.png'))],
        source_pngs=[png(q) for q in sorted((root/'art_src/creatures'/id).rglob('*.png'))],
        mounts=[m['path'] for m in mounts if m.get('creature_skin')==id],
        states=list(d.get('states',{})),structural_errors=errors,
        anatomy='UNVERIFIED',seams='UNVERIFIED',runtime='UNVERIFIED'))
callers=[]
for base in ['game','tests','tools']:
    for p in sorted((root/base).rglob('*.gd')):
        lines=[dict(line=n,text=line) for n,line in enumerate(p.read_text().splitlines(),1)
               if re.search(r'PartCreature|FootGait|ChainCreature|WormCreature|creature_skin|rig_skin',line)]
        if lines: callers.append(dict(path=str(p.relative_to(root)),sha256=sha(p),lines=lines))
tickets=[]
keys=['NE-90','NE-91','NE-92','NE-93','NE-98','NE-99','NE-100','NE-218']
for p in sorted((root/'pm/Nest-Egg').glob('*.md')):
    text=p.read_text()
    if any(p.name.startswith('['+k+']') for k in keys):
        tickets.append(dict(path=str(p.relative_to(root)),sha256=sha(p),text=text))
level_refs=[]
for p in sorted((root/'data/levels').glob('*.tres')):
    txt=p.read_text(); refs=re.findall(r'path="res://data/enemies/([^"]+)\.tres"',txt)
    if refs: level_refs.append(dict(path=str(p.relative_to(root)),sha256=sha(p),enemy_resource_refs=refs,note='resource references; not spawn count or real-input proof'))
portraits=[png(p) for p in sorted((root/'art/portraits').glob('*.png'))]
rosters=json.loads((root/'data/combat/chapter_rosters.json').read_text())
report=dict(level_resource_refs=level_refs,portraits=portraits,chapter_rosters=rosters,scope='pinned snapshot; freshness requires separately recorded fetch; acceptance gates separate',git=[git('status','--short','--branch'),git('rev-parse','HEAD','origin/main'),git('remote','-v')],
            mounts=mounts,models=models,callers=callers,tickets=tickets,elapsed_seconds=time.monotonic()-t)
(out/'inventory.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
rows=['# NE-90 非人形固定基線盤點（未完成驗收）','', '| 模型 | Runtime | 正式 Enemy 掛載 | 實際狀態 | 部件／鏈 | 結果 |','|---|---|---|---|---|---|']
for m in models:
    rows.append('| '+m['id']+' | '+m['kind']+' | '+', '.join(m['mounts'])+' | '+', '.join(m['states'])+' | '+str(len(m['parts']) if m['parts'] else len(m['data'].get('tentacles',[])))+' | 未驗：解剖、逐格接縫、實機 |')
rows+=['','watchdog：FAIL，rig_skin=warden，人形替身，NE218已存在。',
       'shock_hound：FAIL（四腳動畫資料覆蓋），body/tail兩件、gait.legs=[]；外觀肢數另看來源，不以資料推定。',
       'test_creature：測試fixture，無正式Enemy掛載，不當作已交付模型。',
       '', '完整部件帳本、原始JSON、RGBA原生尺寸、alpha bbox（只計alpha非零）、source SHA、掛點／父鏈／z／gait、全caller與原票Commit見inventory.json。',
       'PNG和資料檢查不是Godot截圖、解剖或逐格通過。未驗項不代勾。']
(out/'inventory.md').write_text('\n'.join(rows)+'\n')
print(json.dumps(dict(models=len(models),enemy_resources=len(mounts),elapsed_seconds=report['elapsed_seconds'])))
