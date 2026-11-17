from pathlib import Path
import os,sys,json,hashlib,subprocess,datetime
root=Path('C:/NE/bg32-20261117')
quality,name=sys.argv[1:]
assert quality in ('low','high','medium')
out=Path('D:/NestEggVerification/evidence-20261117/ne259')/name
out.mkdir(parents=True,exist_ok=False)
paths=['tools/enemy_glow_probe.gd','tools/enemy_glow_probe.tscn','tools/viewport_capture.gd','game/enemies/enemy_glow.gd','game/level/light_budget.gd','data/enemies/watchdog.tres','data/enemies/heavy_gunner.tres','data/enemies/sweeper.tres','data/levels/ch1_warehouse.tres','project.godot','core/light_quality.gd']
def sources():
 return {p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in paths}
before=sources()
for p in paths:
 dst=out/'source'/p;dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes((root/p).read_bytes())
env=os.environ.copy()
for key in ['APPDATA','LOCALAPPDATA','XDG_DATA_HOME']:env[key]=str(out/'profile')
argv=['C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe','--path',str(root),'--rendering-driver','vulkan','--rendering-method','forward_plus','res://tools/enemy_glow_probe.tscn','--','--out='+str(out),'--tag='+quality,'--quality='+quality]
locked=[sys.executable,str(root/'tools/comfyui/gpu_lock.py'),'--',*argv]
launch={'argv':argv,'lock_argv':locked,'utc_start':datetime.datetime.now(datetime.timezone.utc).isoformat(),'base':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'source_before':before,'profile_env':{k:env[k] for k in ['APPDATA','LOCALAPPDATA','XDG_DATA_HOME']}}
(out/'launch.json').write_text(json.dumps(launch,indent=2),encoding='utf-8')
with (out/'raw.log').open('wb') as stream:
 run=subprocess.run(locked,cwd=root,env=env,stdout=stream,stderr=subprocess.STDOUT)
after=sources();raw=(out/'raw.log').read_bytes()
report_path=out/(quality+'-index.json')
report=json.loads(report_path.read_text(encoding='utf-8')) if report_path.exists() else None
userdir=report.get('user_data_dir','') if report else ''
result={'natural_exit':run.returncode,'utc_end':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source_after':after,'source_unchanged':before==after,'script_errors':raw.count(b'SCRIPT ERROR:'),'engine_error_lines':sum(line.startswith(b'ERROR:') for line in raw.splitlines()),'report_present':report is not None,'reported_user_data_dir':userdir,'profile_under_redirected_dir':Path(userdir).is_relative_to(out/'profile') if userdir else False,'tool_sha_matches':report.get('tool_sha256')==before['tools/enemy_glow_probe.gd'] if report else False}
(out/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(result,indent=2));sys.exit(run.returncode)
