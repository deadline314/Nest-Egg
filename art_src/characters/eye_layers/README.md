# NE-221 eye-state sources and cut exports

**Current eye-scope status:** the nine corrected source variants were accepted for runtime trial, and the measured head-only native eye-stage audit passed. This does not complete NE-221: clothing integration, full-body behavior and all-motion acceptance remain unchecked.

## Review history

The first-pass PNGs under [`candidates/`](candidates/) remain rejected diagnostic evidence. Their coordinate misses and poor eyelid/skin transitions were not repaired in place. Root later accepted the source-local variants under [`corrected_candidates/`](corrected_candidates/) for a runtime trial; the head-only eye audit now passes. `corrected_candidates/manifest.json` and per-character review notes retain their earlier pre-root-review status; this README records the later decisions without rewriting that history. Rejected revisions, including Wataru v3 and the earlier repairer half, remain in their `rejected_history/` directories. Earlier directory-save and stretched-crop audit attempts were also rejected; only the corrected final run is evidence for the eye-scope pass.

The source mapping is `repairer` → `repairman_chen` and `granny` → `ah_po`. Corrected open/half/closed source images are full-canvas 832×1216 RGBA. Open is byte-identical to its original head; half and closed preserve source alpha and every pixel outside the manually reviewed visible-eye mask. Source hashes, masks, donor details and candidate output hashes remain in [`corrected_candidates/manifest.json`](corrected_candidates/manifest.json) and [`corrected_candidates/candidate_plan.json`](corrected_candidates/candidate_plan.json).

Root compared the CPU-exported normal maps with Godot's `NormalMapMaker.make` output; the maximum channel difference was one byte. This is a normal-map parity result, not visual or runtime acceptance. The source and cut checks also preserve each published open head byte-for-byte, dimensions and pivot.

## Rebuild and checks

From the repository root, regenerate corrected source candidates and run their focused self-check:

```powershell
python art_src/characters/eye_layers/corrected_candidates/build_candidates.py
python art_src/characters/eye_layers/corrected_candidates/self_check.py
python tools/comfyui/test_eye_layers.py --check
```

The last check includes the retained legacy rejection checks, native source/hash and mask validation, failure cases, old-versus-shared cut-helper byte parity for all nine recipe part sets, exact open-head rebuilds, and deterministic private exports. It does not run the scene audit or certify blink behavior.

To derive all nine cut-size trial exports without changing published assets, run:

```powershell
python art_src/characters/eye_layers/export_candidates.py
```

The recipe is [`export_recipe.json`](export_recipe.json). The exporter verifies source and candidate hashes, native RGBA canvases, alpha and mask containment, then uses `cut_layers.py`'s `part_transform` and `render_part` path for the production canvas and pivot. It requires each rebuilt open head to match the current published open texture byte-for-byte. It writes diffuse, normal, applicable glow, contact sheets and metadata beneath the ignored `.godot/eye-state-export/`; a rejected input or failed build leaves the existing export directory intact. Runtime metadata contains only the agreed texture keys, never source paths.

The trial cut integration is already in each of the nine character specs. To rebuild the installed textures from the existing refined sources after a reviewed candidate update, run this existing production pipeline for each skin:

```powershell
$recipes = @("rin", "old_k", "nurse", "night_worker", "repairman_chen", "resident", "ah_po", "wataru", "mei")
foreach ($id in $recipes) {
    python "tools/comfyui/build_character.py" --recipe "tools/comfyui/recipes/$id.json" --from textures --to import
    if ($LASTEXITCODE -ne 0) { throw "Eye-state rebuild failed for $id" }
}
```

This starts at `textures`: registered source rebuilds run first, then `cut_layers.py` validates the full-canvas sources and emits the `head_half`/`head_closed` diffuse, normal and applicable glow textures with the exact head size and pivot. The existing build steps then regenerate normal maps and import them. It does not rerun design, pose, ComfyUI generation, parts or refinement. The current `eye_states` spec stores source paths and hashes for validation; `cut_layers.py` emits only `{part, half_texture, closed_texture, timing}` in `character.json`.

## Measured eye-stage result

Root's corrected head-only eye-stage run passed with no reported errors: 30.047 seconds of real wall time, 4,297 processed frames, Godot 4.7.2 Forward+ HDR 2D on an RTX 4070 SUPER, at 1280×720. It captured the 0/15/30-second stage frames and 27 actual rendered head-pixel crops at 3.4×; root visually reviewed all three character groups and the 15-second stage frame. The raw report and captures remain in ignored `.godot/eye-stage-audit/`; they have not yet been copied to a published evidence path, so this README does not link to them.

The registered `EyeBlinkSuite` standard-runner result was 256 executed tests, zero new failures and zero known failures. The previous affected-run record reports 65 affected and 49,204 executed, also with zero new or known failures.

This establishes the head-only eye-state stage check and blink rendering for this run. The harness hides the other character parts, so it does not establish full-body quality, clothing integration, broader gameplay behavior or all-motion acceptance. NE-221 remains incomplete until those checks are separately evidenced. See [`corrected_candidates/README.md`](corrected_candidates/README.md) for character-specific source notes and [`tools/comfyui/test_eye_layers.py`](../../../tools/comfyui/test_eye_layers.py) for source/cut checks.

The initial NPC-animator setup retained the default two-handed input and used the humanoid fallback body branch. That eye-switch evidence is superseded for NPC posture coverage by the actual unarmed NPC-branch rerun: every frame required `_use_npc == true`, nine characters, 30.047 real wall seconds, 4,297 frames, errors empty. See NE-221 Commit-2; the branch check validates eye-only rendering, not clothing or whole-body motion.
