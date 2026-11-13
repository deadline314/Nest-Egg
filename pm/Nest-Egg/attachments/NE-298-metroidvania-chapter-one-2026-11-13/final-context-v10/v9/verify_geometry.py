"""Read-only CPU map replay. This does not replace Godot/physics/render checks."""
from pathlib import Path
import ast
import json
import re
import sys


def constant(text, name):
    return ast.literal_eval(re.search(r'const ' + name + r'\s*:=\s*([\[{].*?^[\]}])', text, re.S | re.M)[1])


def layout(root, area):
    source = (root / f'data/levels/{area}.tres').read_text(encoding='utf8')
    path = re.search(r'layout_path = "res://([^"]+)"', source)[1]
    segments = json.loads((root / path).read_bytes())['segments']
    return [''.join(segment[y] for segment in segments) for y in range(len(segments[0]))]


def checks(rows, x, y):
    inside = 0 <= x < len(rows[0]) and 0 <= y < len(rows)
    return (inside, inside and rows[y][x] in '#=',
            inside and y >= 4 and all(rows[above][x] != '#' for above in range(y - 4, y)))


def replay(root):
    here = Path(__file__).parent
    result = {}
    for epoch, path in [('original', here / 'before/tools/ch1_readability_check.gd'),
                        ('candidate', root / 'tools/ch1_readability_check.gd')]:
        failures = 0
        for area, spots in constant(path.read_text(encoding='utf8'), 'PROBES').items():
            rows = layout(root, area)
            for _, x, y, *_ in spots:
                columns = [x, x + 6] if area in ['ch1_street', 'ch1_warehouse', 'ch1_vault'] else [x]
                failures += sum(not value for column in columns for value in checks(rows, column, y))
        result[epoch] = failures
    assert result == {'original': 13, 'candidate': 0}, result
    spots = constant((root / 'tools/framing_probe.gd').read_text(encoding='utf8'), 'SPOTS')
    assert len(spots) == 6
    for area, x, y in spots:
        assert all(checks(layout(root, area), x, y)), (area, x, y)
    rows = layout(root, 'ch1_street')
    for case in ['missing_floor', 'blocked_headroom', 'outside']:
        changed = list(rows)
        x, y = 84, 32
        if case == 'missing_floor':
            changed[y] = changed[y][:x] + '.' + changed[y][x + 1:]
        elif case == 'blocked_headroom':
            changed[y - 3] = changed[y - 3][:x] + '#' + changed[y - 3][x + 1:]
        else:
            x = len(rows[0])
        assert not all(checks(changed, x, y)), case
    return {'CPU_only': True, 'original_failures': 13, 'candidate_failures': 0,
            'framing_points': 6, 'rejected_negative_controls': 3}


if __name__ == '__main__':
    print(json.dumps(replay(Path(sys.argv[1])), indent=2))
