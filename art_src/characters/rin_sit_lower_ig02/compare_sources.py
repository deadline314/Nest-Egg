from pathlib import Path
from PIL import Image, ImageDraw
import numpy as np, hashlib, json
root=Path(__file__).resolve().parents[3]
p1=root/'art_src/characters/rin_sit_lower_ig01/raw/source.png'
p2=root/'art_src/characters/rin_sit_lower_ig02/raw/source.png'
import sys
out=Path(sys.argv[1]).resolve()
out.mkdir(parents=True,exist_ok=True)
assert hashlib.sha256(p1.read_bytes()).hexdigest() == '8115265f8ca9e0dbb554c172a8a39f70148b5ab700b3cfd639f4abb690ea9550', 'IG01 source changed'
assert hashlib.sha256(p2.read_bytes()).hexdigest() == '4d6f40cabb7854071d5b7be71bf2185089e425043c1da0adbc7e1cf29bffc520', 'IG02 source changed'
im1=Image.open(p1).convert('RGBA'); im2=Image.open(p2).convert('RGBA')
a=np.asarray(im1); b=np.asarray(im2)
assert a.shape==b.shape,(a.shape,b.shape)
h,w=a.shape[:2]
diff=np.any(a!=b,axis=2)
chan_diff=(a!=b)
# The ticket's listed bounds are treated as half-open [x0,y0,x1,y1); inclusive counts are included as a robustness check.
def boxmask(box, inclusive=False):
 x0,y0,x1,y1=box
 if inclusive: x1+=1; y1+=1
 m=np.zeros((h,w),dtype=bool); m[y0:y1,x0:x1]=True; return m
regions={'target_roi':[85,284,224,568], 'broad_hip_roi':[65,250,380,575]}
metrics={
 'ig01':{'path':str(p1),'sha256':hashlib.sha256(p1.read_bytes()).hexdigest(),'size':list(im1.size),'mode':im1.mode},
 'ig02':{'path':str(p2),'sha256':hashlib.sha256(p2.read_bytes()).hexdigest(),'size':list(im2.size),'mode':im2.mode},
 'image':{'shape_hw':list(a.shape),'total_pixels':int(h*w),'changed_pixels':int(diff.sum()),'changed_channel_bytes':int(chan_diff.sum()),'changed_bbox_xyxy_inclusive':None,'max_abs_channel_delta':int(np.abs(a.astype(np.int16)-b.astype(np.int16)).max())},
 'regions':{}
}
ys,xs=np.where(diff)
if len(xs): metrics['image']['changed_bbox_xyxy_inclusive']=[int(xs.min()),int(ys.min()),int(xs.max()),int(ys.max())]
for name,box in regions.items():
 row={}
 for inclusive in [False,True]:
  m=boxmask(box,inclusive); tag='inclusive_xyxy' if inclusive else 'half_open_xyxy'
  row[tag]={'box':[int(box[0]),int(box[1]),int(box[2]+(1 if inclusive else 0)),int(box[3]+(1 if inclusive else 0))],
    'pixels':int(m.sum()),'changed_pixels':int((diff&m).sum()),'changed_channel_bytes':int((chan_diff&m[:,:,None]).sum()),
    'alpha_changed_pixels':int(((a[:,:,3]!=b[:,:,3])&m).sum()),
    'rgb_changed_pixels':int((((np.any(a[:,:,:3]!=b[:,:,:3],axis=2))&m)).sum())}
  inv=~m
  row[tag]['outside_roi']={'pixels':int(inv.sum()),'changed_pixels':int((diff&inv).sum()),'changed_channel_bytes':int((chan_diff&inv[:,:,None]).sum()),'alpha_changed_pixels':int((((a[:,:,3]!=b[:,:,3])&inv)).sum()),'rgb_changed_pixels':int((((np.any(a[:,:,:3]!=b[:,:,:3],axis=2))&inv)).sum())}
 metrics['regions'][name]=row
# Native-size source-only crop contact sheets. Boxes are half-open and labels are added only to contact sheets.
def contact(box,label):
 x0,y0,x1,y1=box; c1=im1.crop((x0,y0,x1,y1)).convert('RGB'); c2=im2.crop((x0,y0,x1,y1)).convert('RGB')
 sheet=Image.new('RGB',(c1.width+c2.width,c1.height+24),(32,32,32)); sheet.paste(c1,(0,24)); sheet.paste(c2,(c1.width,24)); d=ImageDraw.Draw(sheet); d.text((4,4),f'IG01 source-only | {label} | native pixels',fill='white');d.text((c1.width+4,4),f'IG02 source-only | {label} | native pixels',fill='white')
 return sheet
for n,box in regions.items():
 crop1=im1.crop(tuple(box)); crop2=im2.crop(tuple(box)); crop1.save(out/f'{n}_ig01_source_crop.png'); crop2.save(out/f'{n}_ig02_source_crop.png'); contact(box,n).save(out/f'{n}_side_by_side_native.png')
# Difference overlay: changed source pixels outlined in amber over IG01 crop; no geometry filtering.
diff_rgba=np.zeros((h,w,4),dtype=np.uint8); diff_rgba[diff]=[255,170,0,255]
diff_img=Image.fromarray(diff_rgba,'RGBA'); base=im1.copy(); base.alpha_composite(diff_img); base.save(out/'ig01_ig02_changed_pixels_overlay_native.png')
# Target-only RGB/alpha change mask at full native canvas.
maskimg=np.zeros((h,w,4),dtype=np.uint8); m=boxmask(regions['target_roi']); maskimg[m&diff]=[255,0,0,255]; Image.fromarray(maskimg,'RGBA').save(out/'target_roi_changed_pixels_native.png')
metrics['regions_convention']='Pixel box values from task treated as half-open [x0,y0,x1,y1); both half-open and inclusive counts reported.'
(out/'pixel_diff_metrics.json').write_text(json.dumps(metrics,indent=2),encoding='utf-8')
print(json.dumps(metrics,indent=2))
