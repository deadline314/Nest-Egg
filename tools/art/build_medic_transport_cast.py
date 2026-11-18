"""S13巢狀場景變體：先驗固定來源，沿既有skin/motion路徑，原人物與PNG不改。"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
CONFIG = 'assets_src/pipeline/medic_transport_cast.json'


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def encoded(data):
    return (json.dumps(data, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


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
        if path.exists() and path.read_bytes().replace(b'\r\n', b'\n') != payload:
            raise ValueError('S13既有變體不同，保留並拒絕：' + name)
    for name, payload in outputs.items():
        path = ROOT / name
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(payload)
    receipt = {
        'sources': config['sources'], 'hash_policy': config['hash_policy'],
        'outputs_sha256_lf': {name: digest(payload) for name, payload in outputs.items()},
        'human_pixels': '引用全部原parts，不複製、不改寫；既有character_dir相對路徑解析。',
        'kneel_source': config['kneel_source'],
    }
    path = ROOT / 'assets_src/pipeline/medic_transport_cast-receipt.json'
    payload = encoded(receipt)
    if not path.exists() or path.read_bytes() != payload:
        path.write_bytes(payload)
    print('S13三個巢狀場景變體；固定來源通過，原人物/PNG不改。')


if __name__ == '__main__':
    main()
