from pathlib import Path
import hashlib,json,sys
import numpy as np
from PIL import Image
from verify_bg49_held import FORMATS
def verify(folder):
 quality=folder.name;assert quality in ['low','high'];parent=folder.parent
 assert json.loads((parent/'source-before.json').read_text())==json.loads((parent/'source-after.json').read_text())
 run=next(r for r in json.loads((parent/'runs.json').read_text()) if r['quality']==quality)
 assert run['exit']==run['script_errors']==0 and not run['engine_error'] and run['source_held'] and any('gpu_lock.py' in p for p in run['command'])
 log=(folder/'raw.log').read_text();assert 'Forward+' in log and 'AMD Radeon RX 9070 XT' in log
 s=json.loads((folder/'sun.json').read_text());assert s['quality']==(0 if quality=='low' else 2)
 def pixels(record):
  raw=(folder/record['raw']).read_bytes();assert hashlib.sha256(raw).hexdigest()==record['sha256'] and len(raw)==record['bytes']
  dtype,channels=FORMATS[record['format']];assert channels in [3,4] and (record['width'],record['height'])==(640,360)
  values=np.frombuffer(raw,dtype=dtype).reshape(record['height'],record['width'],channels).astype(np.float64);assert np.isfinite(values).all()
  with Image.open(folder/record['png']) as im:
   assert im.size==(640,360)
  return values
 assert FORMATS[s['alpha']['format']][1]==4
 alpha=pixels(s['alpha'])[...,3];opaque=alpha>=.99
 assert int(opaque.sum())>=32,'Opaque body mask is empty or too small'
 yy,xx=np.where(opaque);assert xx.min()>0 and yy.min()>0 and xx.max()<639 and yy.max()<359
 for part in s['alpha']['drawables']:
  assert part['source_geometry']==part['copy_geometry'] and np.array_equal(part['source_transform'],part['copy_transform'])
 records=s['records'];assert [r['label'] for r in records]==['off-0','on-0','on-1','off-restore','on-final'] and [r['enabled'] for r in records]==[False,True,True,False,True]
 assert records[0]['sha256']==records[3]['sha256'] and records[1]['sha256']==records[2]['sha256']==records[4]['sha256']
 target=[r for r in records[0]['owners']['scene_lights'] if '/sun_patch/' in r['path']];assert len(target)==1;ident=target[0]['instance']
 other=lambda r:[x for x in r['owners']['scene_lights'] if x['instance']!=ident]
 means=[]
 for r in records:
  assert r['hidden_ui'] and all(not x['visible'] for x in r['hidden_ui']) and r['hidden_ui']==records[0]['hidden_ui']
  assert r['pose']==records[0]['pose'] and r['camera']==records[0]['camera'] and r['light_position']==records[0]['light_position']
  assert abs(r['energy']-.9)<2e-6 and r['owners']['valid'] and other(r)==other(records[0])
  light=next(x for x in r['owners']['scene_lights'] if x['instance']==ident);assert light['enabled']==r['enabled'] and light['visible'] and light['energy']==r['energy']
  image=pixels(r);means.append(float((image[...,:3]@[.2126,.7152,.0722])[opaque].mean()))
 assert means[1]>means[0],'Actual point light must brighten opaque player pixels'
 pixels(s['outside'])
 return {'passed':True,'opaque_pixels':int(opaque.sum()),'off_mean':means[0],'on_mean':means[1],'ratio':means[1]/means[0],'stable_restorations':True,'same_pose':True,'other_lights_held':True,'records':len(records),'scope':'Opaque CPU-drawable union, actual same-pose PointLight2D toggle; original glow art stays visible. No head-exposure or performance claim.'}
if __name__=='__main__':
 folder=Path(sys.argv[1]);result=verify(folder);(folder/'independent.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result),flush=True)
