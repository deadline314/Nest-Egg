"""One command from a character recipe to a character running in Godot.

    D:/ComfyUI/.venv/Scripts/python.exe tools/comfyui/build_character.py --recipe tools/comfyui/recipes/rin.json [--from parts] [--to preview]
    ... --list                      print this page
    ... --only design --seed 34     one step only (e.g. try another design seed; then --from parts)
    ... --force                     regenerate pictures that already exist (Qwen steps are skipped when their output exists)

Full description with pictures: design/03-art-pipeline/CHARACTER_PIPELINE.md. `work` = recipe["work"] (art_src/characters/<id>/).

  step      tool                       input                                          output
  design    Qwen Image 2.1 (RGBA)      recipe.design.prompt                           work/01_design/design_s<seed>.png, work/base_rgba.png (transparent side view)
  pose      SAM 3D Body                work/base_rgba.png                             work/keypoints.json, work/02_pose/overlay.png   (reference for the joints in the spec)
  parts     SAM 3.1 + Qwen (peeling)   work/base_rgba.png, spec.groups / stages      work/sam/, work/04_stages/{A,B}.png, work/05_groups/*, work/06_parts/<part>.png
  textures  cut_layers.py              work/06_parts/*.png, spec.joints / bones       art/characters/<id>/parts/*.png (+_glow), character.json, art/rigs/<rig>.json
  normals   Godot paint_normals        art/characters/<id>/parts/*.png                parts/*_n.png
  import    Godot --editor --quit      art/characters/<id>                            .godot/imported (the engine sees the new PNGs)
  preview   Godot rig_preview          art/characters/<id>                            work/08_preview/{poses,closeup,head,damage}.png

Hand-fixed textures: put a PNG with the SAME size as the generated part into work/overrides/<part>.png; it is copied over
art/characters/<id>/parts/ after `textures`, so re-running never loses it.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
STEPS = ["design", "pose", "parts", "textures", "normals", "import", "preview"]
COMFY_DIR = Path(os.environ.get("COMFYUI_DIR", "D:/ComfyUI"))
GODOT = os.environ.get("GODOT", "C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe")


def log(msg: str) -> None:
    print(msg, flush=True)


def rel(path: Path) -> str:
    try:
        return str(Path(path).relative_to(ROOT))
    except ValueError:
        return str(path)


def ensure_comfy() -> None:
    """Make sure the ComfyUI server answers; start it from COMFYUI_DIR when it does not."""
    host = os.environ.get("COMFY_HOST", "http://127.0.0.1:8188")
    try:
        urllib.request.urlopen(host + "/system_stats", timeout=3)
        return
    except Exception:
        pass
    py = COMFY_DIR / ".venv/Scripts/python.exe"
    if not py.exists():
        sys.exit(f"ComfyUI is not running and {py} does not exist. Start it (ART_PIPELINE.md section 5) or set COMFYUI_DIR.")
    log("starting ComfyUI ...")
    subprocess.Popen([str(py), "main.py", "--listen", "127.0.0.1", "--port", "8188", "--disable-auto-launch"], cwd=COMFY_DIR,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    for _ in range(120):
        time.sleep(2)
        try:
            urllib.request.urlopen(host + "/system_stats", timeout=3)
            return
        except Exception:
            continue
    sys.exit("ComfyUI did not come up within 4 minutes.")


def run(cmd: list[str], what: str) -> str:
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        sys.exit(f"[{what}] failed:\n{(r.stderr or r.stdout)[-2500:]}")
    return r.stdout


def godot(*args: str) -> str:
    r = subprocess.run([GODOT, "--path", str(ROOT), *args], cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout + r.stderr


class Build:
    def __init__(self, recipe_path: Path, force: bool, seed: int | None) -> None:
        self.recipe = json.loads(recipe_path.read_text(encoding="utf8"))
        self.id = self.recipe["id"]
        self.work = ROOT / self.recipe["work"]
        self.spec = ROOT / self.recipe["spec"]
        self.rig = ROOT / self.recipe["rig"]
        self.char_dir = ROOT / "art/characters" / self.id
        self.force, self.seed = force, seed
        self.work.mkdir(parents=True, exist_ok=True)
        (self.work / ".gdignore").touch()  # keep Godot from importing the source pictures
        os.environ["OUT_DIR"] = str(self.work / "_gen")
        sys.path.insert(0, str(HERE))
        self.manifest: list[dict] = []

    def need(self, path: Path, step: str) -> Path:
        if not path.exists():
            sys.exit(f"[{step}] missing input {rel(path)} - run the earlier step first")
        return path

    def step_design(self) -> list[Path]:
        ensure_comfy()
        from comfy_api import qwen
        d = self.recipe["design"]
        seed = self.seed or d["pick"]
        out_dir = self.work / "01_design"
        out_dir.mkdir(exist_ok=True)
        target = out_dir / f"design_s{seed}.png"
        base = self.work / "base_rgba.png"
        if target.exists() and not self.force:
            log(f"  keep {rel(target)}")
        else:
            t = time.time()
            prompt = "This is an RGBA image with transparency. " + d["prompt"] + " The image has alpha channel and the background is transparent."
            made = qwen(prompt, w=d["size"][0], h=d["size"][1], seed=seed, prefix=f"{self.id}_design_s{seed}")[0]
            shutil.copy(made, target)
            log(f"  made {rel(target)} ({time.time() - t:.0f}s)")
        if not base.exists() or self.force or self.seed:
            shutil.copy(target, base)
            log(f"  base_rgba.png <- {target.name}")
        return [target, base]

    def step_pose(self) -> list[Path]:
        out = self.work / "02_pose"
        out.mkdir(exist_ok=True)
        grey = self.work / "base_grey.png"
        from PIL import Image
        im = Image.open(self.need(self.work / "base_rgba.png", "pose")).convert("RGBA")
        bg = Image.new("RGBA", im.size, (128, 128, 128, 255))
        bg.alpha_composite(im)
        bg.convert("RGB").save(grey)
        run([sys.executable, str(HERE / "pose_keypoints.py"), "--image", str(grey), "--out", str(self.work / "keypoints.json"),
             "--overlay", str(out / "overlay.png")], "pose")
        return [self.work / "keypoints.json", out / "overlay.png"]

    def step_parts(self) -> list[Path]:
        self.need(self.work / "base_rgba.png", "parts")
        ensure_comfy()
        cmd = [sys.executable, str(HERE / "make_parts.py"), "--spec", str(self.spec), "--work", str(self.work)]
        log("  " + (run(cmd, "parts").strip().splitlines() or [""])[-1])
        return [self.work / "06_parts", self.work / "06_parts/ownership.png"]

    def step_textures(self) -> list[Path]:
        self.need(self.work / "06_parts", "textures")
        out = run([sys.executable, str(HERE / "cut_layers.py"), "--spec", str(self.spec), "--work", str(self.work),
                   "--char", str(self.char_dir), "--rig", str(self.rig)], "textures")
        log("  " + (out.strip().splitlines() or [""])[-1])
        n = 0
        for f in sorted((self.work / "overrides").glob("*.png")) if (self.work / "overrides").exists() else []:
            target = self.char_dir / "parts" / f.name
            from PIL import Image
            if not target.exists() or Image.open(f).size != Image.open(target).size:
                log(f"  WARN override {f.name} ignored (no such part, or a different size)")
                continue
            shutil.copy(f, target)
            n += 1
        if n:
            log(f"  applied {n} hand-made override(s)")
        return [self.char_dir / "character.json", self.rig, self.char_dir / "parts"]

    def step_normals(self) -> list[Path]:
        out = godot("--headless", "res://tools/art/paint_normals.tscn", "--", f"--only={self.id}")
        log("  " + (out.strip().splitlines() or [""])[-1])
        return [self.char_dir / "parts"]

    def step_import(self) -> list[Path]:
        godot("--headless", "--editor", "--quit")  # must come after `normals`, so the new *_n.png are imported too
        return [ROOT / ".godot"]

    def step_preview(self) -> list[Path]:
        out = self.work / "08_preview"
        out.mkdir(exist_ok=True)
        jobs = {"poses": [], "closeup": ["--closeup"], "head": ["--head"], "damage": ["--damage", "--zoom=4.2"]}
        for name, extra in jobs.items():
            text = godot("res://tools/rig_preview.tscn", "--", f"--out={out / (name + '.png')}", f"--chars={self.id}", *extra)
            if "ERROR" in text or "WARNING" in text:
                log(f"  WARN Godot reported problems while rendering {name} (run the preview by hand to read them)")
        return [out / f"{n}.png" for n in jobs]

    def run(self, steps: list[str]) -> None:
        for s in steps:
            t = time.time()
            log(f"[{s}]")
            outs = getattr(self, f"step_{s}")()
            self.manifest.append({"step": s, "seconds": round(time.time() - t, 1), "outputs": [rel(o) for o in outs]})
        (self.work / "manifest.json").write_text(json.dumps(self.manifest, ensure_ascii=False, indent=2), encoding="utf8")
        log(f"done. manifest: {rel(self.work / 'manifest.json')}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--recipe", default="tools/comfyui/recipes/rin.json")
    ap.add_argument("--from", dest="first", choices=STEPS, default=STEPS[0])
    ap.add_argument("--to", dest="last", choices=STEPS, default=STEPS[-1])
    ap.add_argument("--only", choices=STEPS)
    ap.add_argument("--seed", type=int, help="with design: make and pick this seed")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    if args.list:
        print(__doc__)
        return
    steps = [args.only] if args.only else STEPS[STEPS.index(args.first): STEPS.index(args.last) + 1]
    Build(Path(args.recipe), args.force, args.seed).run(steps)


if __name__ == "__main__":
    main()
