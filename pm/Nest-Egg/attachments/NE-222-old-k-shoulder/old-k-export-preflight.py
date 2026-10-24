from pathlib import Path
import json,sys,hashlib
import numpy as np
from PIL import Image
import cv2
root=Path('.');folder=root/'art_src/characters/old_k_shoulder_20261024';sys.path.insert(0,str(root/'tools/comfyui'));from cut_layers import part_transform,render_part,make_normal_map
spec=json.loads((root/'tools/comfyui/specs/old_k_side.json').read_text());k=spec['tex_px_per_wp']/spec['illustration_px_per_wp'];j={n:np.array(p,float)*k for n,p in spec['joints'].items()};source=Image.open(folder/'reference/torso-source.png').convert('RGBA');tr=part_transform(source,spec['parts']['torso'],j,k);rgba=render_part(source,tr,k)
original=np.array(Image.open(folder/'reference/torso-runtime.png'));normal=make_normal_map(rgba);n_original=np.array(Image.open(root/'art/characters/old_k/parts/torso_n.png'))
meta=json.loads((root/'art/characters/old_k/character.json').read_text())['textures']['torso']
r={'base':'bc8c0d4b6a83cde65f44498f77cdda2770a5603b','rgba_equal':bool(np.array_equal(rgba,original)),'normal_equal':bool(np.array_equal(normal,n_original)),'generated_size':Image.open(folder/'raw/torso-generated.png').size,'original_runtime_size':meta['size'],'calculated_size':[tr[1],tr[2]],'original_pivot':meta['pivot'],'calculated_pivot':[round(float(x),2) for x in tr[3]],'A':tr[0].tolist(),'scale':k,'source_alpha_bbox':source.getchannel('A').getbbox(),'generated_alpha_bbox':Image.open(folder/'raw/torso-generated.png').getchannel('A').getbbox(),'reference_runtime_alpha_bbox':Image.open(folder/'reference/torso-runtime.png').getchannel('A').getbbox(),'source_sha256':hashlib.sha256((folder/'reference/torso-source.png').read_bytes()).hexdigest(),'OpenCV':cv2.__version__,'NumPy':np.__version__}
if rgba.shape==original.shape:r['rgba_changed_pixels']=int(np.count_nonzero(np.any(rgba!=original,axis=2)))
if normal.shape==n_original.shape:r['normal_changed_pixels']=int(np.count_nonzero(np.any(normal!=n_original,axis=2)))
Path('/workspace/Nest-Egg/work/batch1024/old-k-export-baseline.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))
Image.fromarray(rgba).save('/workspace/Nest-Egg/work/batch1024/old-k-baseline-export-torso.png')
