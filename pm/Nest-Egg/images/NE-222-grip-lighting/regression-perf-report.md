# NE-222 legacy two-hand grip CPU regression

Snapshot: working HEAD `e1d3507a40f664defc2aa509de98f8c954915df3` (reported by the parent task; no fetch/rebase performed in this bounded subtask).

## Change

`game/rig/humanoid_animator.gd::_solve_arms` now runs the existing common reachable-interval solve for every nonempty weapon. The back arm contributes to that interval whenever `two_handed` is true and `shield_forward` is false, including legacy zero-offset wrists. Missing arm chains are omitted from the interval just as `_reach_arm` safely returns for an incomplete chain. The IK and bone rest lengths are unchanged.

`tests/suite/test_protagonist_motion.gd` adds a data-backed regression for the five reported enemy skin/weapon pairs. It reads each actual `EnemyData.move_speed`, samples 60 frames at patrol speed and `max(40, move_speed * 2)`, in both facings, and checks both world grip points against the actual weapon transforms at the existing `0.025 px` tolerance. It also checks upper/lower arm segment lengths every sampled frame and includes Rin palm-offset, unarmed, pistol, shield/offhand and NPC-path controls.

## Results

| Skin / weapon | Baseline maximum front/back gap (world px) | Fixed maximum front/back gap (world px) |
|---|---:|---:|
| trooper_elite / rifle | 0.000 / 2.973 | 0.000 / 0.000 |
| flamer / flamethrower | 0.000 / 1.522 | 0.000 / 0.000 |
| grenadier / launcher | 0.000 / 2.127 | 0.000 / 0.000 |
| sniper / sniper | 0.000 / 4.396 | 0.000 / 0.000 |
| stalker / rifle | 0.000 / 2.313 | 0.000 / 0.000 |

The before run passed 2,602 assertions and failed only the grouped legacy-grip assertion; all 20 facing/speed cases reproduced their skin's gap, and bone-length assertions passed. The after run passed all 2,605 assertions with zero failures. Every sampled front and back gap was `0.000 px`; fixed-length assertions passed for all frames. The suite reported 1.2 s after the change. Both logs contain no script errors or engine errors.

## Reproduction

From the repository root, with Godot 4.7.2 and Python UTF-8 mode:

```powershell
$env:PYTHONUTF8='1'
& 'C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe' --headless --audio-driver Dummy --path . res://tests/smoke_test.tscn -- --only=ProtagonistMotionSuite
```

Baseline log: [before.log](logs/regression-before.log). Fixed log: [after.log](logs/regression-after.log). This was the explicit affected suite only; no full-suite run, GPU capture, ComfyUI operation, commit, or push was performed. Parent-owned standard affected tests and visual/performance evidence remain to be run/reviewed.

The reported palm is the legacy `hand_*` wrist origin when its authored grip offset is zero; this verifies rig-to-weapon attachment and does not assert finger drawing or anatomical palm placement. The existing `CharactersSuite` has broader Rin action/grip checks; root should include its standard affected-test run.

## CPU performance comparison

The isolated comparison uses a private `HumanoidAnimator` subclass whose `_solve_arms` body is copied from `git show 4a754af0:game/rig/humanoid_animator.gd`; it replaces the instance animator after `CharacterRig.setup`, without changing runtime registration. This gives the old solver and current solver the same code outside `_solve_arms`. Each skin/weapon case uses 10 identical actors, 120 warm-up frames, then 3,000 measured frames at the enemy's actual `move_speed`, facing right, aiming right, on floor, with a two-handed weapon. Three samples per mode alternate order before/after, after/before, before/after. Time includes only repeated `CharacterRig.animate` calls; setup, warmup, grip validation and freeing actors are outside the timer.

| Skin / weapon | Before median µs/actor/frame | After median µs/actor/frame | Delta | Geometry per actor (bones / meshes / vertices) | Baseline offhand gap; fixed |
|---|---:|---:|---:|---:|---:|
| trooper_elite / rifle | 156.429 | 165.057 | +5.52% | 16 / 14 / 276 | 2.958 px; 0.000 px |
| flamer / flamethrower | 154.160 | 158.630 | +2.90% | 16 / 14 / 300 | 1.514 px; 0.000 px |
| grenadier / launcher | 156.103 | 168.419 | +7.89% | 16 / 14 / 258 | 2.114 px; 0.000 px |
| sniper / sniper | 156.025 | 161.174 | +3.30% | 16 / 12 / 228 | 4.363 px; 0.000 px |
| stalker / rifle | 154.247 | 157.377 | +2.03% | 16 / 12 / 222 | 2.298 px; 0.000 px |

The probe collected 30 samples, verified each baseline still has an offhand gap above 0.1 px, verified each fixed sample is within 0.025 px, and checked geometry stayed constant across all six samples for each skin. `results.json` records all individual samples and exact elapsed microseconds; `run.log` has five per-skin medians and no `SCRIPT ERROR`/`ERROR`; `SHA256.txt` records the baseline/probe, data inputs, current implementation and outputs. The exact command is in `command.txt`. These figures are the headless CPU animation cost only; they do not represent rendered FPS or GPU cost.

Root separately reports that the native Forward+ after-capture log emitted a “4 resources still in use” exit message without a `SCRIPT ERROR`, while the before capture did not. That capture metadata is outside these CPU probe results and remains for root's native-capture assessment.
