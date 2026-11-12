"""Keep strict HDR negatives; separately prove exact captured output equivalence."""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from PIL import Image
from verify_bg42_counterfactual_v2 import verify as verify_original
from verify_bg49_held import FORMATS,load_pixels,section

def ordered(values):
 dtype=np.dtype('<u2' if values.dtype.itemsize==2 else '<u4')
 bits=values.view(dtype).astype(np.int64);sign=1<<(dtype.itemsize*8-1)
 return np.where((bits&sign)!=0,sign-(bits&(sign-1)),sign+bits)

def compare_roi(folder,a,b,field):
 assert (a['width'],a['height'],a['format'],a['density'])==(b['width'],b['height'],b['format'],b['density'])
 assert a['canvas_transform_values']==b['canvas_transform_values']
 assert a['held']['lighting_owners']['viewport_final_transform_values']==b['held']['lighting_owners']['viewport_final_transform_values']
 ra,rb=a['player'][field],b['player'][field];assert ra==rb and all(float(v).is_integer()for v in ra)
 rect=list(map(int,ra));x,y,w,h=rect;assert w>0 and h>0 and x>=0 and y>=0 and x+w<=a['width']and y+h<=a['height']
 dtype,channels=FORMATS[a['format']];assert channels in [3,4],'all native channels must be compared'
 arrays=[];pngs=[]
 for r in [a,b]:
  raw=(folder/r['files']['raw']).read_bytes();assert hashlib.sha256(raw).hexdigest()==r['raw_sha256']
  array=np.frombuffer(raw,dtype=dtype).reshape(int(r['height']),int(r['width']),channels);assert np.isfinite(array).all()
  arrays.append(array[y:y+h,x:x+w].copy())
  with Image.open(folder/r['files']['png'])as image:
   assert image.mode=='RGBA'and image.size==(r['width'],r['height']);encoded=np.asarray(image)[y:y+h,x:x+w].copy()
   if channels==3:assert np.all(encoded[...,3]==255),'RGB source must encode its implicit opaque alpha'
   pngs.append(encoded)
 ulps=np.abs(ordered(arrays[0])-ordered(arrays[1]));equal=bool(np.array_equal(pngs[0],pngs[1]));maximum=int(ulps.max())
 return {'field':field,'rect':rect,'source_format':a['format'],'native_channels':channels,'native_alpha':'implicit opaque'if channels==3 else'present','png_mode':'RGBA','png_rgba_byte_equal':equal,'reference_png_roi_sha256':hashlib.sha256(pngs[0].tobytes()).hexdigest(),'product_png_roi_sha256':hashlib.sha256(pngs[1].tobytes()).hexdigest(),'hdr_changed_components':int(np.count_nonzero(arrays[0]!=arrays[1])),'hdr_changed_pixels':int(np.count_nonzero(np.any(arrays[0]!=arrays[1],axis=-1))),'maximum_native_format_ulp':maximum,'equivalent_at_captured_output':equal and maximum<=1}

def verify(folder):
 strict=verify_original(folder);exceptions=[]
 for path in folder.glob('*/*-index.json'):
  data=json.loads(path.read_bytes())
  for shot in data['shots']:
   records=shot['bg42']['records'];a,b=records[0],records[-1]
   for metric,fields in [('player',['screen_rect','outer_screen_rect']),('edge',['edge_screen_rect','below_screen_rect'])]:
    if 'player'not in a:continue
    value_key='contrast'if metric=='player'else'edge_contrast';delta=b['player'][value_key]-a['player'][value_key]
    if delta>=0:continue
    rois=[compare_roi(path.parent,a,b,field)for field in fields]
    exceptions.append({'level':data['level'],'column':shot['column'],'row':shot['row'],'metric':metric,'raw_delta_preserved':delta,'strict_hdr_no_worse':False,'rois':rois,'captured_output_equivalent':all(r['equivalent_at_captured_output']for r in rois)})
 # A new enemy regression cannot be excused by the player/edge-specific proof.
 enemy_decreases=[v for row in strict['observations']for v in row['enemy_deltas']if v<0]
 return {'absolute_original_thresholds_pass':strict['absolute_pass'],'strict_hdr_numeric_no_worse':strict['no_worse'],'captured_output_no_regression':strict['absolute_pass']and not enemy_decreases and all(e['captured_output_equivalent']for e in exceptions),'exceptions':exceptions,'cells':strict['cells'],'scope':'Only these recorded source-matched ROI captures. HDR negative values remain negative/strict=false. Separate exact RGBA PNG equality plus at most one adjacent native-format floating value per component; no epsilon, no lower absolute thresholds, no stochastic-noise or unseen-angle claim.','reader_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('folder',type=Path);p.add_argument('--out',type=Path,required=True);a=p.parse_args();result=verify(a.folder);a.out.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n');print(json.dumps({k:v for k,v in result.items()if k!='exceptions'}));raise SystemExit(0 if result['captured_output_no_regression']else 1)
