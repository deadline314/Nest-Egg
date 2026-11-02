#!/usr/bin/env python3
"""Compare generated channel ownership with checked-in levels in isolated processes."""
import argparse
import importlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def chapter(number):
    module = importlib.import_module('build_ch' + str(number))
    kit = module if number == 1 else module.kit
    if number != 1:
        module.configure()
        areas = [build() for build in module.AREAS]
    else:
        areas = [module.build_prologue(), module.build_pawnshop(), module.build_rooftop(),
                 module.build_street(), module.build_booth_alley(), *module.build_warehouse_pair(),
                 module.build_handoff(), module.build_lounge(), module.build_stall()]
    original = Path(kit.LEVEL_DIR)
    failures = []
    def enabled(text):
        return bool(re.search(r'^durable_channel_results\s*=\s*true\s*$', text, re.MULTILINE))
    with tempfile.TemporaryDirectory(prefix='nest-egg-channel-generation-') as owned:
        kit.LEVEL_DIR = owned
        for area in areas:
            kit.write_level(area, theme=False, theme_path=f'res://data/environment/themes/ch{number}_{area.id}.tres')
            name = f'ch{number}_{area.id}.tres'
            if enabled((Path(owned)/name).read_text()) != enabled((original/name).read_text()):
                failures.append(name + ': generated durable channel owner differs from the shipped level')
    return {'chapter':number,'checks':len(areas),'failures':failures}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--chapter', type=int, choices=(1, 2, 3))
    args = parser.parse_args()
    if args.chapter:
        result = chapter(args.chapter)
        print(json.dumps(result))
        return bool(result['failures'])
    results=[]
    for number in (1, 2, 3):
        proc=subprocess.run([sys.executable,str(Path(__file__).resolve()),'--chapter',str(number)],capture_output=True,text=True)
        print(proc.stdout,end='')
        if proc.returncode:
            print(proc.stderr,end='',file=sys.stderr)
        results.append(proc.returncode)
    return int(any(results))


if __name__ == '__main__':
    raise SystemExit(main())
