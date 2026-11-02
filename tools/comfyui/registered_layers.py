"""Validate reconstructed pixels, then publish frozen approved PNG bytes without re-encoding."""
import hashlib
import io
import os
from pathlib import Path
import tempfile

from PIL import Image


def registered_layer_bytes(layers: dict[str, Image.Image], work: Path, record: dict) -> dict[str, bytes]:
    references = record.get("approved_outputs", {})
    if set(layers) != set(references) or set(layers) != set(record["outputs"]):
        raise ValueError("registered layer names differ from the approved output contract")
    result = {}
    for name, reconstructed in layers.items():
        path = (work / references[name]).resolve()
        if not path.is_relative_to(work.resolve()):
            raise ValueError(f"approved output must be inside its registered source directory: {name}")
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != record["outputs"][name]:
            raise ValueError(f"approved output bytes changed: {name}")
        with Image.open(io.BytesIO(data)) as approved:
            if approved.mode != "RGBA" or reconstructed.mode != "RGBA" or approved.size != reconstructed.size:
                raise ValueError(f"approved output format or dimensions changed: {name}")
            if approved.tobytes() != reconstructed.tobytes():
                raise ValueError(f"reconstructed output pixels changed: {name}")
        result[name] = data
    return result


def write_registered_file(target: Path, data: bytes) -> None:
    """Keep identical outputs untouched; an interrupted write cannot truncate an existing file."""
    if target.is_file() and target.read_bytes() == data:
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    pending = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix=f".{target.name}.", suffix=".pending", delete=False) as stream:
            pending = Path(stream.name)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(pending, target)
    finally:
        if pending is not None:
            pending.unlink(missing_ok=True)
