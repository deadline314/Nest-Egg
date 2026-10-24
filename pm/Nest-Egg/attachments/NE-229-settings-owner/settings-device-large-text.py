from pathlib import Path
import subprocess,os,json,hashlib
root=Path.cwd();w=Path('/workspace/Nest-Egg/work/batch1024');target=root/'ui/settings_screen.gd';candidate=target.read_bytes();original=subprocess.check_output(['git','show','HEAD:ui/settings_screen.gd']);results=[]
try:
 for side,data in [('before',original),('after',candidate)]:
  target.write_bytes(data);name=f'ne229-1024-settings-device-{side}-120';cmd=['python3',str(w/'native-large.py'),name,'res://work/batch1024/settings_device_probe.tscn','--text-scale=1.2']
  with (w/f'settings-device-{side}-120-driver.log').open('w') as f:p=subprocess.run(cmd,cwd=root,env={**os.environ,'NE_NATIVE_PROJECT':'../batch1024/settings-device-worktree'},stdout=f,stderr=subprocess.STDOUT,timeout=300)
  results.append({'side':side,'exit':p.returncode,'source_sha256':hashlib.sha256(data).hexdigest()})
finally:
 target.write_bytes(candidate)
 assert target.read_bytes()==candidate
 (w/'settings-device-large-text-receipt.json').write_text(json.dumps({'runs':results,'candidate_restored':True,'candidate_sha256':hashlib.sha256(candidate).hexdigest()},indent=2)+'\n')
print(json.dumps(results))
