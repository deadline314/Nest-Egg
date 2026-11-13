"""Independent SAT, source-alpha and actual-recording checks for NE277 contacts."""
from __future__ import annotations
import math
from pathlib import Path
import wave
import numpy as np
from PIL import Image


def transform(points, value, inverse=False):
    matrix = np.array([[value[0], value[2]], [value[1], value[3]]], dtype=float)
    origin = np.array(value[4:6], dtype=float)
    points = np.asarray(points, dtype=float)
    return (points - origin) @ np.linalg.inv(matrix).T if inverse else points @ matrix.T + origin


def overlap(triangle, half):
    """SAT in the target rectangle's own coordinates, including degenerate edges."""
    axes = [(1.0, 0.0), (0.0, 1.0)]
    axes += [(a[1]-b[1], b[0]-a[0]) for a, b in zip(triangle, np.roll(triangle, -1, axis=0))]
    for axis in axes:
        if abs(axis[0])+abs(axis[1]) < 1e-10:
            continue
        projected = triangle @ axis
        extent = half[0]*abs(axis[0])+half[1]*abs(axis[1])
        if projected.max() < -extent-1e-5 or projected.min() > extent+1e-5:
            return False
    return True


def point_inside(point, triangle):
    cross = []
    for a, b in zip(triangle, np.roll(triangle, -1, axis=0)):
        cross.append((b[0]-a[0])*(point[1]-a[1])-(b[1]-a[1])*(point[0]-a[0]))
    area = abs((triangle[1, 0]-triangle[0, 0])*(triangle[2, 1]-triangle[0, 1])-(triangle[1, 1]-triangle[0, 1])*(triangle[2, 0]-triangle[0, 0]))
    if area > 1e-7:
        return min(cross) >= -.002 or max(cross) <= .002
    for a, b in zip(triangle, np.roll(triangle, -1, axis=0)):
        line = b-a
        length = np.dot(line, line)
        t = np.clip(np.dot(point-a, line)/length, 0, 1) if length else 0
        if np.linalg.norm(point-a-line*t) <= .002:
            return True
    return False


def swept_contact(hit, require_point=False):
    current = transform(hit['current'], hit['target_transform'], True)
    previous = transform(hit['previous'], hit['target_transform'], True)
    half = np.asarray(hit['target_size']) / 2.0
    start = previous + (current-previous)*hit['from_fraction']
    stop = previous + (current-previous)*hit['to_fraction']
    for index in range(0, len(current), 3):
        a, b = start[index:index+3], stop[index:index+3]
        surfaces = [a, b]
        for j in range(3):
            k = (j+1) % 3
            surfaces += [np.array([a[j], b[j], b[k]]), np.array([a[j], b[k], a[k]])]
        point = transform([hit['point']], hit['target_transform'], True)[0] if require_point else None
        if any(overlap(triangle, half) and (not require_point or point_inside(point, triangle)) for triangle in surfaces):
            return True
    return False


def visible_mesh(hit, weapon, directory):
    current = np.asarray(hit['current'], dtype=float)
    if weapon == 'whip':
        rope = transform(hit['rope_nodes'], hit['canvas_transform'], True)
        if rope.shape != (20, 2):
            return False
        expected = []
        for i in range(1, 20):
            a, b = rope[i-1], rope[i]
            direction = b-a
            length = np.linalg.norm(direction)
            perpendicular = np.array([direction[1], -direction[0]]) / length if length > 0 else np.zeros(2)
            side = perpendicular * (1.8 + (0.6-1.8)*i/19) * .5
            expected.extend([a-side, b-side, b+side, a-side, b+side, a+side])
        expected = transform(expected, hit['canvas_transform'])
        return current.shape == expected.shape and np.max(np.abs(current-expected)) <= .001
    import json
    art = json.loads((directory/'source/data/weapon_art/melee.json').read_bytes())['weapons']['melee_'+weapon]
    pixels = np.array(Image.open(directory/'source'/art['texture'].removeprefix('res://')).convert('RGBA'))[:, :, 3]
    height, width = pixels.shape
    size, grip = np.array(art['size']), np.array(art['grip'])
    scale = size / [width, height]
    span = hit['contact_span']
    local = transform(current, hit['draw_transform'], True)
    if not np.isfinite(local).all() or local[:, 0].min() < max(-grip[0], span[0])-.001 or local[:, 0].max() > min(size[0]-grip[0], span[1])+.001 or local[:, 1].min() < -grip[1]-.001 or local[:, 1].max() > size[1]-grip[1]+.001:
        return False
    ys, xs = np.mgrid[0:height, 0:width]
    centers = np.stack([(xs+.5)*scale[0]-grip[0], (ys+.5)*scale[1]-grip[1]], axis=-1)
    mask = np.zeros((height, width), dtype=bool)
    area = 0.0
    for triangle in local.reshape(-1, 3, 2):
        a, b, c = triangle
        u, v = b-a, c-a
        area += abs(u[0]*v[1]-u[1]*v[0])*.5
        edges = [((q[0]-p[0])*(centers[:, :, 1]-p[1])-(q[1]-p[1])*(centers[:, :, 0]-p[0])) for p, q in zip(triangle, np.roll(triangle, -1, axis=0))]
        mask |= np.logical_and.reduce([edge >= -.0005 for edge in edges]) | np.logical_and.reduce([edge <= .0005 for edge in edges])
    expected = (pixels > 25) & (centers[:, :, 0] >= span[0]) & (centers[:, :, 0] <= span[1])
    left = np.maximum(xs*scale[0]-grip[0], span[0])
    right = np.minimum((xs+1)*scale[0]-grip[0], span[1])
    expected_area = np.sum(np.maximum(right-left, 0)*(pixels > 25))*scale[1]
    return np.array_equal(mask, expected) and math.isclose(area, expected_area, abs_tol=.01)


def verify_contacts(data, expected, directory: Path, native=False):
    errors = []
    def require(ok, message):
        if not ok:
            errors.append(message)
    require(data.get('failures') == [] and isinstance(data.get('checks'), int) and data['checks'] > 0, 'passing contact checks required')
    rows = data.get('rows', [])
    require(isinstance(rows, list) and bool(rows) and len(rows) == len(expected) and {r.get('name') for r in rows} == expected, 'exact nonempty contact matrix required')
    if not isinstance(rows, list):
        return errors
    for row in rows:
        name = row.get('name', '?')
        try:
            require(row['contact_control'] == '', name+': unmodified formal contact path required')
            require(all(math.isclose(frame['progress'], frame['visible_progress'], abs_tol=1e-6) for frame in row.get('frames', []) if frame.get('phase') in [1,2,3] and 'palm_gap' in frame), name+': every fully published grip must share the current module pose, including release')
            hits = row['contact_hits']
            require(bool(hits), name+': actual matching authored-move damage required')
            definition, spec = row['contact_definition'], row['contact_hold_spec']
            import json
            profiles = {'blade':'thermal_blade','dagger':'mono_dagger','glaive':'ion_glaive','maul':'hydraulic_maul','whip':'mono_whip'}
            formal = json.loads((directory/'source/data/melee'/str(profiles[row['weapon']]+'.json')).read_bytes())
            raw = formal['attacks'][row['move']]
            require(all(definition.get(key) == value for key, value in raw.items()), name+': recorded definition must preserve every authored move field')
            require(spec == formal['hold'], name+': original hold contract required')
            if row['held'] and spec['mode'] == 'sustain':
                require(len(hits) >= 2, name+': repeated real held damage required')
            for hit in hits:
                current, previous = np.asarray(hit['current']), np.asarray(hit['previous'])
                require(current.ndim == 2 and current.shape[1] == 2 and 0 < len(current) <= 10000 and len(current) % 3 == 0 and current.shape == previous.shape and np.isfinite(current).all() and np.isfinite(previous).all(), name+': complete finite geometry required')
                require(hit['phase'] == 2 and hit['mesh_tick'] == hit['tick'] and 0 <= hit['previous_tick'] <= hit['tick'] and math.isclose(hit['progress'], hit['visual_progress'], abs_tol=1e-6), name+': damage must observe this physics tick visible pose')
                require(hit['attacker_matches'] is True and hit['team'] == 0 and hit['source'] == 'melee' and hit['target_area_in_space'] is True, name+': real player source and active hurtbox required')
                require(0 <= hit['from_fraction'] <= hit['to_fraction'] <= 1, name+': clipped original-window sweep required')
                sustained = row['held'] and spec['mode'] == 'sustain' and hit['time'] >= definition['active']
                windows = definition['hits']
                require(0 <= hit['window'] < len(windows), name+': valid original window index required')
                window = windows[hit['window']]
                if not sustained:
                    require(0 <= hit['window'] < len(windows) and hit['resolved_to'] >= window['at']-1e-6 and hit['resolved_from'] < window['at']+window['length']+1e-6 and hit['time'] <= definition['active']+1/60+.0001, name+': original authored window required')
                amount = spec['full_damage'] if row['held'] and spec['mode'] == 'charge' and hit['charged'] else window.get('damage', definition['damage'])
                require(hit['amount'] == amount and not hit['weak'] and hit['part'] == '', name+': original formal body damage required')
                require(visible_mesh(hit, row['weapon'], directory), name+': geometry must equal actual source alpha/head span or drawn rope')
                require(hit['contact_span'] == formal.get('contact_span', [-512.0, 512.0]), name+': original visible damaging part required')
                point = transform([hit['point']], hit['target_transform'], True)[0]
                require(np.isfinite(point).all() and np.all(np.abs(point) <= np.asarray(hit['target_size'])/2+.001) and swept_contact(hit, True), name+': independent SAT and real contact on both weapon sweep and target required')
            require(any(s['matching'] and s['id'] in [definition['sounds']['hit'], definition.get('feedback', {}).get('high')] for s in row['contact_sounds']), name+': matching actual hit-sound event required')
            if native:
                path = directory/row['contact_first_image']
                with Image.open(path) as image:
                    require(image.size == (1280, 720) and image.convert('RGB').getextrema() != ((0, 0),)*3, name+': original native full-frame contact image required')
        except (KeyError, IndexError, TypeError, ValueError, OSError, np.linalg.LinAlgError) as error:
            errors.append(name+': malformed contact evidence: '+str(error))
    if native:
        try:
            with wave.open(str(directory/'contact-master.wav'), 'rb') as audio:
                require(audio.getsampwidth() == 2 and audio.getnframes() >= audio.getframerate() and any(audio.readframes(audio.getnframes())), 'actual nonzero PCM master recording required')
        except (OSError, wave.Error) as error:
            errors.append('actual recording: '+str(error))
    return errors
