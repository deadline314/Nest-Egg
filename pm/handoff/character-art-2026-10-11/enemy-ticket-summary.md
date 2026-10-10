# Session 1 ticket handoff: NE-17, NE-181, ST-8, NE-79, NE-80, NE-81

Read-only review of the current Nest-Egg worktree at `C:/Users/stanl/.codex/worktrees/character-art-baseline/Nest-Egg`. Ticket text/status and commit hashes below were checked against the current files and `git log --follow`. No ticket or project source was changed for this handoff.

## Current status and delivered evidence

| Ticket | Ticket status | Latest relevant ticket/progress commit | Evidence and actual scope |
|---|---|---|---|
| NE-17 Rin art | 審查中 | `484085b6d85898602895a29e0659250943afd9c7` (records explicit consent to reuse s33 and repair) | `pm/Nest-Egg/images/NE-17-session-current-poses.png`, `NE-17-session-current-closeup.png`; commit records Godot 4.7.2 Forward+ preview, but no new gameplay test. Earlier source/s33 SHA matches. Consent is explicit only for the Oct 8 preview and repair, not retroactive approval for the earlier overwrite. |
| NE-181 heavy-character waist/hip/thigh repair | 審查中 | `b411d2062f87a13c9e7f53282b20717ff4f1ca2e` | Ticket reports all three characters, waist/front hip/back hip × 8 poses × 120 frames × 2 facings × 2 scales: 34,560 samples, 0 failures; fixed-baseline selected suites 45,212 checks then 50,295 checks, 0 new/known failures; later exposure/map/character suites 1,846 checks. Evidence: `pm/Nest-Egg/images/NE-181-joint-report.json`, `pm/Nest-Egg/images/NE-181-part-dimensions.json`, before/after pose and scene images. This is the delivered NE-181 result; do not open another ticket for the same waist/hip repair. |
| ST-8 first-chapter items, flood pit and icons | 審查中 | `4d71d7a8a0a43ca9b82ac47624357a8ddef4124a` | Latest commit is validation/evidence only: 11 affected suites, 2,801 checks, 0 new/known failures; icon CPU check 294 checks, 0 failures; 14 384×384 RGBA detail assets and 3 icon pages + 11 inventory pages at 1280×720 inspected. Evidence: `pm/ST/images/ST-8-current-validation/README.md`, shards/logs, `ST-8-current-item-icons/`, `ST-8-current-item-inventory/`. Log honestly reports 212 ObjectDB instances leaked at inventory-capture shutdown. Captures prove UI layout, not manual pickup or full flood-pit gameplay. Earlier commit/test coverage already includes FloodPitSuite and story/item data; do not redo or expand ST-8. |
| NE-79 Enforcer | 進行中 | `79e0fa53e3c0b1fbe210c21cc189f4e900117508` (records native joint failures; preceding integration `5db3dfdd`, combat `e60526a4`) | Actual combat evidence: `pm/Nest-Egg/attachments/NE-79-organic-combat/README.md`. CPU action/armor regression and selected suites pass as recorded in `attachments/NE-79-cloud-action-regression/README.md` and `/local/README.md`. But native 14-joint × 2 facings × 8 poses × 120 frames × 2 scales = 53,760 samples has **1,287 failures**, exit 1; report/crops: `pm/Nest-Egg/attachments/NE-79-joint-frame-diagnostic/README.md`, `pm/Nest-Egg/images/NE-79-joint-neck-failure.png`, `NE-79-joint-knee-failure.png`. Eight-action seam/anatomy checkbox remains unchecked. |
| NE-80 Heavy Gunner | 進行中 | `e267ac22b046001e1c63a34c1561abc3b00482bc` | Organic combat/weapon evidence: `pm/Nest-Egg/attachments/NE-80-organic-combat/README.md`. CPU formal action/armor regression: 25,508 checks, 0 failures; fixed-start local selected suites 12 groups/35,396 checks, 0 new/known failures. Native pose/armor images exist (`pm/Nest-Egg/images/NE-80-cloud-local-eight-poses.png`, `NE-80-cloud-local-armour.png`) but are diagnostics, not full per-frame seam approval. Eight-action appearance checkbox remains unchecked; NE-224 owns native joint/anatomy/Forward+ acceptance. |
| NE-81 Warden | 進行中 | `eadc5f8f04bd1bfbdfaaefe489d1127de355a647` (core cannon origin fix); ticket subsequently synchronized by `eb7ac9d5603692aaa8b36aab48996e385ef529bd` (NE-248 handoff) | `pm/Nest-Egg/attachments/NE-81-core-origin/README.md`: actual core-cannon spawn correction, 10 cases/30 shots, max error 0 px; selected suites 38,913 checks then post-main 7,949, 0 new/known failures. Eight-action seam checkbox is unchecked. The actual exposed-core player-bullet part/damage/weak feedback criterion is explicitly delegated to **NE-248**, still 待辦; do not move the core, enlarge hitboxes, or duplicate that combat-system task in NE-81. NE-248 handoff preserves an 11-check/1-failure RED and unresolved native shots with no hit event: `pm/Nest-Egg/attachments/NE-248-core-hit-handoff/README.md`. |

## Handoff cautions

- The 1,287/53,760 Enforcer native failures are real and intentionally not waived. A passing CPU action/attachment suite or a contact sheet does not clear them.
- NE-81's correctly fixed cannon spawn point is distinct from core weakpoint hit resolution. The latter belongs to NE-248; its RED is still the source of truth until a combat-owner fix and real-player regression exist.
- Do not label two visible Slasher boots as a duplicated boot: the character has two legs and two boots. NE-90's single-boot/source-owner review is a separate part-ownership audit, not evidence that a two-boot full character is wrong and not a reason to reopen these six tickets.
- NE-181 and ST-8 remain in `審查中`; preserve those statuses and their recorded scopes. NE-79/80/81 remain `進行中` with the checkboxes noted above. NE-17 records s33 consent but remains `審查中`.
- Do not add tests/features/GPU captures, reopen image generation, clean up files, or change ticket statuses in the STOP/handoff phase. The shared worktree has active untracked WIP and modified files; leave them untouched.

## Latest ticket-file commits verified

- NE-17: `484085b6d85898602895a29e0659250943afd9c7`
- NE-181: `b411d2062f87a13c9e7f53282b20717ff4f1ca2e`
- ST-8: `4d71d7a8a0a43ca9b82ac47624357a8ddef4124a`
- NE-79: `79e0fa53e3c0b1fbe210c21cc189f4e900117508`
- NE-80: `e267ac22b046001e1c63a34c1561abc3b00482bc`
- NE-81 latest code delivery: `eadc5f8f04bd1bfbdfaaefe489d1127de355a647`; latest ticket synchronization: `eb7ac9d5603692aaa8b36aab48996e385ef529bd`.
