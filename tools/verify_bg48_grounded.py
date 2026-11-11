"""Recompute each retained fog-control image from its original HDR bytes."""
from pathlib import Path
import argparse
import hashlib
import json

import numpy as np

from verify_bg55_readability import FORMATS, verify, mapped_world_box, parts_from_pixels


def load_pixels(folder, record):
    raw = (folder / record['files']['raw']).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == record['raw_sha256']
    dtype, channels = FORMATS[record['format']]
    pixels = np.frombuffer(raw, dtype=dtype).reshape(
        int(record['height']), int(record['width']), channels).astype(np.float64)
    assert np.isfinite(pixels).all()
    return pixels[..., :3]


def verify_grounded(folder):
    common = verify(folder, True, True)
    assert common['cells'] == 9 and common['control_failures'] == 0
    observations = []
    for index in folder.glob('ch2_lounge_front/*-index.json'):
        data = json.loads(index.read_bytes())
        assert data['columns'] * data['rows'] == 9 and len(data['shots']) == 9
        for shot in data['shots']:
            assert shot['bg48']['kind'].startswith('same live geometry')
            records = shot['bg55']['records']
            assert len(records) == 5
            first, repeat, product, restored, final = records
            assert [record['fog_density'] for record in records] == [1.0, 1.0, .5, 1.0, .5], 'fog control values'
            for record in records:
                assert record['ambient'] == first['ambient'], 'ambient control'
                assert record['enemy_fill_scale'] == first['enemy_fill_scale'], 'enemy fill control'
                assert record['world_environment'] == first['world_environment'], 'world environment control'
            assert first['raw_sha256'] == repeat['raw_sha256'] == restored['raw_sha256']
            assert product['raw_sha256'] == final['raw_sha256']
            if not final['player_visible']:
                continue
            px, py = shot['player_world']
            values = []
            for record in records:
                rgb = load_pixels(index.parent, record)
                body = mapped_world_box([px - 9, py - 58, 18, 54], record)
                outer = mapped_world_box([px - 29, py - 78, 58, 94], record)
                parts = parts_from_pixels(rgb, body, outer)
                player = max(parts['bright'], parts['dark'])
                luma = rgb @ [.2126, .7152, .0722]

                def mean(box):
                    x, y, width, height = mapped_world_box(box, record)
                    assert width > 0 and height > 0
                    return float(np.mean(luma[y:y + height, x:x + width]))

                below = mean([px - 24, py + 8, 48, 6])
                edge = (mean([px - 24, py, 48, 3]) - below) / (below + .02)
                assert player >= .6 and edge >= 1.0, (index, record['label'], player, edge)
                values.append({'label': record['label'], 'player': player, 'edge': edge,
                               'raw_sha256': record['raw_sha256']})
            observations.append({'column': shot['column'], 'row': shot['row'],
                                 'feet': [px, py], 'values': values})
    assert len(observations) == 6
    result = {'kind': 'original fog and authored fog both independently checked; not historical gameplay',
              'cells': 9, 'supported_player_points': 6, 'observations': observations,
              'common_owner_and_contact_checks_passed': True}
    return result


def verify_related(folder):
    common = verify(folder, True, True)
    assert common['cells'] == 21 and common['control_failures'] == 0
    supported = 0
    for index in folder.glob('ch2_market_gate/*-index.json'):
        data = json.loads(index.read_bytes())
        assert data['columns'] * data['rows'] == 21 and len(data['shots']) == 21
        for shot in data['shots']:
            records = shot['bg55']['records']
            assert len(records) == 5
            assert len({record['raw_sha256'] for record in records}) == 1, 'related raw images changed'
            assert all(record['held'] == records[0]['held'] for record in records)
            assert all(record['fog_density'] == 1.0 and record['enemy_fill_scale'] == 1.0 for record in records)
            if records[-1]['player_visible']:
                supported += 1
    assert supported == 14
    for cell in common['results']:
        player = cell['player_from_raw']
        assert player is None or player['passed']
        for record in cell['observations']:
            assert all(enemy['passed'] for enemy in record['enemies'])
    return {'kind': 'BG48 leaves the published market-gate profile unchanged', 'cells': 21,
            'supported_player_points': supported, 'all_five_raw_images_identical_per_cell': True,
            'common': common}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    parser.add_argument('--out', type=Path)
    parser.add_argument('--related-market-gate', action='store_true')
    args = parser.parse_args()
    result = verify_related(args.folder) if args.related_market_gate else verify_grounded(args.folder)
    text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.out:
        args.out.write_text(text, encoding='utf8', newline='\n')
    print(text)


if __name__ == '__main__':
    main()
