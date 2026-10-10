# NE-222 source-domain review package

This evidence package makes the Polygon2D source-domain check reproducible with Python, Pillow, and NumPy. It is limited to the front and back boot source owners in the 22297 kneeling candidate. It does not adopt that candidate or close NE-222.

## Result

The pinned source is the 1440×736 RGBA `rin_kneel_color_alpha_22297_0.png`, SHA-256 `74044963a9ff8d2bc47b5bceed04d8763b856b252069c4817c7f0685b1bd33ed`. The two owner masks contain 36,817 front-boot and 36,133 back-boot pixels at the published alpha floor of 40. Every tested owned pixel in each published boot crop has byte-identical RGBA to its mapped source pixel: 36,817/36,817 and 36,133/36,133, with zero mismatches.

For each owned source pixel `(x, y)`, the verifier maps its center to local texture UV `(x - crop_x0 + 0.5, y - crop_y0 + 0.5)`, using the half-open crop origin in the published registration report. The boot texture is not atlased. The checker tests each center against the union of the candidate UV triangles using signed cross products and a fixed `1e-9` boundary tolerance.

| Owner | Candidate | Owner centers covered | Missing centers | Domain result |
|---|---:|---:|---:|---|
| Front boot | v1 (9 vertices / 8 triangles) | 22,257 / 36,817 | 14,560 | Fail |
| Front boot | v2 (9 vertices / 12 triangles) | 36,817 / 36,817 | 0 | Pass, domain only |
| Back boot | v1 (9 vertices / 8 triangles) | 18,285 / 36,133 | 17,848 | Fail |
| Back boot | v2 (9 vertices / 12 triangles) | 36,133 / 36,133 | 0 | Pass, domain only |

The earlier quick scan used integer raster positions, which are not source pixel centers; this package replaces that estimate with the pixel-center calculation above. Its results are 14,560 and 17,848 missing v1 centers.

The verifier also checks every mesh UV vertex against the source-to-skeleton affine in the published registration guide. For a mesh vertex it evaluates `source_xy = uv + crop_origin`, then applies `guide.source_to_skeleton`; the result must match the stored skeleton vertex within `0.0001` source pixel. All four boot meshes (front/back, v1/v2) pass this mapping check, with maximum observed error below `2.4e-13` source pixel. UV/vertex values must be finite numeric pairs; triangle indices must be true JSON integers with valid bounds, and degenerate UV triangles are rejected.

The mapping negative control shifts every v2 UV vertex by `+1` source pixel in U while keeping the skeleton vertices unchanged. Owner-domain coverage remains complete for both boots, but each mesh vertex is now displaced from its affine-mapped skeleton point by exactly 1 source pixel and the mapping check rejects it. This demonstrates that domain coverage alone does not accept a wrongly translated mesh.

The other negative control clips each v2 UV triangle domain one source pixel inward from the actual bottom contour of the owner mask. It is anchored to real owned pixels inside the crop, not to transparent padding. The same checker then reports 18 missing front-boot centers and 16 missing back-boot centers, all on the corresponding owned source edge rows. A passing negative control would invalidate this check.

## Candidate status and limits

The v2 geometry passes only this isolated CPU source-domain coverage check. It is not adopted. The latest native review still reports 630 of 3,360 joint samples failing, including front hip 450, back hip 90, front ankle 30, and back ankle 60. Source-domain coverage says nothing about semantic ownership, anatomy, seams, deformation, pose quality, or rendered acceptance. The candidate therefore remains rejected for delivery until those native failures are resolved and the complete applicable gates pass.

The comparison images are generated source/UV overlays, not Godot screenshots. Magenta marks source owner pixels not covered by the relevant mesh; cyan lines show UV triangles; green traces the source owner edge; red in the inset panels marks the actual owned bottom-edge row removed by the negative control. Source pixels are not modified.

## Reproduction

From the repository root:

```powershell
D:/ComfyUI/.venv/Scripts/python.exe pm/Nest-Egg/attachments/NE-222-source-domain-review/verify_source_domain.py
```

The script uses bundled inputs and the existing Pillow/NumPy environment; it adds no dependency. It checks all pinned SHA-256 values, source and mesh metadata, source-to-crop RGBA equality, v1/v2 owner-center coverage, the one-pixel owned-edge negative control, then repeats the analysis and image generation in memory and compares hashes. It writes `results/verification.json`, `input-manifest.json`, and the comparison PNGs under `pm/Nest-Egg/images/NE-222-source-domain-review/`. The saved `results/run-01.log` and `results/run-02.log` are the two final actual executions used for this package; `run-01-domain-only.log` and `run-02-domain-only.log` preserve the earlier check before vertex mapping was added.

## Included inputs and evidence

- `inputs/source/`: pinned source RGBA, owner masks, registered boot crops, registration report, and ownership manifest.
- `inputs/mesh/boot-mesh-v1.json` and `boot-mesh-v2.json`: complete candidate JSON snapshots. Their recorded repository texture paths are provenance metadata; the verifier uses the bundled public registration crops and checks the mesh texture dimensions against the crop.
- `verify_source_domain.py`: standalone CPU verifier and deterministic overlay generator.
- `input-manifest.json`: file sizes and hashes for every verifier input.
- `results/verification.json`: actual coverage, source-crop equality, per-vertex source/skeleton mapping, both negative controls, verifier SHA, and repeat-hash results.
- `../../images/NE-222-source-domain-review/boot_uv_domain_native.png`: 1:1 crop panels for v1, v2, the owned-edge inset, and the UV-shift mapping control.
- `../../images/NE-222-source-domain-review/boot_uv_domain_nearest3x.png`: same diagnostic enlarged with nearest-neighbor sampling for review.
- `../../images/NE-222-source-domain-review/source_owner_context_native.png`: unscaled source context with owner and crop overlays.

The matching source-domain rule is recorded in the three existing rig-animation acceptance references: `.agent/skills/rig-animation/references/character-acceptance.md`, `.agents/skills/rig-animation/references/character-acceptance.md`, and `.claude/skills/rig-animation/references/character-acceptance.md`. This package supplies the CPU example and negative control; it does not replace native checks required by those references.
