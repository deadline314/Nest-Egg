"""Rebuild reviewed visible source cuts, without generation or runtime adoption."""
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def main():
    spec = json.loads((HERE / 'selection.json').read_text(encoding='utf-8'))
    source_path = HERE.parent / 'raw/source.png'
    assert hashlib.sha256(source_path.read_bytes()).hexdigest() == spec['source_sha256']
    liked = ROOT / 'art_src/characters/rin2/base_rgba.png'
    assert hashlib.sha256(liked.read_bytes()).hexdigest() == spec['liked_standing_sha256']
    source = np.asarray(Image.open(source_path).convert('RGBA'))
    assert source.shape == (1516, 1037, 4)
    report = {}
    for name, part in spec['parts'].items():
        canvas = np.zeros(source.shape[:2], dtype=np.uint8)
        polygons = [part['polygon_xy'], *part['additional_polygons'].values()]
        for polygon in polygons:
            cv2.fillPoly(canvas, [np.asarray(polygon, dtype=np.int32)], 255)
        selected = (canvas > 0) & (source[:, :, 3] > 0)
        for component in part['removed_source_sampling_halos']:
            for x, y, expected in component['pixels_xy_rgba']:
                assert source[y, x].tolist() == expected == [0, 0, 0, 1]
                assert selected[y, x], (name, x, y)
                selected[y, x] = False
        assert int(selected.sum()) == part['expected_pixels']
        assert cv2.connectedComponents(selected.astype(np.uint8), 8)[0] == 2

        def valid(candidate):
            return all(candidate[y, x] for x, y in part['required_material_xy']) and not any(candidate[y, x] for x, y in part['forbidden_other_owner_xy'])

        assert valid(selected)
        controls = 0
        for expected, points in ((True, part['required_material_xy']), (False, part['forbidden_other_owner_xy'])):
            for x, y in points:
                mutated = selected.copy()
                mutated[y, x] = not expected
                assert not valid(mutated), (name, x, y)
                controls += 1
        ys, xs = np.where(selected)
        box = [int(xs.min()), int(ys.min()), int(xs.max())+1, int(ys.max())+1]
        x0, y0, x1, y1 = box
        cut = np.zeros_like(source)
        cut[selected] = source[selected]
        Image.fromarray(selected.astype(np.uint8)*255).save(HERE / f'{name}-mask.png')
        Image.fromarray(cut[y0:y1,x0:x1], 'RGBA').save(HERE / f'{name}.png')
        reopened = np.asarray(Image.open(HERE / f'{name}.png'))
        assert np.array_equal(reopened, cut[y0:y1,x0:x1])
        assert np.array_equal(cut[selected], source[selected])
        assert not np.any(cut[~selected])
        report[name] = {'source_crop_xyxy': box, 'native_size': [x1-x0,y1-y0], 'pixels': int(selected.sum()), 'negative_controls_rejected': controls, 'status': 'SOURCE ONLY; wrist/calf underlayers and animation unverified'}
    (HERE / 'results.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
