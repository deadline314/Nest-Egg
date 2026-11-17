"""Offline reader for the NE228 counter packet; Python standard library only.

Never runs a game, installs a profile, rewrites a source, or uses original D paths.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path, PurePosixPath
import re
import struct
import tarfile
import tempfile

HERE=Path(__file__).resolve().parent
def require(ok,message):
    if not ok: raise ValueError(message)
def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''): h.update(block)
    return h.hexdigest()
def load(path): return json.loads(path.read_bytes())
def validate_stats(observation):
    bar=observation['bar_rect'];scroll=observation['scroll_rect'];content=observation['content_rect']
    right=bar[0] if observation['bar_visible'] else scroll[0]+scroll[2]
    require(content[0]+content[2]<=right+.001,'stats content exceeds actual visible width')
    require(observation['frame']>0,'stats actual frame')
    for label in observation['stats']:
        chars=label['characters']
        require(''.join(c['text'] for c in chars)==label['text'],'stats original complete text')
        require([c['index'] for c in chars]==list(range(len(label['text']))),'stats original character sequence')
        require(label['font_size']>0 and label['lines']==label['visible_lines'],'stats wrapped lines')
        for c in chars:
            x,y,w,h=c['global_rect']
            require(w>=0 and h>=0 and scroll[0]-.001<=x and x+w<=right+.001,'stats character exceeds actual horizontal clip')
def extract(root,index):
    count=0
    for item in index['archives']:
        archive=HERE/item['path'];members=HERE/item['members']
        require(archive.stat().st_size==item['size']<50_000_000 and sha(archive)==item['sha256'],f'archive bytes {archive.name}')
        require(sha(members)==item['members_sha256'],f'member manifest {members.name}')
        expected={m['path']:m for m in load(members)}
        require(len(expected)==item['member_count'],f'duplicate manifest {members.name}')
        seen=set()
        with tarfile.open(archive,'r|xz') as source:
            for member in source:
                name=PurePosixPath(member.name)
                require(member.isfile() and not name.is_absolute() and '..' not in name.parts
                    and '\\' not in member.name and ':' not in member.name,f'unsafe member {member.name}')
                require(member.name in expected and member.name not in seen,f'unexpected member {member.name}')
                require(not any(p.lower() in ['profile','app_userdata','data_0','data_1'] for p in name.parts),f'profile included {member.name}')
                destination=root.joinpath(*name.parts)
                require(not destination.exists(),f'duplicate packet destination {destination}')
                destination.parent.mkdir(parents=True,exist_ok=True)
                h=hashlib.sha256();size=0
                with source.extractfile(member) as stream,destination.open('wb') as output:
                    for block in iter(lambda:stream.read(1024*1024),b''):
                        output.write(block);h.update(block);size+=len(block)
                e=expected[member.name]
                require(size==member.size==e['size'] and h.hexdigest()==e['sha256'],f'member bytes {member.name}')
                seen.add(member.name);count+=1
        require(seen==set(expected),f'missing members {archive.name}')
        print('ARCHIVE',archive.name,len(seen),'verified',flush=True)
    return count
def verify(root,index):
    spec=importlib.util.spec_from_file_location('ne228_matrix_reader',HERE/'matrix_reader.py')
    reader=importlib.util.module_from_spec(spec);spec.loader.exec_module(reader)
    native=root/'native'
    smooth=sorted(native.glob('final-*-v6'))
    require(len(smooth)==5,'five smooth configurations')
    result=[reader.read(d) for d in smooth]
    require({x[0] for x in result}==reader.CONFIGS,'smooth configuration coverage')
    sources=result[0][1]
    require(all(s==sources for _,s in result),'smooth source differs between runs')
    pixel_config,pixel_sources=reader.read(native/'supplemental-pixel-1080-v6')
    require(pixel_config==(1920,1080,1.2,False,'pixel') and pixel_sources==sources,'supplemental pixel source/config')
    frozen=index['candidate_files']
    require(load(root/'work/freeze-product-v2.json')==frozen,'frozen source manifest')
    for path,digest in frozen.items():
        require(sha(root/'work/freeze-product-v2'/path)==digest,f'frozen bytes {path}')
        if path.startswith('ui/'): require(sources[path]==digest,f'native product differs {path}')
    local=load(native/'layout-candidate-v2/receipt.json')
    require(local['exit']==0 and local['source_unchanged'] and not local['script_error'],'local UI/Collectibles receipt')
    for path,digest in frozen.items(): require(local['source_before'][path]==local['source_after'][path]==digest,f'local candidate {path}')
    text=(native/'layout-candidate-v2/console.log').read_text(encoding='utf8')
    require('checks: 825, failures: 0' in text and 'SCRIPT ERROR' not in text,'local UI/Collectibles raw summary')
    official=root/'official'
    expected_failures={'large real counter title does not overlap its tab row',
        'large real pawn detail and action stay above the inventory footer','long pawn details expose one bounded reading region'}
    preparation=load(official/'preparation.json')
    for phase in ['baseline','candidate']:
        base=official/phase;receipt=load(base/'receipt.json')
        before=load(base/'source-before.json');after=load(base/'source-after.json')
        require(receipt['base']=='6e47e2fe5e32ee3f13583bf7d59ae79953b65a85' and len(before)==receipt['source_files']==14479,'official base/source scope')
        require(before==after and receipt['source_unchanged'] and receipt['private_before']==receipt['private_after']==preparation['private_files'] and receipt['private_unchanged'],'official source/private drift')
        require(len(preparation['private_files'])==16,'original private files count')
        log=(base/'console.log').read_text(encoding='utf8')
        require(not receipt['script_error'] and 'SCRIPT ERROR' not in log,'official script error')
        for path in frozen:
            digest=sha(base/'source'/path)
            require(digest==before[path]['sha256'] and (base/'source'/path).stat().st_size==before[path]['size'],'official saved source')
            if phase=='candidate' or path.startswith('tests/'): require(digest==frozen[path],'official candidate source')
            else: require(digest==preparation['baseline_products'][path],'official original product')
        if phase=='baseline':
            require(receipt['exit_code']==1 and receipt['valid_expected_red'] and 'checks: 513, failures: 3' in log,'cold original red')
            require(set(re.findall(r'^FAIL: (.+)$',log,re.M))==expected_failures,'cold original exact failures')
        else:
            require(receipt['exit_code']==0 and 'checks: 6527, new failures: 0, known failures (tests/known_failures.txt): 0' in log,'original affected runner summary')
            require('Running 12 groups in 2 processes' in log,'original affected selection')
            for shard in (base/'shards').glob('shard_*.log'):
                require('SCRIPT ERROR' not in shard.read_text(encoding='utf8'),'official shard SCRIPT ERROR')
    for directory in sorted(native.glob('flow-*-v1')):
        receipt=load(directory/'exit.json');before=load(directory/'source-before.json')
        require(receipt['exit']==0 and receipt['checks']==38 and receipt['failures']==0 and not receipt['diagnostics']
            and receipt['sources_unchanged'] and before==receipt['source_after'],'original CLI flow receipt')
        for path,digest in before.items(): require(sha(directory/'source'/path)==digest,'original CLI saved source')
        for path,digest in frozen.items():
            if path.startswith('ui/'): require(before[path]==digest,'CLI product version')
        log=(directory/'run.log').read_text(encoding='utf8')
        require('NE229_SYNTHETIC_FLOW checks=38 failures=0' in log and 'SCRIPT ERROR' not in log,'original CLI raw output')
        images=list(directory.glob('*.png'));require(len(images)==14,'original CLI full PNG count')
        expected=(1280,720) if directory.name=='flow-720-v1' else (1920,1080)
        for image in images:
            data=image.read_bytes();require(data[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',data[16:24])==expected,'original CLI raw image dimensions')
    negatives=[]
    def rejects(name,call):
        try: call()
        except (ValueError,KeyError): negatives.append(name)
        else: raise ValueError('negative control accepted: '+name)
    def row(directory,page): return next(r for r in load(native/directory/'matrix.json')['records'] if r['page']==page)
    for tag in ['all-720-normal-v1','all-720-normal-v2']:
        r=row(tag,'world/bubble')
        rejects(tag+' actual missing/wrong spoken body',lambda r=r:reader.validate_bubble(r,tag,r['geometry']['viewport']))
    for tag in ['all-720-normal-v3','final-720-normal-v5']:
        r=row(tag,'quest/region');rejects(tag+' actual unloaded map',lambda r=r:reader.validate_navigation(r,tag))
    original=load(native/'layout-original-1080-v4/matrix.json')
    recomputed=[r['page']+': '+error for r in original['records'] if r.get('inventory_layout') for error in reader.inventory_errors(r['inventory_layout'])]
    require(recomputed==original['failures'] and len(recomputed)==8,'original native eight geometric failures')
    invalid=(native/'layout-static-original-v2/console.log').read_text(encoding='utf8')
    require('SCRIPT ERROR' in invalid and 'checks: 0, failures: 0' in invalid,'invalid runtime reload must remain invalid')
    original_exit=(native/'layout-static-original-v2/exit.txt').read_text(encoding='utf8').strip()
    require(original_exit=='0','invalid reload engine exit retention')
    base=row('final-1080-large-v6','world/bubble')
    for key,value in [('alpha',0),('text',''),('rect',[0,0,0,0]),('font_size',0),('draw_frame',-1),('scene_id','wrong')]:
        mutated=copy.deepcopy(base)
        for body in mutated['map_bubbles']: body[key]=value
        rejects('synthetic body '+key,lambda r=mutated:reader.validate_bubble(r,'negative',r['geometry']['viewport']))
    for key,value in [('current_path',''),('explored_cells',0),('player_markers',[]),('texture_present',False)]:
        mutated=copy.deepcopy(row('final-1080-large-v6','quest/region'));mutated['navigation_state'][key]=value
        rejects('synthetic navigation '+key,lambda r=mutated:reader.validate_navigation(r,'negative'))
    layout=copy.deepcopy(row('final-1080-large-v6','shop/pawn')['inventory_layout'])
    layout['errors']=[];layout['title_rect']=layout['tabs_rect'][:]
    require('screen title overlaps tab row' in reader.inventory_errors(layout),'independent title negative')
    negatives.append('synthetic title overlap despite empty producer errors')
    layout=copy.deepcopy(row('final-1080-large-v6','shop/pawn')['inventory_layout'])
    layout['errors']=[];layout['action_rect']=layout['footer_rect'][:]
    require('detail action overlaps footer or exceeds page content' in reader.inventory_errors(layout),'independent action negative')
    negatives.append('synthetic action/footer overlap despite empty producer errors')
    omissions=load(HERE/index['omitted_historical_png_inventory'])
    require(sha(HERE/index['omitted_historical_png_inventory'])==index['omitted_inventory_sha256'],'omitted PNG manifest')
    require(all(not o['shipped'] and not (root/o['relative']).exists() for o in omissions),'unshipped historical PNG classification')
    stats_rows=0
    for style in ['smooth','pixel']:
        directory=native/('stats-original-'+style+'-v8')
        receipt=load(directory/'exit.json');before=load(directory/'source-before.json')
        require(receipt['exit']==0 and receipt['strict_clean'] and not receipt['diagnostics'] and before==receipt['source_after'],'valid stats native receipt')
        for path,digest in before.items(): require(sha(directory/'source'/path)==digest,'stats actual saved source '+path)
        for path,digest in frozen.items():
            if path.startswith('ui/'):require(before[path]==digest,'stats unchanged product')
        matrix=load(directory/'matrix.json')
        require(len(matrix['records'])==28 and not matrix['failures'],'stats partial scope is exactly28, not full42')
        for page in ['shop/pawn','shop/redeem']:
            row=next(r for r in matrix['records'] if r['page']==page)
            require(sha(directory/row['file'])==row['png_sha256'],'stats original PNG')
            observation=row['inventory_layout']['stats_observation']
            require(len(observation['stats'])==3,'stats original three values')
            validate_stats(observation);stats_rows+=1
        invalid=load(native/('stats-original-'+style+'-v7')/'exit.json')
        require(not invalid['strict_clean'] and any('Index' in d for d in invalid['diagnostics']),'invalid observer remains rejected')
    mutated=copy.deepcopy(observation)
    mutated['stats'][0]['characters'][0]['global_rect'][0]=mutated['bar_rect'][0]+1
    rejects('synthetic stats character beyond scrollbar',lambda:validate_stats(mutated))
    return {'accepted_matrix_states':252,'smooth_states':210,'supplemental_pixel_states':42,'reading_end_originals':6,
        'stats_supplemental_cases':stats_rows,'stats_product_change':False,
        'original_CLI_checks':76,'original_CLI_png':28,'official_checks':6527,'official_groups':12,'official_new_failures':0,
        'cold_original_checks':513,'cold_original_failures':3,'original_native_geometric_failures':recomputed,
        'negative_controls_rejected':negatives,'invalid_runtime_reload':'retained SCRIPT ERROR / engine0 / checks0; not valid red',
        'omitted_historical_pngs':len(omissions),'physical_controller_verified':False,'human_gameplay_verified':False}
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--receipt',type=Path);args=parser.parse_args()
    index=load(HERE/'index.json')
    with tempfile.TemporaryDirectory(prefix='ne228-offline-') as temp:
        root=Path(temp);count=extract(root,index);result=verify(root,index)
        result['verified_archive_members']=count
    if args.receipt: args.receipt.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps(result,ensure_ascii=False),flush=True)
if __name__=='__main__': main()
