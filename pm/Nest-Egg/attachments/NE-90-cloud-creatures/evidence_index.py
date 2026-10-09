#!/usr/bin/env python3
"""Native screenshot index with real engine/driver/pixels, fixed capture baseline."""
import argparse,hashlib,json,subprocess,time
from pathlib import Path
from PIL import Image
p=argparse.ArgumentParser();p.add_argument('--repo',required=True);a=p.parse_args();root=Path(a.repo).resolve();out=root/'pm/Nest-Egg/attachments/NE-90-cloud-creatures';images=root/'pm/Nest-Egg/images/NE-90-cloud-creatures';start=time.monotonic()
rows=[]
for f in sorted(images.rglob('*.png')):
 with Image.open(f) as im: size=list(im.size);mode=im.mode
 rows.append(dict(path=str(f.relative_to(root)),sha256=hashlib.sha256(f.read_bytes()).hexdigest(),native_size=size,mode=mode,bytes=f.stat().st_size))
index=dict(capture_base='c0250bff9dd6a44a8b1c9df557eaab18b0a12996',diagnostic_old_base='a85b23f94c1ed96e3226191a6b026c91436efa68',current_head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),fetched_origin_main=subprocess.check_output(['git','rev-parse','origin/main'],cwd=root,text=True).strip(),fetch_success_log='fetch-before-save.log',engine='4.7.stable.official.5b4e0cb0f',default_engine_rejected='4.6.3.stable.official.7d41c59c4',renderer='gl_compatibility',driver='opengl3',adapter='llvmpipe (LLVM 19.1.7, 256 bits)',gpu=False,headless_audio_driver='Dummy',window_native_size=[1280,720],project_canvas=[640,360],project_stretch='canvas_items',atlas_cell_native_size=[128,128],atlas_width=2048,atlas_zoom=[1,3.4],status='review evidence; not delivered art acceptance',unverified=['Forward+HDR','real input','machine performance','material sole contact','full-color every frame','WormCreature joint alpha'],images=rows,elapsed_seconds=time.monotonic()-start)
(out/'evidence-index.json').write_text(json.dumps(index,ensure_ascii=False,indent=2)+'\n');print('native images',len(rows),'bytes',sum(r['bytes'] for r in rows))
