from pathlib import Path
import os,subprocess,json,hashlib
root=Path('C:/NE/bg32-20261117');out=Path('D:/NestEggVerification/evidence-20261117/ne259/eye-receipts-final');out.mkdir(parents=True,exist_ok=False)
paths=['tools/enemy_glow_probe.gd','work/ne259-20261117/eye_receipts.gd','work/ne259-20261117/eye_receipts.tscn','game/enemies/enemy_glow.gd','data/enemies/watchdog.tres','art/creatures/watchdog.json','art/creatures/watchdog/head.png']
def hashes():return {p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in paths}
before=hashes()
for p in paths:
 dst=out/'source'/p;dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes((root/p).read_bytes())
env=os.environ.copy()
for key in ['APPDATA','LOCALAPPDATA','XDG_DATA_HOME']:env[key]=str(out/'profile')
argv=['python',str(root/'tools/comfyui/gpu_lock.py'),'--','C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe','--path',str(root),'--rendering-driver','vulkan','--rendering-method','forward_plus','res://work/ne259-20261117/eye_receipts.tscn','--','--out='+str(out)]
(out/'launch.json').write_text(json.dumps({'argv':argv,'source_before':before},indent=2),encoding='utf-8')
with (out/'raw.log').open('wb') as f:r=subprocess.run(argv,cwd=root,env=env,stdout=f,stderr=subprocess.STDOUT)
raw=(out/'raw.log').read_bytes();after=hashes()
(out/'result.json').write_text(json.dumps({'natural_exit':r.returncode,'source_after':after,'source_held':after==before,'script_errors':raw.count(b'SCRIPT ERROR:'),'error_lines':sum(x.startswith(b'ERROR:') for x in raw.splitlines())},indent=2),encoding='utf-8')
print(raw.decode('utf-8',errors='replace'));raise SystemExit(r.returncode)
