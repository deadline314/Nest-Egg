"""Prepare a diagnostic in a separate runtime checkout; never publishes a character."""
import hashlib, json, shutil, sys
from pathlib import Path
import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
assert len(sys.argv) == 2, 'Usage: prepare_native.py SEPARATE_RUNTIME_CHECKOUT'
TARGET = Path(sys.argv[1]).resolve()
assert TARGET != ROOT, 'Use a separate runtime checkout'
PRIVATE = TARGET / '.godot/ne222-walk-torso-22316-native'
assert (TARGET/'project.godot').is_file()
assert not PRIVATE.exists() or not any(PRIVATE.iterdir()), 'Preserve any earlier verification'
SOURCE = ROOT/'art_src/characters/rin_walk_torso_22316/source/rin_ne222_walk_torso_22316_FINAL_0.png'
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
assert sha(SOURCE) == 'b23eb0134bdda1f677751b2b7022e3b7ab747c2acc5906aa6aa706be55a3c5af'
for file in ['game/rig/character_rig.gd','game/rig/humanoid_animator.gd','game/rig/rig_part_mesh.gd',
             'art/characters/rin/character.json','art/rigs/humanoid_tall.json','art/motion/rin.json']:
    assert (ROOT/file).read_bytes().replace(b'\r\n',b'\n')==(TARGET/file).read_bytes().replace(b'\r\n',b'\n'), 'Historical runtime content differs: '+file
PRIVATE.mkdir(exist_ok=True)
sys.path.insert(0,str(ROOT/'tools/comfyui'))
from cut_layers import make_normal_map
from cut_parts import glow_layer
rgba=np.array(Image.open(SOURCE))
assert rgba.shape==(1408,864,4)
normal=make_normal_map(rgba)
assert np.array_equal(normal[:,:,3],rgba[:,:,3])
glow=glow_layer(rgba[:,:,:3],rgba[:,:,3],'cyan')
assert glow is not None and glow.shape==rgba.shape
Image.fromarray(normal).save(PRIVATE/'torso_n.png')
Image.fromarray(glow).save(PRIVATE/'torso_glow.png')
shutil.copy2(SOURCE,PRIVATE/'torso.png')
for file in ['capture.gd','capture.tscn']:
    shutil.copy2(HERE/file,PRIVATE/file)
mask=rgba[:,:,3]>0
n,labels,stats,_=cv2.connectedComponentsWithStats(mask.astype(np.uint8),8)
background=cv2.copyMakeBorder((~mask).astype(np.uint8),1,1,1,1,cv2.BORDER_CONSTANT,value=1)
flood=cv2.floodFill(background.copy(),None,(0,0),2)[1]
holes=int(((background==1)&(flood==1))[1:-1,1:-1].sum())
report={'status':'PRIVATE_INTACT_ARMOR_ONLY_NOT_ACCEPTED','source_sha256':sha(SOURCE),
        'components_alpha_gt_0':n-1,'component_areas':stats[1:,cv2.CC_STAT_AREA].tolist(),
        'enclosed_background_pixels':holes,'native_size':[864,1408],
        'density':0.04205/4,'pivot':[55*4+32,306*4+32],
        'axis_mapping':'new_source=(formal_crop_local*4)+32; proposed guide, not a human anatomy calibration',
        'source_to_world_anchor_error':0.0,
        'omissions':['damage counterpart','alpha seams','actual gameplay/cutscene','cyan armhole trim absent','outline cut by hard silhouette'],
        'runtime_inputs':{file:sha(TARGET/file) for file in ['game/rig/character_rig.gd','game/rig/humanoid_animator.gd','game/rig/rig_part_mesh.gd','art/characters/rin/character.json','art/rigs/humanoid_tall.json','art/motion/rin.json']},
        'private_inputs':{p.name:sha(p) for p in PRIVATE.iterdir() if p.is_file()}}
assert np.allclose((np.array([47,90])*4+32-np.array(report['pivot']))*report['density'],
                   (np.array([47,90])-np.array([55,306]))*.04205,atol=1e-12)
assert np.array_equal(np.array(Image.open(PRIVATE/'torso.png')),rgba)
(PRIVATE/'prepared-inputs.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
