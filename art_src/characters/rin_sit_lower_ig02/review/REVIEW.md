# NE-222 — IG02 seated lower-body source-only comparison

**Disposition: remain candidate / NOT ADOPTED / NOT ACCEPTED.** This is a pixel-level review of two source PNGs only. It does not approve cutouts, anatomical part ownership, binding, posed movement, or any formal character replacement.

## Inputs and integrity

| Source | Canvas | SHA-256 |
|---|---:|---|
| IG01 `rin_sit_lower_ig01/raw/source.png` | 1037×1516 RGBA | `8115265f8ca9e0dbb554c172a8a39f70148b5ab700b3cfd639f4abb690ea9550` |
| IG02 `rin_sit_lower_ig02/raw/source.png` | 1037×1516 RGBA | `4d6f40cabb7854071d5b7be71bf2185089e425043c1da0adbc7e1cf29bffc520` |

Hashes were re-read after producing diagnostics and still match. IG02 `source.json` says `CANDIDATE_NOT_ADOPTED_OR_ACCEPTED`, provider `builtin image_gen edit`; `model`, `seed`, and `workflow` are null, so no more specific generation receipt is established.

## Target appearance

At the requested half-open target ROI `[85,284,224,568)` (39,476 pixels), the wide faceted/dark band visible across the posterior in IG01 appears removed/smoothed in IG02. The adjacent broad hip view still shows a diagonal crease-like shadow toward the right/lower thigh junction. From these pixels alone, I cannot verify the “no new cel-shading crease” criterion; that remains a review item rather than a pass.

The broad hip ROI `[65,250,380,575)` also retains one continuous rounded hip/buttock volume in the visible crop. This is only a 2D appearance observation. Occluded anatomy and near/far leg ownership remain unknown.

## Exact pixel change counts

Boxes below use half-open `[x0,y0,x1,y1)` coordinates; inclusive-xyxy robustness counts are in `pixel_diff_metrics.json`.

| Region | Pixels | Changed pixels | Changed RGBA components | Alpha-changed pixels | RGB-changed pixels |
|---|---:|---:|---:|---:|---:|
| Target ROI `[85,284,224,568)` | 39,476 | 35,930 | 110,654 | 5,155 | 35,445 |
| Outside target ROI | 1,532,616 | 451,667 | 1,430,821 | 143,109 | 438,740 |
| Broad hip ROI `[65,250,380,575)` | 102,375 | 91,267 | 283,739 | 17,085 | 90,098 |
| Outside broad hip ROI | 1,469,717 | 396,330 | 1,257,736 | 131,179 | 384,087 |
| Whole image | 1,572,092 | 487,597 | 1,541,475 | — | — |

Thus IG02 is not a local pixel edit: 451,667 pixels outside the requested target changed, including 143,109 alpha values. Across the whole image, the `alpha >= 128` silhouette mask grows from 457,061 to 464,281 pixels: 7,301 newly opaque pixels and 81 old-only pixels (mask IoU 0.984103). In the target ROI, 178 pixels cross into `alpha >= 128` and none cross out; across the broad hip ROI, 523 enter and none leave. Outside the target, 3,890 leg/boot ROI pixels enter the opaque mask and 66 leave. These are contour/opacity changes to review, not proof of improved cutout quality.

At common opaque pixels, 456,440/456,980 RGB pixels changed; median maximum-channel delta is 12, p90 is 22, and 21,093 pixels differ by more than 32. The widespread recoloring is measurable even where silhouette masks overlap.

## Shape and remaining gates

- The native-size lower-leg/boot comparison still shows two shins and two boots, with no obvious added or missing limb in the visible source. Boot and leg forms were not materially re-authored by eye, but there are substantial RGB and alpha changes in this area (see counts above); “unchanged” is not a pixel-level claim.
- The boots retain the existing strong three-quarter projection and oversized-looking heel/platform proportions in this seated source. This review does not establish that they fit the canonical rig or remain acceptable in motion.
- No hidden/occluded source regions can be inferred from these views. Independent left/right leg ownership, required underlayers, cut seams, bind landmarks, and all-pose stability are still unverified.
- Keep the original acceptance gates: source ownership ledger, complete hidden material, native cut quality, canonical binding, all-pose seam/overlap review, then runtime review. Do not lower them because the stripe looks improved.

## Native-size diagnostics

All contact sheets preserve source pixels at native scale; labels are added only to the contact sheets. No resized screenshot is used as acceptance evidence.

- `target_roi_side_by_side_native.png` — exact target crop, IG01 | IG02.
- `broad_hip_roi_side_by_side_native.png` — broad hip context.
- `waist_buttock_holster_side_by_side_native.png` — waist / hip / holster context.
- `lower_legs_boots_side_by_side_native.png` — both legs and boots.
- `full_source_pair_native.png` — full sources side by side at native pixel scale.
- `ig01_ig02_changed_pixels_overlay_native.png` — changed pixels over IG01 (amber marks differences, not a quality mask).
- `pixel_diff_metrics.json` — exact region and whole-canvas counters.

All review files are scratch diagnostics under `D:/NestEggVerification/ne222-sit-lower-ig02-review/`. The two source files were not modified.
