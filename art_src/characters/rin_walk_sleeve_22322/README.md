# Rin walk sleeve 22322 — source attachment, not adopted

One complete navy upper-arm sleeve, with the original pocket, button and magenta tab,
was generated from the IG01 native source crop `[320,200,704,712)` at 384×512.
This separate source contains no character head, hair, skin, hand or mechanical forearm.
The approved s33 standing illustration and all runtime assets remain unchanged.

The Qwen reference edit used seed 22322, 25 steps and resolution 0. The actual RGBA
reference is joined before encoding; `executed.graph.json`, `generation.json` and
the unmodified `raw/source.png` retain the request and actual output. This is a new
sleeve attachment; it is not a byte-exact copy of the old visible sleeve and has
not passed shoulder/cuff alignment. The actual model output has 90,308 alpha-1
background pixels despite its transparent prompt and RGBA mode.

SAM was run on a separate native gray composite. Its original mask truncates 524
material-core edge pixels and is rejected. `selection.json` retains the explicit
reviewed two-pixel expansion and four low-alpha cuff-edge coordinates; no material RGB is repainted, no global alpha floor is applied, and no canvas is resized.
The rebuilt 181×311 crop retains 34,835 source pixels in one connected sleeve.
The original mask, raw alpha and executed SAM graph remain available for comparison.

Native Forward+ capture additionally revealed unintended transparency through the
solid navy cuff (sample alpha 188/189). The explicitly reviewed cuff polygon and
SAM interior restore 1,952 material alpha values to 255; `cuff-opacity-mask.png`
records exactly these material coordinates. Outer antialias pixels and all retained
RGB remain unchanged. The raw generated PNG is never modified. The rejected native
capture is retained in the NE-222 evidence packet.

```powershell
& '<Python with Pillow, NumPy and OpenCV>' art_src/characters/rin_walk_sleeve_22322/build.py
```

The builder checks source hashes, full core retention, semantic points, connectivity,
native dimensions and exact retained RGB / unchanged outer alpha. Thirteen negative controls reject the
narrow SAM mask and deliberate one-pixel material deletion/background insertion.
This source check does not establish anatomy, dynamic seams, normals/glow, damage
variants, gameplay feel or acceptable walking. Those remain NE-222 gates.

The pose-specific attachment workflow follows [Spine's new-pose tutorial](https://esotericsoftware.com/blog/Rigging-new-poses-tutorial)
and [mesh binding guidance](https://esotericsoftware.com/blog/Mesh-binding-tutorial).
Runtime binding continues through the project's existing pose-slot pipeline;
this source is not registered there yet.
