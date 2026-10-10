"""ComfyUI API client for Nest Egg art (Qwen Image 2.1 Uncensored, int8).

The server is started for you when it is down (tools/comfyui/start_comfyui.ps1), and a hung, crashed or out-of-memory
server is restarted and the job re-queued (tools/comfyui/comfy_guard.py explains what counts as stuck). A job that still
fails after COMFY_MAX_RETRIES restarts raises ComfyFailure and is appended to assets_src/work/comfy_failures.log.
Usage:
    from comfy_api import qwen
    qwen("prompt", w=832, h=1216, seed=1, prefix="rin")                 # text-to-image
    qwen("prompt", images=["pose.png", "ref.png"], prefix="rin_pose")   # edit / reference mode
Outputs go to ./out next to this file (override with the OUT_DIR env var).
"""
import hashlib
import json
import os
import random
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import comfy_guard  # noqa: E402
from comfy_guard import ComfyFailure, ComfyStalled  # noqa: E402,F401  (re-exported for callers)

HOST = os.environ.get("COMFY_HOST", "http://127.0.0.1:8188")
OUT = Path(os.environ.get("OUT_DIR", Path(__file__).parent / "out"))

QWEN_UNET = "qwen-image-2.1-UC-int8_convrot.safetensors"
QWEN_CLIP = "qwen3vl_8b_int8_convrot.safetensors"
QWEN_VAE = "qwen_image_2.1_vae_bf16.safetensors"


def _post(path, data, timeout=60):
    req = urllib.request.Request(HOST + path, json.dumps(data).encode(), {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=timeout))


def _get(path, timeout=30):
    """Every request has a timeout: a frozen server still accepts connections but never answers, and waiting forever is the hang."""
    return urllib.request.urlopen(HOST + path, timeout=timeout).read()


def upload(path):
    """Upload a local image to the ComfyUI input folder; returns the stored name."""
    import requests
    with open(path, "rb") as f:
        r = requests.post(HOST + "/upload/image", files={"image": (Path(path).name, f, "image/png")}, data={"overwrite": "true"}, timeout=60)
    r.raise_for_status()
    return r.json()["name"]


def _run_once(graph, name):
    """Queue the graph once and wait for it; raises ComfyStalled when the server hangs, dies or runs out of memory."""
    comfy_guard.ensure_server()
    client_id = str(uuid.uuid4())
    watch = comfy_guard.Watchdog(client_id)
    try:
        try:
            pid = _post("/prompt", {"prompt": graph, "client_id": client_id})["prompt_id"]
        except urllib.error.HTTPError as ex:  # the server rejected the graph itself: retrying cannot help
            raise RuntimeError(f"ComfyUI rejected the job: {ex.read().decode('utf-8', 'ignore')[:1500]}") from ex
        except OSError as ex:
            raise ComfyStalled(f"could not queue the job: {ex}") from ex
        ok = True
        while True:
            try:
                h = json.loads(_get(f"/history/{pid}", timeout=10))
                ok = True
            except (OSError, ValueError):
                h, ok = {}, False
            if pid in h:
                break
            watch.wait(2.0, ok)
    finally:
        watch.close()
    st = h[pid].get("status", {})
    if st.get("status_str") == "error":
        detail = json.dumps(st, ensure_ascii=False)[:2000]
        if comfy_guard.is_oom_text(detail):
            raise ComfyStalled(f"server reported out of memory: {detail[:200]}")
        raise RuntimeError(detail)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / ".gdignore").touch()  # keep Godot from importing generated images
    paths = []
    try:
        outputs = h[pid]["outputs"]
        savers = [key for key, node in outputs.items() if node.get("images")]
        for node_id, node in outputs.items():
            for i, im in enumerate(node.get("images", [])):
                data = _get(f"/view?filename={im['filename']}&subfolder={im['subfolder']}&type={im['type']}")
                suffix = f"_{node_id}" if len(savers) > 1 else ""
                p = OUT / f"{name}{suffix}_{i}.png"
                p.write_bytes(data)
                paths.append(p)
    except OSError as ex:
        raise ComfyStalled(f"server went away while downloading the result: {ex}") from ex
    return paths


def run(graph, name, retries=None):
    """Queue an API-format graph, wait for it, and download its images to OUT/<name>_<i>.png.

    A stuck server is restarted and the graph queued again, up to `retries` times (default COMFY_MAX_RETRIES); then
    ComfyFailure is raised and the job is logged. Errors in the graph itself (RuntimeError) are not retried.
    """
    retries = comfy_guard.MAX_RETRIES if retries is None else retries
    reasons = []
    with comfy_guard.server_lock():
        for attempt in range(retries + 1):
            try:
                return _run_once(graph, name)
            except ComfyStalled as ex:
                reasons.append(str(ex))
                print(f"  [comfy] {name}: {ex} (attempt {attempt + 1}/{retries + 1})", flush=True)
                if attempt < retries:
                    comfy_guard.restart_server(f"{name}: {ex}")
    raise ComfyFailure(comfy_guard.record_failure(name, reasons))


def _job_key(prompt, w, h, steps, seed, resolution, images):
    """Everything that decides the picture (same key = same image), so a finished job is never generated twice."""
    refs = [hashlib.sha1(Path(p).read_bytes()).hexdigest() for p in images]
    blob = json.dumps([QWEN_UNET, prompt, w, h, steps, seed, resolution, refs], ensure_ascii=False)
    return hashlib.sha1(blob.encode("utf-8")).hexdigest()


def qwen(prompt, w=1024, h=1024, steps=25, seed=None, prefix="qwen", images=(), resolution=1024, retries=4, reuse=True,
         cache_device="cpu", cache_dtype="default"):
    """Text-to-image, or edit mode when reference images (local paths) are given.

    Intel Arc occasionally returns an all-black (NaN) image; it is detected and regenerated with seed+1.
    With a fixed seed and reuse=True, an identical finished job (same prompt, size, steps, seed, references) is returned
    from OUT instead of generated again, so re-running a batch after a failure only does the unfinished jobs.
    cache_device="off" recomputes the reference prefix instead of retaining its
    KV cache in RAM. It trades sampling speed for memory; it does not unload
    model weights. The defaults preserve existing generation and cache keys.
    """
    if cache_device not in ("auto", "gpu", "cpu", "off"):
        raise ValueError(f"Unsupported Qwen cache device: {cache_device!r}")
    if cache_dtype not in ("default", "int8", "int4"):
        raise ValueError(f"Unsupported Qwen cache dtype: {cache_dtype!r}")
    from PIL import Image
    key = _job_key(prompt, w, h, steps, seed, resolution, images) if seed is not None else None
    if key and (cache_device, cache_dtype) != ("cpu", "default"):
        key = hashlib.sha1(json.dumps([key, cache_device, cache_dtype]).encode("utf-8")).hexdigest()
    meta = OUT / f"{prefix}.job.json"
    if reuse and key and meta.exists() and json.loads(meta.read_text(encoding="utf-8")).get("key") == key:
        cached = sorted(OUT.glob(f"{prefix}_[0-9].png"))
        if cached:
            print(f"  [comfy] {prefix}: already generated, reusing", flush=True)
            return cached
    comfy_guard.ensure_server()  # reference images are uploaded before the first job is queued
    names = [upload(p) for p in images]
    paths = []
    for attempt in range(retries):
        s = (seed if seed is not None else random.randint(0, 2**31)) + attempt
        g = {
            "1": {"class_type": "UNETLoader", "inputs": {"unet_name": QWEN_UNET, "weight_dtype": "default"}},
            # Cache on system RAM: "auto" pushes a 12 GB card over its VRAM limit (160 s/step instead of 2 s).
            "1c": {"class_type": "QwenImage21Cache", "inputs": {"model": ["1", 0], "device": cache_device, "dtype": cache_dtype}},
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
            if key:
                meta.write_text(json.dumps({"key": key, "seed": s}), encoding="utf-8")
            return paths
        print(f"  black output, retry {attempt + 1}", flush=True)
    return paths
