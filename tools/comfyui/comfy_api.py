"""ComfyUI API client for Nest Egg art (Qwen Image 2.1 Uncensored, int8).

Requires a running ComfyUI server (launch command: design/03-art-pipeline/ART_PIPELINE.md section 5).
Usage:
    from comfy_api import qwen
    qwen("prompt", w=832, h=1216, seed=1, prefix="rin")                 # text-to-image
    qwen("prompt", images=["pose.png", "ref.png"], prefix="rin_pose")   # edit / reference mode
Outputs go to ./out next to this file (override with the OUT_DIR env var).
"""
import json
import os
import random
import time
import urllib.request
import uuid
from pathlib import Path

HOST = os.environ.get("COMFY_HOST", "http://127.0.0.1:8188")
OUT = Path(os.environ.get("OUT_DIR", Path(__file__).parent / "out"))

QWEN_UNET = "qwen-image-2.1-UC-int8_convrot.safetensors"
QWEN_CLIP = "qwen3vl_8b_int8_convrot.safetensors"
QWEN_VAE = "qwen_image_2.1_vae_bf16.safetensors"


def _post(path, data):
    req = urllib.request.Request(HOST + path, json.dumps(data).encode(), {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req))


def _get(path):
    return urllib.request.urlopen(HOST + path).read()


def upload(path):
    """Upload a local image to the ComfyUI input folder; returns the stored name."""
    import requests
    with open(path, "rb") as f:
        r = requests.post(HOST + "/upload/image", files={"image": (Path(path).name, f, "image/png")}, data={"overwrite": "true"})
    r.raise_for_status()
    return r.json()["name"]


def run(graph, name):
    """Queue an API-format graph, wait for it, and download its images to OUT/<name>_<i>.png."""
    pid = _post("/prompt", {"prompt": graph, "client_id": str(uuid.uuid4())})["prompt_id"]
    while True:
        h = json.loads(_get(f"/history/{pid}"))
        if pid in h:
            break
        time.sleep(1)
    st = h[pid].get("status", {})
    if st.get("status_str") == "error":
        raise RuntimeError(json.dumps(st, ensure_ascii=False)[:2000])
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / ".gdignore").touch()  # keep Godot from importing generated images
    paths = []
    for node in h[pid]["outputs"].values():
        for i, im in enumerate(node.get("images", [])):
            data = _get(f"/view?filename={im['filename']}&subfolder={im['subfolder']}&type={im['type']}")
            p = OUT / f"{name}_{i}.png"
            p.write_bytes(data)
            paths.append(p)
    return paths


def qwen(prompt, w=1024, h=1024, steps=25, seed=None, prefix="qwen", images=(), resolution=1024, retries=4):
    """Text-to-image, or edit mode when reference images (local paths) are given.

    Intel Arc occasionally returns an all-black (NaN) image; it is detected and regenerated with seed+1.
    """
    from PIL import Image
    names = [upload(p) for p in images]
    paths = []
    for attempt in range(retries):
        s = (seed if seed is not None else random.randint(0, 2**31)) + attempt
        g = {
            "1": {"class_type": "UNETLoader", "inputs": {"unet_name": QWEN_UNET, "weight_dtype": "default"}},
            # Cache on system RAM: "auto" pushes a 12 GB card over its VRAM limit (160 s/step instead of 2 s).
            "1c": {"class_type": "QwenImage21Cache", "inputs": {"model": ["1", 0], "device": "cpu", "dtype": "default"}},
            "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": QWEN_CLIP, "type": "qwen_image", "device": "default"}},
            "3": {"class_type": "VAELoader", "inputs": {"vae_name": QWEN_VAE}},
            "4": {"class_type": "TextEncodeQwenImage21", "inputs": {"clip": ["2", 0], "prompt": prompt, "negative_prompt": "",
                                                                    "vae": ["3", 0], "resolution": resolution}},
            "5": {"class_type": "EmptyLatentImage", "inputs": {"width": w, "height": h, "batch_size": 1}},
            "6": {"class_type": "KSampler", "inputs": {"model": ["1c", 0], "positive": ["4", 0], "negative": ["4", 1], "latent_image": ["5", 0],
                                                       "seed": s, "steps": steps, "cfg": 1.0, "sampler_name": "euler", "scheduler": "simple", "denoise": 1.0}},
            "7": {"class_type": "VAEDecode", "inputs": {"samples": ["6", 0], "vae": ["3", 0]}},
            "8": {"class_type": "SaveImage", "inputs": {"images": ["7", 0], "filename_prefix": prefix}},
        }
        for i, name in enumerate(names):
            g[f"L{i}"] = {"class_type": "LoadImage", "inputs": {"image": name}}
            g["4"]["inputs"][f"images.image_{i + 1}"] = [f"L{i}", 0]
        if names:
            # Edit mode: sample on the latent sized like the first reference image.
            g["6"]["inputs"]["latent_image"] = ["4", 2]
            del g["5"]
        paths = run(g, prefix)
        if Image.open(paths[0]).getextrema()[0] != (0, 0):
            return paths
        print(f"  black output, retry {attempt + 1}", flush=True)
    return paths
