"""Independently read original BG40 float pixels and prop-only A/A/B/A/B."""
from pathlib import Path
import argparse, hashlib, json, sys
import numpy as np
from verify_bg49_held import contrast, load_pixels, raster, section, verify_owners


def verify(folder, partial=False):
    receipt = json.loads((folder/'exit.json').read_bytes())
    assert receipt['strict_clean'] and receipt['exit']==0 and receipt['sources_unchanged']
    before=json.loads((folder/'source-before.json').read_bytes())
    assert before==receipt['source_after']
    for path,sha in before.items(): assert hashlib.sha256((folder/'source'/path).read_bytes()).hexdigest()==sha
    observations=[]
    for index in sorted(folder.glob('*/*-index.json')):
        data=json.loads(index.read_bytes())
        expected={'ch2_pawnshop':(6,3), 'ch2_lounge_front':(3,3), 'ch3_office_hall':(4,3)}[data['level']]
        assert (data['columns'],data['rows'])==expected
        if not partial:
            assert len(data['shots'])==expected[0]*expected[1]
            assert {(s['column'],s['row']) for s in data['shots']}=={(x,y) for x in range(expected[0]) for y in range(expected[1])}
        for shot in data['shots']:
            group=shot['bg40'];assert group['controls_valid']
            records=group['records'];assert [r['label'] for r in records]==['A0','A1','product','restore-product','authored-final']
            assert records[0]['raw_sha256']==records[1]['raw_sha256']==records[3]['raw_sha256']
            assert records[2]['raw_sha256']==records[4]['raw_sha256']
            original=records[0];cache={}
            for r in records:
                assert r['world_environment']['active'] and r['world_environment']['glow_enabled']
                verify_owners(r['held']['lighting_owners'],r['canvas_transform_values'])
                assert r['weapon_light']['origin_error']<=.00001 and r['weapon_light']['fade_level']>=.999
                for key in ['actors','rain','fog_time','shader_time_scale','camera','player','aim','player_support']:
                    assert r['held'][key]==original['held'][key],key
                assert not r['enemy_inventory'] and not r['enemies'], 'unexpected enemies need actual coverage/exposure checks'
                assert r['prop_reference']==(r['label'] in ['A0','A1','restore-product'])
                for entry in group['prop_delta']['added']:
                    nodes=[p for p in r['props'] if p['id']==entry['id']]
                    assert len(nodes)==1 and nodes[0]['visible']!=r['prop_reference']
                for entry in group['prop_delta']['removed']:
                    nodes=[p for p in r['props'] if p['id']==entry['id']]
                    assert len(nodes)==1 and nodes[0]['visible']==r['prop_reference']
                selected={p['id'] for p in group['prop_delta']['added']+group['prop_delta']['removed']}
                assert [p for p in r['props'] if p['id'] not in selected]==[p for p in original['props'] if p['id'] not in selected]
                key=r['raw_sha256']
                if key not in cache: cache[key]=load_pixels(index.parent,r)
                rgb=cache[key]
                if not r['player_visible']:
                    assert 'player' not in r
                    continue
                assert r['held']['player_support']['valid'] and r['held']['player_support']['solver_contact']
                support=r['held']['player_support']
                assert support['found'] and abs(support['gap'])<=support['safe_margin']+.001
                p=r['player'];fx,fy=p['feet']
                body=raster([fx-9,fy-58,18,54],r)
                outer=raster([fx-29,fy-78,58,94],r)
                assert body==p['screen_rect'] and outer==p['outer_screen_rect']
                values=contrast(rgb,body,outer)
                assert all(abs(values[k]-p['parts'][k])<.000002 for k in values)
                assert abs(max(values['bright'],values['dark'])-p['contrast'])<.000002
                edge=raster([fx-24,fy,48,3],r);below=raster([fx-24,fy+8,48,6],r)
                assert edge==p['edge_screen_rect'] and below==p['below_screen_rect']
                luma=rgb@[.2126,.7152,.0722]
                value=(section(luma,edge).mean()-section(luma,below).mean())/(section(luma,below).mean()+.02)
                assert abs(value-p['edge_contrast'])<.000002
            final=records[-1]
            item=dict(level=data['level'],column=shot['column'],row=shot['row'],player_visible=final['player_visible'],enemy_count=0,controls_valid=True)
            if final['player_visible']:
                a,b=original['player'],final['player']
                item.update(player=b['contrast'],edge=b['edge_contrast'],original_player=a['contrast'],original_edge=a['edge_contrast'],player_delta=b['contrast']-a['contrast'],edge_delta=b['edge_contrast']-a['edge_contrast'],feet=b['feet'],support=final['held']['player_support'],thresholds_passed=b['contrast']>=.6 and b['edge_contrast']>=1)
            observations.append(item)
    assert observations
    groups={}
    for level in sorted({o['level'] for o in observations}):
        rows=[o for o in observations if o['level']==level];standing=[o for o in rows if o['player_visible']]
        groups[level]=dict(cells=len(rows),standable=len(standing),minimum_player=min(o['player'] for o in standing),minimum_edge=min(o['edge'] for o in standing),all_thresholds_passed=all(o['thresholds_passed'] for o in standing),player_decrease_cells=[dict(column=o['column'],row=o['row'],delta=o['player_delta']) for o in standing if o['player_delta']<0],edge_decrease_cells=[dict(column=o['column'],row=o['row'],delta=o['edge_delta']) for o in standing if o['edge_delta']<0])
    return dict(controls_valid=True,levels=groups,observations=observations,all_thresholds_passed=all(v['all_thresholds_passed'] for v in groups.values()),scope='same present geometry; only original BG40 prop delta; decreases retained explicitly; no enemies/exposure sample is fabricated',verifier_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('folder',type=Path);p.add_argument('--partial',action='store_true');p.add_argument('--out',type=Path,required=True)
    a=p.parse_args();result=verify(a.folder,a.partial);a.out.write_bytes((json.dumps(result,indent=2)+'\n').encode())
    print(json.dumps({k:v for k,v in result.items() if k!='observations'}));sys.exit(0 if result['all_thresholds_passed'] else 1)
