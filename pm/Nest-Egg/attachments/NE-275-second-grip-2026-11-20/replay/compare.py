from pathlib import Path
import json
import numpy as np
from PIL import Image

base=Path(__file__).resolve().parent.parent
prior=json.loads((base/'before/base-redraw.json').read_bytes())
new=json.loads((base/'after/base-redraw.json').read_bytes())
assert prior['failures']==new['failures']==0
for key in prior['cases']:
    a,b=[item['cases'][key] for item in (prior,new)]
    assert a==b,key
    print(key, [(a[n],b[n]) for n in ('idle_draws','attack_draws','idle_emission','attack_emission')])
    for mode in ('idle','attack'):
        name=key+'-'+mode+'.png'
        path=[base/run/name for run in ('before','after')]
        image=[np.asarray(Image.open(p).convert('RGB'),dtype=np.int16) for p in path]
        diff=np.abs(image[1]-image[0]); changed=(diff.max(axis=2)>0)
        assert not changed.any(),(key,mode,int(diff.max()))
        ys,xs=changed.nonzero()
        print(' ', mode, 'diff',len(ys),int(diff.max()),(int(xs.min()),int(ys.min()),int(xs.max()),int(ys.max())) if len(ys) else None)
        if key in ('blade','whip','blade-left') and len(ys):
            overlay=Image.fromarray(np.uint8(np.clip(diff*4,0,255)))
            overlay.save(base/(key+'-'+mode+'-diff.png'))
