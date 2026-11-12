"""Replay Root's existing reviewer algorithms in fresh temporary paths only."""
from pathlib import Path,PurePosixPath
import hashlib,json,shutil,subprocess,sys,tempfile,zipfile
here=Path(__file__).resolve().parent
def sha(raw):return hashlib.sha256(raw).hexdigest()
def extract(archive,target,rows):
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None and len(z.namelist())==len(rows)
        assert set(z.namelist())=={r['path'] for r in rows}
        for r in rows:
            raw=z.read(r['path']);assert len(raw)==r['bytes'] and sha(raw)==r['sha256']
            path=PurePosixPath(r['path']);assert not path.is_absolute() and '..' not in path.parts and ':' not in r['path']
            dest=target.joinpath(*path.parts);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(raw)
index=json.loads((here/'root-epochs-index.json').read_bytes());summary=[]
with tempfile.TemporaryDirectory(prefix='st22-root-review-') as temporary:
    tmp=Path(temporary);originals=tmp/'originals';replay=tmp/'replay';work=replay/'work';work.mkdir(parents=True)
    reviews=index['parser_import_reviewers'];raw=(here/reviews['file']).read_bytes()
    assert len(raw)==reviews['bytes'] and sha(raw)==reviews['sha256'];extract(here/reviews['file'],originals/'parser-import',reviews['members'])
    for name in ['review_st22_native_v1.py','review_st22_alpha_v3.py']:
        raw=(originals/'parser-import'/name).read_bytes();source=raw.decode('utf-8')
        old="root = Path('C:/Users/stanl/Github/Nest-Egg')";assert source.count(old)==1
        # The only adapted text is the root path. Assertions/formulas/thresholds
        # remain the exact original reviewer logic; original bytes stay in ZIP.
        adapted=source.replace(old,'root = Path('+repr(str(replay))+')',1)
        (work/name).write_text(adapted,encoding='utf-8',newline='\n')
    for case in index['native']:
        archive=here/case['file'];raw=archive.read_bytes();assert len(raw)==case['bytes'] and sha(raw)==case['sha256']
        original=originals/case['epoch'];extract(archive,original,case['members'])
        target=work/'st22-native-review-v1'/case['epoch'];target.mkdir(parents=True)
        for r in case['members']:
            # Copy original inputs into a new replay directory, leaving the
            # original generated review outputs in the untouched originals copy.
            if r['path'] in ['independent-review.json','alpha-review.json']:continue
            p=target/r['path'];p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((original/r['path']).read_bytes())
        script='review_st22_alpha_v3.py' if 'alpha-v3' in case['epoch'] else 'review_st22_native_v1.py'
        result=subprocess.run([sys.executable,'-X','utf8',str(work/script),case['epoch']],cwd=replay,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        assert result.returncode==0,result.stdout.decode('utf-8',errors='replace')
        native=json.loads((target/'independent-review.json').read_bytes())
        item={'epoch':case['epoch'],'archive_sha256':case['sha256'],'members':len(case['members']),'native_records':len(native['records']),'body_bbox_outliers':[{'label':r['label'],'bounds':r['conservative_actor_bounds_outside']} for r in native['records'] if r['conservative_actor_bounds_outside']]}
        if 'alpha-v3' in case['epoch']:
            alpha=json.loads((target/'alpha-review.json').read_bytes());assert alpha['all_heads_inside'] and len(alpha['records'])==6
            item.update(alpha_records=6,any_alpha_outside_total=sum(r['any_alpha_outside_safe'] for r in alpha['records']))
        else:item['alpha_scope']='none in original; body outlier is not an opaque clipping/padding verdict'
        summary.append(item)
print(json.dumps({'passed':True,'scope':'original reviewer algorithms with only temporary root path substitution, no original epoch or reviewer edits; earliest six have no alpha, final12 are settled samples not a continuous trace','records':summary,'parser_import_source_members':len(reviews['members'])},indent=2))
