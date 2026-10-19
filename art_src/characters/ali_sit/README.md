# Ali seated part source

This adds a seated trouser thigh and a pose-specific pelvis ownership mask. It preserves the approved standing source, every original runtime PNG and the canonical bone lengths. The generated seated identity reference and isolated trouser source are retained in `01_design`, with exact prompts and actual provider metadata in `generation.json`; no local Comfy/SAM run or reproducible seed is claimed.

`PYTHONPATH=<opencv environment> python art_src/characters/ali_sit/register.py --publish` registers the isolated source on the original hip and knee, calibrates trouser colour against the existing opaque thigh, and uses the existing cutter's density/transform. It is not a new high-resolution illustration. Source hashes fail before runtime writes. The new source has no front-leg embellishments to duplicate onto the far side.

The standing pelvis includes a round grey trouser cap. During sit, retaining this cap over the seated thigh produced a hanging ball even after two changes to thigh registration. Sit now assigns those trouser pixels to its thigh and retains the original mint shirt texels and three pixels of its original hem outline. This is a recorded source ownership mask, not painted-in body pixels. The near thigh uses pose-local draw order behind the pelvis; stand retains its existing order. Both replacement sprites are validated as a complete pose set.

Build the matching normals with `Godot --headless --path . res://tools/art/paint_normals.tscn -- --only=ali`, then import normally. Rebuilds of the seated runtime are byte-identical; the corrupt-source negative control retains the prior delivery. Native sitting, standing, both-facing pose sheets, full-colour transition sheets and the unaltered alpha joint checker remain separate checks. Rejected v1–v3 sources, renders and diagnostics are retained with the ticket evidence.

Source directories are excluded from Godot import via `.gdignore`; the Python recipe still reads their original files. Only the delivered runtime parts and matching normals carry import records. Source PNGs, masks and provenance are preserved.
