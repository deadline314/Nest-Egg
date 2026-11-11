"""Independent current-profile/prototype factors and actual drawable white bounds."""
from pathlib import Path
import argparse
import hashlib
import json

import numpy as np

from verify_bg49_held import affine, load_pixels, raster, section
from verify_bg55_readability import exposure_bound
from verify_street_shared_contrast import verify

FIELDS = {'identity': None, 'enemy-fill1': ('enemy_fill_scale', 1),
          'character-floor1': ('character_floor', 1), 'contrast1': ('contrast', 1),
          'contrast098': ('contrast', .98), 'fog1': ('fog_density', 1),
          'fog2': ('fog_density', 2), 'rim1': ('rim_energy', 1)}
FILLS = {'creature-shader1': 1, 'creature-fill24': 2.4, 'creature-fill3': 3, 'creature-fill4': 4}


def check(folder):
    controls = verify(folder)
    index = next(folder.glob('*/*-index.json'))
    document = json.loads(index.read_bytes())
    results, cache = [], {}
    for shot in document['shots']:
        factor = shot['street_shared']['factor']
        records = shot['bg55']['records']
        base = records[0]
        original_profile = base['profile_values']
        expected_field = FIELDS.get(factor)
        fill = FILLS.get(factor, 0)
        original_materials = base['part_creature_materials']
        assert len(original_materials) == 3
        observations = []
        for record in records:
            altered = record['label'] in ['product', 'authored-final']
            changed = {name for name, value in record['profile_values'].items()
                       if value != original_profile[name]}
            assert changed == ({expected_field[0]} if altered and expected_field else set())
            if altered and expected_field:
                assert abs(record['profile_values'][expected_field[0]] - expected_field[1]) < 1e-6
            actual_fill = fill if altered else 0
            assert record.get('prototype_creature_fill', 0) == actual_fill
            if 'all_primitive_source_materials_restored' in record:
                assert record['all_primitive_source_materials_restored'] == (actual_fill == 0)
            materials = record['part_creature_materials']
            assert [p['path'] for p in materials] == [p['path'] for p in original_materials]
            for part, original in zip(materials, original_materials):
                for field in ['diffuse', 'normal', 'light_mask', 'visible', 'modulate', 'use_parent_material']:
                    assert part[field] == original[field]
                if actual_fill:
                    assert part['material_class'] == 'ShaderMaterial'
                    assert part['shader_path'] == 'res://art/shaders/character_light.gdshader'
                    assert abs(part['shader_fill'] - actual_fill) < 1e-6
                    luma = np.dot(original_profile['ambient_color'][:3], [.2126, .7152, .0722])
                    cap = np.clip(1 - luma * actual_fill, .2, .5) * 1.6
                    assert abs(part['shader_light_cap'] - cap) < 1e-6
                    expected = np.asarray(original['self_modulate']) * [actual_fill, actual_fill, actual_fill, 1]
                    assert np.max(np.abs(part['self_modulate'] - expected)) < 1e-6
                else:
                    assert part == original
            target = [e for e in record['enemies'] if e['id'] == 'drone' and e['feet'] == [2984, 192]]
            assert len(target) == 1
            enemy = target[0]
            actor = next(a for a in record['enemy_inventory'] if a['instance'] == enemy['instance'])
            assert actor['full_body_in_view'] and actor['full_visual_in_view']
            assert len(actor['visible_drawables']) == 3
            key = record['raw_sha256']
            if key not in cache:
                cache[key] = load_pixels(index.parent, record)
            rgb = cache[key]
            exposure = exposure_bound(rgb, enemy, record)
            pieces = []
            for drawable in actor['visible_drawables']:
                x, y, w, h = drawable['local_rect']
                vertices = np.array([[x, y, 1], [x + w, y, 1], [x, y + h, 1], [x + w, y + h, 1]])
                world = (vertices @ affine(drawable['global_transform']).T)[:, :2]
                low, high = world.min(axis=0), world.max(axis=0)
                box = raster([*low, *(high - low)], record)
                white = int(np.all(section(rgb, box) > .92, axis=-1).sum())
                pieces.append(dict(path=drawable['path'], containing_pixel_rect=box,
                                   white_pixels_including_background=white))
            observations.append(dict(label=record['label'], contrast=enemy['contrast'],
                                     parts=enemy['parts'], exposure=exposure, drawables=pieces,
                                     actual_visible_white_pixels_proved_zero=exposure['white_pixels_including_background'] == 0))
        results.append(dict(factor=factor, baseline=observations[0], candidate=observations[-1],
                            passed=observations[-1]['contrast'] >= .45))
    return dict(controls_valid=controls['controls_valid'], factors=len(results),
                results=results, verifier_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                scope='single-factor diagnostic only; a zero containing-box count proves zero actual visible drawable whites; nonzero is never divided by background area')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    result = check(args.folder)
    args.out.write_bytes((json.dumps(result, indent=2) + '\n').encode())
    print(json.dumps({k: v for k, v in result.items() if k != 'results'}))
