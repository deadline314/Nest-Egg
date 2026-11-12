"""Offline NE264 native proof. Python 3 + numpy + Pillow; never launches Godot."""
from pathlib import Path,PurePosixPath
import argparse,copy,datetime,hashlib,json,subprocess,sys,tempfile,zipfile

def sha(raw):return hashlib.sha256(raw).hexdigest()
def unpack(archive,target,members=None):
    with zipfile.ZipFile(archive) as z:
        names=z.namelist();assert len(names)==len(set(names))
        if members is not None:assert set(names)=={r['path'] for r in members}
        expected={r['path']:r for r in members} if members else {}
        for name in names:
            parts=PurePosixPath(name);assert not parts.is_absolute() and '..' not in parts.parts and ':' not in name
            raw=z.read(name)
            if members is not None:
                record=expected[name];assert len(raw)==record['bytes'] and sha(raw)==record['sha256'],name
            dest=target.joinpath(*parts.parts);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(raw)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raw-root',type=Path,help='External exact ZIP directory; default ./raw')
    parser.add_argument('--only',help='One case name; default all eight')
    parser.add_argument('--receipt',type=Path,help='Write a new receipt; refuses to replace an existing file')
    args=parser.parse_args();here=Path(__file__).resolve().parent
    rawroot=args.raw_root or here/'raw'
    index=json.loads((here/'raw-index.json').read_text(encoding='utf-8'))
    selected=json.loads((here/'selected-index.json').read_text(encoding='utf-8'))
    for row in selected:
        raw=(here/row['path']).read_bytes();assert len(raw)==row['bytes'] and sha(raw)==row['sha256']
    cases=[r for r in index['captures'] if args.only is None or r['case']==args.only];assert cases
    summary=[];negative_done=False
    with tempfile.TemporaryDirectory(prefix='ne264-readonly-') as temporary:
        tmp=Path(temporary);readers=tmp/'readers';unpack(here/'readers-original.zip',readers)
        sys.path.insert(0,str(readers));import reader_native_v14 as reader
        for case in cases:
            archive=rawroot/case['file'];raw=archive.read_bytes()
            assert len(raw)==case['bytes'] and sha(raw)==case['sha256'],case['file']
            root=tmp/case['case'];unpack(archive,root,case['members'])
            report=json.loads((root/'result.json').read_text(encoding='utf-8'))
            if case['case']=='aim-full60':command=[sys.executable,str(readers/'reader_aimfull_v14.py'),str(root),str(tmp/(case['case']+'-reader'))]
            else:
                role='matrix' if case['case'].startswith('matrix') else {'mixed30':'mixed','aim60':'aim','shoot60':'shoot'}[case['case']]
                command=[sys.executable,str(readers/'reader_native_v14.py'),str(root),str(tmp/(case['case']+'-reader')),'--role='+role]
            result=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            assert result.returncode==0,result.stdout.decode('utf-8',errors='replace')
            if not negative_done:
                # Same actual recorded muzzle/canvas; injected on-ray primitive
                # is metadata-only, never passed off as a native image.
                fake=copy.deepcopy(report);row=fake['frames'][0]
                a,b,c,d,_,_=row['canvas_transform'];x,y=row['aim'];direction=[a*x+c*y,b*x+d*y]
                center=[row['aim_start_logical'][i]+direction[i]*10 for i in range(2)]
                row['plate_logical']=[center[0]-1,center[1]-1,2,2]
                assert reader.ray_failures(fake),'injected on-ray HUD must be rejected'
                base=report['phase_baselines'][0];bad=copy.deepcopy(report['frames'][0]);bad['far_slot_local']=[base['far_slot_local'][0]+24,base['far_slot_local'][1]]
                try:reader.common.movement([bad],base)
                except AssertionError:pass
                else:raise AssertionError('original exactly24 displacement negative must be rejected')
                negative_done=True
            item={'case':case['case'],'zip_sha256':case['sha256'],'members':len(case['members']),'draws':len(report['frames']),'passed':True}
            summary.append(item);print(json.dumps(item),flush=True)
    record={'passed':True,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'reader_sha256':sha(Path(__file__).read_bytes()),'cases':summary,'selected_images_verified':len(selected),'negative_controls':{'metadata_on_actual_ray':'rejected','original_exactly24_displacement':'rejected'},'scope':'original bytes and independent read-only geometry/pixel/source/queue validation; no new native, physical input, chapter completion or performance claim'}
    if args.receipt:
        with args.receipt.open('x',encoding='utf-8',newline='\n') as file:file.write(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record,indent=2))

if __name__=='__main__':main()
