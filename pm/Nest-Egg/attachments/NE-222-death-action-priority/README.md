# NE-222 death/action-priority capture pair

This packet contains the untouched raw PNGs and manifests from two actual Forward+ captures of the same three staged lethal-hit cases. The enemy actors were created in a real `Level`, forced into the preceding FSM state listed below, then killed through their `Hurtbox`; facing is right and the hit source is in front. These are staged state/action comparisons, not organic-combat coverage.

The samples target animator death time 0.0, 0.2, 0.5 and 0.8 seconds, plus one pre-fade sample per role. The capture pauses the `SceneTree` only after reaching each target, while waiting for render/readback. Every row records the timer before and after this freeze; the values match. The enemy's physics processing flag remains enabled, but it receives no simulation ticks during the render freeze. This avoids the Warden being freed during screenshot readback and does not claim animation advanced while paused.

| Skin | Staged preceding FSM/action | Requested pre-fade time | Captured pre-fade time |
|---|---|---:|---:|
| Enforcer | `dazed` / `shield_rusher.stagger_back` | 0.84 s | 0.85 s |
| Heavy Gunner | `vent` / `heavy_gunner.vent` | 0.84 s | 0.85 s |
| Warden | `phase_shift` / `warden.vent` | 1.20 s | 1.20 s |

At the matched 0.5-second target, the recorded death action blend weight is **1.0 before** and **0.0 after** for all three roles. The selected action string remains recorded in both runs; the change is the blend weight. Actual captured timers are Enforcer 0.5167 s in both, Heavy Gunner 0.5167 s in both, and Warden 0.5083 s before versus 0.5167 s after, within one 60 Hz tick. The staged action progress is not identical: Enforcer `action_t` at capture is 0.06536 before versus 0.13072 after; Heavy Gunner and Warden are unchanged. Treat this as evidence of the action-priority interaction, not a pixel-identical pose A/B.

Both manifests report checkout HEAD `a5efd3e48d85b10addfbdbda198cb7f2c395c1af`; their source hashes differ only for `game/rig/humanoid_animator.gd` (`381500a7…36a769` before, `5e846897…7e93fc` after). Each capture reports 158 checks, no failures, 15 unique PNGs, native 1536×1400 image dimensions, and requested/camera zoom 3.4.

The view is the real level composition at requested zoom 3.4. It is **not a tight character close-up**: at the 0.5-second sample the manifest's projected actor bounds are approximately 203×104 px (Enforcer), 193×143 px (Heavy Gunner), and 332×180 px (Warden) within the 1536×1400 image. The screenshots retain live stage lighting, rain, HUD and death effects. The Warden effects obscure some body pixels; root visual review also noted below-floor appearance in some death frames. The 0.5-second samples are useful for checking action suppression, but the packet does not establish complete death-pose, floor-contact, seam, anatomy, or natural-combat acceptance.

## Files and verification

- `before/manifest.json` and `after/manifest.json` are byte-copied raw manifests. Original manifest image paths are unchanged; their PNGs are stored in the project ticket images directory and resolved by the verifier's explicit image-root mapping.
- `../../images/NE-222-death-action-priority/before/` and `../../images/NE-222-death-action-priority/after/` contain all 30 original PNGs; none were cropped, resized, or recompressed.
- `replay/` contains the capture fixture and a shared capture helper snapshot; replay resource paths are adapted to this published packet. The fixture still depends on this project's actual enemy/level/rig code and data.
- `verify_death_timeline.py` checks manifests, timer/freeze metadata, source hash delta, dimensions, unique paths, and each PNG's SHA-256.

From the repository root, verify the packaged pair with:

```powershell
python pm/Nest-Egg/attachments/NE-222-death-action-priority/verify_death_timeline.py
```

To rerun the capture from this checkout, keep the packet at its current project-relative path, choose a **new output directory that does not already exist**, then run:

```powershell
python tools/comfyui/gpu_lock.py -- C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe --path . res://pm/Nest-Egg/attachments/NE-222-death-action-priority/replay/death_action_capture.tscn -- --capture --out=D:/NestEggVerification/ne222-death-action-priority-replay-NEW
```

The capture refuses to reuse an existing output directory. The `before` and `after` PNGs in this packet remain the original capture artifacts; reruns should use a separate output path and will record the actual checkout/source hashes in their own manifest.

## Representative 0.5-second raw frames

- `../../images/NE-222-death-action-priority/before/enforcer/death_t0p500_level_f1_z3.4_s0003_ft0p017_at0p065.png`
- `../../images/NE-222-death-action-priority/before/heavy_gunner/death_t0p500_level_f1_z3.4_s0008_ft0p033_at0p051.png`
- `../../images/NE-222-death-action-priority/before/warden/death_t0p500_level_f1_z3.4_s0013_ft0p033_at0p067.png`
- `../../images/NE-222-death-action-priority/after/enforcer/death_t0p500_level_f1_z3.4_s0003_ft0p033_at0p131.png`
- `../../images/NE-222-death-action-priority/after/heavy_gunner/death_t0p500_level_f1_z3.4_s0008_ft0p033_at0p051.png`
- `../../images/NE-222-death-action-priority/after/warden/death_t0p500_level_f1_z3.4_s0013_ft0p033_at0p067.png`

## Runtime verification

The regression adds both facings and death force 0/1 for each role, living action playback, weapon hiding and revival. Direct RigActionsSuite: 4,382 checks, 24 failures before and 0 after. The fixed 978cbc49 clean checkout ran the actual changed-test selector: 50 groups, 17,212 checks, no new/known failures, exit 0, 186 seconds, 8 headless processes. HeavyEnemiesSuite and HitReactionSuite supplement the enemy/debris callers; 415 checks, zero failures, exit 0; their raw result is recorded separately. Full testing is delegated to CI. Expected deliberate bad-data ERROR messages and any exit diagnostics remain in raw logs; no SCRIPT ERROR occurred in successful runs.

Text logs use LF line endings for Git; original capture JSON manifests and PNG bytes are preserved. The original Windows logs remain in the private verification directories. `test-receipt.json` identifies the fixed nonempty test baseline; `logs/` contains the selector summary, all eight shards, direct red/green and supplement output.

Rebased onto 82882bb4 (contextual prompt/dialogue UI), refreshed Godot imports, then ran eight affected integration groups: 5,050 checks, no new/known failures, exit 0, 28 seconds. The first attempt used a cache missing the newly introduced DialogueMaterial class, produced script errors and zero checks, and is rejected; both failed and successful logs are retained.
