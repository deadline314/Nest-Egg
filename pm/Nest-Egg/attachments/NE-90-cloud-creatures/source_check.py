#!/usr/bin/env python3
"""Reproduce existing CPU cut in memory; never writes source/PNG/rig data.
Native gray alpha composites are analysis artifacts, not Godot screenshots.
"""
import argparse,importlib.util,json,hashlib,time
from pathlib import Path
import numpy as np
from PIL import Image
ap=argparse.ArgumentParser();ap.add_argument('--repo',required=True);args=ap.parse_args()
root=Path(args.repo).resolve();out=root/'pm/Nest-Egg/attachments/NE-90-cloud-creatures'
spec=importlib.util.spec_from_file_location('existing_cut',root/'tools/art/make_creature_parts.py')
cut=importlib.util.module_from_spec(spec);spec.loader.exec_module(cut)
rows=[];start=time.monotonic();composites=out/'source-gray';composites.mkdir(exist_ok=True)
for id,parts in cut.PARTS.items():
 for filename,name,axis,world in parts:
  source=root/'art_src/creatures'/id/filename;target=root/'art/creatures'/id/(name+'.png')
  src=Image.open(source);rgba=src.convert('RGBA');pixels=np.array(rgba)
  cleaned=cut.clean(src);factor=world*cut.SCALE/(cleaned.width if axis=='w' else cleaned.height)
  size=(max(1,round(cleaned.width*factor)),max(1,round(cleaned.height*factor)))
  reproduced=cleaned.resize(size,Image.Resampling.LANCZOS);delivered=Image.open(target).convert('RGBA')
  equal=reproduced.size==delivered.size and reproduced.tobytes()==delivered.tobytes()
  bg=Image.new('RGBA',rgba.size,(128,128,128,255));bg.alpha_composite(rgba)
  composite=composites/(id+'-'+filename);bg.save(composite)
  row=dict(id=id,part=name,source=str(source.relative_to(root)),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
     runtime=str(target.relative_to(root)),runtime_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
     source_native_size=src.size,source_mode=src.mode,source_alpha_bbox=rgba.getchannel('A').getbbox(),
     existing_cut_alpha=24,existing_crop_size=cleaned.size,k=factor,runtime_native_size=delivered.size,
     reproduced_rgba_equal=equal,reproduced_native_size=size,
     alpha0_nonzero_rgb_pixels=int(((pixels[:,:,3]==0)&(pixels[:,:,:3]!=0).any(2)).sum()),
     composite=str(composite.relative_to(root)),anatomy='UNVERIFIED',normal_glow='SEPARATE_GATE')
  rows.append(row)
report=dict(rows=rows,parts=len(rows),mismatches=sum(not r['reproduced_rgba_equal'] for r in rows),elapsed_seconds=time.monotonic()-start)
(out/'source-check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['parts','mismatches','elapsed_seconds']}))
