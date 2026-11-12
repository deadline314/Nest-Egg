"""Build small per-case external raw archives and replay canonical pixel precision."""
import argparse,hashlib,json,runpy,zipfile
from pathlib import Path
from PIL import Image
ROOT=Path('C:/Users/stanl/.codex/worktrees/ne286-boss-cache-verification/Nest-Egg')
P=Path(__file__).resolve().parent
def load(p):return json.loads(p.read_text(encoding='utf8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def verify(root,make_archives):
    assert sha(root/'verification-source-originals/verify_capture_precision.py')==load(root/'verification-source-originals/index.json')['sha256']
    canonical=runpy.run_path(str(root/'verification-source-originals/verify_capture_precision.py'))['verify']
    reports=[]
    for count in [2,3]:
        folder=root/('native-layout-v3-count%d'%count)
        before=load(folder/'before.json');after=load(folder/'after.json');assert before==after
        proc=load(folder/'process.json');assert proc['exit_code']==0 and not proc['diagnostics']
        assert len(before['primary_C'])==397
        for name in ['queue-before-lock.json','queue-inside-before.json','queue-inside-after.json','queue-after-unlock.json']:assert load(folder/name)['clear']
        data=load(folder/'measurement.json');native=data['native'];captures=native['captures']
        assert data['target_count']==count and native['renderer']=='forward_plus' and native['menu_focus_preserved'] and native['all_raw_before_encode']
        assert [c['page'] for c in captures]==['early-actions','voluntary-card','natural-finish-menu']
        assert not captures[0]['sequence_complete'] and not captures[1]['sequence_complete'] and captures[2]['sequence_complete']
        assert all(c['readiness']['hint_ready'] and c['readiness']['hint_text'] for c in captures)
        assert all(c['readiness']['card_ready'] and c['readiness']['card_scale']==[1.0,1.0] and c['readiness']['card_alpha']==1.0 for c in captures[1:])
        assert captures[0]['focus_text']=='從檢查點重來' and captures[1]['focus_text']==captures[2]['focus_text']=='回主選單'
        assert 'ST13_le_3000msec' not in data['measurement'],'Native layout must never claim natural clock acceptance'
        names=[]
        for c in captures:
            assert c['actions_visible'] and c['hint_visible'] and c['size']==[1280,720] and c['hdr_2d']
            assert (folder/c['linear_raw']).stat().st_size==c['raw_bytes']
            with Image.open(folder/c['encoded_png']) as image:assert image.mode=='RGBA' and image.size==(1280,720)
            names.extend([c['linear_raw'],c['encoded_png'],c['page']+'-format.json'])
        archive=folder/'native-raw.zip'
        if make_archives:
            assert not archive.exists()
            manifest=dict(resolution=[1280,720],captures=captures,files={n:dict(bytes=(folder/n).stat().st_size,sha256=sha(folder/n)) for n in names})
            with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_STORED) as z:
                for n in names:z.write(folder/n,n)
                z.writestr('manifest.json',json.dumps(manifest,indent=2)+'\n')
        report=canonical(archive);reports.append(report)
    print(json.dumps(dict(scope='Native layout and independent full-pixel encoding only; not natural retry timing',reports=reports),indent=2))
    return reports
if __name__=='__main__':
    a=argparse.ArgumentParser();a.add_argument('--raw-root',type=Path,default=P);a.add_argument('--make-archives',action='store_true');v=a.parse_args();verify(v.raw_root,v.make_archives)
