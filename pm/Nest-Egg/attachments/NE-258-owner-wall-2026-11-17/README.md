# NE-258 owner + wall review packet

Raw archive: 9,451,332 bytes, 239 members, SHA256 `d5e0adbaa81a284870ad2ba55e47287f258e88c8df9ebc79b4e891b36394b34c`. No profile or save directory is included. `members.json` gives every original member's byte size and SHA256. No archive source is silently normalized for line endings.

Run `python -B verify_archive.py` here (Python + numpy). It checks every member and safely restores only the reader and two raw wall runs to a temporary directory. The same gate must reject original `wall-v2-native` with exit 1 and pass corrected `wall-v4-native` with exit 0. Native renderer is not required for this offline recomputation. These are arranged automation results, not human gameplay acceptance.

Source snapshots and full histories are inside `source/`. The original products and probe versions are retained, including bad phone timing, black-fade/timing fixtures, v5 duplicate-connect ERRORs, the initial RGBH reader assertion, and the original same-owner stale-lock microcontrol. `source/OWNER-RESULTS.md` and `source/LOCK-AUDIT.md` identify those earlier epochs. The original-source hash set did not include Terrain/Prop/Gate, so their first prototype wall run is not presented as a complete-source freeze. The final wall runner includes those sites and records all its sources unchanged.

Stable combined source for root review is `source/freeze-wall-v4.json` plus `source/freeze-wall-v4/`: original owner 5 products unchanged from owner-v7, plus LightKit and the 3 occluder registration sites, permanent Exposure and Cutscene regressions, the final private probes/readers and design. Formal affected test results are supplied separately by root.

The authorized isolated official run is now also preserved in `official-AAE.tar.xz` with per-member and archive SHA256 in `official-AAE.json`. The unchanged selector on `aae101cfc85b192af9558d5b38d250aea4f1e726` plus exactly 13 frozen runtime/test sources selected 77 groups (3 workers): 96,249 checks, zero new/known assertion failures, natural runner exit 0, wall time 1,041 seconds. All 14,198 guarded runtime/tool/test/asset files (1,250,919,295 bytes) match before/after. Full runner and shard output remains intact, including intentional corrupt fixtures and raw exit RID/ObjectDB/resource diagnostics. The original repository output policy excludes its historical exit diagnostics; no rule or whitelist was added. This is an official-rule pass, not a claim that its raw log contains no ERROR or leak.

Latest measured results:

- Owner v7: CPU 47 / 0 and native 54 / 0, natural exit 0, all receipt sources unchanged and no engine ERROR/leak/orphan diagnostics. Only the two deliberate rejected reentry warnings remain.
- Lock permanent helper: original 4 / 3 plus duplicate-connect ERROR and stale paused state; candidate 4 / 0, clean.
- Exposure with owner + wall regression: 280 / 0, exit 0, no ERROR. Its deliberately unsupported directional-cull fixture emits one explicit, bounded diagnostic; current formal occluders use double-sided polygons.
- Wall v4: native 8 checks / 0 (4 capture writes + 4 real state assertions), exit 0, complete receipt source set unchanged, diagnostics empty. Behind real wall query 0 and opacity 0.05; open query 0.71563777 and opacity 1; moving aim away naturally returns opacity 0.05. Original wall query was 0.70277067 despite a fully black rendered receiver and opacity 1.
- Same inset receiver samples remain mean/median 0 behind the wall; the open-side mean 0.03652609 / median 0.03627939 is numerically unchanged. Pixel areas are 870 or 900 from actual final×canvas raster bounds, not a rescaled denominator. This is an interior visibility check, not an exact PCF soft-edge lighting model.

NE-258 remains in progress. Its Stalker, cinematic and three-quality/performance criteria are reopened in the ticket; old Commit-1 historical measurements remain intact. Seven weapons/three angles, three quality tiers, current 8-tile enemy/platform gates, white-hair/reduce-flash captures and <=105% sustained-fire proof remain a separate matrix phase. Neither this packet nor exit 0 of the old probe claims those conditions passed.

Native repro uses private APPDATA/LOCALAPPDATA and one outer `gpu_lock.py`; commands/environment/source receipts are under each `runs/` directory. Probe scenes reference `res://work/ne258-light-owner-20261117/`: restore the corresponding frozen files to that exact workspace path before native repro. The offline reader above is portable without a game checkout.
