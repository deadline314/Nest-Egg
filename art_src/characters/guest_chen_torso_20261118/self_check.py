"""僅在指定暫存目錄驗證來源拒收與重跑不改寫，不改遊戲來源或runtime。"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import shutil
import sys
import tempfile
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / "tools/comfyui"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch", type=Path, required=True, help="已存在且可寫的私有暫存父目錄")
    scratch = parser.parse_args().scratch.resolve()
    if not scratch.is_dir() or scratch.is_relative_to(ROOT):
        raise ValueError("請提供專案之外的私有暫存父目錄")
    record = json.loads((HERE / "provenance.json").read_text(encoding="utf-8"))
    with tempfile.TemporaryDirectory(prefix="ne267-torso-check-", dir=scratch) as temporary:
        fixture = Path(temporary).resolve()
        if not fixture.is_relative_to(scratch):
            raise ValueError("自檢暫存目錄超出指定位置")
        for name in record["inputs"]:
            target = fixture / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        callback = fixture / "art_src/characters/guest_chen_torso_20261118"
        shutil.copytree(HERE, callback)
        spec = importlib.util.spec_from_file_location("guest_chen_torso_check", callback / "rebuild.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        source = fixture / "art_src/characters/guest_chen/base_rgba.png"
        target = fixture / "art_src/characters/guest_chen/overrides/refined/torso.png"
        approved = callback / record["approved_outputs"]["torso"]
        source_bytes = source.read_bytes()
        approved_bytes = approved.read_bytes()
        spec_path = fixture / "tools/comfyui/specs/guest_chen_side.json"
        spec_bytes = spec_path.read_bytes()

        def reject_change(path, changed, expected):
            original = path.read_bytes()
            path.write_bytes(changed)
            try:
                module.main()
            except ValueError as error:
                if expected not in str(error):
                    raise
            else:
                raise AssertionError(f"變動來源未被拒收：{path.name}")
            finally:
                path.write_bytes(original)

        reject_change(source, source_bytes + b"changed", "陳女士來源版本不同")
        assert not target.exists(), "錯誤來源不應發布輸出"
        reject_change(approved, approved_bytes + b"changed", "approved output bytes changed")
        assert not target.exists(), "損毀批准PNG不應發布輸出"
        # 阻止PNG encoder，仍須能由RGBA驗證後發布批准原始bytes。
        with patch("PIL.Image.Image.save", side_effect=AssertionError("不可重編碼批准PNG")):
            spec_path.write_bytes(spec_bytes.replace(b"\r\n", b"\n"))
            module.main()
            accepted = target.read_bytes()
            timestamp = target.stat().st_mtime_ns
            assert accepted == approved_bytes
            assert hashlib.sha256(accepted).hexdigest() == record["source_override_sha256"]
            spec_path.write_bytes(spec_bytes.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"))
            module.main()
            assert target.read_bytes() == accepted and target.stat().st_mtime_ns == timestamp
            spec_path.write_bytes(spec_bytes)
            module.main()
        assert target.read_bytes() == accepted and target.stat().st_mtime_ns == timestamp
        reject_change(source, source_bytes + b"changed", "陳女士來源版本不同")
        reject_change(approved, approved_bytes + b"changed", "approved output bytes changed")
        assert b'"scale": 1.0' in spec_bytes
        reject_change(spec_path, spec_bytes.replace(b'"scale": 1.0', b'"scale": 1.1', 1), "陳女士來源版本不同")
        assert target.read_bytes() == accepted and target.stat().st_mtime_ns == timestamp
        wrong_output = accepted + b"changed"
        target.write_bytes(wrong_output)
        wrong_timestamp = target.stat().st_mtime_ns
        try:
            module.main()
        except ValueError as error:
            if "已有不同的來源覆寫" not in str(error):
                raise
        else:
            raise AssertionError("不同既有輸出未被拒收")
        assert target.read_bytes() == wrong_output and target.stat().st_mtime_ns == wrong_timestamp
    print("軀幹來源自檢通過：批准PNG原bytes發布且損毀拒收；LF/CRLF一致而內容變更拒收；重跑不改寫；既有輸出保持；fixture已清理")


if __name__ == "__main__":
    main()
