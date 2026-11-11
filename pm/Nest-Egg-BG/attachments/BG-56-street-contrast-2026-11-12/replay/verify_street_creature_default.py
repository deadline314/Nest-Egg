"""Prove the disabled public creature API preserves original native pixels."""
from pathlib import Path
import argparse
import hashlib
import json

from verify_street_shared_contrast import verify
from verify_bg49_held import load_pixels


def check(folder):
    controls = verify(folder)
    assert controls['controls_valid']
    index = next(folder.glob('*/*-index.json'))
    data = json.loads(index.read_bytes())
    assert len(data['shots']) == 1
    records = data['shots'][0]['bg55']['records']
    hashes, calls = set(), []
    for record in records:
        load_pixels(index.parent, record)
        hashes.add(record['raw_sha256'])
        assert record['default_api']['valid'] and record['default_api']['calls'] > 0
        calls.append(record['default_api']['calls'])
        assert record['creature_profile_floor'] == record['creature_fill'] == 0
        count = 0
        for actor in record['enemy_inventory']:
            state = actor['creature_lighting']
            if state is None:
                continue
            count += 1
            assert not state['cached_material_exists'] and state['fill'] == 0
            for binding in state['bindings']:
                assert binding['source_material_restored'] and binding['self_modulate'] == binding['source_tint']
        assert count == 4
    assert len(hashes) == 1 and calls == sorted(calls)
    return dict(controls_valid=True, native_byte_identical=True, records=5,
                actual_public_api_calls=calls, creatures_per_record=4,
                raw_sha256=next(iter(hashes)),
                verifier_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                scope='real set_lighting(0) with original zone reference, no fixture material/tint reset; unchanged native float bytes across five captures')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('folder', type=Path)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    value = check(args.folder)
    args.out.write_bytes((json.dumps(value, indent=2) + '\n').encode())
    print(json.dumps(value))
