#!/usr/bin/env python3
"""Differential rendered negative controls and unchanged native representative crops."""
import argparse,gzip,importlib.util,json
from pathlib import Path
import numpy as np
from PIL import Image
p=argparse.ArgumentParser();p.add_argument('--repo',required=True);a=p.parse_args();root=Path(a.repo).resolve();out=root/'pm/Nest-Egg/attachments/NE-90-cloud-creatures';images=root/'pm/Nest-Egg/images/NE-90-cloud-creatures'
s=importlib.util.spec_from_file_location('original',root/'tools/check_joint_frames.py');c=importlib.util.module_from_spec(s);s.loader.exec_module(c);c.self_check()
def key(cell,z):return (cell['char'],cell['joint'],cell['actual_state'],cell['facing'],z)
def scan(groups):
 result={}
 for g in groups:
  sample=g['samples'][0];im=np.array(Image.open(out/sample['file']).convert('RGBA'))[:,:,3]
  for cell in g['cells']:
   x,y,w,h=cell['rect'];r=cell['radius'];cx=x+w//2;cy=y+h//2
   m=c.inspect(im[cy-r:cy+r,cx-r:cx+r]);m.update(file=sample['file'],rect=cell['rect'])
   result[key(cell,g['zoom'])]=m
 return result
def fail(m):return m['components']!=1 or m['hole_pixels']>0 or m['center_alpha']<128
positive=scan([g for g in json.loads((out/'frames.json').read_text()) if g['pose']=='actual_state_index0'])
negative=scan(json.loads((out/'negative-frames.json').read_text()));cases=[]
for k,m in negative.items():
 if k in positive and not fail(positive[k]) and fail(m):cases.append(dict(model=k[0],part=k[1],state=k[2],face=k[3],zoom=k[4],original=positive[k],moved_part=m))
if not cases:raise AssertionError('no newly induced failure; baseline failures cannot validate controls')
(out/'negative-control-delta.json').write_text(json.dumps(dict(induced_new_failures=len(cases),cases=cases),indent=2)+'\n')
models={m['id']:m for m in json.loads((out/'inventory.json').read_text())['models']};seen=set();rows=[]
with gzip.open(out/'contact-failures.jsonl.gz','rt') as f:
 for line in f:
  row=json.loads(line);k=(row['char'],row['kind'])
  if k in seen:continue
  seen.add(k);x,y,w,h=row['rect'];name=f"{row['char']}-{row['kind']}-{row['joint']}-{row['actual_state']}-frame{row['frame']}-face{row['facing']}-zoom{row['zoom']}-native-crop.png"
  Image.open(out/row['file']).crop((x,y,x+w,y+h)).save(images/name)
  row['native_crop']=str((images/name).relative_to(root));row['source_data_sha256']=models[row['char']]['data_sha256'];row['source_png_sha256']={p['path']:p['sha256'] for p in models[row['char']]['source_pngs']};row['note']='native unscaled pixels; flagged band is NOT a confirmed anatomy defect';rows.append(row)
(out/'representative-failures.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
print('induced_new_failures',len(cases),'representative_crops',len(rows))
