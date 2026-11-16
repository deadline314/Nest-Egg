"""Add later original performance records without rewriting historical volumes."""
from pathlib import Path
import argparse,hashlib,json,tarfile
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
def sha(path):
 with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()
def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--index',type=Path,required=True)
 args=parser.parse_args();index_path=args.index.resolve();folder=index_path.parent
 index=json.loads(index_path.read_text(encoding='utf8'))
 assert index['format']==1
 frozen=json.loads((HERE/'production-v12-freeze-123.json').read_text(encoding='utf8'))['files']
 for name,value in frozen.items():assert sha(ROOT/name)==value,name
 old=set()
 for item in index['archives']:
  assert sha(folder/item['file'])==item['sha256']
  manifest=folder/item['manifest'];assert sha(manifest)==item['manifest_sha256']
  old.update(row['path'] for row in json.loads(manifest.read_text(encoding='utf8'))['members'])
 performance=HERE/'performance-v12'
 assert (performance/'runs.json').is_file() and (performance/'source-guard.json').is_file(),'Completed performance records required'
 runs=json.loads((performance/'runs.json').read_text(encoding='utf8'))['runs']
 assert len(runs)==10 and all(row['exit']==0 for row in runs),'All ten original CLI probes must complete'
 assert json.loads((performance/'source-guard.json').read_text(encoding='utf8'))['unchanged'],'Performance source guard failed'
 paths=sorted([p for p in performance.rglob('*') if p.is_file()]+[Path(__file__).resolve()])
 assert paths,'No performance records'
 assert all(p.relative_to(ROOT).as_posix() not in old for p in paths),'Duplicate original evidence path'
 name='v12-performance-01.raw.tar.xz';target=folder/name
 assert not target.exists(),'Refusing to replace a historical volume'
 assert sum(p.stat().st_size+2048 for p in paths)<38_000_000,'Supplement needs more volumes'
 rows=[]
 with tarfile.open(target,'w:xz',preset=4,format=tarfile.PAX_FORMAT) as archive:
  for p in paths:
   stat=p.stat();relative=p.relative_to(ROOT).as_posix()
   rows.append({'path':relative,'size':stat.st_size,'sha256':sha(p),'original_mtime_ns':stat.st_mtime_ns})
   info=tarfile.TarInfo(relative);info.size=stat.st_size;info.mode=0o644;info.mtime=0
   with p.open('rb') as stream:archive.addfile(info,stream)
 assert target.stat().st_size<50_000_000
 member_name=name+'.members.json';member_file=folder/member_name
 member_file.write_bytes((json.dumps({'archive':name,'members':rows},indent=2)+'\n').encode('utf8'))
 index['archives'].append({'file':name,'epoch':'v12-performance','size':target.stat().st_size,'sha256':sha(target),'manifest':member_name,'manifest_sha256':sha(member_file),'member_count':len(rows)})
 index['source_files']+=len(rows);index['source_bytes']+=sum(x['size'] for x in rows)
 index['performance_supplement_note']='Later original probe records added; all earlier archive bytes retained unchanged.'
 temporary=index_path.with_suffix('.pending.json');assert not temporary.exists()
 temporary.write_bytes((json.dumps(index,indent=2)+'\n').encode('utf8'));temporary.replace(index_path)
 print(name,len(rows),'original members',target.stat().st_size,'bytes; historical volumes unchanged',flush=True)
if __name__=='__main__':main()
