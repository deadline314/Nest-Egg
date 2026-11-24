"""Crop and resize the five registered PNGs from the original transparent atlas."""
from hashlib import sha256
from pathlib import Path
import json

from PIL import Image


SOURCE = Path(__file__).resolve().parent
RUNTIME = SOURCE.parents[2] / "art/equipment/forearm_deflector"


def split() -> None:
    metadata = json.loads((SOURCE / "registration.json").read_bytes())
    atlas_path = SOURCE / "atlas.png"
    if sha256(atlas_path.read_bytes()).hexdigest() != metadata["source_sha256"]:
        raise ValueError(f"Recheck the crop and registration before replacing {atlas_path}")
    pieces = {}
    with Image.open(atlas_path) as atlas:
        if atlas.mode != "RGBA" or list(atlas.size) != metadata["source_size"]:
            raise ValueError(f"Expected a registered RGBA atlas: {atlas_path}")
        for name, placement in metadata["pieces"].items():
            tile = atlas.crop(placement["crop"])
            # Remove low-opacity specks outside the art while retaining edge antialiasing.
            alpha = tile.getchannel("A").point(lambda a: 0 if a <= 8 else a)
            bounds = alpha.getbbox()
            if bounds is None or bounds[0] == 0 or bounds[1] == 0 or bounds[2] == tile.width or bounds[3] == tile.height:
                raise ValueError(f"{name} must have a transparent margin")
            if alpha.getextrema()[1] < 240:
                raise ValueError(f"{name} must have a solid metal silhouette")
            tile.putalpha(alpha)
            size = tuple(round(dimension * metadata["texels_per_world_pixel"]) for dimension in placement["size"])
            pieces[name] = tile.resize(size, Image.Resampling.LANCZOS)
    RUNTIME.mkdir(parents=True, exist_ok=True)
    for name, piece in pieces.items():
        piece.save(RUNTIME / f"{name}.png", optimize=True)


if __name__ == "__main__":
    split()
