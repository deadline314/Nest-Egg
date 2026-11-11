from pathlib import Path
import json, os, subprocess, sys, time, hashlib
root=next(p for p in Path(__file__).resolve().parents if (p/'project.godot').is_file())
out=Path(os.environ.get('NE_READABILITY_OUT',str(root/'pm/Nest-Egg-BG/attachments/BG-53-corrected-lighting-2026-11-11')))
out.mkdir(parents=True,exist_ok=True)
mode=sys.argv[1] if len(sys.argv)>1 else 'focus'
cases=[('geometry-native-corrected',['--native'])]
for quality in ['high','low']:
 cases.append(('scene-'+quality,['--level=ch2_pawnshop,ch2_ledger_front,ch2_ledger_office,ch3_office_hall','--quality='+quality]))
for quality in ['high','low']:
 cases.append(('ch1-'+quality+'-all',['--quality='+quality,'--level=']))
env=dict(os.environ,PYTHONIOENCODING='utf-8',APPDATA=str(root/'work/bg48-corrected-user'))
for tag,extra in cases:
 folder=out/tag
 if folder.exists():raise SystemExit('refusing to overwrite '+str(folder))
 folder.mkdir()
 scene='res://tools/test_contrast_probe_geometry.tscn' if tag.startswith('geometry-') else ('res://tools/readability_phase_probe.tscn' if tag.startswith('scene-') else 'res://pm/Nest-Egg-BG/attachments/BG-53-corrected-lighting-2026-11-11/native_ch1.tscn')
 command=[sys.executable,str(root/'tools/comfyui/gpu_lock.py'),'--','C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe','--path',str(root),'--rendering-method','forward_plus','--rendering-driver','vulkan',scene,'--','--out='+str(folder),'--player','--fixed-aim','--quality=high','--brightness=0.5','--level=ch2_lounge_front','--tag='+tag,*extra]
 (folder/'command.json').write_bytes((json.dumps(command,indent=2)+'\n').encode())
 hashes={path:hashlib.sha256((root/path).read_bytes()).hexdigest() for path in ['tools/contrast_probe.gd','tools/readability_phase_probe.gd','tools/viewport_capture.gd','tools/scene_tour.gd','data/lighting/lounge_front.tres','data/lighting/market.tres','tools/readability_check.gd','tools/ch1_readability_check.gd','core/aim_input.gd','tools/test_contrast_probe_geometry.gd','pm/Nest-Egg-BG/attachments/BG-53-corrected-lighting-2026-11-11/native_ch1.gd','pm/Nest-Egg-BG/attachments/BG-53-corrected-lighting-2026-11-11/native_ch1.tscn']}
 (folder/'source-before.json').write_bytes((json.dumps(hashes,indent=2)+'\n').encode())
 for path,expected in hashes.items():
  raw=(root/path).read_bytes();assert hashlib.sha256(raw).hexdigest()==expected
  dest=folder/'source'/path;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(raw)
 started=time.monotonic()
 with (folder/'run.log').open('wb') as log:
  process=subprocess.Popen(command,cwd=root,env=env,stdout=log,stderr=subprocess.STDOUT)
  try:code=process.wait(timeout=600)
  except subprocess.TimeoutExpired:
   subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],capture_output=True);code=124
 result={'exit':code,'seconds':time.monotonic()-started,'source_after':{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in hashes}}
 (folder/'exit.json').write_bytes((json.dumps(result,indent=2)+'\n').encode())
 print(tag,code,round(result['seconds'],2),flush=True)
