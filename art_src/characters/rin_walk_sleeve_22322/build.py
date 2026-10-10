"""Rebuild one reviewed sleeve from native RGBA, never a runtime replacement."""
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent


def main():
    spec = json.loads((HERE / 'selection.json').read_text())
    liked = HERE.parents[2] / 'art_src/characters/rin2/base_rgba.png'
    assert hashlib.sha256(liked.read_bytes()).hexdigest() == spec['liked_standing_sha256']
    for path, expected in ((HERE / 'raw/source.png', spec['raw_sha256']),
                           (HERE / 'sam/mask.png', spec['sam_sha256'])):
        assert hashlib.sha256(path.read_bytes()).hexdigest() == expected
    source = np.asarray(Image.open(HERE / 'raw/source.png').convert('RGBA'))
    mask = np.asarray(Image.open(HERE / 'sam/mask.png').convert('L'))
    assert source.shape == (512, 384, 4) and mask.shape == source.shape[:2]
    narrow = mask > spec['sam_threshold']
    core = source[:, :, 3] > 127
    assert int((core & ~narrow).sum()) == 524
    radius = spec['mask_expand_chebyshev_px']
    selected = cv2.dilate(narrow.astype(np.uint8), np.ones((radius*2+1, radius*2+1), np.uint8)).astype(bool)
    for x, y in spec['reviewed_extra_edge_xy']:
        assert source[y, x, 3] in (2, 3)
        selected[y, x] = True
    selected &= source[:, :, 3] > 0

    def valid(candidate):
        return (not np.any(core & ~candidate)
                and all(candidate[y, x] for x, y in spec['positive_xy'])
                and not any(candidate[y, x] for x, y in spec['negative_xy']))

    assert valid(selected) and not valid(narrow)
    controls = 1
    for expected, points in ((True, spec['positive_xy']), (False, spec['negative_xy'])):
        for x, y in points:
            bad = selected.copy()
            bad[y, x] = not expected
            assert not valid(bad)
            controls += 1
    assert selected.sum() == spec['expected_retained_pixels']
    assert cv2.connectedComponents(selected.astype(np.uint8), 8)[0] == 2
    ys, xs = np.where(selected)
    box = [int(xs.min()), int(ys.min()), int(xs.max())+1, int(ys.max())+1]
    assert box == spec['expected_bbox']
    output = np.zeros_like(source)
    output[selected] = source[selected]
    cuff = np.zeros(mask.shape, dtype=np.uint8)
    cv2.fillPoly(cuff, [np.asarray(spec['cuff_opaque_polygon_xy'], dtype=np.int32)], 255)
    distance = cv2.distanceTransform(narrow.astype(np.uint8), cv2.DIST_L2, 5)
    opaque = (cuff > 0) & selected & (distance >= spec['cuff_opaque_min_sam_inside_distance_px'])
    alpha_changes = int(np.sum(opaque & (source[:, :, 3] != 255)))
    output[opaque, 3] = 255
    assert opaque[368, 120] and opaque[349, 128] and alpha_changes > 0
    assert np.all(output[opaque, 3] == 255)
    bad_alpha = output[:, :, 3].copy()
    bad_alpha[368, 120] = source[368, 120, 3]
    assert not np.all(bad_alpha[opaque] == 255)
    controls += 1
    Image.fromarray(output).save(HERE / 'sleeve-canvas.png')
    Image.fromarray(output[box[1]:box[3], box[0]:box[2]]).save(HERE / 'sleeve.png')
    Image.fromarray(selected.astype(np.uint8)*255).save(HERE / 'material-mask.png')
    reopened = np.asarray(Image.open(HERE / 'sleeve-canvas.png'))
    assert np.array_equal(reopened[selected, :3], source[selected, :3])
    assert np.array_equal(reopened[selected & ~opaque], source[selected & ~opaque])
    Image.fromarray(opaque.astype(np.uint8)*255).save(HERE / 'cuff-opacity-mask.png')
    report = {'scope': 'SOURCE ONLY; shoulders, cuff binding, normals, glow and walk unaccepted',
              'retained_pixels': int(selected.sum()), 'crop_xyxy': box, 'native_size': [box[2]-box[0], box[3]-box[1]],
              'material_core_clipped': 0, 'connected_components': 1, 'negative_controls_rejected': controls,
              'reviewed_cuff_alpha_changes': alpha_changes, 'retained_rgb_exact': True, 'outer_alpha_exact': True}
    (HERE / 'results.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
