#!/usr/bin/env python3
"""Pin old/new git trees for audit dependencies; change requires rerender, not false reuse."""
import argparse,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--repo',required=True);p.add_argument('--old',default='c0250bff9dd6a44a8b1c9df557eaab18b0a12996');p.add_argument('--new',default='HEAD');a=p.parse_args();root=Path(a.repo).resolve()
paths=['game/creature','game/enemies','game/rig/rig_library.gd','core/lit_textures.gd','data/enemies','data/scripts/enemy_data.gd','art/creatures','art_src/creatures','tools/check_joint_frames.py','tools/art/make_creature_parts.py','project.godot','.github/workflows/tests.yml','tests/suite/test_part_creature.gd','tests/suite/test_chain_creature.gd','tests/suite/test_exotic_enemies.gd','tests/suite/test_ch1_enemies.gd','tests/suite/test_assault_enemies.gd']
def git(*args):return subprocess.check_output(['git',*args],cwd=root,text=True).strip()
rows=[dict(path=x,old=git('rev-parse',a.old+':'+x),new=git('rev-parse',a.new+':'+x)) for x in paths]
report=dict(old=git('rev-parse',a.old),new=git('rev-parse',a.new),rows=rows,unchanged=all(r['old']==r['new'] for r in rows))
(root/'pm/Nest-Egg/attachments/NE-90-cloud-creatures/rebase-source-equivalence.json').write_text(json.dumps(report,indent=2)+'\n')
if not report['unchanged']:raise SystemExit('dependencies changed: old images cannot certify new base')
print('pinned dependencies unchanged',len(rows))
