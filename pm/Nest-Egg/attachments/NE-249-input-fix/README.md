# NE-249 input precondition and restoration

This packet verifies the encounter test, not character anatomy or animation.
The production change is nine added lines in `tests/suite/test_encounter.gd`:
save the incoming aim source, direction and timestamp before opening the level;
explicitly use LEFT gamepad aim during the existing movement; restore all three
after level cleanup and assert restoration. Player and gameplay files are unchanged.

The original test retains both 60-frame movement intervals, entry/exit thresholds,
living enemy membership, active encounter, invisible/non-colliding gates, timeout,
actual deaths and persisted completion. RIGHT-facing backpedal remains 127.5;
forward movement remains 150. Neither input tuning nor known failures changed.

## Actual results

| Check | Result |
|---|---|
| Original published same-process RED | 2049 checks / 1 failure; previous NE-249 packet |
| Original RIGHT gamepad EncounterSuite RED | 157 checks / 1 failure; exit x=105.4917 |
| Final EncounterSuite, incoming RIGHT / LEFT / mouse | Each 158 checks / 0 failures; entry x=187.4444, exit x=59.25 |
| Direct function-return restoration, all three incoming modes | Each 8 checks / 0 failures; all three saved fields equal independently captured inputs |
| Final same-process main, Props, EyeBlink, Continuity, Encounter | 2051 checks / 0 failures; this is a selected sequence, not the complete suite |
| Root fixed-base changed selector, f2798bdc942c93b49336d09f4e4695eeaf40184a | EncounterSuite selected; 158 checks / 0 new / 0 known failures |
| Actual native capture and public-path replay | Each 8 checks / 0 failures; 1280x720, HDR 2D, Forward+, RTX 4070 SUPER |

Final candidate SHA-256:
`54af8acc125876746cf9aa13a6bb19ec3b61594587b22f35ae9679d99d022be0`.
Different historical snapshots have different check counts; the original published
2049-check RED is preserved unchanged in `../NE-249-input-isolation/`.

The final selected main-order log contains 14 `ERROR:` diagnostics, exactly the
same multiset as the published RED log, including two `body_test_motion` engine
diagnostics. They remain in the raw log. The three final Encounter-only controls
have zero `ERROR:` and zero `SCRIPT ERROR`; the final selected sequence has zero
`SCRIPT ERROR` and no failed assertions. No diagnostic was added to known failures.

## Replay

Run from the repository root with the actual Godot executable. For each of
`right`, `left`, `mouse`:

```powershell
& $godot --headless --path . res://pm/Nest-Egg/attachments/NE-249-input-fix/probe.tscn -- --probe-mode=right --only=EncounterSuite
& $godot --headless --path . res://pm/Nest-Egg/attachments/NE-249-input-fix/probe.tscn -- --probe-mode=right --probe-direct
```

The same-process sequence uses that scene and
`--only=main,PropsSuite,EyeBlinkSuite,ContinuitySuite,EncounterSuite`.
Use a fixed pre-change revision with `tools/run_tests_changed.sh`, including
after commit/rebase, to avoid selecting an empty diff.

The native fixture wraps the unchanged real movement test. At its exit assertion,
it records actual player position, living members, encounter state and both gate
collision layers; pauses simulation for readback; checks the player position stayed
unchanged; saves HDR-to-sRGB pixels; then resumes and completes the test. Its label
is diagnostic metadata. Existing character art shown here is not approved by this test.

```powershell
python tools/comfyui/gpu_lock.py -- $godot --path . res://pm/Nest-Egg/attachments/NE-249-input-fix/capture.tscn -- --out=<absolute-path>/NE-249-free-exit.png
```

ComfyUI was stopped through the existing start script before native capture.
Complete testing belongs to CI; its outcome must be recorded separately.
