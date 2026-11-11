"""Verify archived BG-52 observations without starting a server or loading a model."""
from __future__ import annotations

import hashlib
import io
import json
import re
import sys
from pathlib import Path
from zipfile import ZipFile

from PIL import Image


def main() -> None:
    folder = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("pm/Nest-Egg-BG/attachments/BG-52-rocm-runtime")
    receipt = json.loads((folder / "receipt.json").read_text(encoding="utf-8"))
    checks = 0

    def check(condition: bool, message: str) -> None:
        nonlocal checks
        if not condition:
            raise ValueError(message)
        checks += 1

    archive_path = folder / "raw.zip"
    check(hashlib.sha256(archive_path.read_bytes()).hexdigest() == receipt["archive_sha256"], "archive SHA differs")
    with ZipFile(archive_path) as archive:
        check(archive.testzip() is None, "archive CRC failure")
        manifest = json.loads(archive.read("manifest.json"))
        check(set(archive.namelist()) == {row["file"] for row in manifest} | {"manifest.json"}, "archive entries differ")
        for row in manifest:
            data = archive.read(row["file"])
            check(len(data) == row["bytes"] and hashlib.sha256(data).hexdigest() == row["sha256"], f"original bytes differ: {row['file']}")

        runtime = json.loads(archive.read("runtime-probe.log"))
        check(runtime["backend"] == "rocm" and runtime["name"] == "AMD Radeon RX 9070 XT", "wrong exercised device")
        check(runtime["tensor_sum_of_squares"] == 1240.0, "GPU kernel did not produce known result")
        check(runtime["torch"] == "2.13.0+rocm10.0.0", "wrong exercised PyTorch")

        generation = json.loads(archive.read("generation.json"))
        original = archive.read("generated/bg52_medic_rgba_0.png")
        check(generation["passed"] and generation["candidate_only"], "runtime sample must not be an adopted character")
        check(hashlib.sha256(original).hexdigest() == generation["sha256"], "original generated PNG differs")
        with Image.open(io.BytesIO(original)) as picture:
            check(picture.mode == "RGBA" and list(picture.size) == [832, 1216], "wrong native image format or size")
            alpha = picture.getchannel("A")
            histogram = alpha.histogram()
            check(histogram == generation["alpha_histogram"], "original alpha histogram differs")
            check(histogram[0] > 0 and sum(histogram[250:]) > 0, "missing transparent background or opaque subject")
            check(all(alpha.getpixel(point) == 0 for point in [(0, 0), (831, 0), (0, 1215), (831, 1215)]), "corners are not transparent")
        stats = generation["server_stats_before"]
        check(generation["shared_existing_service"] and generation["service_port"] == 8188, "generation service scope differs")
        check(stats["system"]["pytorch_version"] == "2.13.0+rocm10.0.0" and "9070 XT" in stats["devices"][0]["name"], "wrong generation server runtime")

        result = json.loads(archive.read("lifecycle-v2/result.json"))
        check(result == [{"case": name, "exit": 0} for name in ["start", "reuse", "restart", "stop"]] +
              [{"case": "stopped_endpoint_unreachable", "passed": True}], "final lifecycle failed")
        for name in ["start", "reuse", "restart"]:
            stats = json.loads(archive.read(f"lifecycle-v2/{name}-stats.json"))
            argv = stats["system"]["argv"]
            check(stats["system"]["pytorch_version"] == "2.13.0+rocm10.0.0" and "9070 XT" in stats["devices"][0]["name"], f"{name}: wrong device/runtime")
            check("service-8189/user/comfyui.db" in argv[argv.index("--database-url") + 1], f"{name}: database is not isolated")
            check(not re.search(rb"\[ERROR\]|Traceback|IMPORT FAILED", archive.read(f"lifecycle-v2/{name}-server.log")), f"{name}: server diagnostics failed")
        for name in ["test_runtime_probe", "test_cache_options", "test_gpu_lock"]:
            check(json.loads(archive.read("unit-results.json"))[name] == 0, f"{name}: CPU regression failed")

    project = Path(__file__).resolve().parents[2]
    for name, expected in receipt["delivery_source_sha256"].items():
        check(hashlib.sha256((project / name).read_bytes()).hexdigest() == expected, f"delivery source differs: {name}")
    print(json.dumps({"checks": checks, "failures": 0, "scope": "archived GPU runtime, shared-service generation and separate local service lifecycle; no character approval or exclusive benchmark"}, indent=2))


if __name__ == "__main__":
    main()
