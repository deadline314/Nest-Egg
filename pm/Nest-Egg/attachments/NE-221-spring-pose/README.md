# NE-221 authored garment pose plus spring motion

This delivery fixes composition in the shared humanoid animator. The authored pose and overlay are assigned first; the bounded secondary spring angle is then added once. Existing spring-only bones with a zero authored angle retain their previous result. Reapplying the body within one update resets that base before adding the spring, so rotations do not accumulate.

The basis is [Spine's official physics constraint documentation](https://esotericsoftware.com/spine-physics-constraints), which describes secondary motion as an offset from the unconstrained animated pose. Applying that principle to this project's existing angle-based spring is an engineering choice; the fixture's ±0.35 rad coat angles are diagnostic values, not recommended garment poses or new gameplay data.

## Scope and verification

- The runtime change is shared by humanoid and NPC animation. No character art, rig definitions, spring parameters, NPC pose data or story placement is changed.
- A cache-backed Rin NPC regression drives nonzero stand/sit coat angles through the actual NPC branch. It checks blending, a bounded secondary component, nonzero author/overlay/spring composition, repeated body application, zero-author compatibility, and 30/60/120 Hz offset consistency. The cached NPC data is restored afterward.
- The final regression is run against the unchanged baseline runtime in an isolated checkout before testing the fix. Its four failures reproduce discarded authored/overlay angles. The fixed runtime passes those same assertions.
- Native before/after images use the same original Rin art, diagnostic NPC data, lighting, source scale and framing. Each run simulates 480 updates, verifies 968 conditions and saves four Forward+ HDR 2D snapshots. Frames are simulated before snapshots; this is not continuous real-time playback evidence.
- The images deliberately show the original full character. Existing hips, hands, coat construction, joints and glow are not approved by this composition check. NE-221's clothing and all-motion acceptance remains separate.

## Reproduce

Use the same Godot version and native GPU environment for both runs. In a detached checkout of `bdd46937d29313e3d76764d19f81dd6a84fa796c`, copy this packet's capture scene and the final regression test. Run `NpcAnimationSuite` to reproduce the four failures, then capture the original runtime with `--legacy`:

```powershell
& 'D:/ComfyUI/.venv/Scripts/python.exe' tools/comfyui/gpu_lock.py -- 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --path . res://pm/Nest-Egg/attachments/NE-221-spring-pose/capture.tscn -- --out=D:/NestEggVerification/ne221-spring-before --legacy
```

Copy the delivered `game/rig/humanoid_animator.gd` into that isolated checkout. Run `tools/run_tests_changed.sh` with the fixed baseline above; then repeat the native command with a fresh output directory and without `--legacy`. The native report records actual authored, overlay, spring and resulting coat angles. Do not swap a runtime file in a shared active checkout to produce the comparison.

All raw logs and native reports are in `evidence/`; the corresponding original 1200×1400 screenshots are in `../../images/NE-221-spring-pose/`. `manifest.json` hashes packet files and screenshots, excluding itself and Godot-generated `.uid`/`.import` sidecars.
