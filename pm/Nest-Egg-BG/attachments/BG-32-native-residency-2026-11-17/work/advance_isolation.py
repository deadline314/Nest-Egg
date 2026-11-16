from pathlib import Path
import hashlib,json,subprocess,shutil

project=Path('C:/NE/bg32-20261117')
work=Path(__file__).resolve().parent
saved=json.loads((work/'isolation-before-advance.json').read_text())
git=lambda *args:subprocess.check_output(['git','-C',str(project),*args])
files=list(saved['files'])
owned_status={entry['path'] for entry in saved['status']}
for item in git('status','--porcelain=v1','-z').decode('utf-8').split('\0'):
 if not item: continue
 path=item[3:]
 assert path in files or path in owned_status,('unowned dirty path',item)
for name,entry in saved['files'].items():
 assert hashlib.sha256((project/name).read_bytes()).hexdigest()==entry['sha256'],('changed frozen source',name)
# Preserve only this task's untracked probes outside the project so the official
# selector sees exactly the candidate; never alter unrelated untracked files.
target=Path('C:/NE/evidence-20261117/bg32/isolation-work-sources')
target.mkdir(parents=True,exist_ok=True)
for relative in sorted(owned_status):
 if not relative.startswith('work/bg32-'): continue
 source=project/relative.rstrip('/')
 assert source.resolve().is_relative_to((project/'work').resolve())
 destination=target/source.name
 assert destination.resolve().is_relative_to(target.resolve())
 assert not destination.exists(),destination
 shutil.move(str(source),str(destination))
tracked=[name for name in files if git('ls-files','--',name).strip()]
subprocess.run(['git','-C',str(project),'restore','--source=HEAD','--',*tracked],check=True)
subprocess.run(['git','-C',str(project),'checkout','--detach',saved['target_commit']],check=True)
for name,entry in saved['files'].items():
 source=work/'frozen-candidate'/name
 destination=project/name
 destination.parent.mkdir(parents=True,exist_ok=True)
 destination.write_bytes(source.read_bytes())
 assert hashlib.sha256(destination.read_bytes()).hexdigest()==entry['sha256']
manifest={'base':git('rev-parse','HEAD').decode().strip(),'source_files':saved['files'],
          'status':git('status','--porcelain=v1').decode('utf-8'),
          'note':'Own dirty sources backed up, own probes preserved outside project; no hard reset or unrelated cleanup.'}
(work/'official-source-before.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
print(json.dumps(manifest,indent=2))
