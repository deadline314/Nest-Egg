"""只在專案外私有fixture驗證五片原bytes發布、來源拒收與mtime保持。"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import shutil
import sys
import tempfile
from unittest.mock import patch
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
sys.dont_write_bytecode=True
sys.path.insert(0,str(ROOT/'tools/comfyui'))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scratch',type=Path,required=True,help='專案外、已存在且可寫的私有暫存父目錄')
    scratch=parser.parse_args().scratch.resolve()
    if not scratch.is_dir() or scratch.is_relative_to(ROOT):
        raise ValueError('請提供專案之外的私有暫存父目錄')
    record=json.loads((HERE/'provenance.json').read_text(encoding='utf-8'))
    with tempfile.TemporaryDirectory(prefix='ne267-hong-combined-check-',dir=scratch) as temporary:
        fixture=Path(temporary).resolve()
        if not fixture.is_relative_to(scratch):
            raise ValueError('自檢fixture超出指定位置')
        for name in record['inputs']:
            target=fixture/name
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(ROOT/name,target)
        callback=fixture/'art_src/characters/guest_hong_repairs_20261118'
        shutil.copytree(HERE,callback)
        spec=importlib.util.spec_from_file_location('guest_hong_combined_check',callback/'rebuild.py')
        module=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        targets={name:fixture/f'art_src/characters/guest_hong/overrides/refined/{name}.png' for name in record['outputs']}
        approved={name:callback/path for name,path in record['approved_outputs'].items()}
        approved_bytes={name:path.read_bytes() for name,path in approved.items()}
        source=fixture/'art_src/characters/guest_hong/base_rgba.png'
        spec_path=fixture/'tools/comfyui/specs/guest_hong_side.json'
        claims={part:callback/config['file'] for part,config in record['coordinate_claims'].items()}
        spec_bytes=spec_path.read_bytes()
        claims_bytes={part:path.read_bytes() for part,path in claims.items()}
        def reject_change(path,changed,expected):
            original=path.read_bytes()
            path.write_bytes(changed)
            try:
                module.main()
            except ValueError as error:
                if expected not in str(error):raise
            else:raise AssertionError(f'變動來源未被拒收：{path.name}')
            finally:path.write_bytes(original)
        reject_change(source,source.read_bytes()+b'changed','洪先生來源版本不同')
        for relative in ['overrides/arm_upper.png','overrides/refined/head.png']:
            foreign=fixture/'art_src/characters/guest_hong'/relative
            assert foreign.is_relative_to(fixture)
            foreign.parent.mkdir(parents=True,exist_ok=True)
            foreign.write_bytes(b'unregistered override')
            try:
                module.main()
            except ValueError as error:
                if '未登記的來源覆寫' not in str(error):raise
            else:raise AssertionError('未登記覆寫未被拒收')
            finally:foreign.unlink()
            assert not any(p.exists() for p in targets.values()),'後置覆寫不可部分發布來源'
        for name,path in approved.items():
            reject_change(path,path.read_bytes()+b'changed','approved output bytes changed')
            assert not any(p.exists() for p in targets.values()),'損毀批准PNG不應部分發布任何輸出'
        reject_change(callback/'neck-mask.png',(callback/'neck-mask.png').read_bytes()+b'changed','頸部遮罩版本不同')
        for part,path in claims.items():reject_change(path,claims_bytes[part]+b' ','分件座標映射版本不同')
        assert not any(p.exists() for p in targets.values())
        with patch('PIL.Image.Image.save',side_effect=AssertionError('不可重編碼批准PNG')):
            spec_path.write_bytes(spec_bytes.replace(b'\r\n',b'\n'))
            for part,path in claims.items():path.write_bytes(claims_bytes[part].replace(b'\r\n',b'\n'))
            module.main()
            timestamps={name:p.stat().st_mtime_ns for name,p in targets.items()}
            for name,path in targets.items():
                assert path.read_bytes()==approved_bytes[name]
                assert hashlib.sha256(path.read_bytes()).hexdigest()==record['outputs'][name]
            spec_path.write_bytes(spec_bytes.replace(b'\r\n',b'\n').replace(b'\n',b'\r\n'))
            for part,path in claims.items():path.write_bytes(claims_bytes[part].replace(b'\r\n',b'\n').replace(b'\n',b'\r\n'))
            module.main()
            assert all(p.read_bytes()==approved_bytes[name] and p.stat().st_mtime_ns==timestamps[name] for name,p in targets.items())
            spec_path.write_bytes(spec_bytes)
            for part,path in claims.items():path.write_bytes(claims_bytes[part])
            module.main()
        reject_change(source,source.read_bytes()+b'changed','洪先生來源版本不同')
        for part,path in claims.items():reject_change(path,claims_bytes[part]+b' ','分件座標映射版本不同')
        assert b'"scale": 1.0' in spec_bytes
        reject_change(spec_path,spec_bytes.replace(b'"scale": 1.0',b'"scale": 1.1',1),'洪先生來源版本不同')
        assert all(p.read_bytes()==approved_bytes[name] and p.stat().st_mtime_ns==timestamps[name] for name,p in targets.items())
        wrong=targets['arm_lower']
        wrong_bytes=approved_bytes['arm_lower']+b'changed'
        wrong.write_bytes(wrong_bytes)
        wrong_time=wrong.stat().st_mtime_ns
        first=targets['torso']
        assert first.is_relative_to(fixture)
        first.unlink()
        second=targets['arm_upper']
        assert second.is_relative_to(fixture)
        second.unlink()
        try:module.main()
        except ValueError as error:
            if '已有不同的來源覆寫' not in str(error):raise
        else:raise AssertionError('不同既有輸出未被拒收')
        assert not first.exists() and not second.exists(),'最後一片錯誤不得先發布前兩片'
        assert wrong.read_bytes()==wrong_bytes and wrong.stat().st_mtime_ns==wrong_time
    print('洪先生合併來源自檢通過：五片批准PNG原bytes/損毀拒收；LF/CRLF一致與內容拒收；mtime保持；最後一片錯誤不部分發布；fixture已清理')

if __name__=='__main__':
    main()
