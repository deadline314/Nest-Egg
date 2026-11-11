"""Independent native physical-coverage exposure bounds; no background denominator."""
from pathlib import Path
import argparse
import hashlib
import json
import math

import numpy as np
from PIL import Image

from verify_bg49_held import FORMATS, affine, load_pixels
from verify_street_shared_contrast import intersects, verify


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def mask_pixels(folder, mask):
    raw = (folder / mask['raw']).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == mask['raw_sha256']
    dtype, channels = FORMATS[mask['format']]
    values = np.frombuffer(raw, dtype=dtype).reshape(mask['height'], mask['width'], channels)
    rgb = values[..., :3].astype(np.float64)
    assert np.isfinite(rgb).all() and rgb.min() >= 0 and rgb.max() <= 1.000001
    assert np.max(np.ptp(rgb, axis=-1)) <= .00001, 'unshaded grayscale coverage required'
    png = np.asarray(Image.open(folder / mask['png']).convert('RGB')) / 255
    expected = np.where(rgb <= .0031308, rgb * 12.92, 1.055 * rgb ** (1 / 2.4) - .055)
    assert np.max(np.abs(png - expected)) <= 1 / 255 + .00001
    x, y, w, h = mask['containing_rect']
    inside = rgb[y:y+h, x:x+w]
    positive = np.max(inside, axis=-1) > 0
    opaque = np.min(inside, axis=-1) >= .999
    assert int(positive.sum()) == mask['positive_pixels']
    assert int(opaque.sum()) == mask['opaque_pixels']
    assert mask['valid'] and positive.any() and mask['proof_valid']
    # The conservative source envelope must contain the entire rendered mask.
    assert int((rgb.max(axis=-1) > 0).sum()) == int(positive.sum())
    return rgb


def check_proof(folder, mask, record):
    path = folder / mask['proof_file']
    assert digest(path) == mask['proof_sha256']
    proof = json.loads(path.read_bytes())
    assert proof['valid'] and not proof['blank_negative'] and proof['offset_negative_pixels'] == 0
    assert proof['signature'] == mask['pose_signature']
    matrix = affine(record['held']['lighting_owners']['viewport_final_transform_values']) @ affine(record['canvas_transform_values'])
    assert np.max(np.abs(affine(proof['main_matrix']) - matrix)) < .00001
    assert np.max(np.abs(affine(proof['mask_matrix']) - matrix)) < .00001
    assert proof['actor_count'] == len(proof['actor_draw_order']) > 0
    source_order = [row['source_index'] for row in proof['actor_draw_order']]
    copy_order = [row['copy_index'] for row in proof['actor_draw_order']]
    assert source_order == sorted(source_order) and copy_order == sorted(copy_order)
    assert len(set(source_order)) == len(source_order) and len(set(copy_order)) == len(copy_order)
    assert proof['foreground_policy'] == 'exclude entire projected envelope from opaque denominator; keep original main foreground unchanged'
    for actor in proof['actor_draw_order']:
        expected_clear = all(not intersects(actor['physical_world_bounds'], foreground)
                             for foreground in proof['foreground_bounds'])
        assert actor['foreground_clear'] == expected_clear
    assert proof['rows']
    for row in proof['rows']:
        assert row['native_type'] == row['copy_native_type']
        assert row['source_sibling_index'] == row['copy_sibling_index']
        assert row['source_z'] == row['copy_z'] and row['same_visible']
        assert row['source_alpha'] == row['copy_alpha'] and row['source_self_alpha'] == row['copy_self_alpha']
        assert np.max(np.abs(np.array(row['source_global']) - row['copy_global'])) <= .0003
        if 'source_rest' in row:
            assert np.max(np.abs(np.array(row['source_rest']) - row['copy_rest'])) <= .0003
        if 'source_polygon_sha256' in row:
            assert row['source_polygon_sha256'] == row['copy_polygon_sha256']
            assert row['source_uv_sha256'] == row['copy_uv_sha256']
            assert row['bone_count'] == len(row['bone_bindings'])
            for bone in row['bone_bindings']:
                assert bone['path'] == bone['copy_path'] and bone['weights_unchanged']
                assert bone['source_weights_sha256'] == bone['copy_weights_sha256']
            if row['bone_count']:
                assert row['skeleton_inside_copy']
    return proof


def dilate(mask, radius):
    """Square envelope, larger than the post chromatic displacement and AA."""
    padded = np.pad(mask, ((0, 0), (radius, radius)))
    horizontal = np.zeros_like(mask)
    for dx in range(2 * radius + 1):
        horizontal |= padded[:, dx:dx+mask.shape[1]]
    padded = np.pad(horizontal, ((radius, radius), (0, 0)))
    result = np.zeros_like(mask)
    for dy in range(2 * radius + 1):
        result |= padded[dy:dy+mask.shape[0], :]
    return result


def check(folder):
    controls = verify(folder, require_enemies=False)
    assert controls['controls_valid']
    result, raw_cache, mask_cache, proof_cache = [], {}, {}, {}
    for index in folder.glob('*/*-index.json'):
        data = json.loads(index.read_bytes())
        for shot in data['shots']:
            raw_cache.clear()
            mask_cache.clear()
            proof_cache.clear()
            for record in shot['bg55']['records']:
                physical = record['physical_exposure']
                assert physical['controls_valid'] and physical['acceptance_pending_independent_pixels']
                assert physical['mask_source_sha256'] == digest(folder / 'source/tools/street_actor_mask.gd')
                assert {int(r['instance']) for r in physical['observations']} == {int(r['instance']) for r in record['enemies']}
                if record['raw_sha256'] not in raw_cache:
                    raw_cache[record['raw_sha256']] = load_pixels(index.parent, record)
                rgb = raw_cache[record['raw_sha256']]
                white = np.all(rgb > .92, axis=-1)
                for observed in physical['observations']:
                    assert observed['white_threshold'] == .92 and observed['limit'] == .02
                    coverage, opaque = observed['physical_mask'], observed['opaque_mask']
                    assert not coverage['opaque_only'] and opaque['opaque_only'] and opaque['source_alpha_cutoff'] == .999999
                    assert coverage['instance'] == opaque['instance'] == observed['instance']
                    assert coverage['pose_signature'] == opaque['pose_signature']
                    values = []
                    for mask in [coverage, opaque]:
                        assert (mask['height'], mask['width']) == rgb.shape[:2]
                        key = mask['proof_sha256']
                        if key not in proof_cache:
                            proof_cache[key] = check_proof(index.parent, mask, record)
                        if mask['raw_sha256'] not in mask_cache:
                            mask_cache[mask['raw_sha256']] = mask_pixels(index.parent, mask)
                        values.append(mask_cache[mask['raw_sha256']])
                    positive = values[0].max(axis=-1) > 0
                    # Only fragments with source alpha >= .999999 can contribute
                    # white to this separate pass. Semi-transparent overlap is
                    # black, so it cannot create an opaque denominator pixel.
                    opaque_lower = values[1].min(axis=-1) >= .999
                    # Entire top/bottom repeat envelopes are excluded, including
                    # transparent holes. This is a conservative denominator and
                    # does not remove any foreground from the actual main PNG.
                    proof = proof_cache[coverage['proof_sha256']]
                    matrix = affine(proof['main_matrix'])
                    for x, y, w, h in proof['foreground_bounds']:
                        vertices = np.array([[x, y, 1], [x+w, y, 1], [x, y+h, 1], [x+w, y+h, 1]]) @ matrix.T
                        start = np.maximum(np.floor(vertices[:, :2].min(axis=0)).astype(int), [0, 0])
                        end = np.minimum(np.ceil(vertices[:, :2].max(axis=0)).astype(int), [record['width'], record['height']])
                        if np.all(end > start): opaque_lower[start[1]:end[1], start[0]:end[0]] = False
                    assert not np.any(opaque_lower & ~positive)
                    h_lower = int(opaque_lower.sum())
                    assert h_lower > 0, 'empty opaque lower bound'
                    aberration = abs(record['profile_values']['aberration'])
                    radius = math.ceil(aberration * max(rgb.shape[:2])) + 2
                    assert radius <= 32, 'unexpected post displacement requires review'
                    w_upper = int((white & dilate(positive, radius)).sum())
                    upper = w_upper / h_lower
                    result.append(dict(waypoint=shot['waypoint'], label=record['label'], id=observed['id'],
                                       instance=observed['instance'], feet=observed['feet'],
                                       opaque_pixels_lower_bound=h_lower, white_pixels_upper_bound=w_upper,
                                       dilation_radius=radius, ratio_upper_bound=upper, exact_ratio=None,
                                       passed=upper <= .02))
    assert result
    finals = [r for r in result if r['label'] == 'authored-final']
    return dict(controls_valid=True, observations=len(result), final_observations=len(finals),
                final_exposure_passed=all(r['passed'] for r in finals), results=result,
                verifier_sha256=digest(Path(__file__)),
                scope='W conservatively includes displaced white pixels and may include background; H counts only opaque physical source fragments. W/H is an upper bound, never an exact ratio or background denominator.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    value = check(args.folder)
    args.out.write_bytes((json.dumps(value, indent=2) + '\n').encode())
    print(json.dumps({k: v for k, v in value.items() if k != 'results'}))
    raise SystemExit(0 if value['final_exposure_passed'] else 1)
