"""Portable read-only proof + meaningful copied-data negatives. No Godot."""
from pathlib import Path,PurePosixPath
import argparse,hashlib,json,sys,tempfile,zipfile
import numpy as np

def sha(raw):return hashlib.sha256(raw).hexdigest()
def unpack(archive,target,index):
    with zipfile.ZipFile(archive) as z:
        names=z.namelist();assert len(names)==len(set(names)) and set(names)=={r['path'] for r in index}
        for r in index:
            raw=z.read(r['path']);assert len(raw)==r['bytes'] and sha(raw)==r['sha256']
            parts=PurePosixPath(r['path']);assert not parts.is_absolute() and '..' not in parts.parts and ':' not in r['path']
            dest=target.joinpath(*parts.parts);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(raw)

def main():
    here=Path(__file__).resolve().parent
    parser=argparse.ArgumentParser();parser.add_argument('--raw-root',type=Path,default=here);args=parser.parse_args()
    index=json.loads((here/'raw-index.json').read_bytes());archive=args.raw_root/index['file'];raw=archive.read_bytes()
    assert len(raw)==index['bytes'] and sha(raw)==index['sha256']
    history=json.loads((here/'history-index.json').read_bytes())
    with zipfile.ZipFile(here/'history-and-source-original.zip') as z:
        for r in history:
            raw=z.read(r['path']);assert len(raw)==r['bytes'] and sha(raw)==r['sha256']
    for r in json.loads((here/'images-index.json').read_bytes()):
        raw=(here/r['path']).read_bytes();assert len(raw)==r['bytes'] and sha(raw)==r['sha256']
    sys.path.insert(0,str(here));import read_capture_v2 as reader
    with tempfile.TemporaryDirectory(prefix='st22-readonly-') as temporary:
        epoch=Path(temporary);unpack(archive,epoch,index['members'])
        result=reader.validate(epoch)
        report_path=epoch/'captures/observations.json';original=report_path.read_bytes();report=json.loads(original)
        row=report['rows'][0];mask_path=epoch/'captures'/row['mask_path'];mask_original=mask_path.read_bytes()
        width,height=row['mask_size'];shape=(height,width,4)
        empty=np.frombuffer(mask_original,dtype='<f2').reshape(shape).copy();empty[:,:,3]=0
        mask_path.write_bytes(empty.tobytes());row['mask_sha256']=sha(mask_path.read_bytes())
        report_path.write_text(json.dumps(report),encoding='utf-8')
        try:reader.validate(epoch)
        except AssertionError:empty_rejected=True
        else:raise AssertionError('nonempty>=200 gate did not reject empty actual raw alpha')
        report=json.loads(original);row=report['rows'][0]
        faint=np.frombuffer(mask_original,dtype='<f2').reshape(shape).copy();assert faint[2,2,3]==0
        assert row['roi'][1]+2.5<row['safe_pixels'][1]
        faint[2,2,3]=np.float16(.0001)
        mask_path.write_bytes(faint.tobytes());row['mask_sha256']=sha(mask_path.read_bytes());row['any_alpha_outside_safe']=1
        report_path.write_text(json.dumps(report),encoding='utf-8')
        try:reader.validate(epoch)
        except AssertionError as error:
            assert 'actual positive head alpha outside original safe boundary' in str(error),repr(error)
            faint_rejected=True
        else:raise AssertionError('faint nonopaque alpha outside original boundary was accepted')
    print(json.dumps({'passed':True,'draws':result['draws'],'after50_actor_seconds':result['actor_seconds_after50'],'after50_actual_breath_cycles':result['actual_breath_cycles_after50'],'minimum_alpha_margin_physical_pixels':result['minimum_alpha_margin_pixels'],'source_count':18967,'c_guard_count':397,'archive_sha256':index['sha256'],'original_member_count':len(index['members']),'negative_controls':{'copied_raw_empty_alpha':empty_rejected,'copied_raw_faint_outside_alpha':faint_rejected},'scope':'new continuous epoch only; negatives alter only tempfile copies with updated data SHA, original ZIP unchanged; no new native or missing old-frame alpha claim'},indent=2))

if __name__=='__main__':main()
