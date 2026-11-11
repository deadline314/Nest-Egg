"""Reject corrupt counterfactual metadata without changing retained evidence."""
from pathlib import Path
import argparse
import copy
import hashlib
import json
from unittest.mock import patch

from verify_bg48_grounded import verify_grounded


def check(folder):
    baseline = verify_grounded(folder)
    index = next(folder.glob('ch2_lounge_front/*-index.json')).resolve()
    original_read = Path.read_bytes
    source = original_read(index)
    base = json.loads(source)
    results = []
    for mode in ['fog', 'ambient', 'enemy-fill', 'world-environment']:
        modified = copy.deepcopy(base)
        record = modified['shots'][0]['bg55']['records'][0]
        if mode == 'fog':
            record['fog_density'] = .5
        elif mode == 'ambient':
            record['ambient'] = 'corrupt control'
        elif mode == 'enemy-fill':
            record['enemy_fill_scale'] += .25
        else:
            record['world_environment']['threshold'] += .1
        encoded = json.dumps(modified).encode('utf8')

        def read(path):
            return encoded if path.resolve() == index else original_read(path)

        try:
            with patch.object(Path, 'read_bytes', read):
                verify_grounded(folder)
        except AssertionError as error:
            results.append({'case': mode, 'rejected': True, 'reason': str(error)})
        else:
            raise AssertionError('Accepted corrupt ' + mode)
    assert original_read(index) == source
    return {'baseline_cells': baseline['cells'], 'baseline_supported_points': baseline['supported_player_points'],
            'negative_controls': results, 'original_index_unchanged_sha256': hashlib.sha256(source).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('folder', type=Path)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    result = check(args.folder)
    text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.out:
        args.out.write_text(text, encoding='utf8', newline='\n')
    print(text)


if __name__ == '__main__':
    main()
