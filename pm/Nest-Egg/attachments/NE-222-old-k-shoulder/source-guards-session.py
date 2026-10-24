from pathlib import Path
import tempfile,shutil,subprocess,json,hashlib
from PIL import Image
root=Path.cwd();source=Path('art_src/characters/old_k_shoulder_20261024');manifest=json.loads((root/source/'provenance.json').read_text());out=[]
with tempfile.TemporaryDirectory(prefix='old-k-source-guards-') as temp:
 t=Path(temp)
 for relative in [*manifest['inputs'],str(source/'rebuild.py'),str(source/'provenance.json'),'tools/comfyui/cut_layers.py','tools/comfyui/cut_rig_parts.py']:
  p=t/relative;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/relative,p)

 for module in (root/'tools/comfyui').glob('*.py'):shutil.copy2(module,t/'tools/comfyui'/module.name)
 target=t/'art_src/characters/old_k/overrides/refined/torso.png';target.parent.mkdir(parents=True);Image.new('RGBA',(832,1216),(1,2,3,4)).save(target);before=target.read_bytes()
 p=subprocess.run([__import__('sys').executable,str(t/source/'rebuild.py')],capture_output=True,text=True)
 assert p.returncode!=0 and 'Refusing to replace a different source override' in p.stderr and target.read_bytes()==before
 out.append({'case':'foreign_override','rejected':True,'target_unchanged':True,'stderr':p.stderr})
 target.unlink();p=t/source/'shoulder-mask.png';p.write_bytes(p.read_bytes()+b'changed')
 q=subprocess.run([__import__('sys').executable,str(t/source/'rebuild.py')],capture_output=True,text=True)
 assert q.returncode!=0 and 'Source changed' in q.stderr and not target.exists()
 out.append({'case':'changed_input','rejected':True,'no_output_written':True,'stderr':q.stderr})
Path('/workspace/Nest-Egg/work/batch1024/old-k-source-guards.json').write_text(json.dumps(out,indent=2)+'\n');print('2 source refusal controls passed')
