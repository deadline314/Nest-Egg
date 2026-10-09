#!/usr/bin/env python3
"""Owned private runner installer; rejects wrong engine and empty suite selection.
Python dependencies: Pillow, numpy. Render requires existing software Xvfb DISPLAY.
No network/install/runtime/art/selector/ticket mutations. Full contact render ~15min.
"""
import argparse, os, shutil, subprocess, time, json, re
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--repo',required=True);p.add_argument('--godot',required=True)
p.add_argument('--step',choices=['install','inventory','source','affected','numeric','gait','gait_capture','metadata','capture','watchdog','joints','negative','check','controls','repro'],required=True)
a=p.parse_args();root=Path(a.repo).resolve();owned=root/'pm/Nest-Egg/attachments/NE-90-cloud-creatures';private=root/'.godot/cloud-creature-audit'
env=os.environ.copy()
for key,sub in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]:
 directory=private/sub;directory.mkdir(parents=True,exist_ok=True);env[key]=str(directory)
version=subprocess.check_output([a.godot,'--version'],text=True,env=env).strip()
if not version.startswith('4.7.stable.'): raise SystemExit('REJECTED engine '+version+'; CI requires 4.7-stable')
private.mkdir(parents=True,exist_ok=True)
for f in (owned/'runner').iterdir():
 if f.suffix in ['.gd','.tscn']: shutil.copyfile(f,private/f.name)
if a.step=='install': print(version,private);raise SystemExit(0)
env=os.environ.copy()
for key,sub in [('XDG_DATA_HOME','data'),('XDG_CONFIG_HOME','config'),('XDG_CACHE_HOME','cache')]: env[key]=str(private/sub)
base=[a.godot,'--audio-driver','Dummy','--path',str(root)]
render=a.step in ['capture','gait_capture','watchdog','joints','negative','repro']
if render:
 if not env.get('DISPLAY'): raise SystemExit('UNVERIFIED render: DISPLAY required; no GPU fallback')
 env['LIBGL_ALWAYS_SOFTWARE']='1';base+=['--rendering-method','gl_compatibility','--rendering-driver','opengl3']
else: base+=['--headless']
if a.step in ['inventory','source','check','controls']:
 script={'inventory':'inventory.py','source':'source_check.py','check':'check_contacts.py','controls':'controls.py'}[a.step]
 cmd=['python3',str(owned/script),'--repo',str(root)]
 if a.step=='inventory':cmd+=['--out',str(owned)]
elif a.step=='affected':
 suites=['PartCreatureSuite','ChainCreatureSuite','ExoticEnemiesSuite','Chapter1EnemiesSuite','AssaultEnemiesSuite']
 cmd=base+['tests/smoke_test.tscn','--','--only='+','.join(suites)]
else:
 scene='joints' if a.step in ['negative','repro'] else a.step
 cmd=base+['.godot/cloud-creature-audit/'+scene+'.tscn']
 if a.step=='negative':cmd+=['--','--negative-control']
 if a.step=='repro':cmd+=['--','--id=shock_hound','--state=idle','--part=tail','--frames=1','--face=1','--zoom=3.4','--tag=repro-shock-tail']
start=time.monotonic()
with (owned/('rerun-'+a.step+'.log')).open('w') as f:
 result=subprocess.run(cmd,cwd=root,env=env,stdout=f,stderr=subprocess.STDOUT)
if a.step=='affected':
 text=(owned/('rerun-'+a.step+'.log')).read_text()
 actual=set(re.findall(r'^SUITE_TIME (\w+) ',text,re.M));checks=re.search(r'checks: (\d+), failures: (\d+)',text)
 if actual!=set(suites) or not checks or int(checks[1])<=0 or int(checks[2])!=0:
  result.returncode=1;print('FAIL suite coverage/assertions',actual)
(owned/('command-'+a.step+'.json')).write_text(json.dumps({'command':cmd,'engine':version,'exit':result.returncode,'elapsed_seconds':time.monotonic()-start,'baseline':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),'render':render},indent=2)+'\n')
print(a.step,result.returncode,'elapsed',round(time.monotonic()-start,3))
raise SystemExit(result.returncode)
