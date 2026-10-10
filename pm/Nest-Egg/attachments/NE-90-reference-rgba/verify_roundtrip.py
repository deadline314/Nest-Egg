"""Actual installed Comfy nodes, without loading a diffusion model or a VAE."""
import os, sys, json, hashlib
from pathlib import Path
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
os.environ['OUT_DIR'] = str(HERE/'outputs')
sys.path.insert(0, str(ROOT/'tools/comfyui'))
import comfy_api

HERE.mkdir(exist_ok=True)
pixels = np.empty((16, 16, 4), dtype=np.uint8)
alphas = [0, 1, 39, 40, 128, 254, 255, 64]
for y in range(16):
    for x in range(16):
        pixels[y,x] = [32+x*7, 48+y*8, 170-x*3, alphas[x%8]]
source = HERE/'reference.png'
Image.fromarray(pixels).save(source)
rgb_source = HERE/'reference_rgb.png'
Image.fromarray(pixels[:,:,:3]).save(rgb_source)
with comfy_api.comfy_guard.server_lock():
    comfy_api.comfy_guard.ensure_server()
names = [comfy_api.upload(p) for p in [source, rgb_source]]
graph = {
 'L0': {'class_type':'LoadImage','inputs':{'image':names[0]}},
 'A0': {'class_type':'JoinImageWithAlpha','inputs':{'image':['L0',0],'alpha':['L0',1]}},
 'L1': {'class_type':'LoadImage','inputs':{'image':names[1]}},
 'A1': {'class_type':'JoinImageWithAlpha','inputs':{'image':['L1',0],'alpha':['L1',1]}},
 'S0': {'class_type':'SaveImage','inputs':{'images':['L0',0],'filename_prefix':'NE90_reference_before_rgb'}},
 'S1': {'class_type':'SaveImage','inputs':{'images':['A0',0],'filename_prefix':'NE90_reference_after_rgba'}},
 'S2': {'class_type':'SaveImage','inputs':{'images':['A1',0],'filename_prefix':'NE90_reference_opaque_rgb'}},
}
paths = comfy_api.run(graph,'NE90_reference_roundtrip')
arrays = {}
for path in paths:
    with Image.open(path) as im:
        arrays[path.stem] = {'mode':im.mode,'size':list(im.size),'rgba':np.asarray(im.convert('RGBA')),
                            'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
before = next(v for k,v in arrays.items() if k.endswith('_S0_0'))
after = next(v for k,v in arrays.items() if k.endswith('_S1_0'))
opaque = next(v for k,v in arrays.items() if k.endswith('_S2_0'))
assert before['mode']=='RGB' and np.all(before['rgba'][:,:,3]==255)
assert after['mode']=='RGBA' and after['size']==[16,16]
assert np.array_equal(after['rgba'][:,:,:3], pixels[:,:,:3])
alpha_delta = after['rgba'][:,:,3].astype(int)-pixels[:,:,3].astype(int)
assert abs(alpha_delta).max() <= 1  # Float tensor save truncation is recorded, never used as a seam tolerance.
assert np.all(after['rgba'][:,:,3][pixels[:,:,3]==0] == 0)
assert np.all(after['rgba'][:,:,3][pixels[:,:,3]==255] == 255)
assert np.all(opaque['rgba'][:,:,3]==255)
assert np.array_equal(opaque['rgba'][:,:,:3],pixels[:,:,:3])
report = {'status':'actual_comfy_load_join_save_no_model', 'model_loaded':False,
 'graph':graph,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
 'input_alphas':alphas, 'output_alphas':[int(after['rgba'][0,x,3]) for x in range(8)],
 'alpha_byte_different_pixels':int(np.count_nonzero(alpha_delta)), 'max_alpha_byte_difference':int(abs(alpha_delta).max()),
 'rgb_byte_equal':True,'opaque_rgb_alpha_255':True,'outputs':{k:{n:v for n,v in item.items() if n!='rgba'} for k,item in arrays.items()},
 'node_source_sha256':{name:hashlib.sha256(Path('D:/ComfyUI',name).read_bytes()).hexdigest()
  for name in ['nodes.py','comfy_extras/nodes_compositing.py','comfy_extras/nodes_qwen.py']}}
(HERE/'roundtrip-report.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k not in ['graph','outputs','node_source_sha256']}),flush=True)
