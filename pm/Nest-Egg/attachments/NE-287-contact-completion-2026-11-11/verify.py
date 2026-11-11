"""Read-only byte/source and independent native RGBH evidence verification."""
from pathlib import Path
import hashlib
import io
import json
import math
import re
import sys
import zipfile


def require(condition,message):
    if not condition:
        raise ValueError(message)


def verify(root):
    import numpy as np
    from PIL import Image
    receipt=json.loads((root/'archive.json').read_bytes())
    path=root/receipt['file']
    with path.open('rb') as source:digest=hashlib.file_digest(source,'sha256').hexdigest()
    require(path.stat().st_size==receipt['bytes'] and digest==receipt['sha256'],'archive changed')
    with zipfile.ZipFile(path) as archive:
        manifest=json.loads(archive.read('manifest.json'))
        require(len(manifest)==receipt['members'],'wrong member count')
        require(len(archive.namelist())==len(manifest)+1 and set(archive.namelist())==set(manifest)|{'manifest.json'},'unlisted/duplicate member')
        for member,expected in manifest.items():
            with archive.open(member) as source:digest=hashlib.file_digest(source,'sha256').hexdigest()
            require(archive.getinfo(member).file_size==expected['bytes'] and digest==expected['sha256'],f'changed member {member}')
        read=lambda name:json.loads(archive.read(name))
        unit=read('unit44/exit.json')
        require(unit['exit']==0 and not unit['error_lines'] and unit['sources_unchanged'],'unit process failed')
        unit_log=archive.read('unit44/run.log').decode('utf-8',errors='replace')
        match=re.search(r'NE287_UNIT (\{.*\})',unit_log)
        require(match is not None,'missing unit assertions')
        checks=json.loads(match[1]);require(checks['checks']==44 and not checks['failures'],'unit assertions failed')
        results={}
        for kind in ['old','new']:
            prefix=f'native-v4/{kind}/'
            run=read(prefix+'exit.json');meta=read(prefix+'scene.png.json');before=read(prefix+'before.json')
            require(run['exit']==(1 if kind=='old' else 0) and not run['error_lines'] and run['sources_unchanged'],f'{kind}: process expectation failed')
            require(before['source_before']==run['source_after'],f'{kind}: sources changed')
            for name,digest in before['source_before'].items():
                require(hashlib.sha256(archive.read(prefix+'source/'+name)).hexdigest()==digest,f'{kind}: source bytes missing')
            log=archive.read(prefix+'run.log').decode('utf-8',errors='replace')
            require('Forward+' in log and '9070 XT' in log and not re.search(r'SCRIPT ERROR|ERROR:|leaked at exit',log,re.I),f'{kind}: native diagnostics')
            require(meta['renderer']=='forward_plus' and meta['hdr_2d'] and meta['raw_format']==14 and meta['fixture_only'] and meta['not_full_story_playthrough'],f'{kind}: wrong rendering scope')
            distance=math.dist(meta['actual'],meta['expected'])
            require(abs(distance-meta['distance'])<1e-8,f'{kind}: position calculation')
            require(not meta['held'] and (distance<.08)==(kind=='new') and meta['settled_on_return']==(kind=='new'),f'{kind}: contact expectation')
            width,height=meta['image_size']
            raw=np.frombuffer(archive.read(prefix+'scene.png.bin'),dtype='<f2').reshape(height,width,3).astype(np.float64)
            require(np.isfinite(raw).all(),f'{kind}: nonfinite RGBH')
            linear=np.maximum(raw,0)
            srgb=np.where(linear<.0031308,linear*12.92,1.055*linear**(1/2.4)-.055)
            expected=(np.clip(np.concatenate((srgb,np.ones((height,width,1))),axis=2),0,1)*255).astype(np.uint8)
            actual=np.asarray(Image.open(io.BytesIO(archive.read(prefix+'scene.png'))).convert('RGBA'))
            error=np.abs(actual.astype(int)-expected.astype(int))
            require(error.max()<=1,f'{kind}: original HDR and PNG disagree')
            results[kind]=dict(exit=run['exit'],distance=distance,elapsed=meta['elapsed_on_return'],max_png_channel_error=int(error.max()))
        require(results['old']['elapsed']<.4 and results['new']['elapsed']>=.4,'nominal time still precedes actual consumption')
        return dict(members=len(manifest),unit_checks=checks['checks'],native=results,fixture_only=True)


if __name__=='__main__':
    root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parent
    try:print(json.dumps(verify(root),indent=2))
    except (OSError,ValueError,KeyError,zipfile.BadZipFile) as error:raise SystemExit(f'[NE287 evidence] {error}')
