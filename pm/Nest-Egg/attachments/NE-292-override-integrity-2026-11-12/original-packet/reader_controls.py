"""Read-only adversarial controls for the sealed evidence reader."""
import copy
import hashlib
import io
import json
from pathlib import Path
import zipfile

from verify_ne292 import verify


def main():
    root = Path(__file__).resolve().parent
    index = json.loads((root / "index.json").read_text(encoding="utf8"))
    raw = (root / "raw.zip").read_bytes()
    try:
        verify(index, raw[:-1] + bytes([raw[-1] ^ 1]))
    except AssertionError as error:
        assert "raw.zip SHA differs" in str(error)
    else:
        raise AssertionError("reader accepted raw-byte corruption")

    target = "fixtures/after/test_tiff_named_png_refuses_before_delivery_changes/after/skin/parts/panel.png"
    donor = "fixtures/after/test_valid_png_keeps_its_original_encoded_bytes/after/skin/parts/panel.png"
    changed = copy.deepcopy(index)
    payload = io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(raw)) as source, zipfile.ZipFile(payload, "w", compression=zipfile.ZIP_DEFLATED) as output:
        for name in source.namelist():
            data = source.read(donor if name == target else name)
            output.writestr(name, data)
            if name == target:
                changed["members"][name] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
    forged = payload.getvalue()
    changed["raw_zip"]["sha256"] = hashlib.sha256(forged).hexdigest()
    changed["raw_zip"]["bytes"] = len(forged)
    try:
        verify(changed, forged)
    except AssertionError as error:
        assert "delivery changed despite refusal" in str(error), str(error)
    else:
        raise AssertionError("reader accepted changed delivery with recomputed archive/member hashes")
    print(json.dumps({"raw_byte_corruption_rejected": True, "rehashed_but_changed_delivery_rejected": True,
                      "files_modified": False}, indent=2))


if __name__ == "__main__":
    main()
