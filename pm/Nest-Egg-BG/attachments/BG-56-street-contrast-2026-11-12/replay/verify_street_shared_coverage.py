"""Independent completeness checks on authored platform runs and actual actors."""
from pathlib import Path
import argparse
import hashlib
import json

from verify_street_shared_contrast import verify


def check(folder, require_drawables=False):
    result = verify(folder, require_enemies=True)
    assert len(list(folder.glob('*/*-index.json'))) == 1
    index = next(folder.glob('*/*-index.json'))
    document = json.loads(index.read_bytes())
    if require_drawables:
        for shot in document['shots']:
            for record in shot['bg55']['records']:
                assert all(actor.get('visible_drawables') for actor in record['enemy_inventory']
                           if actor['alive'] and actor['tree_visible']), 'actual visible sprite bounds were not preserved'
    assert document['level'] == 'ch1_street'
    assert document['columns'] == 11 and document['rows'] == 3
    originals = [s for s in document['shots'] if s['waypoint_kind'] == 'original-grid']
    assert len(originals) == 33
    assert {(int(s['column']), int(s['row'])) for s in originals} == {
        (x, y) for y in range(3) for x in range(11)}
    view = document['view']
    size = document['level_size']
    for shot in originals:
        expected = [min(view[i] * .5 + view[i] * .92 * shot[['column', 'row'][i]],
                        max(view[i] * .5, size[i] - view[i] * .5)) - view[i] * .5
                    for i in range(2)]
        assert max(abs(shot['world'][i] - expected[i]) for i in range(2)) < .001
        assert max(abs(shot['world'][i + 2] - view[i]) for i in range(2)) < .001
    source = folder / 'source/data/levels/ch1_street_map.json'
    layout = json.loads(source.read_bytes())
    rows = [''.join(segment[y] for segment in layout['segments'])
            for y in range(len(layout['segments'][0]))]
    platforms = []
    for y, row in enumerate(rows):
        x = 0
        while x < len(row):
            if row[x] != '=':
                x += 1
                continue
            start = x
            while x < len(row) and row[x] == '=':
                x += 1
            platforms.append(dict(cells=[start, y, x - start, 1], stances=[]))
    assert len(platforms) == 8
    for platform in platforms:
        x, y, w, _ = platform['cells']
        for shot in document['shots']:
            final = shot['bg55']['records'][-1]
            if not final['player_visible']:
                continue
            support = final['held']['player_support']
            assert support['valid'] and support['solver_contact']
            fx, fy = shot['player_world']
            if x * 16 <= fx < (x + w) * 16 and abs(support['floor'][1] - y * 16) < .001:
                assert abs(fy - y * 16) <= support['safe_margin'] + .001
                platform['stances'].append(dict(waypoint=shot['waypoint'], feet=[fx, fy],
                                                contrast=shot['player_contrast'], edge=shot['edge_contrast']))
        assert platform['stances'], platform
    result['platform_coverage'] = dict(authored=8, covered=8, platforms=platforms)
    result['original_camera_grid'] = dict(expected=33, actual=len(originals), complete=True)
    result['coverage_verifier_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--require-thresholds', action='store_true')
    parser.add_argument('--require-drawable-bounds', action='store_true')
    args = parser.parse_args()
    result = check(args.folder, args.require_drawable_bounds)
    args.out.write_bytes((json.dumps(result, ensure_ascii=False, indent=2) + '\n').encode())
    print(json.dumps({k: result[k] for k in ['cells', 'controls_valid', 'candidate_thresholds_passed',
                                            'original_camera_grid', 'coverage_verifier_sha256']}))
    raise SystemExit(1 if args.require_thresholds and not result['candidate_thresholds_passed'] else 0)
