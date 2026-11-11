"""Read-only independent verification of the NE292 sealed CPU evidence.

Usage: python verify_ne292.py [--raw-root <folder-containing-raw.zip>]
No engine, model, filesystem writes, or current working-tree images are used.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import zipfile

from PIL import Image


def verify(index, raw):
    assert hashlib.sha256(raw).hexdigest() == index["raw_zip"]["sha256"], "raw.zip SHA differs"
    with zipfile.ZipFile(io.BytesIO(raw)) as bundle:
        assert bundle.testzip() is None, "bad ZIP CRC"
        assert set(bundle.namelist()) == set(index["members"]), "raw members differ"
        for name, meta in index["members"].items():
            data = bundle.read(name)
            assert len(data) == meta["bytes"] and hashlib.sha256(data).hexdigest() == meta["sha256"], name

        def data(name):
            return bundle.read(name)

        def files(prefix):
            return {name[len(prefix):]: data(name) for name in bundle.namelist() if name.startswith(prefix)}

        valid = "test_valid_png_keeps_its_original_encoded_bytes"
        baseline_fail = {"test_truncated_png_refuses_before_delivery_changes", "test_tiff_named_png_refuses_before_delivery_changes",
                         "test_valid_crc_broken_idat_requires_complete_decode", "test_all_overrides_validate_before_first_delivery_change"}
        expected_cases = baseline_fail | {valid, "test_wrong_size_refuses_before_delivery_changes", "test_wrong_mode_refuses_before_delivery_changes",
                                          "test_unknown_part_refuses_before_delivery_changes"}
        result = {}
        for mode in ("before", "after"):
            log = data(f"logs/ne292-final-{mode}.stderr.log").decode("utf8")
            failures = set(re.findall(r"^FAIL: (\w+) ", log, re.M))
            assert failures == (baseline_fail if mode == "before" else set()), (mode, failures)
            assert "Ran 8 tests" in log
            assert ("FAILED (failures=4)" in log) if mode == "before" else ("OK" in log.splitlines())
            receipt = json.loads(data(f"logs/ne292-final-{mode}.json"))
            assert receipt["exit_code"] == (1 if mode == "before" else 0)
            cases = {name.split("/")[2] for name in bundle.namelist() if name.startswith(f"fixtures/{mode}/")}
            assert cases == expected_cases, (mode, cases)
            results = {}
            for case in sorted(cases):
                prefix = f"fixtures/{mode}/{case}/"
                previous = files(prefix + "delivery-before/")
                current = files(prefix + "after/")
                source = files(prefix + "source-before/")
                assert source and all(current[name] == original for name, original in source.items()), (mode, case, "source changed")
                same = all(current[name] == original for name, original in previous.items())
                if case == valid:
                    assert current["skin/parts/panel.png"] == current["source/overrides/panel.png"]
                    with Image.open(io.BytesIO(current["skin/parts/panel.png"])) as image:
                        image.load()
                        assert (image.format, image.mode, image.getpixel((0, 0))) == ("PNG", "RGBA", (15, 85, 145, 235))
                elif mode == "after" or case not in baseline_fail:
                    assert same, (mode, case, "delivery changed despite refusal")
                else:
                    assert not same, (mode, case, "negative did not replace delivery")
                if case == "test_valid_crc_broken_idat_requires_complete_decode":
                    encoded = source["source/overrides/panel.png"]
                    with Image.open(io.BytesIO(encoded)) as image:
                        image.verify()
                    try:
                        with Image.open(io.BytesIO(encoded)) as image:
                            image.load()
                    except OSError:
                        pass
                    else:
                        raise AssertionError("valid-CRC negative did not fail actual decoding")
                results[case] = {"source_exact": True, "delivery_exact": same, "expected_original_failure": mode == "before" and case in baseline_fail}
            result[mode] = results
        pipeline = {}
        for name, label in index["pipeline_final_logs"].items():
            receipt = json.loads(data(f"logs/{label}.json"))
            assert receipt["exit_code"] == 0, (name, receipt["exit_code"])
            pipeline[name] = 0
        for path, meta in index["candidate"].items():
            payload = data("sources/after/" + path)
            assert hashlib.sha256(payload).hexdigest() == meta["sha256"], path
        # This line is an exact addition to the eight existing CPU test calls.
        old = data("sources/before/.github/workflows/art-cuts.yml")
        new = data("sources/after/.github/workflows/art-cuts.yml")
        line = b"          python tools/comfyui/test_final_overrides.py\n"
        assert new == old + line and new.count(line) == 1
        return {"verified": True, "ticket": "NE-292", "published_base": index["published_base"],
                "members": len(index["members"]), "permanent_before": "8 tests / 4 expected failures", "permanent_after": "8 tests / 0 failures",
                "pipeline": pipeline, "cases": result,
                "scope": "CPU encoded source integrity and publication only; no actor/native/performance acceptance"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-root", type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    folder = args.raw_root.resolve()
    index = json.loads((folder / "index.json").read_text(encoding="utf8"))
    result = verify(index, (folder / index["raw_zip"]["name"]).read_bytes())
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
