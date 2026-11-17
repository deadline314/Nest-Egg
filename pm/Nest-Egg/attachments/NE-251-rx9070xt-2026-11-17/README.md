# NE251 — RX9070 XT native exposure verification

This delivery repairs the acceptance instrument and verifies the existing clinic lighting. It changes no game lighting, renderer, character art, rig, story result or BG31 base tool. Native source epoch: `e053354ce390eb399e99dbb36db08f1566ec2b2a`; Godot4.7.2 Forward+, HDR2D, AMD Radeon RX9070XT,1280×720. Root's later Level camera−43 work is outside this fixed epoch.

## Effective evidence and scope

| Evidence | Script epoch | Natural checks/failures | Opaque H | White | Washed |
|---|---|---:|---:|---:|---:|
| Main warehouse flood → clinic | wake-smoke-v11 | 41/0 | 1668 | 0.299760% | 0.659472% |
| Controlled lethal enemy hit → clinic | route-hit-v7 | 37/0 | 1665 | 0.240240% | 0.660661% |
| Leave clinic → Main menu → actual Continue | resume-flood-v7 | 44/0 | 1672 | 0.358852% | 0.777512% |
| Three deaths, actual DeathScreen/retry after first wake | deaths3-v7 | 51/0 | 1671 | 0.418911% | 0.718133% |
| Controlled legacy level-lighting mode (expected rejection) | legacy-fill-v6 | 39/1 | 1668 | 96.223022% | 0.719424% |
| Native blank clone alpha H=0 (expected rejection) | blank-mask-v8 | 8/1 | 0 | 0.000000% | 0.000000% |

These are separate real processes with independent explicit save slots and redirected user profiles. Each launch/result includes its actual command,6 before/after script hashes,source snapshot and raw EOF. The native JSON records the real Godot PID,user:// path and tool hash. Warehouse entry uses Main's area-route owner; checkpoint/pit placement is arranged, not natural whole-chapter play. Flood uses actual player/plate physics and FloodPit death; important freeze:true radios are read to completion via real ui_accept. Hit is an explicitly synthetic fatal enemy-team hit. Resume uses actual Main menu/Continue; the three-death run records counts2/3,one total clinic wake and real retry buttons. Its remaining first clinic dialogue is explicitly skipped to reach the later-death checks; it is not a full-dialogue-play claim.

The legacy control flips only the stage actor's existing use-level-lighting option, thereby adopting warehouse fill3.64283985 and light cap0.5 instead of stage fill1/light cap0.2.96.223% white is this controlled legacy-lighting result, not the old white-background version or the historical B58044.2% observation. Historical B580 files are untouched. Current opaque-alpha ratios and old RGB-difference ratios use different denominators and are not directly comparable.

The v12 dark-stage sweep naturally exits0:289 checks/0 failures,29 setups/18 stages. It keeps the real warehouse alive beneath direct CutscenePlayer fixtures (safe checkpoint1240,784; global fill3.64283985,glow0.8/threshold1.15),while every actor retains stage fill1. Max white0.456621%,washed2.284710%,under the unchanged2%/5% gates. Coverage deduplicates authored stage/camera,actor position/scale/pose/facing and lists represented scenes. The recursive static JSON audit found no nested stage/Rin actor setup to add; native Story's loaded case manifest remains authoritative. This is setup coverage,not natural completion of every scene or every later camera/pose/FX frame.

Twenty-two final samples retain authored position. Seven are explicitly diagnostic placements:3 need X centering,6 need Y adjustment,2 of those need both. Their original offscreen/cut-head attempts,intermediate X-only failures,and final geometry-only displacement remain in the report and original PNGs. Y-only cases preserve authored X. The correction uses actual content bounds and the actual stage parent affine transform; no brightness/washed value chooses a new point. These diagnostics establish stage exposure at the stated fixture location. They do not establish that original author framing has been repaired or that an intentionally offscreen actor is meant to be visible. Product composition/grounding/full-scene acceptance is outside this tool-only delivery.

## Measurement

H is alpha≥0.999 from the actual primary `name=head` CPU drawable duplicated into a transparent HDR SubViewport,with its real final×CanvasLayer transform,material,texture sampling and sway uniforms. Back hair may be covered by the shoulder and is excluded from H. Complete existing head+hair geometry is used for content-frame validity and the4×visual crop. Known shader/CPU geometry,ancestor alpha/clipping,full content bounds,H≥200 and file/HDR validity are required. RGB values come from the real final composite inside the primary source silhouette;these are not isolated-material measurements or proof for arbitrary opaque foreground occlusion. The supplied native crops must also be reviewed.

The instrument holds actual node processing (including ALWAYS actors),running tweens and engine time,records geometry/uniform signatures and source restoration,and reads shown/mask from the same held rendered frame. Head-hidden background comes from the subsequent held state;both shown and hidden are separately repeated and their ROI raw bytes must be identical. This is a verified held-scene comparison,not a claim that two visibility states were rendered in one frame. Unknown/unstable cases refuse acceptance. Product glow is retained;no glow-off image participates in the result.

Raw main RGBH(format14),mask RGBAH(format15),dimensions,SHA and matching sRGB PNGs are retained. W counts all RGB channels>.97;washed counts linear luma>.75 with absolute hidden-background luma gap<.2,only at the opaque primary alpha. A zero H is rejection even when both ratios print0. Full head+hair geometry must fit the true CinematicFraming content rectangle. A fixed black-bar negative test rejects y40 in1280×72021:9;the scaled/rotated stage-parent test requests+22.7142868px and observes+22.71429px,tolerance0.001px.

The official Transform2D documentation requires an affine inverse for non-orthonormal bases;basis_xform_inv alone is unsuitable with scale: [Godot reference](https://docs.godotengine.org/en/stable/classes/class_transform2d.html#class-transform2d-method-basis-xform-inv).

## Regression and retained failures

Final CPU selftest:13/0,natural0,ERROR0. Separate blank/white/washed/non-HDR/black-bar controls each naturally exit1 with no engine/script errors. Native blank-v8 likewise naturally rejects H0. `tools/run_tests_changed.sh e053354ce390eb399e99dbb36db08f1566ec2b2a` naturally exits0 with no dependent game suites selected for these standalone tool files;this does not mean the full game suite ran. Native routes,CPU contracts and selector output are separate evidence.

`function-source-map-v12.json` plus exact unified diffs map original/e053 and v6/v7/v8/v10 functions to the frozen v11 source. The actual4 routes retain their actual v6/v7 source/PNG/raw measurements;later edits affect instrument frame validity/diagnostic placement. The final actual flood wake41/0 separately covers final full-head validity. No unchanged routes were relabeled as having run a different whole-file SHA.

Preliminary history is preserved. In particular:v6 menu-only sweep is not a dark-level test;v7 numeric189/0 omitted black-bar validity;v8 naturally fails197/2 with washed6.5141%/5.16735% at a wrongly transformed XY point;v9 CPU naturally fails13/1. The v9 queued wrapper was cancelled before any Godot child existed (Win32_Process receipt);its4294967295 exit is not natural Godot EOF or native coverage. v10 primary-only frame197/0 still clipped the higher ponytail top,so it is superseded for full-hair validity. See `preliminary/PRELIMINARY_ATTEMPTS.md` and the full run ledger. Original counts and failed PNGs are not overwritten. The first SceneTree harness compile error/manual interruption is also retained and is not a clean run.

## Portable custody and offline reader

All original native PNGs,source snapshots,logs,reports and run receipts remain portable. Identical bytes are stored once as blobs/SHA256;manifest logical aliases restore each original path. Full raw HDR is portable for final v12 sweep (including original/failed attempts),the4 effective route samples,legacy/H0 controls,v8's2 actual washed failures,and v11 case20 UI-occlusion counterexample (with their attempt trees). Thin primary alpha masks from all29 v11 final samples plus the independently rendered native hint alpha permit the complete glyph-overlap table to be recomputed without a second full World HDR set. Superseded passing/invalid diagnostic HDR binaries are explicitly listed under omitted_historical_binaries with original SHA/size and D location;they remain on D but are not in this packet. Their historical numeric observations are not independently recomputed or used as final pass evidence. PNG/source preservation is not a substitute claim for those omitted linear HDR bytes.

The first all-raw packaging attempt was741.8MB. Its alias manifest had an archive-name indexing bug detected before any ready/pass claim. Its wrong manifest/index and original D archives are retained as packaging history. The final index uses each actual archive filename and the offline reader reads every declared member,validates its SHA,and independently recomputes all portable raw measurements. Raw content is not rewritten to repair an index.

Run with Python3.8+ standard library;no Godot,GPU,network,NumPy or extraction is needed:

```text
python verify.py
python verify.py --workspace C:/Users/stanl/Github/Nest-Egg
python verify.py --export evidence/sweep-dark-v8/sweep-17-ch3_office_hall-xy-diagnostic.png D:/review/ne251-v8-failed.png
```

The last command validates/exports one artifact,not the whole packet;it refuses an existing destination. All volumes must sit beside manifest.json. source-newlines.json preserves the3 native raw sources and the explicit CRLF→LF Git mapping (only the selftest scene has6CRLFs). Workspace verification compares canonicalLF;it does not claim those native scene bytes were already identical to the later Git blob. runtime-source-manifest-after-native.json is explicitly a selected1025-path post-run manifest,not a retroactive all-file before-run guard.

Design contracts remain the existing stage-owned character lighting and original2%/5% thresholds. No game assets or lights were altered. This packet is frozen independently of later main revisions and provides no human-playtest or all-game performance claim.


## Final v12 UI-occlusion correction

Root review invalidated v11 case20's unobstructed-head premise:the existing Escape skip hint overlays primary H. Actual e053 native Label/theme/font size11 and final×CanvasLayer transform[2,0,0,2,1040,97.7142868] were rendered alone as transparent glyph alpha and intersected with the original v11 masks. Exactly283 pixels(glyph alpha>.001) intersect H1304 at bbox[1139,107,20,18];fully opaque glyph alpha≥.999 intersects0. Other28 final samples intersect0. This is a visible antialiased/semitransparent foreground,not an unobstructed source,even though the old numerical run exited0. Its original PNG,HDR,mask,source and alignment evidence remain intact.

Only the sweep fixture now temporarily hides the existing skip-hint Label during capture and restores its actual prior visibility immediately after. All29 v12 receipts record before=true,hidden=true,after=true,restored=true. This is stage-exposure diagnosis with that UI excluded,not acceptance or repair of product UI composition. No UI product code or exposure threshold changes. Actual4 route functions,measure_head,head_stats and the exposure gate remain byte-identical to their effective epochs;only sweep fixture/scope changes after v11. No unrelated4 routes were rerun for a whole-file SHA.

v12 whole sweep naturally exits0,289/0,ERROR0,with all six source guards held.13CPU checks naturally pass. Case20 without the hint has H1304,white0.153374%,washed0.076687%;the full29 maxima remain white0.456621%,washed2.284710%. Native glyph-support evidence has its own small result schema and post-render source hashes;it does not claim the6-script before/after route guard. The first v3 package builder incorrectly treated this separate schema as a route result and stopped with KeyError before any archive;the small failure receipt remains. The final reader separately checks glyph native EOF and all29 pixel intersections.

Local complete offline verification:5466 checks/0 failures,53 complete raw measurements recomputed,170 historical measurements explicitly not recomputed,822 historical binary files explicitly omitted. All29 original glyph intersections and all v12 hint-restoration receipts are independently checked. Ten volumes total394,445,419bytes,each below50,000,000bytes.
