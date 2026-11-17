from pathlib import Path
import os,json,sys,subprocess,hashlib
name=sys.argv[1];root=Path('C:/NE/bg32-20261117');out=Path('D:/NestEggVerification/evidence-20261117/ne259')/name;out.mkdir(parents=True,exist_ok=False)
paths=['tools/enemy_glow_probe.gd','tools/enemy_glow_probe_selftest.gd','tools/enemy_glow_probe_selftest.tscn','game/enemies/enemy_glow.gd','game/level/light_budget.gd']
def hashes():return {p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in paths}
before=hashes()
for p in paths:
 dst=out/'source'/p;dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes((root/p).read_bytes())
env=os.environ.copy()
for k in ['APPDATA','LOCALAPPDATA','XDG_DATA_HOME']:env[k]=str(out/'profile')
args=['C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe','--headless','--path',str(root),'res://tools/enemy_glow_probe_selftest.tscn']
(out/'launch.json').write_text(json.dumps({'argv':args,'source_before':before},indent=2),encoding='utf-8')
with (out/'raw.log').open('wb') as f:run=subprocess.run(args,cwd=root,env=env,stdout=f,stderr=subprocess.STDOUT)
after=hashes();raw=(out/'raw.log').read_bytes()
(out/'result.json').write_text(json.dumps({'natural_exit':run.returncode,'source_after':after,'source_unchanged':before==after,'script_errors':raw.count(b'SCRIPT ERROR:'),'engine_error_lines':sum(line.startswith(b'ERROR:') for line in raw.splitlines())},indent=2),encoding='utf-8');print((out/'raw.log').read_text(encoding='utf-8',errors='replace'));sys.exit(run.returncode)
