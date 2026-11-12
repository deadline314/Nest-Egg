"""Read the original native baseline/candidate pair without trusting pass labels."""
from pathlib import Path
import argparse, hashlib, json
from PIL import Image

def digest(data):
    return hashlib.sha256(data).hexdigest()

def verify(folder):
    assert json.loads((folder/'source-before.json').read_bytes()) == json.loads((folder/'source-after.json').read_bytes())
    assert json.loads((folder/'c-before.json').read_bytes()) == json.loads((folder/'c-after.json').read_bytes())
    result = {}
    for candidate in (False, True):
        leaf = folder/('candidate' if candidate else 'baseline')
        receipt = json.loads((leaf/'exit.json').read_bytes())
        assert receipt['exit'] == (0 if candidate else 1) and not receipt['diagnostics']
        assert receipt['source_unchanged'] and receipt['c_unchanged'] and receipt['queue_clear']
        for label in ('before','after'):
            queues = json.loads((leaf/f'queue-{label}.json').read_bytes())
            assert [r['port'] for r in queues] == [8188,8189]
            assert all((r['state']=='empty' and r['running']==r['pending']==0) or (r['state']=='refused' and r['winerror']==10061) for r in queues)
        record = json.loads((leaf/'result.json').read_bytes())
        expected = [] if candidate else ['live reduced flashes clears the actual rendered grain']
        assert record['candidate'] == candidate and record['failures'] == receipt['actual_failures'] == expected
        assert record['renderer']=='forward_plus' and record['hdr_2d'] and record['display']!='headless'
        assert [r['label'] for r in record['records']] == ['grain-on','grain-reduced','grain-restored','grain-empty','authored-hidden']
        raw, png = {}, {}
        for shot in record['records']:
            name = shot['label']
            raw[name] = (leaf/(name+'.bin')).read_bytes()
            assert digest(raw[name])==shot['raw_sha256'] and len(raw[name])==shot['bytes']
            assert (shot['width'],shot['height'])==(1280,720)
            with Image.open(leaf/(name+'.png')) as picture:
                assert picture.mode=='RGBA' and picture.size==(1280,720)
                png[name]=picture.tobytes()
        for pixels in (raw,png):
            assert pixels['grain-on']==pixels['grain-restored'] and pixels['grain-on']!=pixels['grain-empty']
            assert pixels['authored-hidden']==pixels['grain-empty']
            assert pixels['grain-reduced']==pixels['grain-empty' if candidate else 'grain-on']
        assert [r['reduce_flashes'] for r in record['records'][:3]]==[False,True,False]
        assert len({r['seed'] for r in record['records'][:3]})==1
        result[leaf.name]=dict(engine_exit=receipt['exit'],expected_negative=not candidate,checks=record['checks'],original_pixel_assertions_pass=True,seconds=receipt['seconds'])
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('folder',type=Path)
    args=parser.parse_args();print(json.dumps(verify(args.folder),indent=2))
