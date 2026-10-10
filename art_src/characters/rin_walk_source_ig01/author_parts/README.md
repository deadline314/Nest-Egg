# Reviewed visible hand and boot source cuts

The approved standing illustration and formal Rin parts remain unchanged. These two native cuts belong to the separate walk-source candidate; they are **not adopted or rigged**, and do not establish walk, full-body, seam, normal/glow, damage or gameplay acceptance.

`build.py` uses the explicit source-coordinate contours in `selection.json`, including the independently traced upper lace knot. SAM is not an ownership input. The metal thumb, fingers, wrist edge, boot cuff, heel, toe and complete magenta outsole have been reviewed against the original RGBA source. The output is one visible metal hand and one visible boot, with no neighboring limb or shoe.

| Cut | Source crop, exclusive maximum | Native PNG | Source pixels |
|---|---|---|---|
| Metal hand | `[341,711,436,841)` | 95×130 | 7,974 |
| Near boot | `[696,1243,928,1490)` | 232×247 | 35,059 |

The PNG dimensions are the tight crop of the material, not a resized copy of the whole 1037×1516 illustration. Every selected RGBA pixel is copied byte-for-byte; full-canvas masks preserve its source coordinates. No filtering, repainting, upscaling, alpha threshold or inferred hidden anatomy is applied.

Root inspected all 14 detached components on native black/gray/white context images. Their 16 pixels are all `[0,0,0,1]`, disconnected by 2.0–2.24 native pixels from the continuous material outline. They are faint source sampling halos outside the hand/boot, not lace, metallic details or outsole. Each exact coordinate and original RGBA is recorded in `selection.json`; only those pixels are excluded. Connected alpha-1 contour pixels are preserved. Some former point samples on the heel were these detached halos and are superseded by this explicit contour decision; the genuine outsole, cuff, thumb and foreign-owner controls remain independent.

Run from the repository root:

```powershell
D:/ComfyUI/.venv/Scripts/python.exe art_src/characters/rin_walk_source_ig01/author_parts/build.py
```

The source and liked standing SHA assertions, exact output readback and 13 one-pixel material-omission/foreign-owner controls passed. Two builds were byte-identical. The visible source crop alone does not supply hidden wrist/calf material or prove a moving attachment. The coat and remaining body parts must be authored and checked before assembling the walk pose set.

The method follows the [Spine new-pose workflow](https://esotericsoftware.com/blog/Rigging-new-poses-tutorial): preserve the existing rig, create the needed pose attachments, match their authored binds, then test weights and motion independently. This is an implementation choice for Nest Egg, not a claim that this static cut has passed that complete workflow.
