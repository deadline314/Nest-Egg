# BG-57 scene lighting candidate

Base `92521d0cf3c18bd3dad4b13a316844e70bfaecd0`; protected primary context C463/v29. Candidate contains exactly 18 BG-owned paths (17 non-UID paths plus the imported scene_lighting_checks UID). The six borrowed NE295 context files, including its shader-include UID, are separately indexed and must be committed by NE295. No unrelated cold-import missing UIDs are delivered.

Physical pickup/throwable/legacy-vehicle bodies now use ordinary canvas lighting while authored glow stays on a separate emissive child. Physical stage sprites and their texture states use existing normal pairs; baked backplates retain their old appearance. StageLibrary supports explicit optional local ambient/bounded lights, never auto-converts decorative glow, and gives actors the same local context. Real held props bind the actor material and restore their original appearance on release. Settings owns the LitTextures normal-map lifecycle across quality/load/Level exit. Cutscene UI is isolated only at build/choice creation, preserving foreign shaders and skipping the physical stage holder. No production stage JSON was retuned, no all-scene brightness change, no new manager, and no loot/carry/throw/fuse/movement/story timing changes.

## Actual evidence

- First real control: 36/1, because the new helper wrongly expected destructible components on an intentionally indestructible pipe. Corrected helper respects actual max_health; product bytes unchanged for that correction. Recheck36/0.
- Stage binding structural epoch337/0 predates the chunk/cache/UI additions. Final eighteen-path structural epoch347/0 is on base92521, default fullautoload, strict0 diagnostics, C463/D10201 fixed.
- Nine native gallery frames use actual 1280x720 RGBH14 Image (5,529,600 raw bytes each). Texture declaration2560x1440 is separately recorded and is not the physical Image size. No resize/pad/AA/HDR intervention. All raw persisted before canonical PNG encode. Original A1=A2=A3 bytes exactly; old-unshaded A/B negative exactly constant; eight physical ROIs respond, baked ROI does not. Same-canvas old UI under dark ambient dims; white UI new/old whole raw is exactly equal.
- Original gallery reader hit a cp950 UTF8-decoding error. The failed reader/log remain in evidence; the new reader changes only explicit UTF8 metadata decode and passes on the same original raw.
- Seven additional native frames use a real Rin3.9 and the published kitchen kettle/contact350,200 inside the real CutscenePlayer Stage canvas58. Real StagePropHold binding/release is exercised. Maximum measured contact error0.0000152587890625 world unit. Held AABA and released HIGH/LOW/HIGH restoration are exact raw; cached normal is absent in LOW and restored in HIGH. Every visible body transform is frozen and recorded. This is a controlled lighting/ownership fixture, not a natural pickup/place choreography or floor-support acceptance. Its diagnostic dialogue says "放下" but only ownership release was arranged; the kettle was deliberately not moved on release.
- Both final native engines exit0/strict0diag, four dual-port boundaries clear, primary C463 and complete scoped runtime+own inputs unchanged. Own Godot processes retired and canonical lock released. Foreign headless processes existed; no performance claim.

The held wrapper inherited the gallery scope string saying nine/HIGH-only. This is a preserved metadata label erratum; the actual seven-phase capture/producer/reader are authoritative. No old receipt or failed source epoch is rewritten.

Distinct native source images were visually read: gallery A1/B/old-A/ui-old/ui-white-new and held-A1/held-B/released-HIGH/released-LOW. Other originals are exact raw/PNG duplicates established by reader, not separate claimed manual reviews. Full characters/hands and UI are inside the original image; authored neon is retained. No controller/human gameplay/exposure or exhaustive all-skin visual claim.

## Portable replay

Requires Python, NumPy and Pillow; no Godot, worktree, primary repository or network needed:

```
python verify.py
```

This validates all archive/member/source/PNG bytes and replays the two independent raw/PNG readers. It extracts into a temporary owned directory and removes only that directory. `--raw-root DIR` may instead point to an already extracted raw.zip containing gallery/ and held/. All16 original PNGs are outside the raw archive, unchanged. ZIPs are each below90MB.

The original selector on the exact eighteen paths chooses70groups (including main). Root will supply the clean four-ticket union formal receipt; this packet does not yet claim formal affected tests or overall completion. `python verify.py --require-official` must refuse until an explicit accepted official.json with an actual receipt hash is supplied. PM status/checks and commits remain Root-owned.

`evidence.zip` preserves original commands, source inventories, four queue readings, isolated five-environment declarations, logs/exits, positive/negative controls and historical failed tools. Transient userdata caches are excluded; their declared locations remain in original environment metadata. `sources.zip` preserves exact owned/context/base/producer bytes. Original proof directories remain untouched on persistent local storage.
