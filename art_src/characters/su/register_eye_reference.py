"""Su's GPT-expression reference registered only inside a source-coordinate eye ROI.
The generated face is never used as a replacement head. All original alpha and
all original RGBA outside the eye polygon are exact; reference downsizing is local.
"""
from pathlib import Path
import json, hashlib
import numpy as np
from PIL import Image, ImageDraw
WORK=Path(__file__).resolve().parent
ROOT=WORK.parents[2]
head_path=WORK/'overrides/refined/head.png'
head=np.array(Image.open(head_path).convert('RGBA'))
source=WORK/'base_rgba.png'
assert hashlib.sha256(source.read_bytes()).hexdigest()=='d7c403d6c83fdffa39b068f239d7abbefae35aa3c66d6f31c0a07f141c5be4e5'
assert head.shape==(1516,1037,4)
polygon=[[570,139],[576,134],[589,133],[607,138],[611,143],[608,150],[594,154],[578,148]]
mask_image=Image.new('L',(1037,1516),0)
ImageDraw.Draw(mask_image).polygon([tuple(p) for p in polygon],fill=255)
mask=(np.array(mask_image)>0)&(head[:,:,3]>0)
spec_path=ROOT/'tools/comfyui/specs/su_side.json'
spec=json.loads(spec_path.read_text(encoding='utf-8'))
refs={'half':'f65907806403c064c059afaae4c289d2bb55ef5aaeeebd10ef74c094b45333ff','closed':'69d21678fa443c6996e2e94903b08dd8893d8aa027e11ab22c6d21932c2485ba'}
sources={'original_head':{'path':head_path.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(head_path.read_bytes()).hexdigest()}}
review=[]
box=(550,110,630,170)
review.append(Image.fromarray(head).crop(box))
record={}
for name,sha in refs.items():
 reference=WORK/'eyes/references'/(name+'.png')
 assert hashlib.sha256(reference.read_bytes()).hexdigest()==sha
 # The GPT output is a reference at its own size. Map it back to the known
 # native 250x255 crop, whose retained source origin is (395,15).
 resized=np.array(Image.open(reference).convert('RGB').resize((250,255),Image.Resampling.LANCZOS))
 canvas=head.copy()
 # Authored -1/-1 native translation aligns the outer eye corners; no body/head resize.
 ys,xs=np.where(mask)
 canvas[ys,xs,:3]=resized[ys-15+1,xs-395+1]
 assert np.array_equal(canvas[:,:,3],head[:,:,3])
 assert np.array_equal(canvas[~mask],head[~mask])
 target=WORK/'eyes'/(name+'.png')
 Image.fromarray(canvas).save(target)
 sources[name]={'path':target.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
 record[name]={'reference_sha256':sha,'rgba_changed_pixels':int(np.any(canvas!=head,axis=2).sum()),'alpha_held':True,'outside_registered_mask_rgba_exact':True}
 review.append(Image.fromarray(canvas).crop(box))
spec['eye_states']={'part':'head','half_texture':'head_half','closed_texture':'head_closed','head_box':[395,15,645,270],'eye_mask':polygon,'sources':sources,'timing':{}}
spec_path.write_text(json.dumps(spec,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
sheet=Image.new('RGBA',(240,60),(128,128,128,255))
for i,tile in enumerate(review):sheet.alpha_composite(tile,(i*80,0))
sheet.resize((960,240),Image.Resampling.NEAREST).save(WORK/'eyes/review.png')
(WORK/'eyes/registration.json').write_text(json.dumps({'states':record,'mask':polygon,'native_reference_crop_origin':[395,15],'native_reference_registration_translation':[-1,-1],'original_head_sha256':sources['original_head']['sha256'],'model':'Built-in GPT ImageGen; exact model version/seed unavailable','not_entire_generated_face':True},indent=2)+'\n')
print('SU_REGISTERED_EYES',json.dumps(record))
