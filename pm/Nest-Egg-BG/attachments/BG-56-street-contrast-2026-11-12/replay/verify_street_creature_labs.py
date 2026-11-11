"""Read native action, public-damage and real-zone receipts independently."""
from pathlib import Path
import argparse
import hashlib
import json

import numpy as np

from verify_bg49_held import contrast, load_pixels, raster, verify_owners


def image_record(folder, capture):
    record = dict(capture)
    record['files'] = {'raw': capture['raw'], 'png': capture['file']}
    if 'size' in capture:
        record['width'], record['height'] = capture['size']
    return load_pixels(folder, record), record


def check_action(folder):
    document = json.loads((folder / 'actions.json').read_bytes())
    assert document['failures'] == 0 and document['renderer'] == 'forward_plus' and document['hdr_2d']
    expected = {'collector_brute': {'windup', 'leap', 'recover'}, 'sweeper': {'aim', 'recover'},
                'drone': {'hover', 'lock', 'dive', 'climb'}}
    rows = []
    for actor in document['actors']:
        assert actor['stats_before'] == actor['stats_after']
        assert expected[actor['id']] <= set(actor['states'])
        path = folder / 'source/data/enemies' / (actor['id'] + '.tres')
        assert hashlib.sha256(path.read_bytes()).hexdigest() == actor['enemy_data_sha256']
        times = [tick['milliseconds'] for tick in actor['timeline']]
        assert times == sorted(times) and times[-1] >= 7900
        for tick in actor['timeline']:
            assert tick['enemy_body_space_valid'] and tick['player_body_space_valid']
            assert tick['enemy_hp'] == actor['stats_before']['max_health']
        frames = []
        for capture in actor['captures']:
            rgb, record = image_record(folder, capture)
            values = contrast(rgb, capture['body_screen_rect'], capture['outer_screen_rect'])
            for key, value in values.items():
                assert abs(value - capture['parts'][key]) < .000002
            canonical = max(values['bright'], values['dark'])
            assert abs(canonical - capture['contrast']) < .000002
            x, y, w, h = capture['visual_world_bounds_values']
            auxiliary = contrast(rgb, raster([x, y, w, h], record), raster([x-20, y-20, w+40, h+40], record))
            assert capture['world_environment_active'] and capture['glow_enabled']
            frames.append(dict(file=capture['file'], state=capture['state'], canonical_contrast=canonical,
                               auxiliary_drawable_contrast=max(auxiliary['bright'], auxiliary['dark']),
                               creature_fill=capture.get('creature_lighting', {}).get('fill') if capture.get('creature_lighting') else None))
        assert frames
        rows.append(dict(id=actor['id'], states=actor['states'], frames=frames,
                         minimum_canonical_contrast=min(frame['canonical_contrast'] for frame in frames),
                         actual_frozen_samples=sum(tick.get('enemy_frozen', False) or tick.get('player_frozen', False) for tick in actor['timeline']),
                         observed_live_beam_max_error=max(tick['weapon_light_origin_error'] for tick in actor['timeline']),
                         beam_scope='live values retained including published Fx jitter; exact held-beam invariants are verified separately by the full static grid'))
    return dict(valid=True, actors=rows,
                scope='original natural AI/stats/real spaces and independently recomputed pixels; dynamic canonical values are all retained, not claimed to pass the static grid thresholds; auxiliary drawable values never replace canonical boxes')


def check_damage(folder):
    document = json.loads((folder / 'damage.json').read_bytes())
    assert document['failures'] == 0
    records = document['records']
    assert [r['label'] for r in records[:4]] == ['before-public-damage', 'hurt-flash', 'recovered-wear', 'death-start']
    assert [r['hp'] for r in records[:4]] == [3, 2, 2, 0]
    assert records[1]['lighting']['flash_left'] > 0 and records[2]['lighting']['flash_left'] == 0
    assert records[3]['dying'] and all(r['dying'] for r in records[3:])
    assert any(r['actor_modulate'][3] < .95 for r in records[3:])
    assert any(abs(r['rotation']) > .1 for r in records[3:])
    for record in records:
        image_record(folder, record)
        state = record['lighting']
        assert state['cached_material_exists']
        for binding in state['bindings']:
            assert binding['material_is_cached'] and binding['shader_fill'] == state['fill']
            expected = np.array(binding['source_tint']) * [state['fill'], state['fill'], state['fill'], 1]
            assert np.max(np.abs(expected - binding['self_modulate'])) < .000001
    return dict(valid=True, frames=len(records), original_health_transitions=[r['hp'] for r in records],
                scope='explicit public Hurtbox.receive lab, no direct HP/FSM write; preserved parent flash/wear and original spin/fade death, not a claim of player shooting')


def check_region(folder):
    path = next(folder.glob('*/street-region.json'))
    document = json.loads(path.read_bytes())
    assert document['valid']
    records = document['records']
    assert [r['label'] for r in records] == ['A0', 'A1', 'product', 'restore-product', 'authored-final']
    assert records[0]['raw_sha256'] == records[1]['raw_sha256'] == records[3]['raw_sha256']
    assert records[2]['raw_sha256'] == records[4]['raw_sha256']
    seen = {}
    for record in records:
        load_pixels(path.parent, record)
        verify_owners(record['held']['lighting_owners'], record['canvas_transform_values'])
        x = record['player_feet'][0]
        assert x == (2984 if record['inside'] else 2680)
        assert abs(record['player_feet'][1] - 320) < .02
        # Final authored ramp reaches .6 at2784. The original diagnostic
        # two-zone variant used the original 181/14 smoothstep instead.
        has_ramp = (folder / 'source/data/lighting/street_market_creature.tres').exists()
        t = np.clip((x - (181 * 16 - 14 * 16 / 2)) / (14 * 16), 0, 1)
        expected = .6 if has_ramp and record['inside'] else .6 * t*t*(3-2*t)
        assert abs(record['creature_profile_floor'] - expected) < 1e-6
        for actor in record['api_states']:
            assert actor['instance'] not in seen or seen[actor['instance']] == actor['feet']
            seen[actor['instance']] = actor['feet']
            for binding in actor['state']['bindings']:
                assert binding['material_is_cached'] if record['inside'] else binding['source_material_restored']
    assert len(seen) == 4
    return dict(valid=True, records=5, original_zone_pixels_restored=True, creatures=4,
                floors=[r['creature_profile_floor'] for r in records],
                scope='real collision-solved test-player positions x2680/2984, hidden player/fixed camera, unchanged authored enemy positions; actual zone blend and public bindings')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['action', 'damage', 'region'])
    parser.add_argument('folder', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    receipt = json.loads((args.folder / 'exit.json').read_bytes())
    assert receipt['strict_clean'] and receipt['exit'] == 0 and receipt['sources_unchanged']
    result = globals()['check_' + args.mode](args.folder)
    result['verifier_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    args.out.write_bytes((json.dumps(result, indent=2) + '\n').encode())
    print(json.dumps({k: v for k, v in result.items() if k != 'actors'}))
