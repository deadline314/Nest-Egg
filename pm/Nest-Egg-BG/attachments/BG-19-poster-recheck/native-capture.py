from pathlib import Path
import hashlib
import json
import os
import subprocess

root = Path('C:/tmp/Nest-Egg-poster-support')
out = Path('C:/tmp/poster-support-native')
map_path = root/'data/levels/ch1_booth_alley_map.json'
original = map_path.read_bytes()
capture_path = root/'tools/scenery_capture.gd'
capture_original = capture_path.read_bytes()
probe = capture_original.decode('utf-8').replace('["ch1_booth_alley", 28]', '["ch1_booth_alley", 24]')
probe = probe.replace('\t\tlevel.player.velocity = Vector2.ZERO', '\t\tlevel.player.velocity = Vector2.ZERO\n\t\tlevel.player.facing = 1\n\t\tlevel.player.aim_dir = Vector2.RIGHT')
probe = probe.replace('\t\t\t(camera as LevelCamera).snap_to_target()', '\t\t\t(camera as LevelCamera)._aim_look = Vector2.ZERO\n\t\t\t(camera as LevelCamera).snap_to_target()\n\t\t\tprint("[poster_camera] ", camera.global_position, " zoom=", camera.zoom)')
(out/'fixed-camera-probe.gd').write_text(probe, encoding='utf-8')
records = []
try:
    capture_path.write_text(probe, encoding='utf-8')
    for phase in ['before', 'after']:
        if phase == 'before':
            content = json.loads(original)
            next(p for p in content['props'] if p['id'] == 'anchor_phone_booth__poster_wall')['y'] = 14
            map_path.write_text(json.dumps(content, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
        else:
            map_path.write_bytes(original)
        profile = out/'profiles'/phase
        profile.mkdir(parents=True, exist_ok=True)
        folder = out/('fixed-'+phase)
        folder.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, APPDATA=str(profile), LOCALAPPDATA=str(profile))
        log = out/('fixed-'+phase+'.log')
        with log.open('wb') as stream:
            result = subprocess.run(['C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe', '--path', str(root),
                'res://tools/scenery_capture.tscn', '--', '--out='+str(folder),
                '--only=ch1_booth_alley:24'], cwd=root,
                env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=120)
        text = log.read_text(encoding='utf-8-sig')
        assert result.returncode == 0, str(log)
        assert 'Forward+' in text and 'Arc(TM) B580' in text, str(log)
        assert not any(s in text for s in ['SCRIPT ERROR', 'Parse Error', 'Compile Error', 'ERROR:']), str(log)
        image = folder/'BG-19-ch1_booth_alley-24.png'
        assert image.is_file()
        records.append({'phase': phase, 'exit': result.returncode,
            'map_sha256': hashlib.sha256(map_path.read_bytes()).hexdigest(),
            'camera': next(line for line in text.splitlines() if '[poster_camera]' in line),
            'image_sha256': hashlib.sha256(image.read_bytes()).hexdigest(), 'image': str(image),
            'scope': 'actual Level at identical column 24; before changes only reported historical poster y14; after uses unchanged latest formal y19'})
finally:
    map_path.write_bytes(original)
    capture_path.write_bytes(capture_original)
assert map_path.read_bytes() == original
assert capture_path.read_bytes() == capture_original
assert records[0]['camera'] == records[1]['camera'], 'comparison camera differs'
(out/'native-manifest.json').write_text(json.dumps(records, indent=2)+'\n', encoding='utf-8')
print('Both native captures completed; formal map exact bytes restored.')
