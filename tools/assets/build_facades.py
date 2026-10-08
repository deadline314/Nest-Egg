"""Paint the building facade modules in cel style and patch the facade data (BG-2; replaces the NE-57 / NE-59 model renders).

Usage: python tools/assets/build_facades.py [--only ID ...]

Reads assets_src/pipeline/facades.json and paints every module with cel_facade.py / decor.py (flat colours, ink lines,
hard two-tone shadows, chamfered octagon windows; no external art needed). A module is one of
  ground: storefront / garage / door (64 x 40 logical px)   body: standard floor (64 x 32)   cap: roof edge with clutter (64 x 8)
and is written as art/environment/facades/<id>_g<i>|_b<i>|_cap<i>.png with _n.png (normals, from the painted heights) and _glow.png
(window light, LEDs, beacons) at texture_scale pixels per logical px. Then data/environment/facades/<id>.tres gets its ground /
body / cap arrays rewritten, so the number of variants is whatever the JSON lists.

facades.json, per facade:
  id, light_chance, light_colors, pal {...}      palette (hex); keys in cel_facade.DEFAULT_PAL; "tones" is a list of wall tones
  wall {"kind": plaster|brick|corrugated|slab|panel|curtain, ...painter parameters}
  window {cols, rows, w, h, y, chamfer, panes [c, r], frame, sill, grill, blind, glare, row_gap, margin}   defaults for every body module
  decor  {pipe, pipe_x [logical px], ac, balcony, led, traces, camera...}        chances / counts, can also be set per variant
  body / ground / cap  lists of variant dicts; each is deep-merged over the facade defaults (window, wall, decor) and so
                       can change the layout. ground variants hold "items": [{"t": shutter|door|shop|vent, "cx", "w", "h", ...}]
                       cap variants hold {"kind": parapet|saw|pediment|stepped, "clutter": ["antenna", "vent", "dish", "tank", "mast"]}
Every body module has at least one lit window (the data promises a glow layer). Fixed random seed per module name, so a
rebuild gives the same picture. Lit windows are lit as a whole in a colour from light_colors scaled by light_gain (big bright
windows next to the player flatten dark-scene readability).
"""
import argparse
import copy
import json
import random
import re
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cel_facade as cf  # noqa: E402
import decor  # noqa: E402
import grade as grade_lib  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
PIPELINE = ROOT / "assets_src" / "pipeline" / "facades.json"
OUT = ROOT / "art" / "environment" / "facades"
DATA = ROOT / "data" / "environment" / "facades"
MODULE_W = 64.0
HEIGHTS = {"ground": 40.0, "body": 32.0, "cap": 8.0}
SUFFIX = {"ground": "g", "body": "b", "cap": "cap"}
PLINTH = 3.0


def deep_merge(base: dict, over: dict) -> dict:
    out = copy.deepcopy(base)
    for k, v in over.items():
        out[k] = deep_merge(out[k], v) if isinstance(v, dict) and isinstance(out.get(k), dict) else copy.deepcopy(v)
    return out


def chance(rng: random.Random, value) -> bool:
    """decor entries are booleans or probabilities."""
    if value is True:
        return True
    return bool(value) and rng.random() < float(value)


def paint_decor(c: cf.Canvas, p: dict, rng: random.Random, d: dict, colors: list, lit_boxes: list, boxes: list) -> None:
    u, W, H = c.u, c.w, c.h
    for b in boxes:  # things hung under windows
        if chance(rng, d.get("balcony", 0)) and b[3] + 1.0 * u + 3.0 * u < H - 2.6 * u:
            decor.balcony(c, p, b[0] - 0.8 * u, b[2] + 0.8 * u, b[3] + 2.4 * u)
        elif chance(rng, d.get("ac", 0)) and b[3] + 3.4 * u + 4.5 * u < H - 2.4 * u:
            decor.ac_unit(c, p, (b[0] + b[2]) / 2 - 3.5 * u, b[3] + 3.4 * u)
    if chance(rng, d.get("pipe", 0)):  # one pipe per module, in a gap between windows or at the module edge
        spots = [1.2 * u, W - 3.4 * u] + [(a[2] + b[0]) / 2 - 1.1 * u for a, b in zip(boxes, boxes[1:]) if b[0] > a[2]]
        rng.shuffle(spots)
        for x in spots:
            if c.is_free(x - 0.6 * u, 0, x + 3.0 * u, H):
                decor.pipe_run(c, p, x)
                break
    if d.get("traces"):
        decor.circuit_traces(c, p, rng, colors, int(d["traces"]))
    if chance(rng, d.get("led", 0)):
        decor.led_row(c, p, rng, colors)
    if chance(rng, d.get("camera", 0)):
        decor.wall_camera(c, p, rng.uniform(0.1, 0.8) * W, rng.uniform(0.08, 0.2) * H)
    if chance(rng, d.get("lamp", 0)):
        decor.emergency_lamp(c, p, rng.uniform(0.1, 0.8) * W, rng.uniform(0.1, 0.25) * H)


def build_body(e: dict, v: dict, name: str, k: int):
    rng = random.Random(zlib.crc32(name.encode()))
    p = cf.pal_of(e)
    c = cf.Canvas(int(MODULE_W * k), int(HEIGHTS["body"] * k), k, p["ink"], rng)
    cf.paint_wall(c, p, v["wall"])
    spec = v["window"]
    boxes, lit = cf.window_grid(c, p, spec, rng, e["light_colors"], float(e["light_chance"]), float(e["light_gain"]), float(spec.get("y", 0.44)))
    cf.floor_edges(c, p)
    paint_decor(c, p, rng, v.get("decor", {}), e["light_colors"], lit, boxes)
    return c


def build_ground(e: dict, v: dict, name: str, k: int):
    rng = random.Random(zlib.crc32(name.encode()))
    p = cf.pal_of(e)
    c = cf.Canvas(int(MODULE_W * k), int(HEIGHTS["ground"] * k), k, p["ink"], rng)
    cf.paint_wall(c, p, v["wall"])
    cf.floor_edges(c, p, top_shadow=True, bottom_ledge=False)
    H = c.h
    bottom = H - PLINTH * k
    colors, gain = e["light_colors"], float(e["light_gain"])

    def color(scale: float = 1.0):
        return cf.lit_color(rng, colors, gain * scale)

    for it in v.get("items", []):
        t, cx, w = it["t"], float(it["cx"]) * k, float(it["w"]) * k
        h = float(it.get("h", 22)) * k
        g = float(it.get("gain", 0.7))  # big ground-floor lights are dimmer than a floor of small windows
        lit = color(g) if rng.random() < float(it.get("lit", e["light_chance"])) else None
        if t == "shutter":
            lamp = color(1.0) if it.get("lamp") else None
            cf.shutter(c, p, cx, w, bottom - h, bottom, bool(it.get("hazard")), lamp)
        elif t == "door":
            cf.door(c, p, cx, w, bottom - h, bottom, lit, color(1.0) if it.get("sign") else None)
        elif t == "shop":
            awning = cf.hexc(it["awning"]) if it.get("awning") else None
            cf.shop_window(c, p, cx, w, bottom - h, bottom - float(it.get("sill", 3.0)) * k, lit or color(g), rng, awning)
        elif t == "vent":
            cf.vent_grate(c, p, cx, w, bottom - h, bottom - float(it.get("sill", 4.0)) * k)
        elif t == "window":
            spec = deep_merge(e["window"], it.get("window", {}))
            spec.update({k2: it[k2] for k2 in ("w", "h", "panes", "chamfer") if k2 in it})
            y0 = bottom - h - float(it.get("sill", 7.0)) * k
            cf.window(c, p, (cx - w / 2, y0, cx + w / 2, y0 + h), spec, lit, rng)
        else:
            raise KeyError(f"{name}: unknown ground item '{t}'")
    cf.plinth(c, p, bottom)
    d = v.get("decor", {})
    if chance(rng, d.get("hazard", 0)):
        decor.hazard_band(c, p, bottom + 0.9 * k, H - 0.5 * k)
    paint_decor(c, p, rng, {kk: vv for kk, vv in d.items() if kk != "ac" and kk != "balcony"}, colors, [], [])
    return c


def build_cap(e: dict, v: dict, name: str, k: int):
    rng = random.Random(zlib.crc32(name.encode()))
    p = cf.pal_of(e)
    c = cf.Canvas(int(MODULE_W * k), int(HEIGHTS["cap"] * k), k, p["ink"], rng, transparent=True)
    cf.cap_module(c, p, v, rng)
    return c


BUILDERS = {"body": build_body, "ground": build_ground, "cap": build_cap}


def variant_spec(e: dict, kind: str, v: dict) -> dict:
    base = {"wall": e.get("wall", {}), "window": e.get("window", {}), "decor": (e.get("decor") or {}).get(kind, {})}
    return deep_merge(base, v)


def write_module(e: dict, kind: str, i: int) -> str:
    k = int(e["texture_scale"])
    name = f"{e['id']}_{SUFFIX[kind]}{i}"
    v = variant_spec(e, kind, e[kind][i])
    c = BUILDERS[kind](e, v, name, k)
    color, normal, glow = c.finish(float(e.get("normal_strength", 4.0)), max(0.8, k * 0.2))
    if kind == "body" and not glow.getbbox():
        raise ValueError(f"{name}: no lit window")
    OUT.mkdir(parents=True, exist_ok=True)
    color = grade_lib.grade_image(color, "facade")
    color.save(OUT / f"{name}.png", optimize=True)
    normal.save(OUT / f"{name}_n.png", optimize=True)
    glow_path = OUT / f"{name}_glow.png"
    if glow.getbbox():
        glow.save(glow_path, optimize=True)
    elif glow_path.exists():
        glow_path.unlink()
    return name


def remove_stale(e: dict, counts: dict[str, int]) -> None:
    """Delete variants of this facade that the JSON no longer lists (the .png.import files stay: Godot cleans them)."""
    for kind, n in counts.items():
        for path in OUT.glob(f"{e['id']}_{SUFFIX[kind]}[0-9]*.png"):
            m = re.fullmatch(rf"{re.escape(e['id'])}_{SUFFIX[kind]}(\d+)(_n|_glow)?\.png", path.name)
            if m and int(m.group(1)) >= n:
                path.unlink()


def patch_tres(e: dict, names: dict[str, list[str]]) -> None:
    path = DATA / f"{e['id']}.tres"
    raw = path.read_bytes().decode("utf-8")
    eol = "\r\n" if "\r\n" in raw else "\n"  # keep the file's own line ending
    text = raw.replace("\r\n", "\n")
    for kind in ("ground", "body", "cap"):
        paths = ", ".join(f'"res://art/environment/facades/{n}.png"' for n in names[kind])
        text = re.sub(rf"^{kind} = PackedStringArray\(.*\)$", lambda m, k=kind, v=paths: f"{k} = PackedStringArray({v})", text, flags=re.M)
    path.write_bytes(text.replace("\n", eol).encode("utf-8"))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=[])
    args = ap.parse_args()
    cfg = json.loads(PIPELINE.read_text(encoding="utf-8"))
    failed = 0
    for spec in cfg["facades"]:
        if args.only and spec["id"] not in args.only:
            continue
        e = {**cfg["defaults"], **spec}
        try:
            if not (DATA / f"{e['id']}.tres").exists():
                raise FileNotFoundError(f"{e['id']}.tres not found")
            names = {kind: [write_module(e, kind, i) for i in range(len(e[kind]))] for kind in ("ground", "body", "cap")}
            remove_stale(e, {kind: len(names[kind]) for kind in names})
            patch_tres(e, names)
            print(f"ok    {e['id']:14} ground {len(names['ground'])} body {len(names['body'])} cap {len(names['cap'])}  [{e['wall']['kind']}]")
        except Exception as ex:  # one bad facade must not block the rest
            failed += 1
            print(f"FAIL  {spec.get('id')}: {ex!r}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    from texture_import import finish_pipeline
    sys.exit(finish_pipeline(main()))
