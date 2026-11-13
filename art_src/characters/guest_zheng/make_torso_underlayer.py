"""One native cropped cloth-underlayer candidate; run through run_parts --torso."""
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
BOX = (256, 224, 768, 736)
SEED = 433
PROMPT = (
    "This is an RGBA image with transparency. Edit only the upper side panel of the ochre-brown canvas work jacket. "
    "The near arm has been removed for a separate animation layer. Replace the large circular armhole, the concentric black oval rim "
    "and the featureless flat oval with continuous worn ochre canvas cloth across the torso beneath the moving arm. "
    "Draw a few purposeful angular cel-shaded cloth folds following the side of the chest and armpit, subtle worn canvas grain "
    "and irregular hand-inked linework matching the surrounding jacket. This is closed cloth, not a hole or a shoulder socket. "
    "No arm, no sleeve, no hand, no round rim, no flat oval patch, no armour, no ornament, no new pocket. "
    "Preserve the collar, lapel, front grey shirt, original front pocket, jacket silhouette, waist seam, composition and scale. "
    "Keep flat muted colours and hard two-tone shading, matte fabric, no glow, no airbrush gradient. "
    "Keep the exact native crop dimensions and transparent outside silhouette."
)


def main():
    import comfy_api
    folder = WORK / "torso_underlayer"
    raw = folder / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    (raw / ".gdignore").touch()
    reference = raw / "reference.png"
    stage = WORK / "04_stages/P.png"
    image = Image.open(stage)
    if image.mode != "RGBA" or image.size != (1024, 1536):
        raise ValueError("Torso reference requires the retained native RGBA stage")
    image.crop(BOX).save(reference)
    comfy_api.OUT = raw
    made = comfy_api.qwen(PROMPT, images=[str(reference)], w=512, h=512, resolution=0,
                          seed=SEED, prefix="guest_zheng_torso_underlayer_s433",
                          retries=1, cache_device="off")[0]
    candidate = Image.open(made)
    if candidate.mode != "RGBA" or candidate.size != (512, 512):
        raise ValueError("Reject wrong native torso output; never resize or add an opaque alpha channel")
    if candidate.getextrema()[0] == (0, 0):
        raise ValueError("Reject failed all-black torso output without a second model attempt")
    spec = json.loads((ROOT / "tools/comfyui/specs/guest_zheng_side.json").read_text(encoding="utf8"))
    region = next(e["poly"] for e in spec["refine"]["inpaint"] if e["part"] == "torso")
    mask = Image.new("L", image.size)
    ImageDraw.Draw(mask).polygon([tuple(p) for p in region], fill=255)
    mask = mask.filter(ImageFilter.MaxFilter(17))
    mask = mask.filter(ImageFilter.GaussianBlur(3))
    # The candidate remains unadopted until native-pixel review. This full-canvas
    # source is only RGB within the authored mask; actual part alpha stays separate.
    values = np.array(image)
    edited = values.copy()
    edited[BOX[1]:BOX[3], BOX[0]:BOX[2], :3] = np.array(candidate)[:, :, :3]
    weight = np.array(mask, dtype=np.float32)[:, :, None] / 255
    result = values.copy()
    result[:, :, :3] = np.rint(edited[:, :, :3] * weight + values[:, :, :3] * (1 - weight)).astype("uint8")
    assert np.array_equal(result[:, :, 3], values[:, :, 3])
    assert np.array_equal(result[np.array(mask) == 0], values[np.array(mask) == 0])
    patch = Image.fromarray(result)
    patch.save(folder / "candidate_full_canvas.png")
    mask.save(folder / "reviewed_region_candidate.png")
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    receipt = dict(classification="unadopted local torso RGB candidate, not a new pose or an edit to the original source",
                   source=stage.relative_to(ROOT).as_posix(), source_sha256=digest(stage),
                   reference=reference.relative_to(ROOT).as_posix(), reference_sha256=digest(reference),
                   generated=made.relative_to(ROOT).as_posix(), generated_sha256=digest(made),
                   native_crop=list(BOX), requested_resolution=0, actual_size=list(candidate.size),
                   prompt=PROMPT, seed=SEED, generation_provider="shared existing ComfyUI service",
                   proposed_source_polygon=region, mask_dilate_source_pixels=8, mask_gaussian_sigma=3,
                   alpha_exact=True, outside_saved_mask_exact=True, adopted=False)
    (folder / "candidate.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8")
    print("Torso native candidate saved; not adopted")


if __name__ == "__main__":
    main()
