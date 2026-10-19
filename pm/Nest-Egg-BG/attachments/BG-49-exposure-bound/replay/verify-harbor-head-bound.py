from pathlib import Path
import json,hashlib,numpy as np
from PIL import Image
b=Path(__file__).parent;results={}
for name,expected in [('bg49-head-bound-blank-v3',1),('bg49-head-bound-high-v3',0),('bg49-head-bound-low-v3',0)]:
 assert int((b/(name+'.exit')).read_text())==expected
 log=(b/(name+'.log')).read_text();assert 'llvmpipe' in log and 'Forward+' in log and not any(e in log for e in ['SCRIPT ERROR:','Parse Error:','Compile Error:','\nERROR:'])
 data=json.loads((b/name/'enemy-exposure.json').read_text());assert len(data['observations'])==3;values=[]
 for x in data['observations']:
  raw=x['raw_hdr'];assert raw['format']==14
  a=np.frombuffer((b/name/raw['file']).read_bytes(),dtype='<f2').reshape(raw['height'],raw['width'],3)
  px,py,w,h=x['screen_rect'];white=int(((a[py:py+h,px:px+w]>.92).all(axis=2)).sum());assert white==x['white_pixels_including_background']
  alpha=np.array(Image.open(b/name/f"sample{x['sample']:02d}-head-mask.png"))[:,:,3];count=int((alpha[py:py+h,px:px+w]==255).sum());outside=int((alpha==255).sum())-count
  assert count==x['mask']['opaque_head_pixels'] and outside==x['mask']['outside_rectangle']==0 and x['mask']['source_held']
  if expected:
   assert count==0 and x['enemy_white_ratio_upper_bound'] is None and not x['valid']
  else:
   ratio=white/count;assert abs(ratio-x['enemy_white_ratio_upper_bound'])<1e-14 and ratio<=.02 and x['valid'] and x['enemy_only_ratio'] is None
  values.append({'sample':x['sample'],'white_in_rectangle':white,'opaque_head_lower_bound':count,'enemy_white_upper_bound':white/count if count else None})
 results[name]={'exit':expected,'observations':values}
(b/'bg49-head-bound-independent-verification.json').write_text(json.dumps({'method':'independent numpy float16 RGB readback and PIL opaque alpha count; no image edits','hdr_format':14,'encoding':'little-endian RGB half floats from Linux x86_64 Godot4.7.2','results':results},indent=2)+'\n')
print(json.dumps(results,indent=2))
