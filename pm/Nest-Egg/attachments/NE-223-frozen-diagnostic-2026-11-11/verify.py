"""Verify the diagnostic archive; does not launch Godot or claim isolated performance."""
from pathlib import Path
from zipfile import ZipFile
from PIL import Image
import hashlib, io, json

folder=Path(__file__).resolve().parent
receipt=json.loads((folder/'receipt.json').read_text(encoding='utf-8'))
checks=0
def check(value, message):
    global checks
    if not value: raise ValueError(message)
    checks+=1
with ZipFile(folder/'raw.zip') as archive:
    check(hashlib.sha256((folder/'raw.zip').read_bytes()).hexdigest()==receipt['archive_sha256'],'archive SHA')
    manifest=json.loads(archive.read('manifest.json'))
    check(set(archive.namelist())==set(manifest)|{'manifest.json'},'archive members')
    for name,row in manifest.items():
        data=archive.read(name)
        check(len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'],name)
    runs=json.loads(archive.read('validation.json'))
    check([row['name'] for row in runs]==['always-negative','native-1280','native-1920'],'three complete programs')
    for row in runs:
        name=row['name']; width=1920 if name=='native-1920' else 1280; height=width*9//16
        report=json.loads(archive.read(f'{name}/quest-map-perf-{width}.json'))
        negative=name=='always-negative'
        check(row['exit']==(1 if negative else 0),'actual program result '+name)
        check(len(report['issues'])==(4 if negative else 0),'issue count '+name)
        check(len(report['freeze_samples'])==4 and [item['unchanged'] for item in report['freeze_samples']]==[not negative]*4,'all four pause samples '+name)
        check(report['adapter']=='AMD Radeon RX 9070 XT' and report['renderer']=='forward_plus','real renderer '+name)
        check(report['resolution']==[width,height] and report['shared_workload'],'dimensions and scope '+name)
        log=archive.read(f'{name}/run.log')
        check(b'SCRIPT ERROR' not in log,'no script error '+name)
        check(log.count(b'ERROR:')==(4 if negative else 0),'only expected engine diagnostics '+name)
        for source,sha in report['sources'].items():
            source_name=source.removeprefix('res://').replace('/','_')+'.txt'
            check(hashlib.sha256(archive.read(name+'/'+source_name)).hexdigest()==sha,'tested source '+source)
        for sample in report['freeze_samples']:
            before,after=sample['before'],sample['after']
            check((before==after)==(not negative),'real state equality '+name)
            check(before['level_can_process']==negative and before['player_can_process']==negative,'real process eligibility '+name)
        for page in ['journal','region-focus','world']:
            with Image.open(io.BytesIO(archive.read(f'{name}/NE-223-native-{page}-{width}.png'))) as picture:
                check(picture.size==(width,height),'actual PNG '+name+'/'+page)
    original=archive.read('tested-normal-source.gd.txt')
    negative=archive.read('tested-negative-source.gd.txt')
    expected=original.replace(b'level.process_mode = Node.PROCESS_MODE_PAUSABLE',b'level.process_mode = Node.PROCESS_MODE_ALWAYS',1)
    expected=expected.replace(b'"res://tools/quest_map_perf_probe.gd"',b'"res://work/ne223_perf_always_negative.gd"',1)
    check(negative==expected,'negative changes only Level process mode and its own source receipt path')
project=folder.parents[3]
check(hashlib.sha256((project/'tools/quest_map_perf_probe.gd').read_bytes()).hexdigest()==receipt['tested_probe_sha256'],'current probe equals tested bytes')
print(json.dumps({'checks':checks,'failures':0,'positive_rounds':8,'negative_rounds':4,'scope':'shared-workload diagnostic; no physical input, isolated performance or human no-hitch acceptance'},indent=2))
