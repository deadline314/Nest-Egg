# Eye source-coordinate review

These PNGs are diagnostics over the existing original native 832×1216 RGBA heads. They show a source-window overview and a nearest-neighbor eye crop with source-coordinate axes; the overlays are location annotations only. No character pixels, original sources, published PNGs, rig, runtime, or ticket were modified.

`manifest.json` records the original source path and SHA-256, exact review crop, visible-eye polygon, upper/lower lid traces, excluded neighboring features, confidence, and mapping aliases. Rin and Mei reuse the existing blink coordinates in their ComfyUI specs and were checked against their source pixels. `repairer` is repairman_chen; `granny` is ah_po. A one-eye count is appropriate for the profile head drawings; hidden far eyes were not inferred.

Open `<id>-contact.png` to see the overview and detailed crop. Green marks the candidate eye region, red the upper-lid trace, and cyan the lower-lid trace. Coordinates remain native source pixels; only the displayed diagnostics are enlarged, using nearest-neighbor sampling. Markings are manual source-coordinate review, not generated eyelids or blink frames.

Run `python build_contact_sheets.py` to regenerate all review images. Run `python self_check.py` to verify original-source hashes, native RGBA dimensions, coordinate/crop bounds, nontransparent pixels under the eye polygons, gray compositing, invalid-ID rejection, and byte-identical reruns. This review does not establish blink-art quality, runtime integration, full animation behavior, or the 30-second stage acceptance.

## Coordinate findings

| Character/source | Visible eye | Confidence / limitation |
| --- | --- | --- |
| Rin | One profile eye; existing spec quad reused | High; the existing spec box includes a small margin below the visible lid |
| Mei | One eye; existing spec quad reused | High; hair fully obscures the far eye |
| old_k | One profile eye | Medium-high; nearby age/shadow pixels border the lower lid |
| nurse | One profile eye | High; eyebrow and lower-eye bag excluded |
| night_worker | One eye under hardhat | Medium-high; hardhat shadow borders the upper lid |
| repairer / repairman_chen | One profile eye | Medium-high; nearby wrinkle excluded from the lower lid trace |
| resident | One profile eye | High |
| granny / ah_po | One profile eye | Medium; wrinkles closely border the lower lid |
| wataru | One eye partly covered by long fringe | Medium; visible contour only, occluded pixels not inferred |
