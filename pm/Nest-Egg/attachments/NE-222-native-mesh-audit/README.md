# Native pose bounds and animation audit

This delivery fixes a validation gap: active native pose meshes were absent from visual bounds and from AnimAudit's triangle-fold measurement. It keeps the existing mesh-fold limit of 0.4. Only visible logical native owners count; hidden alternatives and glow children do not. The shared reconstruction uses current bone transforms and the authored skeleton rest transforms, with the character root applied once to world bounds.

`PoseMeshSuite` includes a native-only fixture, nonzero authored binds, a numerical 50/50 two-bone deformation oracle, root translation/rotation/reflection, hidden rigs, damage counterparts, pose switching and clearing. A deliberately reflected native mesh must exceed the existing fold limit even when there are no legacy limb meshes. At the fixed pre-fix baseline, the new regression records 140 checks and eight failures without script errors. With the fix, it records 141 checks and zero failures. Raw logs and source/cache hashes are in `evidence/`.

The native capture reuses the published [NE-222 source control](../NE-222-native-pose/README.md). It also checks that both native owners enter the audit, contribute bounds, and record a fold result. Godot 4.7.2 / Forward+ / HDR 2D on an RTX 4070 SUPER recorded 2,033 checks, zero failures and exit 0. The unchanged seam checker recorded zero failures in 480 samples. Every PNG SHA matches the earlier published 480-frame capture exactly; `evidence/replay-hashes.json` records the comparison instead of duplicating those frames. Two actual replay PNGs are saved in `../../images/NE-222-native-mesh-audit/`.

To repeat the source control:

```text
godot --headless --path . res://pm/Nest-Egg/attachments/NE-222-native-mesh-audit/capture.tscn -- --mode=native_bind --prepare-check
python tools/comfyui/gpu_lock.py -- godot --path . --rendering-method forward_plus res://pm/Nest-Egg/attachments/NE-222-native-mesh-audit/capture.tscn -- --mode=native_bind --out=<absolute-empty-directory>
python tools/check_joint_frames.py <absolute-empty-directory>
```

Use the actual configured Godot and Python executables. The native run must not overlap ComfyUI generation. Rebuild/validate the linked source bundle before capture if its generated source controls were changed. Its one-pixel holes, disconnected parts and alpha thresholds retain their original rejection rules.

This is a shared validation correction and localized source replay. It does not select a new pose in gameplay or approve Rin's whole-body anatomy, hands, jacket, transitions, lighting or control feel. Native triangle narrowing and area compression are not measured by `mesh_fold`; native source coverage and visual seam checks remain separate gates. Existing legacy `limb_pinch` behavior is retained.

The affected-test run used a clean isolated checkout at fixed base `3b14844a`, containing only the three game/test changes. `tools/run_tests_changed.sh 3b14844a` selected 60 registered groups and recorded 16,409 checks, zero new/known failures and exit 0 in 347 seconds. Other unfinished portrait and watchdog changes were excluded. The scope and four raw shard logs are included. No local full-suite run is claimed. GitHub's latest checked CI job did not start because of account billing/spending-limit restrictions, so no CI success is claimed.
