from pathlib import Path
import os,sys,subprocess,json,hashlib,datetime
root=Path('C:/NE/bg32-20261117');out=Path('D:/NestEggVerification/evidence-20261117/ne259/official-38d8');out.mkdir(parents=True,exist_ok=False)
paths=['game/enemies/enemy_glow.gd','data/enemies/watchdog.tres','tests/suite/test_environment.gd','tools/enemy_glow_probe.gd','tools/enemy_glow_probe_selftest.gd','tools/enemy_glow_probe_selftest.tscn','design/08-lighting/LIGHT_SOURCES.md']
def hashes():return {p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in paths}
before=hashes()
script=out/'run.sh'
script.write_text("#!/usr/bin/env bash\npython3() { '"+sys.executable.replace('\\','/')+"' \"$@\"; }\nexport -f python3\nexec tools/run_tests_changed.sh 38d8f3d3d404cb7baba0727804e86ffb1e882157\n",encoding='utf-8',newline='\n')
env=os.environ.copy();env.update({'PYTHONIOENCODING':'utf-8','GODOT':'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe','SHARDS':'2','LOG_DIR':str(out)})
argv=['C:/Program Files/Git/bin/bash.exe',str(script)]
(out/'launch.json').write_text(json.dumps({'argv':argv,'env':{k:env[k] for k in ['PYTHONIOENCODING','GODOT','SHARDS','LOG_DIR']},'source_before':before,'utc_start':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2),encoding='utf-8')
with (out/'raw.log').open('wb') as f:r=subprocess.run(argv,cwd=root,env=env,stdout=f,stderr=subprocess.STDOUT)
after=hashes()
(out/'result.json').write_text(json.dumps({'natural_exit':r.returncode,'source_after':after,'source_held':after==before,'utc_end':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2),encoding='utf-8')
print((out/'raw.log').read_text(encoding='utf-8',errors='replace'));raise SystemExit(r.returncode)
