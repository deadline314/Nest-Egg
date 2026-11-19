"""Rebuild the market screen from Shen Wang's retained portrait and panel."""

import argparse
import hashlib
import io
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
BOARD = ROOT / "art/environment/scene_props/neon_market/neon_market__speech_screen"
PANEL = (218, 64, 543, 327)
LAYERS = ("", "_glow", "_n")


def read_image(path: Path, sha: str, size: tuple[int, int]) -> Image.Image:
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != sha:
        raise ValueError(f"{path}: source SHA differs")
    with Image.open(io.BytesIO(data)) as image:
        if image.mode != "RGBA" or image.size != size:
            raise ValueError(f"{path}: expected native RGBA {size}, got {image.mode} {image.size}")
        return image.copy()


def clear_screen(image: Image.Image) -> Image.Image:
    left, top, right, bottom = PANEL
    width = right - left
    strip = np.asarray(image, dtype=np.float32)[top:bottom]
    across = np.linspace(0.0, 1.0, width, dtype=np.float32)[None, :, None]
    fill = strip[:, left-1:left] * (1.0 - across) + strip[:, right:right+1] * across
    return Image.fromarray(np.round(fill).astype(np.uint8))


def build(check: bool) -> None:
    source = json.loads((HERE / "portrait.json").read_text(encoding="utf-8"))[0]
    figure = read_image(ROOT / source["source"], source["sha256"], tuple(source["dimensions"]))
    figure.putalpha(figure.getchannel("A").point(lambda value: 0 if value < source["alpha_floor"] else value))
    figure = figure.resize((325, 325), Image.Resampling.LANCZOS).crop((0, 16, 325, 279))
    if figure.size != (PANEL[2] - PANEL[0], PANEL[3] - PANEL[1]) or not figure.getchannel("A").getbbox():
        raise ValueError("Shen portrait must cover the central screen crop")

    hashes = json.loads((HERE / "board.json").read_text(encoding="utf-8"))
    pending: dict[Path, bytes] = {}
    for suffix in LAYERS:
        template = f"template{suffix}.png"
        image = read_image(HERE / template, hashes[template], (762, 468))
        screen = clear_screen(image)
        if suffix != "_n":
            person = ImageEnhance.Brightness(figure).enhance(0.50 if suffix == "_glow" else 1.0)
            screen.alpha_composite(person)
        image.paste(screen, PANEL)
        output = BOARD.with_name(f"{BOARD.name}{suffix}.png")
        with io.BytesIO() as buffer:
            image.save(buffer, format="PNG")
            pending[output] = buffer.getvalue()

    for output, data in pending.items():
        if check:
            if not output.exists() or output.read_bytes() != data:
                raise ValueError(f"{output}: screen differs from its source")
        else:
            temporary = output.with_suffix(".pending")
            temporary.write_bytes(data)
            temporary.replace(output)
        print(f"{output.name}: {hashlib.sha256(data).hexdigest()}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
