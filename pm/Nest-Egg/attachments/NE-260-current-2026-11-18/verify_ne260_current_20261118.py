from pathlib import Path
import argparse,hashlib,json,sys
import numpy as np
from PIL import Image
sys.path.insert(0,str(Path(__file__).resolve().parent))
try:import verify_bg49_held as pixels
except ImportError:
 sys.path.insert(0,str(Path('C:/Users/stanl/Github/Nest-Egg/tools')))
 import verify_bg49_held as pixels

def image(folder,stem,width,height,fmt):
 raw=(folder/(stem+'.bin')).read_bytes();dtype,channels=pixels.FORMATS[fmt]
 value=np.frombuffer(raw,dtype=dtype).reshape(height,width,channels).astype(np.float64)
 assert np.isfinite(value).all()
 rgb=pixels.load_pixels(folder,{'width':width,'height':height,'format':fmt,'files':{'raw':stem+'.bin','png':stem+'.png'},'raw_sha256':hashlib.sha256(raw).hexdigest()})
 assert rgb.shape==(height,width,3)
 return value

def head(folder,r):
 assert r['bound_valid'] and r['source_held'] and r['expanded_geometry_fully_in_bounds']
 world=image(folder,r['files']['world_raw'][:-4],r['width'],r['height'],r['world_format'])
 mask=image(folder,r['files']['mask_raw'][:-4],r['width'],r['height'],r['mask_format'])
 assert mask.shape[2]==4
 yy,xx=np.nonzero(mask[...,3]>0);assert len(xx)>0
 rect=[int(xx.min()),int(yy.min()),int(xx.max()-xx.min()+1),int(yy.max()-yy.min()+1)]
 assert rect==r['sample_rect'];opaque=int((mask[...,3]>=.999).sum())
 white=int((pixels.section(world[...,:3],rect)>.92).all(axis=2).sum())
 assert opaque>0 and opaque==r['opaque_head_pixels'] and white==r['white_rectangle_pixels']
 rectangle_ratio=white/opaque;assert abs(rectangle_ratio-r['white_ratio_upper_bound'])<1e-12
 if 'white_head_ratio_upper_bound' in r:
  white_head=int(((world[...,:3]>.92).all(axis=2)&(mask[...,3]>0)).sum());assert white_head<=white and white_head==r['white_head_pixels_upper_bound']
  ratio=white_head/opaque;assert abs(ratio-r['white_head_ratio_upper_bound'])<1e-12 and ratio<=.02
 else:ratio=rectangle_ratio;assert ratio<=.02
 return ratio

def pair(folder,r):
 assert r['held'];matrix=pixels.affine(r['world_to_image']);feet=np.array(r['enemy_feet']);size=np.array(r['body_size'])
 a=(matrix@np.r_[feet+[-size[0]*.5,-size[1]],1])[:2];b=(matrix@np.r_[feet+[size[0]*.5,0],1])[:2]
 start=a.astype(int);extent=(b-a).astype(int);assert (extent>0).all()
 width,height=r['size'];assert (start>=0).all() and (start+extent<=[width,height]).all()
 values={}
 for state in ['on','off','restore']:
  raw=image(folder,r['files'][state],width,height,r['format'])
  x,y=start;w,h=extent;v=np.sort((raw[y:y+h:2,x:x+w:2,:3]@[.2126,.7152,.0722]).reshape(-1));assert len(v)>0
  values[state]=float(v[int(len(v)*.9):].mean());assert abs(values[state]-r[state])<=.00006,(state,values[state],r[state])
 assert abs(values['on']-values['restore'])<=.001
 return values['on']/max(values['off'],.0001)

def verify(folder,clean=True):
 report=json.loads((folder/'current-index.json').read_text());assert set(report['weapons'])=={'blade','dagger','glaive','maul','whip'}
 raw=(folder/'raw.log').read_bytes();assert b'SCRIPT ERROR:' not in raw and b'MELEE_ART_PROBE failures 0' in raw and b'AMD Radeon RX 9070 XT' in raw
 if clean:
  result=json.loads((folder/'result.json').read_text());assert result['exit']==0 and result['source_held'] and not result['error_lines'] and b'ERROR:' not in raw
  assert 'framing' in report
 if 'framing' in report:
  assert len(report['framing'])==len({r['name'] for r in report['framing']})==92
  for r in report['framing']:
   assert r['player_held'] and 0<r['zoom']<=3.4
   x,y,w,h=r['world_bounds'];matrix=pixels.affine(r['world_to_image']);corners=(matrix@np.array([[x,y,1],[x+w,y+h,1]]).T).T[:,:2]
   actual=np.r_[corners[0],corners[1]-corners[0]];assert np.max(np.abs(actual-r['screen_bounds']))<.0001
   assert (corners[0]>=-.01).all() and (corners[1]<=[640.01,360.01]).all() and (folder/(r['name']+'.png')).is_file()
 rows=[]
 for weapon,n in [('blade',3),('dagger',3),('glaive',2),('maul',2),('whip',1)]:
  r=report['weapons'][weapon];assert r['has_art'] and len(r['moves'])==n and len(r['head_exposure'])==n+1
  bound=max(head(folder,h) for h in r['head_exposure']);ratios=[pair(folder,m['light_pair']) for m in r['moves']]
  assert max(ratios)>1.15 and abs(max(m['light_pair']['on']/max(m['light_pair']['off'],.0001) for m in r['moves'])-r['paired_light_ratio'])<1e-10
  assert r['idle_light']>0 and r['swing_light']>r['idle_light']*1.2 and r['swing_light_reduced']<r['swing_light']*.95
  assert len(r['film_hands'])==(24 if weapon=='whip' else 8)
  for pose in ['idle','crouch','air','dash','left']:
   assert Image.open(folder/f'current-{weapon}-{pose}.png').size==(640,360)
  rows.append({'weapon':weapon,'head_bound':bound,'paired_linear_ratio':max(ratios),'moves':n,'film_frames':len(r['film_hands'])})
 assert len(list(folder.glob('*.png')))==159
 return {'pixel_checks_passed':True,'clean_native_required':clean,'rows':rows,'head_frames':16,'light_pairs':11,'images':159}

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('folder',type=Path);parser.add_argument('--pixels-only',action='store_true');a=parser.parse_args();print(json.dumps(verify(a.folder,not a.pixels_only),indent=2))
