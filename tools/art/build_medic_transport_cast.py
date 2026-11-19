"""Build the S13 cast variants from their pinned character sources."""
from pathlib import Path
import hashlib
from io import BytesIO
import json

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CONFIG = 'assets_src/pipeline/medic_transport_cast.json'
COAT_PARTS = ('torso', 'pelvis', 'leg_upper', 'arm_upper', 'arm_lower', 'hand')


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def encoded(data):
    return (json.dumps(data, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def remove_sleeve_badge(image):
    # Blend the medical badge into the surrounding cloth in both texture maps.
    left, top, right, bottom = 21, 53, 82, 119
    pixels = image.load()
    for y in range(top + 1, bottom):
        vertical = (y - top) / (bottom - top)
        for x in range(left + 1, right):
            upper, lower = pixels[x, top], pixels[x, bottom]
            edge = min(x - left, right - x, y - top, bottom - y, 4) / 4.0
            original = pixels[x, y]
            cloth = [a + (b - a) * vertical for a, b in zip(upper[:3], lower[:3])]
            pixels[x, y] = tuple(round(value + (target - value) * edge)
                                 for value, target in zip(original[:3], cloth)) + (original[3],)


def coat_texture(data, sleeve=False, normal=False):
    with Image.open(BytesIO(data)) as image:
        coat = image.convert('RGBA')
    alpha = coat.getchannel('A').tobytes()
    if sleeve:
        remove_sleeve_badge(coat)
    if not normal:
        pixels = coat.load()
        for y in range(coat.height):
            for x in range(coat.width):
                red, green, blue, opacity = pixels[x, y]
                if opacity and green - red > 4 and green - blue > 5:
                    shade = (54 * red + 183 * green + 19 * blue + 128) // 256
                    pixels[x, y] = (max(0, shade - 2), shade, min(255, shade + 4), opacity)
    if coat.getchannel('A').tobytes() != alpha:
        raise ValueError('S13 coat edit cannot change the source silhouette')
    output = BytesIO()
    coat.save(output, format='PNG', optimize=True)
    return output.getvalue()


def main():
    config = json.loads((ROOT / CONFIG).read_text(encoding='utf-8'))
    for name, expected in config['sources'].items():
        raw = (ROOT / name).read_bytes()
        if name.endswith('.json'):
            raw = raw.replace(b'\r\n', b'\n')
        if digest(raw) != expected:
            raise ValueError('S13原角色來源不同，停止發布：' + name)
    profile = json.loads((ROOT / config['kneel_source']).read_text(encoding='utf-8'))['crouch']['kneel']
    outputs = {}
    for role in config['roles']:
        base, alias = role['base'], role['id']
        if base not in ['egret', 'ch2_greycoat', 'ch2_medic'] or alias != base + '/transport':
            raise ValueError('S13變體僅接受登記的三個角色巢狀路徑')
        skin = json.loads((ROOT / f'art/characters/{base}/character.json').read_text(encoding='utf-8'))
        skin['id'] = alias
        skin['display_name'] += '（S13搬送資料）'
        skin['description'] = f'S13限定資料變體；引用{base}全部原parts與同一rig，沒有新人物圖或骨長修改。'
        for definition in skin['textures'].values():
            definition['file'] = '../' + definition['file']
            if 'glow' in definition:
                definition['glow'] = '../' + definition['glow']
        if base == 'ch2_medic':
            skin['display_name'] = '後側搬運者'
            skin['description'] = 'S13後側搬運者的灰外套；沿用原骨架、輪廓及其餘零件。'
            for part in COAT_PARTS:
                for suffix in ('', '_n'):
                    filename = f'parts/{part}{suffix}.png'
                    source = f'art/characters/{base}/{filename}'
                    if source not in config['sources']:
                        raise ValueError('S13未登記外套來源：' + source)
                    raw = (ROOT / source).read_bytes()
                    if suffix and part != 'arm_upper':
                        payload = raw
                    else:
                        payload = coat_texture(raw, sleeve=part == 'arm_upper', normal=bool(suffix))
                    outputs[f'art/characters/{alias}/{filename}'] = payload
                skin['textures'][part]['file'] = f'parts/{part}.png'
        motion = json.loads((ROOT / f'art/motion/{base}.json').read_text(encoding='utf-8'))
        motion['skin'] = alias
        motion['description'] = 'S13限定搬運資料；原角色檔案不變。'
        if 'death' in role:
            motion['death'].update(role['death'])
        else:
            crouch = dict(role['crouch'])
            motion['crouch']['kneel'] = {**profile, **crouch.pop('kneel', {})}
            motion['crouch'].update(crouch)
        outputs[f'art/characters/{alias}/character.json'] = encoded(skin)
        outputs[f'art/motion/{alias}.json'] = encoded(motion)
    # 整批先驗，不能在後一個輸出拒收前悄悄覆寫前面的既有資料。
    for name, payload in outputs.items():
        path = ROOT / name
        if path.exists():
            actual = path.read_bytes()
            if name.endswith('.json'):
                actual = actual.replace(b'\r\n', b'\n')
            if actual != payload:
                raise ValueError('S13既有變體不同，保留並拒絕：' + name)
    for name, payload in outputs.items():
        path = ROOT / name
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(payload)
    receipt = {
        'sources': config['sources'], 'hash_policy': config['hash_policy'],
        'outputs_sha256_lf': {name: digest(payload) for name, payload in outputs.items() if name.endswith('.json')},
        'textures_sha256': {name: digest(payload) for name, payload in outputs.items() if name.endswith('.png')},
        'human_pixels': '後側搬運者的上身、袖子、袖口與外套下襬保留原輪廓。膚色、臉及其他角色沿用原素材。',
        'kneel_source': config['kneel_source'],
    }
    path = ROOT / 'assets_src/pipeline/medic_transport_cast-receipt.json'
    payload = encoded(receipt)
    if not path.exists() or path.read_bytes() != payload:
        path.write_bytes(payload)
    print('S13三個巢狀場景變體與後側搬運外套；固定來源通過。')


if __name__ == '__main__':
    main()
