from pathlib import Path
import hashlib,json,subprocess,shutil

project=Path('C:/NE/bg32-20261117')
work=Path(__file__).resolve().parent
files=['core/asset_prefetch.gd','tests/suite/test_ch1_map.gd','tests/helpers/prefetch_scope_checks.gd','tools/texture_route_probe.gd']
git=lambda *args:subprocess.check_output(['git','-C',str(project),*args])
entries=[]
for item in git('status','--porcelain=v1','-z').decode('utf-8').split('\0'):
 if not item: continue
 status,path=item[:2],item[3:]
 assert path in files or path.startswith('work/bg32-'),('unowned dirty path',status,path)
 entries.append({'status':status,'path':path})
snapshot={'head':git('rev-parse','HEAD').decode().strip(),'target_commit':git('rev-parse','3713db510^{commit}').decode().strip(),'status':entries,'files':{}}
for name in files:
 data=(project/name).read_bytes()
 target=work/'frozen-candidate'/name
 target.parent.mkdir(parents=True,exist_ok=True)
 target.write_bytes(data)
 snapshot['files'][name]={'sha256':hashlib.sha256(data).hexdigest(),'bytes':len(data)}
(work/'isolation-before-advance.json').write_text(json.dumps(snapshot,indent=2)+'\n',encoding='utf-8')
print(json.dumps(snapshot,indent=2))
