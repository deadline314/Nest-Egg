"""Offline portrait regression: source overrides, output density and rejected inputs."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image


def main():
    tool = Path(__file__).with_name("make_portrait.py")
    with tempfile.TemporaryDirectory() as directory:
        work = Path(directory)
        (work / "07_refined").mkdir()
        (work / "overrides/refined").mkdir(parents=True)
        for path, color in [(work / "base_rgba.png", "white"), (work / "07_refined/head.png", "red"),
                            (work / "overrides/refined/head.png", "blue")]:
            Image.new("RGBA", (16, 16), color).save(path)
        spec = {"parts": {"head": {"uses": [{"name": "head", "z": 1}]}},
                "dialog_portrait": {"box": [0, 0, 16, 16], "out": str(work / "portrait.png"), "size": 16}}
        source = work / "spec.json"
        source.write_text(json.dumps(spec), encoding="utf8")
        cmd = [sys.executable, str(tool), "--spec", str(source), "--work", str(work)]
        subprocess.run(cmd, check=True, capture_output=True)
        with Image.open(work / "portrait.png") as image:
            assert image.size == (16, 16) and image.getpixel((8, 8)) == (0, 0, 255, 255)
        before = (work / "portrait.png").read_bytes()
        for size, mode in [((15, 16), "RGBA"), ((16, 16), "RGB")]:
            Image.new(mode, size, "blue").save(work / "overrides/refined/head.png")
            result = subprocess.run(cmd, capture_output=True, text=True)
            assert result.returncode != 0 and "portrait source override" in result.stderr
            assert (work / "portrait.png").read_bytes() == before
        (work / "overrides/refined/head.png").unlink()
        spec["dialog_portrait"].pop("size")
        source.write_text(json.dumps(spec), encoding="utf8")
        subprocess.run(cmd, check=True, capture_output=True)
        with Image.open(work / "portrait.png") as image:
            assert image.size == (128, 128) and image.getpixel((64, 64)) == (255, 0, 0, 255)
    print("portrait: reviewed override used; declared size retained; invalid inputs preserve output; legacy default unchanged")


if __name__ == "__main__":
    main()
