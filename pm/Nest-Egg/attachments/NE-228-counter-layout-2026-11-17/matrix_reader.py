"""Independent ticket reader: actual PNG bytes, 42-state scope and five configs.

This validates layout observations and provenance, not human/hardware gameplay.
Source producer/geometry implementation is not imported or executed here.
"""
from pathlib import Path
import argparse,hashlib,json,struct,zipfile

PAGES = set('''main/main main/difficulty main/overwrite-confirm
settings/audio settings/bindings settings/display settings/controller
codex/defeat codex/replay-list codex/replay-empty pause/main pause/skip-confirm
inventory/weapons inventory/upgrades inventory/consumables inventory/cyber
inventory/story-items inventory/status inventory/full-document
shop/stock shop/pawn shop/redeem shop/workbench
quest/active quest/completed quest/main quest/side quest/region quest/world
world/hud world/pickup-feed world/context-prompt world/bubble world/npc-dialogue
world/radio world/choice world/object-reading flow/death flow/victory
recovery/radio-save recovery/destination-save recovery/controller-recovery'''.split())
CONFIGS = {(1280,720,1.0,False,'smooth'),(1280,720,1.2,True,'smooth'),
           (1920,1080,1.0,False,'smooth'),(1920,1080,1.2,False,'smooth'),(2560,1080,1.2,True,'smooth')}

def require(ok,message):
    if not ok: raise ValueError(message)

def intersects(a,b):
    return a[0]<b[0]+b[2] and b[0]<a[0]+a[2] and a[1]<b[1]+b[3] and b[1]<a[1]+a[3]

def encloses(a,b,inset=0):
    return a[0]<=b[0]+inset and a[1]<=b[1]+inset and b[0]+b[2]-inset<=a[0]+a[2] and b[1]+b[3]-inset<=a[1]+a[3]

def validate_bubble(row,directory,viewport):
    body=[b for b in row.get('map_bubbles',[]) if b['host_visible'] and b['scene_id']=='ch1_b_street_in'
          and b['text'].strip() and b['alpha']>=.999 and b['rect'][2]>0 and b['rect'][3]>0
          and b['lines']>0 and b['font_size']==int(9*row['text_scale']+.5)]
    require(body,f'{directory}: spoken bubble body absent; unread ellipsis is insufficient')
    require(row['content'].get('play_returned') and row['content'].get('scene_id')=='ch1_b_street_in',
            f'{directory}: no real authored bubble request')
    original={line['text'] for line in row['content']['authored_lines']}
    for b in body:
        require(b['text'] in original,f'{directory}: bubble differs from authored text')
        require(b['draw_frame']==b['post_draw_frame'],f'{directory}: bubble body was not observed in captured draw frame')
        x,y,w,h=b['rect']
        require(0<=x<=x+w<=viewport[2] and 0<=y<=y+h<=viewport[3],f'{directory}: spoken bubble outside active viewport')

def validate_navigation(row,directory):
    nav=row.get('navigation_state',{})
    level='res://data/levels/ch1_pawnshop.tres'
    require(nav and nav['data_path']==nav['current_path']==nav['player_path']==level,
            f'{directory}: formal current map identity missing')
    require(nav['registered_area'] and nav['explored_cells']>0,f'{directory}: actual exploration missing')
    if row['page'] in ['quest/region','quest/world']:
        require(nav['canvas_present'] and nav['canvas_path']==level and nav['player_markers'],f'{directory}: actual current-player map canvas missing')
        require(all(m['text'].startswith('▲') and m['rect'][2]>0 and m['rect'][3]>0 for m in nav['player_markers']),
                f'{directory}: actual visible player marker absent')
    if row['page']=='quest/region':
        require(nav['texture_present'],f'{directory}: actual region terrain missing')
    require(not any(l['text']=='尚未載入區域' for l in row['geometry']['labels']),f'{directory}: unloaded map cannot pass as formal content')

def inventory_errors(layout):
    errors=[]
    if layout['tabs_visible'] and intersects(layout['title_rect'],layout['tabs_rect']):
        errors.append('screen title overlaps tab row')
    if 'detail_rect' in layout and not encloses(layout['page_host_rect'],layout['detail_rect'],.5):
        errors.append('detail panel exceeds bounded page content')
    if 'action_rect' in layout and (not encloses(layout['page_host_rect'],layout['action_rect'],.5) or intersects(layout['action_rect'],layout['footer_rect'])):
        errors.append('detail action overlaps footer or exceeds page content')
    return errors

def read(directory):
    archive=zipfile.ZipFile(directory) if directory.is_file() else None
    raw=lambda path: archive.read(path) if archive else (directory/path).read_bytes()
    report=json.loads(raw('matrix.json'))
    receipt=json.loads(raw('exit.json'))
    before=json.loads(raw('source-before.json'))
    require(receipt['exit']==0 and receipt['sources_unchanged'] and receipt['strict_clean'],f'{directory}: invalid engine receipt')
    require(before==receipt['source_after'],f'{directory}: source changed')
    for path,sha in before.items():
        require(hashlib.sha256(raw('source/'+path)).hexdigest()==sha,f'{directory}: source bytes {path}')
    require(report['renderer']=='forward_plus' and '9070 XT' in report['adapter'] and report['hdr'],f'{directory}: wrong rendering mode')
    require(report['font_style']==report['settings_font'] and report['font_style'] in ['smooth','pixel'],f'{directory}: actual font style differs from settings')
    expected_font='res://art/fonts/'+('Cubic_11.ttf' if report['font_style']=='pixel' else 'NotoSansTC-Regular-subset.ttf')
    require(report['font_base_resource']==expected_font,f'{directory}: actual renderer font resource differs')
    require(not report['physical_controller_verified'] and not report['human_gameplay_verified'],f'{directory}: unsupported hardware/human claim')
    require(not report['failures'],f'{directory}: producer failures')
    require(report['page_state_scope_complete'] and report['full_matrix_accepted'] is False,
            f'{directory}: single-config/full-matrix scope not distinguished')
    rows=report['records']
    require(len(rows)==42 and {r['page'] for r in rows}==PAGES,f'{directory}: missing or duplicate state')
    config=None
    for row in rows:
        data=raw(row['file'])
        require(data[:8]==b'\x89PNG\r\n\x1a\n' and data[12:16]==b'IHDR',f'{directory}: invalid PNG')
        width,height=struct.unpack('>II',data[16:24])
        require(hashlib.sha256(data).hexdigest()==row['png_sha256'],f'{directory}: PNG hash {row["page"]}')
        require((width,height)==(row['png_width'],row['png_height']),f'{directory}: actual PNG size')
        window=row['window_size']
        require(row['native_window_size']==window,f'{directory}: native window disagrees with requested size')
        viewport=row['geometry']['viewport']
        a,b,c,d,tx,ty=row['geometry']['final_transform']
        corners=[(a*x+c*y+tx,b*x+d*y+ty)
                 for x in (viewport[0],viewport[0]+viewport[2])
                 for y in (viewport[1],viewport[1]+viewport[3])]
        left=min(p[0] for p in corners);top=min(p[1] for p in corners)
        right=max(p[0] for p in corners);bottom=max(p[1] for p in corners)
        require((width,height)==(round(right-left),round(bottom-top)),f'{directory}: active texture transform mismatch')
        require(0<=left<=right<=window[0] and 0<=top<=bottom<=window[1],f'{directory}: drawable outside native window')
        require(row['active_drawable_window_rect']==[left,top,right-left,bottom-top],f'{directory}: drawable metadata mismatch')
        actual=(*window,row['text_scale'],row['reduce_motion'],row['font_style'])
        require(row['font_style']==report['font_style'],f'{directory}: font style changed within configuration')
        require(row.get('requested_text_scale',row['text_scale'])==row['text_scale'],f'{directory}: effective text scale differs from requested')
        config=actual if config is None else config
        require(actual==config,f'{directory}: configuration changed')
        require(not row['geometry']['errors'],f'{directory}: layout errors')
        if row['page'].startswith(('inventory/','shop/')):
            layout=row.get('inventory_layout',{})
            require(layout and not layout['errors'],f'{directory}: inventory header/action layout gate missing or failed')
            require(not inventory_errors(layout),f'{directory}: independently recomputed inventory overlap')
            if layout['tabs_visible']:
                require(not intersects(layout['title_rect'],layout['tabs_rect']),f'{directory}: title overlaps tabs')
            if 'detail_rect' in layout:
                require(encloses(layout['page_host_rect'],layout['detail_rect'],.5),f'{directory}: detail outside page host')
            if 'action_rect' in layout:
                require(encloses(layout['page_host_rect'],layout['action_rect'],.5),f'{directory}: action outside page host')
                require(not intersects(layout['action_rect'],layout['footer_rect']),f'{directory}: action overlaps footer')
            if row['page']=='shop/pawn':
                proof=row.get('detail_reading',{})
                require(proof and proof['before']==proof['after'] and proof['after']['paused'],f'{directory}: public reading changed gameplay')
                require(proof['input']=='public PageDown press/release' and abs(proof['scroll']-proof['limit'])<=1,
                        f'{directory}: detail reading did not reach the end')
                require(proof['body_text']==layout['body_text'] and encloses(proof['scroll_rect'],proof['body_rect'],.5),
                        f'{directory}: original complete body is not visible at reading end')
                require(proof['action_text']==layout['action_text'] and encloses(layout['page_host_rect'],proof['action_rect'],.5)
                        and not intersects(proof['action_rect'],layout['footer_rect']),f'{directory}: reading displaced the action')
                require(proof['restored_scroll']==0,f'{directory}: PageUp did not restore reading start')
                data=raw(proof['file'])
                require(hashlib.sha256(data).hexdigest()==proof['png_sha256'],f'{directory}: reading-end PNG hash')
                require(struct.unpack('>II',data[16:24])==tuple(proof['png_size'])==(width,height),f'{directory}: reading-end PNG dimensions')
        require(row['content'].get('basis'),f'{directory}: missing content provenance')
        if row['page'].startswith('quest/'):
            validate_navigation(row,directory)
        require(row['presentation_settle_trace'] and row['presentation_settle_trace'][-1]['ready'],
                f'{directory}: required presentation absent or unfinished')
        if row['page']=='pause/main':
            require(any(label['text']=='目前進度' for label in row['geometry']['labels']),f'{directory}: pause info absent')
            require(row['pause_settle_trace'] and row['pause_settle_trace'][-1]['info_visible']
                    and row['pause_settle_trace'][-1]['info_alpha']>=0.999,f'{directory}: pause did not finish opening')
        if row['complete_window'].get('file'):
            whole=row['complete_window'];pixels=raw(whole['file'])
            require(hashlib.sha256(pixels).hexdigest()==whole['sha256'],f'{directory}: complete window hash')
            require(struct.unpack('>II',pixels[16:24])==tuple(window),f'{directory}: complete native window size')
        if window[0]==2560 and row['page']=='main/main':
            require(row['complete_window']['accepted_as_unobstructed_window'] is False,
                    f'{directory}: external desktop overlay passed without review')
        if row['paused_world_before']:
            world=row['paused_world_after']
            require(world==row['paused_world_before'],f'{directory}: paused state moved')
            require(not any(world[k] for k in ('level_can_process','player_can_process','camera_can_process')),f'{directory}: paused owner active')
        state=row['reading_state']
        if row['page']=='world/bubble':
            validate_bubble(row,directory,viewport)
        if row['page']=='world/npc-dialogue':
            require(state['cinematic'] and state['dialogue_kind']=='dialogue' and state['dialogue_name'] and state['dialogue_body'],f'{directory}: wrong/empty person reading')
        if row['page']=='world/object-reading':
            require(state['cinematic'] and state['dialogue_kind']=='object' and state['reading_title'] and state['dialogue_body'],f'{directory}: wrong/empty object reading')
        if row['page']=='world/radio':
            require(state['radio_visible'] and state['radio_name'] and state['radio_text'],f'{directory}: absent radio')
            require(row['content']['scene_id']=='ch1_g06_lamp' and row['content']['authored_freeze'] is True,
                    f'{directory}: not the stated current-campaign radio definition')
    if archive: archive.close()
    return config,before

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('runs',nargs='*',type=Path)
    parser.add_argument('--index',type=Path)
    parser.add_argument('--raw-root',type=Path)
    args=parser.parse_args()
    runs=args.runs
    if args.index:
        require(not runs,'choose explicit paths or index')
        root=args.raw_root or args.index.parent
        index=json.loads(args.index.read_bytes())
        runs=[]
        for entry in index['archives']:
            if entry['role']!='matrix-final': continue
            path=root/entry['path']
            require(hashlib.sha256(path.read_bytes()).hexdigest()==entry['sha256'],f'{path}: archive hash mismatch')
            require(path.stat().st_size==entry['bytes'],f'{path}: archive length mismatch')
            runs.append(path)
    require(len(runs)==5,'exactly five configuration directories or archives required')
    results=[read(p) for p in runs]
    require({x[0] for x in results}==CONFIGS,'five required configurations not covered')
    baseline=results[0][1]
    for _,source in results[1:]: require(source==baseline,'final matrix source bytes differ between runs')
    if args.index:
        for entry in index['candidate_files']:
            require(baseline[entry['path']]==entry['candidate_sha256'],f'candidate source mismatch: {entry["path"]}')
    print('NE228_MATRIX_READER: 210/210 PNG/state observations verified; five configurations; exact frozen source bytes; hardware/human acceptance excluded')

if __name__=='__main__': main()
