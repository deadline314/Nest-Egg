# NE-249 input isolation evidence

Candidate source SHA256: `54af8acc125876746cf9aa13a6bb19ec3b61594587b22f35ae9679d99d022be0`  
Candidate diff SHA256: `628b3a602d449b0d84ca45d5bbf123fef9140b8e8b4a9e6aa0a1f7e0226fefb6`  
Base: `origin/main` / `76180645419ae5010a222a8622352714ec53cf05`  
Worktree branch: `codex/ne249-ci-test-isolation`  
Scope: `tests/suite/test_encounter.gd` only. No commit or ticket edit.

The free-encounter movement test explicitly selects gamepad aim facing left for its right-then-left movement, snapshots `AimInput.using_gamepad`, `_last_stick_dir`, and `_last_stick_msec` before opening the level, then restores all three after level cleanup. Existing movement durations and zone, gate, enemy, and completion assertions are unchanged.

## Final verification

- `tools/run_tests_changed.sh origin/main` selected `EncounterSuite`: 158 checks, 0 new failures, 0 known failures, exit 0.
- Full same-process order `main,PropsSuite,EyeBlinkSuite,ContinuitySuite,EncounterSuite`: 2051 checks, 0 failures, exit 0.
- Final full EncounterSuite with incoming RIGHT/gamepad, LEFT/gamepad, and mouse modes: each 158 checks, 0 failures, exit 0; player exit x=59.25.
- Direct `_test_free_encounter()` boundary probes independently compared all three static fields after return: right `[true, RIGHT, ...]`, left `[true, LEFT, ...]`, mouse `[false, RIGHT, ...]`; expected and actual tuples match, 8 checks/0 failures each.

## Historical RED labels and check counts

The original NE-249 packet reports 2049 checks / 1 failure. The bundled `ne249-baseline-right.log` (157/1) and `ne249-baseline-main-order.log` (2050/1) are historical prior RED runs. The main-order log shows RIGHT/gamepad input, exit x=105.4917, and the same sole escape assertion failure. Neither log records the candidate source SHA, so these are labeled as prior unpinned revisions; they are not represented as source-verified untouched baselines.

The final current-revision run is 2051/0. The current diff adds a restoration assertion, but the missing source SHA for the historical 2050-check log prevents attributing every check-count difference to a specific revision. `tests/known_failures.txt` was not changed.

The final same-process log contains 14 `ERROR:` diagnostics, exactly the same multiset as the original packet `local-main-order.log`, including the two `body_test_motion` engine errors. They are preserved in the logs. Final EncounterSuite-only controls have zero `ERROR:` and zero `SCRIPT ERROR` lines.

Commands:

```powershell
& 'C:/Program Files/Git/bin/bash.exe' -lc 'cd /d/NestEggVerification/ne249-input-isolation && GODOT=/c/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe tools/run_tests_changed.sh origin/main'
& 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless 'res://pm/Nest-Egg/attachments/NE-249-input-isolation/probe.tscn' -- --probe-mode=right --only=main,PropsSuite,EyeBlinkSuite,ContinuitySuite,EncounterSuite
```

`candidate.diff` is the exact working diff; file hashes are in `manifest.sha256`.
