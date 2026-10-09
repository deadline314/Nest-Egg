#!/usr/bin/env python3
"""Existing alpha metrics on actual nonhuman bands; never certifies anatomy.
Zero/empty coverage fails. Single-source bands and joint-pair bands stay distinct.
Open notches and legal silhouette openings require source/mask review.
"""
import argparse, importlib.util, json, hashlib, time, gzip
from pathlib import Path
import numpy as np
from PIL import Image
ap=argparse.ArgumentParser();ap.add_argument('--repo',required=True);ap.add_argument('--negative-control',action='store_true')
args=ap.parse_args();root=Path(args.repo).resolve();out=root/'pm/Nest-Egg/attachments/NE-90-cloud-creatures'
spec=importlib.util.spec_from_file_location('existing_checker',root/'tools/check_joint_frames.py')
checker=importlib.util.module_from_spec(spec);spec.loader.exec_module(checker);checker.self_check()
groups=json.loads((out/('negative-frames.json' if args.negative_control else 'frames.json')).read_text())
if not groups or not all(g['cells'] and g['samples'] for g in groups): raise ValueError('empty contact set forbidden')
start=time.monotonic(); failures=[]; summary={}; counts={}; total=0; images={}
for g in groups:
 for sample in g['samples']:
  p=(out/sample['file']).resolve()
  images[str(p.relative_to(root))]=dict(native_size=Image.open(p).size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
  alpha=np.array(Image.open(p).convert('RGBA'))[:,:,3]
  for c in g['cells']:
   x,y,w,h=c['rect'];r=c['radius'];cx=x+w//2;cy=y+h//2
   if r>=min(w,h)//2: raise ValueError('band clipped')
   metrics=checker.inspect(alpha[cy-r:cy+r,cx-r:cx+r]);total+=1
   counts[c['char']]=counts.get(c['char'],0)+1
   if metrics['components']!=1 or metrics['hole_pixels'] or metrics['center_alpha']<128:
    key='/'.join([c['char'],c['joint'],c['actual_state'],str(c['facing']),str(g['zoom'])])
    summary[key]=summary.get(key,0)+1
    failures.append(dict(c,zoom=g['zoom'],**sample,**metrics,driver='opengl3',renderer='gl_compatibility',verdict='FLAGGED_BAND_REQUIRES_SOURCE_REVIEW'))
report=dict(samples=total,flagged_samples=len(failures),per_species_samples=counts,summary=summary,failures=failures,
            images=images,elapsed_seconds=time.monotonic()-start,empty_sets_allowed=False,
            metrics='unchanged tools/check_joint_frames.py inspect; alpha>=128; 8 world pixel radius; one pixel holes count',
            excluded='WormCreature top_level body; anatomy/full color/normal/glow/input/Forward/perf are separate unverified gates')
if not args.negative_control:
 failure_path=out/'contact-failures.jsonl.gz'
 with gzip.open(failure_path,'wt',encoding='utf-8') as f:
  for failure in failures: f.write(json.dumps(failure,ensure_ascii=False)+'\n')
 report.pop('failures');report['failures_file']=failure_path.name
(out/('negative-report.json' if args.negative_control else 'contacts-report.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:report[k] for k in ['samples','flagged_samples','per_species_samples','elapsed_seconds']}))
if args.negative_control:
 if not failures: raise AssertionError('rendered separated-part negative control was not caught')
else:
 raise SystemExit(1 if failures else 0)
