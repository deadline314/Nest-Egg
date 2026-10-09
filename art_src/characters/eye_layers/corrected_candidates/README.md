# Corrected source-local blink candidates

Root accepted the corrected variants as source candidates and the head-only native eye-stage trial has since passed. This is limited to eye behavior in the head-state harness. Each `characters/<id>/open.png` is an exact native 832×1216 RGBA copy of its source head. `half.png` and `closed.png` preserve source alpha and change pixels only inside the manually fitted visible-eye polygon. Candidate contours and lid paths are in `candidate_plan.json`; source/output hashes and the original review notes are in `manifest.json`. That manifest predates root's visual decision and still records the earlier pending status; this README records the later review. Rejected variants are preserved and remain rejected.

Run `python build_candidates.py` to regenerate. Run `python self_check.py` for two full CPU builds in temporary directories, source SHA/RGBA/native-size checks, exact open-image comparison, outside-mask byte equality, three distinct states, deterministic hashes, and modified-source rejection. The generator requires the existing Pillow dependency only. It does not invoke ComfyUI, GPU, Godot, or runtime code.

The skin fill is either a same-character cheek sample specified in `candidate_plan.json` or a local harmonic continuation from the eye-mask boundary. The new eyelid stroke is clipped to that polygon. Open eye pixels, far-side occluded eyes, brows, fringe, helmets, and nearby eye-bag/wrinkle regions are preserved outside the mask. Manual visual review remains mandatory; mechanical checks do not certify artwork.

## Root source review: accepted for runtime trial

| Character | Status | Review note |
| --- | --- | --- |
| Rin | Accepted as source for runtime trial | Half retains the cyan iris; original final art and source coordinates are retained. |
| Mei | Accepted as source for runtime trial | Half retains the purple iris; her existing spec lid line is used only for closed. |
| old_k | Accepted as source for runtime trial | Half retains the eye opening; nearby age lines remain outside the mask. |
| nurse | Accepted as source for runtime trial | Half retains visible sclera/iris; brow and under-eye fold remain. |
| night_worker | Accepted as source for runtime trial | Hardhat cast shadow is preserved; the subtle lid uses source-matched dark color. |
| repairer / repairman_chen | Accepted as source for runtime trial | Revised curved half lid leaves lower sclera and pupil visible; brow and lower wrinkle remain outside the mask. |
| resident | Accepted as source for runtime trial | Half retains visible sclera; lower cheek contour remains. |
| granny / ah_po | Accepted as source for runtime trial | Eye bag and wrinkles are preserved. |
| wataru | Accepted as source for runtime trial | v4 covers the full visible eye using the upper brow-bone and outer lower-eyelid skin bands; half and closed lids use curved traces. See `wataru-v4-donor-review.png` and `rejected_history/v3/` for donor review and prior rejected evidence. |

## Production-transform export and status boundary

The nine half/closed variants have been exported with the existing production cut transforms. The private export and installed trial textures retain exact head dimensions and pivot; open heads remain byte-identical to their published source. Native source variants are RGBA 832×1216, alpha is unchanged, and pixels outside each manually reviewed eye mask are byte-identical. Root's CPU comparison of the exported normal maps with Godot `NormalMapMaker.make` had a maximum channel difference of one byte. These checks establish source and export integrity, not in-game blink acceptance.

## Measured eye-stage trial

The corrected head-only stage audit passed with no reported errors: 30.047 seconds of real wall time, 4,297 processed frames, Godot 4.7.2 Forward+ HDR 2D on an RTX 4070 SUPER, and a 1280×720 viewport. It captured stage frames at 0, 15 and 30 seconds plus 27 actual rendered head-pixel crops at 3.4×. Root visually reviewed all three groups and the 15-second stage frame. Earlier directory-save and stretched-crop runs were rejected; only the corrected final run counts. The raw JSON and captures are still under ignored `.godot/eye-stage-audit/` and have not been copied to a published evidence path.

The registered `EyeBlinkSuite` standard-runner result was 256 executed tests with zero new failures and zero known failures. The previous affected-run record reports 65 affected and 49,204 executed, also with zero new or known failures.

This harness hides the other character parts. It verifies eye-state rendering and timing for this run, but cannot establish full-body quality, clothing integration, broad gameplay behavior or all-motion NE-221 acceptance. Keep those items unchecked until their own evidence is available. Do not treat the eye trial as final NE-221 acceptance.

## Wataru v4

The deterministic Wataru fill uses only source skin samples from upper band `[470,163,499,164)` and lower band `[492,192,499,194)`. The upper color is sampled per column; the lower-band color is sampled where the clean lower skin band exists and its median color delta is extended across the overlapping left columns. The mask, half-cover polygon, and both lid curves are stored in `candidate_plan.json`. No random operation is used (`random_seed: null`). Previous rejected v3 files are preserved in `rejected_history/v3/`. The v4 self-check verifies full-mask isolation, exact open state, no bright sclera remnant in closed, deterministic rerun, and unchanged hashes for the other eight characters.

## Repairer half revision

The previous repairer half candidate is preserved at `rejected_history/repairer-half-v1/` with its original SHA-256 and root's rejection reason. The revised half replaces only pixels inside the existing repairer eye mask: it interpolates same-row skin color from the explicit left `[440,89,443,95)` and right `[467,89,471,95)` source bands, then draws a curved y=92–94 upper-lid contour. This keeps lower sclera and pupil pixels from the open source. Open, closed, and the other eight characters retain their earlier hashes. `self_check.py` verifies those invariants. Root accepted this revision as a runtime-trial source; runtime acceptance remains pending.

The initial NPC-animator setup retained the default two-handed input and used the humanoid fallback body branch. That eye-switch evidence is superseded for NPC posture coverage by the actual unarmed NPC-branch rerun: every frame required `_use_npc == true`, nine characters, 30.047 real wall seconds, 4,297 frames, errors empty. See NE-221 Commit-2; the branch check validates eye-only rendering, not clothing or whole-body motion.
