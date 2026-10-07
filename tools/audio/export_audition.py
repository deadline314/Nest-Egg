"""Build a local playable review from shipped outputs and Godot mixer captures.

python tools/audio/export_audition.py --out pm/Nest-Egg/attachments/NE-196 \
    --capture /tmp/lab /tmp/game --base 6f4805be
Does not build audio, download raw packs, change placements, or imply listening.
"""
import argparse
import hashlib
import html
import json
import os
import subprocess
from pathlib import Path

import numpy as np
import audio_lib as lib

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def metrics(path):
    x = lib.decode(path, mono=False)
    env = lib.envelope(x)
    active = np.flatnonzero(env > lib.from_db(-45))
    return {'seconds': round(len(x) / lib.SR, 4), 'peak_dbfs': round(lib.db(np.abs(x).max()), 2),
            'head_1s_rms_dbfs': round(lib.db(np.sqrt(np.mean(x[:lib.SR] ** 2))), 2),
            'tail_100ms_rms_dbfs': round(lib.db(np.sqrt(np.mean(x[-4410:] ** 2))), 2),
            'first_above_minus45_ms': int(active[0] * 4) if len(active) else None,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--capture', nargs='*', type=Path, default=[])
    parser.add_argument('--base', required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    (out / '.gdignore').touch()
    bank = read('data/audio/sound_bank.json')['sounds']
    music = read('data/audio/music.json')
    slots = read('data/audio/slots.json')['slots']
    licenses = read('assets_src/audio/LICENSES.json')
    pipeline = read('assets_src/audio/pipeline.json')
    before_music = json.loads(subprocess.check_output(['git', 'show', args.base + ':data/audio/music.json'], cwd=ROOT))
    unchanged = subprocess.check_output(['git', 'diff', '--name-only', args.base, '--', 'audio',
                                        'assets_src/audio/build_cache.json', 'assets_src/audio/pipeline.json',
                                        'data/audio/sound_bank.json', 'design/16-audio/PLACEMENTS.md'], cwd=ROOT).decode().splitlines()
    report = {'base': args.base, 'subjective_listening': False, 'full_playthrough': False,
              'selected_audio_or_placements_changes': unchanged, 'files': {}, 'slots': slots,
              'music_provenance_before': before_music['tracks'], 'music_provenance_after': music['tracks'],
              'captures': [], 'errors': [], 'incomplete_captures': []}
    referenced = set()
    for entry in bank.values():
        referenced.update(entry.get('files', []))
        for files in entry.get('speed_files', {}).values():
            referenced.update(files)
    referenced.update(t['file'] for t in music['tracks'].values())
    for file in sorted(referenced):
        path = ROOT / file.removeprefix('res://')
        if not path.is_file():
            report['errors'].append('Missing shipped file: ' + file)
            continue
        try:
            report['files'][file] = metrics(path)
        except (OSError, subprocess.CalledProcessError) as error:
            report['errors'].append(str(error))
    for track_id, entry in music['tracks'].items():
        registered = licenses.get(entry['pack'], {})
        source = pipeline['music'][track_id]
        if (entry['pack'] != source['pack'] or entry['file'] not in registered.get('outputs', [])
                or source['file'] not in registered.get('files_used', [])
                or not registered.get('license', '').startswith('CC0')):
            report['errors'].append('Wrong music provenance: ' + track_id)
    for capture in args.capture:
        data = json.loads((capture / 'capture.json').read_text())
        for rec in data['records']:
            source = capture / (rec['name'] + '.wav')
            dest = out / 'media' / (capture.name + '_' + rec['name'] + '.ogg')
            dest.parent.mkdir(exist_ok=True)
            subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(source), '-c:a', 'libvorbis',
                            '-q:a', '5', '-map_metadata', '-1', str(dest)], check=True)
            rec['audio'] = dest.relative_to(out).as_posix()
            rec['metrics'] = metrics(source)
            if rec['context'].get('activated') is False:
                rec['verified'] = False
                report['incomplete_captures'].append(data['mode'] + '/' + rec['name'] + ': phone interaction did not activate')
            elif rec['save_error'] or rec['metrics']['peak_dbfs'] < -90.0:
                report['errors'].append('Empty or failed runtime capture: ' + data['mode'] + '/' + rec['name'])
            else:
                rec['verified'] = True
                rec['quiet_window'] = rec['metrics']['first_above_minus45_ms'] is None
        report['captures'].append(data)
    (out / 'technical.json').write_text(json.dumps(report, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    esc = html.escape

    def player(path):
        return '<audio controls preload="none" src="' + esc(path, quote=True) + '"></audio>'

    def official(file):
        path = ROOT / file.removeprefix('res://')
        rel = os.path.relpath(path, out).replace(os.sep, '/')
        return '<div>' + esc(path.name) + player(rel) + '</div>'

    content = ['<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><title>NE-196 音訊審查</title>',
               '<style>body{font:16px system-ui;max-width:1200px;margin:32px auto;background:#121821;color:#eef3fa}'
               'a{color:#9ccfff}audio{display:block;max-width:100%;height:34px;margin:6px 0}section{border-top:1px solid #596879;padding:16px 0}'
               'summary{cursor:pointer;padding:12px;background:#253142}td,th{padding:10px;text-align:left;vertical-align:top}table{width:100%}'
               'pre{white-space:pre-wrap}input{font:inherit;padding:8px;width:80%}</style>',
               '<h1>NE-196 正式音訊與真實場景對照</h1>',
               '<p>基準 ' + esc(args.base) + '。沒有實際聽音；以下是混音器錄音與訊號檢查，聲音喜好及完整試玩由使用者審查。</p>',
               '<p>本次只修正曲名／授權包。既有選音、片段、音量、速度變體與增量快取保持原樣；修前與修後音訊位元組一致。'
               '因此保留同一段可播放音訊作前後對照，不宣稱有音質改善。素材播放器是原成品；場景播放器包含遊戲內增益、音高、淡化與混音。</p>',
               '<p>Godot 捕捉皆使用 0 dB 匯流排，隔離存檔；場景是腳本輸入抽查，過場自動跳過、血量提高，非完整通關。'
               '2x 射速透過本次執行中的超頻倍率注入，未修改能力資料。</p>',
               '<input id="filter" placeholder="搜尋位置、音效、關卡、素材編號" aria-label="搜尋">',
               '<p><a href="technical.json">完整技術數據、來源前後、事件時間與播放路徑</a></p>']
    for capture in report['captures']:
        content.append('<h2>' + ('實驗室：遊戲內實際聲音' if capture['mode'] == 'lab' else '真實關卡輸入抽查') + '</h2>')
        for rec in capture['records']:
            ctx = rec['context']
            name = rec['name'] + ' ' + ctx.get('slot', {}).get('name', '')
            if not rec.get('verified', False):
                name += ' — 未通過（按鍵嘗試未啟動通話）'
            content.append('<section class="entry"><b>' + esc(name) + '</b>' + player(rec['audio'])
                           + '<details><summary>操作與實际事件</summary><pre>'
                           + esc(json.dumps({'context': ctx, 'events': rec['events'], 'metrics': rec['metrics']}, ensure_ascii=False, indent=1))
                           + '</pre></details></section>')
    for domain in dict.fromkeys(s['domain'] for s in slots):
        content.append('<h2>' + esc(domain) + ' 正式素材變體（前後相同）</h2>')
        for slot in [s for s in slots if s['domain'] == domain]:
            target = slot['target']
            entry = music['tracks'][target] if slot['kind'] == 'music' else bank.get(target, {})
            files = [entry['file']] if slot['kind'] == 'music' else entry.get('files', [])
            content.append('<details class="entry"><summary>' + esc(slot['id'] + ' ' + slot['name'] + ' ' + target)
                           + '</summary><p>' + esc(', '.join(slot['current'])) + '</p>')
            for file in files:
                content.append(official(file))
                content.append('<pre>' + esc(json.dumps(report['files'].get(file, {}), ensure_ascii=False)) + '</pre>')
            for rate, speed_files in entry.get('speed_files', {}).items():
                content.append('<p>速度 ' + esc(rate) + '×（離線保持音高；音高微調複本是另一個變體）</p>')
                content.extend(official(file) for file in speed_files)
            packs = entry.get('pack', [])
            for pack in ([packs] if isinstance(packs, str) else packs):
                record = licenses.get(pack, {})
                page = record.get('page', '')
                if page and not page.startswith(('https://', 'http://')):
                    page = os.path.relpath(ROOT / page, out).replace(os.sep, '/')
                content.append('<p>' + esc(pack + ' · ' + record.get('license', '未登記') + ' · ' + record.get('author', ''))
                               + ' <a href="' + esc(page, quote=True) + '">來源登記</a></p>')
            content.append('</details>')
    content.append('<script>document.querySelector("#filter").oninput=e=>{const q=e.target.value.toLowerCase();'
                   'document.querySelectorAll(".entry").forEach(x=>x.hidden=!x.textContent.toLowerCase().includes(q));};'
                   'document.addEventListener("play",e=>{if(e.target.tagName==="AUDIO")document.querySelectorAll("audio").forEach(a=>{if(a!==e.target)a.pause();});},true);'
                   '</script></html>')
    (out / 'index.html').write_text('\n'.join(content), encoding='utf-8')
    print(json.dumps({'files': len(referenced), 'slots': len(slots), 'runtime_captures': sum(len(c['records']) for c in report['captures']),
                      'errors': report['errors'], 'selected_audio_or_placements_changes': unchanged}, ensure_ascii=False))
    return bool(report['errors'])


if __name__ == '__main__':
    raise SystemExit(main())
