"""Generate NE-225 world sprites one at a time, through the existing ComfyUI client.

Usage: python tools/art/build_world_items.py [--only id ...] [--no-gen]
Source RGBA and receipt are retained under assets_src/generated/world_items/.
Never holds a batch of decoded pictures. Existing backpack art is not overwritten.
"""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import threading
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
CFG = ROOT / "assets_src/pipeline/world_items.json"
SOURCE = ROOT / "assets_src/generated/world_items"
OUT = ROOT / "art/items/world"


def available_ram_gb() -> float:
    if os.name != "nt":
        import psutil
        return psutil.virtual_memory().available / 2**30
    from ctypes import wintypes
    class Memory(ctypes.Structure):
        _fields_ = [("length", wintypes.DWORD), ("load", wintypes.DWORD)] + [
            (key, ctypes.c_ulonglong) for key in
            ("total", "available", "page", "page_available", "virtual", "virtual_available", "ext")]
    memory = Memory()
    memory.length = ctypes.sizeof(memory)
    if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(memory)):
        raise RuntimeError("Cannot measure available RAM; generation not started")
    return memory.available / 2**30


def stop_server() -> None:
    subprocess.run(["powershell", "-NoProfile", "-File",
                    str(ROOT / "tools/comfyui/start_comfyui.ps1"), "-Stop"], check=True)


def generate(entry: dict, cfg: dict) -> Path:
    sys.path.insert(0, str(ROOT / "tools/comfyui"))
    # User requested observation instead of the early RAM-abort threshold.
    os.environ.setdefault("COMFY_MIN_FREE_RAM_GB", "0")
    os.environ.setdefault("COMFY_MAX_RETRIES", "0")
    os.environ.setdefault("OUT_DIR", str(ROOT / "assets_src/work/world_items"))
    from comfy_api import qwen, QWEN_UNET, QWEN_CLIP, QWEN_VAE
    import comfy_guard
    generation = cfg["generation"]
    prompt = ("This is an RGBA image with transparency. " + cfg["style"] + " " +
              entry["subject"] + " The image has alpha channel and the background is transparent.")
    receipt = {"prompt": prompt, "seed": entry["seed"], **generation,
               "models": [QWEN_UNET, QWEN_CLIP, QWEN_VAE]}
    source = SOURCE / (entry["id"] + ".png")
    metadata = source.with_suffix(".json")
    if source.exists() and metadata.exists():
        old = json.loads(metadata.read_text(encoding="utf-8"))
        if all(old.get(key) == value for key, value in receipt.items()):
            return source
    print(f"GENERATE {entry['id']} RAM available={available_ram_gb():.2f} GiB, one image", flush=True)
    finished = threading.Event()
    observed_ram = []
    def observe() -> None:
        while not finished.is_set():
            free = available_ram_gb()
            observed_ram.append(free)
            gpu = ""
            try:
                with urllib.request.urlopen("http://127.0.0.1:8188/system_stats", timeout=1) as response:
                    stats = json.load(response)
                for device in stats.get("devices", []):
                    gpu += f" VRAM available={device.get('vram_free', 0) / 2**30:.2f}/{device.get('vram_total', 0) / 2**30:.2f} GiB"
            except (OSError, ValueError):
                pass
            print(f"MEMORY RAM available={free:.2f} GiB{gpu}", flush=True)
            finished.wait(3)
    observer = threading.Thread(target=observe, daemon=True)
    observer.start()
    try:
        generated = qwen(prompt, w=generation["width"], h=generation["height"],
                         steps=generation["steps"], seed=entry["seed"],
                         prefix="world_" + entry["id"], retries=1)
    except Exception:
        stop_server()  # never leave a failed model consuming RAM/VRAM
        raise
    finally:
        finished.set()
        observer.join(timeout=2)
    SOURCE.mkdir(parents=True, exist_ok=True)
    # Copy encoded bytes instead of decoding another image beside the client's image.
    source.write_bytes(generated[0].read_bytes())
    receipt["source_sha256"] = hashlib.sha256(source.read_bytes()).hexdigest()
    receipt["ram_available_after_gb"] = round(available_ram_gb(), 3)
    receipt["minimum_observed_ram_gb"] = round(min(observed_ram), 3) if observed_ram else None
    metadata.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return source


def process(source: Path, entry: dict, cfg: dict) -> None:
    from PIL import Image
    with Image.open(source) as original:
        rgba = original.convert("RGBA")
    alpha = rgba.getchannel("A")
    if alpha.getextrema()[0] > 5:
        raise ValueError(f"{entry['id']}: generated source has no native transparency; reject it")
    box = alpha.point(lambda value: 255 if value >= 32 else 0).getbbox()
    if box is None:
        raise ValueError(f"{entry['id']}: empty generated silhouette")
    cropped = rgba.crop(box)
    side = int(cfg["texture_size"])
    cropped.thumbnail((side - 16, side - 16), Image.Resampling.LANCZOS)
    sprite = Image.new("RGBA", (side, side))
    sprite.alpha_composite(cropped, ((side - cropped.width) // 2, (side - cropped.height) // 2))
    OUT.mkdir(parents=True, exist_ok=True)
    sprite.save(OUT / (entry["id"] + ".png"), optimize=True)
    # Neutral base sprite; pickup recognition is handled separately from material emission.
    # This prevents a whole medical pack or sheet of paper becoming a glowing white shape.
    Image.new("RGBA", (side, side)).save(OUT / (entry["id"] + "_glow.png"), optimize=True)
    print(f"PROCESSED {entry['id']} {side}x{side}, logical {cfg['logical_size']}x{cfg['logical_size']}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", nargs="*", default=[])
    parser.add_argument("--no-gen", action="store_true")
    args = parser.parse_args()
    cfg = json.loads(CFG.read_text(encoding="utf-8"))
    entries = [entry for entry in cfg["items"] if not args.only or entry["id"] in args.only]
    if args.only and set(args.only) - {entry["id"] for entry in entries}:
        raise ValueError("Unknown world item id")
    try:
        for entry in entries:
            source = SOURCE / (entry["id"] + ".png") if args.no_gen else generate(entry, cfg)
            process(source, entry, cfg)
    finally:
        if not args.no_gen:
            stop_server()


if __name__ == "__main__":
    main()
