"""Registered Su-only source reconstruction; no models or shared runtime changes."""
from pathlib import Path
import hashlib, json
import numpy as np
from PIL import Image, ImageDraw

WORK = Path(__file__).resolve().parent
ROOT = WORK.parents[2]
original = WORK / 'base_rgba.png'
assert hashlib.sha256(original.read_bytes()).hexdigest() == 'd7c403d6c83fdffa39b068f239d7abbefae35aa3c66d6f31c0a07f141c5be4e5'
base = np.array(Image.open(original).convert('RGBA'))
stage_path = WORK / '04_stages/P.png'
assert hashlib.sha256(stage_path.read_bytes()).hexdigest() == '7501aa21c2720c7e030ba02697ea86b9157d28b00e229feaadfc06c3ed8b8950'
stage = np.array(Image.open(stage_path).convert('RGBA'))
layers = {name: np.array(Image.open(WORK / '07_refined' / (name + '.png')).convert('RGBA'))
          for name in ['torso', 'leg_upper', 'head']}
assert base.shape == stage.shape == (1516, 1037, 4)
assert all(value.shape == base.shape for value in layers.values())
before = {name: value.copy() for name, value in layers.items()}
mask_image = Image.new('L', (base.shape[1], base.shape[0]), 0)
neck = [[479,220],[505,227],[535,235],[559,237],[559,261],[541,256],[524,247],[507,242],[492,239],[481,236]]
ImageDraw.Draw(mask_image).polygon([tuple(point) for point in neck], fill=255)
neck_mask = (np.asarray(mask_image) > 0) & (base[:, :, 3] > 0)
layers['torso'][neck_mask] = base[neck_mask]
# Recover only continuous original neck skin/ink below the former head cut.
# The lower green knitted collar is explicitly excluded by source material color.
head_polygon = [[478,229],[495,232],[520,239],[540,250],[561,257],
                [561,262],[540,257],[520,250],[514,248],[509,246],
                [505,244],[500,242],[494,240],[478,234]]
head_mask_image = Image.new('L', (base.shape[1],base.shape[0]),0)
ImageDraw.Draw(head_mask_image).polygon([tuple(p) for p in head_polygon],fill=255)
rgb = base[:,:,:3].astype(float)
skin_or_brown_ink = (rgb[:,:,0]>rgb[:,:,1]*1.1)&(rgb[:,:,0]>rgb[:,:,2]*1.2)
head_claim = (np.array(head_mask_image)>0)&(base[:,:,3]>0)&skin_or_brown_ink
layers['head'][head_claim] = base[head_claim]
assert np.array_equal(layers['head'][~head_claim],before['head'][~head_claim])
assert not np.any((layers['head'][:,:,3]>before['head'][:,:,3])&(base[:,:,3]==0))
mapped = []
ys, xs = np.where((layers['leg_upper'][:, :, 3] > 0) & (np.indices(base.shape[:2])[0] < 736))
for x, y in zip(xs, ys):
    sy = int(y) + 100
    # Original trouser material (after the documented hidden-hand reconstruction),
    # never the jacket/knitted hem that happened to occlude the hip disc.
    sx = min(585, max(536, int(x)))
    assert stage[sy, sx, 3] >= 250, (x, y, sx, sy)
    layers['leg_upper'][y, x, :3] = stage[sy, sx, :3]
    mapped.append([int(x), int(y), sx, sy])
assert np.array_equal(layers['leg_upper'][:, :, 3], before['leg_upper'][:, :, 3])
assert np.array_equal(layers['torso'][~neck_mask], before['torso'][~neck_mask])
out = WORK / 'overrides/refined'
out.mkdir(parents=True, exist_ok=True)
report = {'source_sha256': hashlib.sha256(original.read_bytes()).hexdigest(),
          'neck_original_source_polygon': neck,
          'head_continuous_source_neck_polygon':head_polygon, 'head_claim_pixels':int(head_claim.sum()),
          'head_outside_claim_unchanged':True, 'head_no_original_alpha0_filled':True, 'neck_original_rgba_samples': int(neck_mask.sum()),
          'hip_hidden_trouser_rgb_samples': len(mapped), 'hip_alpha_unchanged': True,
          'torso_outside_neck_unchanged': True, 'source_original_png_unchanged': True,
          'method': 'Authored hidden-layer reconstruction, not GPT/SAM model output', 'outputs': {}}
for name, pixels in layers.items():
    target = out / (name + '.png')
    Image.fromarray(pixels).save(target)
    report['outputs'][name] = {'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                             'rgba_changed_pixels': int(np.any(pixels != before[name], axis=2).sum())}
np.savez_compressed(out / 'trouser-source-map.npz', xy=np.asarray(mapped, dtype=np.int32))
(out / 'registration.json').write_text(json.dumps(report, indent=2) + '\n')
print('SU_REGISTERED_MANUAL_LAYERS', json.dumps(report, ensure_ascii=True))
