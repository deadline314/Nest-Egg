from pathlib import Path
import sys,subprocess,json,hashlib,os
root=Path('C:/NE/bg32-20261117');out=Path('D:/NestEggVerification/evidence-20261117/ne259')/sys.argv[1];out.mkdir(parents=True,exist_ok=False)
paths=['game/enemies/enemy_glow.gd','data/enemies/watchdog.tres','tests/suite/test_environment.gd','work/ne259-20261117/anchor_test.gd','work/ne259-20261117/anchor_test.tscn']
def hashes():return {p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in paths}
before=hashes()
for p in paths:
 dst=out/'source'/p;dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes((root/p).read_bytes())
env=os.environ.copy()
for key in ['APPDATA','LOCALAPPDATA','XDG_DATA_HOME']:env[key]=str(out/'profile')
argv=['C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe','--headless','--path',str(root),'res://work/ne259-20261117/anchor_test.tscn']
(out/'launch.json').write_text(json.dumps({'argv':argv,'source_before':before},indent=2),encoding='utf-8')
with (out/'raw.log').open('wb') as f:r=subprocess.run(argv,cwd=root,env=env,stdout=f,stderr=subprocess.STDOUT)
raw=(out/'raw.log').read_bytes();after=hashes()
(out/'result.json').write_text(json.dumps({'natural_exit':r.returncode,'source_after':after,'source_held':before==after,'script_errors':raw.count(b'SCRIPT ERROR:'),'error_lines':sum(x.startswith(b'ERROR:') for x in raw.splitlines())},indent=2),encoding='utf-8')
print(raw.decode('utf-8',errors='replace'));raise SystemExit(r.returncode)
