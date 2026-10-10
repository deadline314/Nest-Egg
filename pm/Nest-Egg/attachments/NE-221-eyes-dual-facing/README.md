# NE-221 dual-facing eye-state capture

This capture provides a rendered runtime check of the existing NE-221 eye states. It adds no eye art or game behavior. The ticket remains **in progress**: the Old K coat and Ah Po apron hem conditions and the all-motion audit are still unchecked.

The native run used Godot 4.7.2, Forward+, HDR 2D, and RTX 4070 SUPER. It ran for 30.218 seconds and 4,115 frames, with 18 configured skin/facing rows, no capture errors, at least 10 completed natural blink cycles in each row, and two separately recorded interrupted cycles. Those interruptions are reported separately and are not counted as completed cycles. Each row has actual rendered open, half, and closed crops. The capture kept HDR enabled and used the shared viewport readback conversion to produce PNG-compatible RGBA8 sRGB output.

The fixture uses the real configured eye-state branch and `CharacterRig.animate()` timeline, not direct state assignment. It covers the nine characters currently configured with `eye_states` (`rin`, `old_k`, `nurse`, `night_worker`, `repairman_chen`, `resident`, `ah_po`, `wataru`, and `mei`) at both facings. It isolates each existing head part and compensates its outer holder scale to capture one screen pixel per source texel. This is a head-only diagnostic view; its scale and framing are not normal gameplay presentation. It does not verify full-body rendering, clothing, or every motion, and it does not complete NE-221.

The project `images/NE-221-eyes-dual-facing/` directory contains the 54 exact v4 native head crops and three full viewport checkpoints. The PNG bytes are copied unchanged from the captured output. `native-report.json` and `native-run.log` preserve the raw capture report and log; their embedded `D:/NestEggVerification/...` paths are run provenance. The portable verifier maps crop/stage basenames to the project image directory rather than requiring that old output directory. `capture-manifest.json` pins the public PNG copies and the raw report. `failed-attempts/` preserves the first three failed reports/logs only, without duplicating their PNG sets:

| Attempt | Result | Cause |
|---|---|---|
| v1 | Failed | Private recorder formatting error stopped the run. |
| v2 | Failed | HDR `RGBAH` readback was passed directly to PNG capture without the standard linear-to-sRGB conversion. |
| v3 | Failed | The old recorder kept an interrupted blink active and attributed later transitions to it. |

The v4 capture fixes those fixture issues. It keeps the driver's `MAX_DELTA` behavior and timing checks unchanged; aborted cycles remain separate from complete cycles.

## Re-run

Run from the repository root. The native capture requires the shared GPU lock and writes to a new empty output directory:

```powershell
& 'D:/ComfyUI/.venv/Scripts/python.exe' tools/comfyui/gpu_lock.py -- 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --path . res://pm/Nest-Egg/attachments/NE-221-eyes-dual-facing/runtime_capture.tscn -- --out=C:/absolute/new-directory/native-report.json
```

Expected success is exit 0 and `captured_not_accepted`. The report still requires 18 distinct rows, rendered crops for all three natural states, at least one complete timing-valid cycle in every row, and a real 30-second wall duration. The existing manifest/PNG evidence remains read-only; write a replay to a fresh output directory.

CPU-only checks, which do not render images:

```powershell
& 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://pm/Nest-Egg/attachments/NE-221-eyes-dual-facing/runtime_capture.tscn -- --cpu-check --out=C:/absolute/cpu-output/cpu-report.json
python pm/Nest-Egg/attachments/NE-221-eyes-dual-facing/verify_capture.py
& 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://tests/smoke_test.tscn -- --only=EyeBlinkSuite
```

The recorded preflight used 36 character/facing/rate combinations (nine roles × two facings × 60/120 Hz) with no script errors. The standard `EyeBlinkSuite` reported 256 checks and zero failures. `verify_capture.py` checks raw report status, 18 rows, one-to-one crop/stage PNG set and hashes, source hashes against the current repository, crop dimensions/source density, complete-cycle flags, and minimum wall time. It does not claim game-wide or full-ticket acceptance.

The portable fixture and scene are copies of the private capture harness with only the scene's script resource path changed to this attachment. Their production dependencies remain the repository's current `CharacterRig`, `EyeBlink`, character data, and `tools/viewport_capture.gd`; they do not import or depend on private `.godot` artifacts. The preserved capture was run at source HEAD `212768fa4a98e9db5bb1b3f4c067ef6027c7547d`.
