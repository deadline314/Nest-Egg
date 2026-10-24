from pathlib import Path
import subprocess,os,json,hashlib
r=Path.cwd();w=Path('/workspace/Nest-Egg/work/batch1024');test=r/'tests/suite/test_throwables.gd';old_tests=test.read_bytes();(w/'preview-tests-v2.gd').write_bytes(old_tests)
s=old_tests.decode();a=s.index('func _test_preview_matches_first_contact()');s=s[:a]+s[a:].replace('[CRATE, PIPE]','[CRATE, PIPE, BARREL]',1);assert s!=old_tests.decode();test.write_text(s)
p=r/'game/player/player_carry.gd';candidate=p.read_bytes();original=subprocess.check_output(['git','show','HEAD:game/player/player_carry.gd']);receipt={'runs':[],'accepted_test_sha256':hashlib.sha256(test.read_bytes()).hexdigest()}
try:
 for side,source in [('before-final',original),('after-final',candidate)]:
  p.write_bytes(source)
  env=os.environ.copy();env.update(GODOT='/workspace/Nest-Egg/work/batch1020b/godot472/Godot_v4.7.2-stable_linux.x86_64',LOG_DIR=str(w/f'preview-{side}-shards'),SHARDS='1')
  with (w/f'preview-{side}-tests.log').open('w') as log: result=subprocess.run(['bash','tools/run_tests_parallel.sh','--only=ThrowablesSuite'],env=env,stdout=log,stderr=subprocess.STDOUT)
  (w/f'preview-{side}-tests.exit').write_text(str(result.returncode)+'\n');receipt['runs'].append({'side':side,'exit':result.returncode,'source_sha256':hashlib.sha256(source).hexdigest()});print(side,result.returncode,flush=True)
finally:
 p.write_bytes(candidate);receipt.update(candidate_restored=p.read_bytes()==candidate,candidate_sha256=hashlib.sha256(candidate).hexdigest());(w/'preview-final-cases-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
