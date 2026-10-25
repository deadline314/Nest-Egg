import os,subprocess,sys,signal,time
from pathlib import Path
base=Path('/workspace/Nest-Egg/work/batch1020b')
import fcntl
display_guard=(base/'native-display.lock').open('a')
fcntl.flock(display_guard,fcntl.LOCK_EX)
wt=base/os.environ.get('NE_NATIVE_PROJECT','lighting')
if sys.argv[1].startswith('ne257-before-'):wt=base/'sway-baseline'
name=sys.argv[1]; tool=sys.argv[2]
env=os.environ.copy();env.update(DISPLAY=':99',LD_LIBRARY_PATH='/workspace/Nest-Egg/work/ne279/runtime/usr/lib/x86_64-linux-gnu',VK_ICD_FILENAMES='/workspace/Nest-Egg/work/ne279/runtime/usr/share/vulkan/icd.d/lvp_icd.json',XDG_DATA_HOME=str(base/(name+'-profile')))
(base/name).mkdir(exist_ok=True)
command=['python','tools/comfyui/gpu_lock.py','--',env.get('NE_NATIVE_GODOT','/workspace/Nest-Egg/work/batch1020b/godot472/Godot_v4.7.2-stable_linux.x86_64'),'--path',str(wt),'--audio-driver','Dummy','--rendering-driver','vulkan','--rendering-method','forward_plus',*(['--script'] if env.get('NE_NATIVE_SCRIPT')=='1' else []),tool,'--','--out='+str(base/name),*sys.argv[3:]]
with (base/(name+'-xvfb.log')).open('w') as xlog:
 server=subprocess.Popen(['/workspace/Nest-Egg/work/ne279/runtime/usr/bin/Xvfb',':99','-screen','0','3200x1800x24'],env=env,stdout=xlog,stderr=subprocess.STDOUT)
 try:
  import time
  time.sleep(0.4)
  if server.poll() is not None: raise RuntimeError('Xvfb failed')
  with (base/(name+'.log')).open('w') as log:
   result=subprocess.Popen(command,cwd=wt,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
   started=time.monotonic()
   while result.poll() is None:
    if time.monotonic()-started>1800 or 'SCRIPT ERROR:' in (base/(name+'.log')).read_text(errors='replace'):
     os.killpg(result.pid,signal.SIGTERM)
     result.wait(timeout=10)
     break
    time.sleep(0.5)
 finally:
  server.terminate();server.wait(timeout=10)
(base/(name+'.exit')).write_text(str(result.returncode))
print(name,'exit',result.returncode,flush=True)
print((base/(name+'.log')).read_text()[-4000:])
sys.exit(result.returncode)
