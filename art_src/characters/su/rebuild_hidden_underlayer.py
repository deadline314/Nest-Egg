"""Su-only source-coordinate authoring experiment. Never edits the retained design.

Manual source outlines and same-row cloth extension replace only genuinely hidden
material. This is authored reconstruction, not SAM or a successful Qwen output.
"""
from pathlib import Path
import os, json, hashlib
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / 'art_src/characters/su'
EVIDENCE = ROOT / 'assets_src/work/su-underlayer'
EVIDENCE.mkdir(parents=True, exist_ok=True)
base_path = WORK / 'base_rgba.png'
base = np.asarray(Image.open(base_path).convert('RGBA')).copy()
source_sha = hashlib.sha256(base_path.read_bytes()).hexdigest()
assert source_sha == 'd7c403d6c83fdffa39b068f239d7abbefae35aa3c66d6f31c0a07f141c5be4e5'
height, width = base.shape[:2]
spec_path = ROOT / 'tools/comfyui/specs/su_side.json'
spec = json.loads(spec_path.read_text(encoding='utf-8'))

outlines = {
    'arm': [[462,346],[479,350],[493,365],[506,390],[516,426],[522,466],[519,498],[507,533],
            [506,570],[508,621],[512,668],[516,718],[517,767],[508,778],[519,800],[525,829],
            [528,851],[520,884],[508,900],[492,904],[478,898],[463,880],[457,855],[455,823],
            [457,789],[442,778],[430,746],[421,705],[414,664],[409,623],[410,595],[396,571],
            [389,543],[396,511],[402,464],[401,426],[403,395],[415,374],[437,355]],
    'arm_far': spec['groups']['arm_far']['outline'],
    'leg_far': [[526,1340],[573,1340],[575,1375],[612,1385],[650,1404],[655,1446],
                [610,1453],[607,1437],[581,1418],[552,1406],[526,1390]],
    'head': [[400,0],[650,0],[650,240],[561,262],[540,254],[520,245],[495,236],[478,233],
             [445,236],[400,238]],
}

def polygon(points):
    mask = Image.new('L', (width, height), 0)
    ImageDraw.Draw(mask).polygon([tuple(point) for point in points], fill=255)
    return np.asarray(mask) > 0

masks = {name: polygon(points) & (base[:, :, 3] > 0) for name, points in outlines.items()}
core_occlusion = masks['arm'] | masks['arm_far']
affected = (np.asarray(Image.fromarray(core_occlusion.astype('uint8') * 255).filter(ImageFilter.MaxFilter(21))) > 0) & (base[:, :, 3] > 0)
result = base.copy()
result[affected] = 0
ys = np.array([346,375,450,525,600,675,710,733,780,830,905], dtype=float)
xs = np.array([423,405,400,395,390,382,380,414,426,430,431], dtype=float)
mapped = []
unfilled = []
for y in np.where(affected.any(axis=1))[0]:
    lo = int(round(float(np.interp(y, ys, xs))))
    front = int(round(620 - 0.14 * (y - 780))) if 780 <= y <= 860 else width - 1
    targets = np.where(affected[y] & (np.arange(width) >= lo) & (np.arange(width) <= front))[0]
    if not len(targets):
        continue
    # The unoccluded jacket/pants to the right supplies real hard-shaded cloth.
    # No skin, outline ink, zipper or new flat RGB is manufactured.
    band = range(550, 601) if 721 <= y < 735 else range(570, 601) if y < 735 else range(536, 586)
    candidates = []
    for x in band:
        r, g, b, a = (int(v) for v in base[y, x])
        navy = b > r * 1.1 and b >= g
        knit = 721 <= y < 735 and g >= r and b >= r * 0.8
        if a >= 250 and 18 <= r <= 120 and (navy or knit):
            candidates.append(x)
    if not candidates:
        unfilled.append(int(y))
        continue
    for x in targets:
        t = min(1.0, max(0.0, (int(x) - lo) / max(1, 526 - lo)))
        sx = candidates[min(len(candidates) - 1, int(round(t * (len(candidates) - 1))))]
        result[y, x] = base[y, sx]
        mapped.append([int(x), int(y), int(sx), int(y)])
assert not unfilled, f'No reviewed same-row cloth at rows {unfilled}'
assert np.array_equal(result[~affected], base[~affected]), 'Visible unaffected source changed'
assert hashlib.sha256(base_path.read_bytes()).hexdigest() == source_sha

stage = WORK / '04_stages'
stage.mkdir(exist_ok=True)
Image.fromarray(result).save(stage / 'P.png')
Image.fromarray(affected.astype('uint8') * 255).save(EVIDENCE / 'affected-source-mask.png')
for name, mask in masks.items():
    Image.fromarray(mask.astype('uint8') * 255).save(EVIDENCE / (name + '-outline-mask.png'))
    spec['groups'][name].pop('points', None)
    spec['groups'][name]['sam'] = []
    spec['groups'][name]['outline'] = outlines[name]
    spec['groups'][name]['authoring_method'] = 'Reviewed manual original-source outline, not SAM output'
spec['stages'][0]['authoring_method'] = 'Su-only same-row original cloth extension; failed Qwen startup retained separately'
spec['groups']['body']['complete']['occluders'] = ['arm', 'arm_far']
spec_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
np.savez_compressed(EVIDENCE / 'original-cloth-sample-map.npz',
                    source_xy=np.asarray(mapped, dtype=np.int32), source_sha=np.array(source_sha))
report = {'method': 'Manual source outlines + nearest original same-row cloth extension in hidden-only mask',
          'not_generated': True, 'source_sha256': source_sha, 'source_original_bytes_held': True,
          'native_size': [width, height], 'outside_affected_rgba_byte_exact': True,
          'affected_original_pixels': int(affected.sum()), 'hidden_cloth_samples': len(mapped),
          'removed_pixels_outside_inferred_body_silhouette': int(affected.sum()) - len(mapped),
          'outlines': outlines, 'inferred_back_boundary_y_x': [[int(y), int(x)] for y, x in zip(ys, xs)],
          'stage_P_sha256': hashlib.sha256((stage / 'P.png').read_bytes()).hexdigest(),
          'acceptance': 'Unaccepted authoring experiment; source/material/ownership/native plate/pose checks remain',
          'limitations': ['The occluded body silhouette is authored reconstruction, not observed anatomy.',
                         'A repeated plain cloth band may look flat; inspect real arm-raised poses before adopting.',
                         'Far hand sliver is removed from body, not used as a complete hand.',
                         'Both single-shoe ownership and actual sole contact require independent verification.']}
(EVIDENCE / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({k: v for k, v in report.items() if k not in ('outlines', 'inferred_back_boundary_y_x', 'limitations')}, indent=2))
