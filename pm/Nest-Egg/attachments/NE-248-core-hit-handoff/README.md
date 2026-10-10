# NE-81 exposed-core projectile handoff

## Published packet and scope correction

This packet is NE-248's cross-session handoff. `original-cpu-red.json/.log` are the byte-preserved original 11-check / 1-failure result. `original-probe.*` and `original-base.gd` preserve the scripts used by that record. Their original private resource paths remain in the archived bytes; they are provenance, not directly runnable public scenes. For reproduction, copy them into a **fresh private folder**, update only its scene/extends paths and output path, and preserve a separate hash ledger; never overwrite another session's private fixture. The archived probe's hardcoded historical revision label is not a current-run label and must be updated to actual HEAD in that new replay.

Native observations on `e286a1be` are separate from the headless RED. V1 and V2 each finished with 14 checks, 2 failures, exit 1. In V1 the encounter approached the map's left edge. V2 positioned only the test Player on the unobstructed right side before the shot; boss FSM/health remained natural. Both shots produced **no recorded hit event**, unlike the original CPU body hit. The cause of that miss is unresolved, so neither native run proves the same weakpoint resolution defect or a fix. `native-observation-v2.gd` is V2 only; the earlier script was changed and is not represented as an exact V1 source archive. The picture `../../images/NE-248-core-exposed-context.png` is only actual scene context. Do not equate absent native collisions with the original CPU's confirmed main-body interception.

Raw observations, errors and source hashes remain in `native-observation-v1.json/.log` and `native-observation-v2.json/.log`. `files-sha256.json` pins this public packet and the context picture. No passing gameplay or art acceptance is claimed. The proposed segment continuation below needs a combat-owner decision and RED/GREEN tests; it is not an implemented fix.

Private diagnosis only. No runtime, test, ticket, or art files were changed for this handoff. Snapshot read: `e286a1be92226d70f9432a5213eb9c48d98b9393` (worktree had unrelated concurrent edits; this report is bounded to the listed files and preserved RED probe). The RED JSON itself embeds `212768fa4a98e9db5bb1b3f4c067ef6027c7547d` as the fixture label; do not treat that embedded field as proof of the execution checkout HEAD.

## Finding

The existing probe uses the real `Player._try_fire` → weapon/projectile pool → swept projectile → `Hurtbox.receive` path during Warden `core_recover`, while `core` is exposed at 2x. It aims at the core, but the projectile first contacts the enclosing body hurtbox. At that contact, `Projectile._strike` calls `Hurtbox.resolve_at(global_position)`, which tests only the current contact point against each part and falls back to the root body.

Preserved RED: 11 checks, 1 failure, expected process exit 1, no script error in `red.log`. `red-report.json` records `health 44 → 42`, ordinary `hit` marker, `part=""`, `weak_hit=false`, `resolved_core_part=false`, and core multiplier 2.0. The intended target was `[147.093, 246.439]`; actual swept contact was `[166.212, 251.110]`. Core center was `[146.505, 246.438]`, a 20.25 px separation. The configured part is 10×12, and `resolve_at` uses a 3 px point margin, so the part accepts at most 8 px horizontally; the impact point is 19.71 px from center. The parent body is 40×86 and encloses that approach. This is a collision-resolution contract gap, not evidence that the core bone is misplaced or its multiplier is off.

The call chain is `Projectile._move_swept` → `_on_area_entered` → `_strike` → `Hurtbox.resolve_at` → `Hurtbox.receive` → shared health. The sweep correctly stops at the nearest collision; the missing information is the projectile segment when choosing a hurt part. `_update_hurt_parts` follows `core_port`; `WardenBoss._set_core_exposed` sets the part multiplier to 2 during recovery. The data declares `core` at `core_port`, size 10×12, multiplier 1 at rest. Do not move the core or inflate the point margin to cover this gap.

## Smallest viable follow-up

Add a bounded continuation-resolution contract for swept projectiles. Preserve the actual sweep’s first blocking root target and wall ordering. At root-body contact, test whether the incoming projectile’s forward path, continued only through that same root hurtbox’s actual shape, intersects one of that root’s currently enabled weakpoint parts. Do not test only the segment ending at the body-entry point: in this RED the core is 20 px farther along the incoming path, inside the 40×86 body box. Resolve at most one target/part per projectile; choose the first eligible intersection along that bounded continuation, then call its existing `receive` once. A wall or different collider encountered before that part must win, and the query must not select a later enemy. Keep the existing point-based resolver for melee, explosions, and callers without a projectile path. This lets an aimed shot reach a visible exposed core within the already-selected enemy without globally ignoring that enemy’s body collider.

Avoid a broad “weakpoints always win anywhere inside body” rule. Segment and circle geometry must use the projectile’s current radius and transforms, and the part must be enabled/eligible at impact. A core segment hit should produce `part="core"`, `weak_hit=true`, weak marker/feedback, and the existing configured damage scaling. A miss to body remains normal damage. The existing per-health `_hit_ids` behavior must still prevent duplicate hits, including overlapping body/part shapes and pierce. Decide whether non-weak parts remain point-only or participate by their actual swept intersection; do not change behavior implicitly for all part types.

## Required follow-up RED/GREEN cases

- Same real `Player._try_fire` path, exposed core: trajectory through the core resolves `core`, applies the current part multiplier exactly once, and emits weak feedback.
- Exposed core: body trajectory that misses the core remains root/body damage and ordinary hit marker.
- Closed core: same trajectory does not report a weak hit; damage follows the closed-state contract.
- Both facings; projectile approaching from the other side must use actual transformed part geometry.
- A wall before the Warden still wins; an intervening enemy is not skipped in favor of a later core.
- Overlapping or duplicate contacts still apply damage once; piercing keeps its existing target deduplication.
- Core opening/closing during a projectile step uses the collision state actually active for that physics tick.

Likely ownership for a follow-up: `game/projectiles/projectile.gd` to carry the swept segment into resolution, `core/components/hurtbox.gd` for shared part geometry/selection, and `tests/suite/test_heavy_enemies.gd` plus the existing projectile/hit-reaction suite selected by the actual changed-test map. Avoid modifying Warden core position, the 20 px margin, visual geometry, or all attack values as a workaround.

## Scope and evidence

NE-81 is still in progress. The ticket depends on NE-73, NE-181, and NE-224; it blocks NE-88 and relates to NE-71. The path history is `40d6c1a0` (ticket created), `29ad886b` (redraw assets), `103dfff2` (NE-181 relation), `a370963a` (cutscene/core-glow encounter updates), `dfacf916` (NE-224 relation), and `eadc5f8f` (core cannon origin fix). These commits cover redraw, visual/encounter adjustments, and spawn-origin correctness; none tests an actual Player projectile hitting the exposed core. The existing `HeavyEnemiesSuite` checks core cannon spawning and multiplier state, but not real player hit-part selection. This RED is a focused missing regression, not a complete NE-81 quality verdict.

Preserved fixture and raw outputs:

- `../core_probe.gd` (extends the real organic combat probe; invokes its Warden case)
- `../core_probe.tscn`
- `../red.log`
- `../red-report.json`

Recorded hashes (SHA-256):

- RED report: `68de7ba2343325afb5cc0ba3838f089021f3892a104ec23ffb2181c34381f85d`
- RED log: `a5669a3d7cdd9acc28e987e6cf5628736f284a13c362a057348e474985b9b608`
- scene: `3d932ee9e6a6a0a8d16767bad9a3fbba454a31a92638b0c98dfddaeaa7e7352a`
- probe: `3bedd672c44d63215d3a95faa8108edcceef474eadb4079ea51368a0c8793150`

Relevant source hashes at the captured snapshot:

- `game/projectiles/projectile.gd`: `183c6ad9f4bcfbfd71a1475f1409e7a3402dc8f85f466a2ed8d4dcf480ebe534`
- `core/components/hurtbox.gd`: `8da545725886ae29c64edae534de3f4a7483ba0ce667aef84545796debf9edc7d`
- `game/enemies/enemy.gd`: `95cf1cc9ef2e9b15b2d95f5e79955a75869461026c9df2fb3bd637eaa8fa6ce2`
- `game/enemies/warden_boss.gd`: `3410ce2b8680b63b92f8f88b6f65e5cb42d3d9fed32f28bf29b63f5549054aba`
- `data/enemies/warden.tres`: `41760c61a715254fdfaa8f211ae234cf99fb4913ebf5f77366971276bab0d06e`
- organic combat probe base: `00d0bf1d730bba13d3da1280cd31c466fd79aab17d4baeaac0fe8086ee31c041`

The focused probe command used for RED is the existing project Godot 4.7.2 headless runner with `res://.godot/ne81-core-real-hit/core_probe.tscn`; do not count the expected nonzero RED as a passing test. No second run was performed.

## Official API reference

Godot 4.7 documents `PhysicsDirectSpaceState2D.get_rest_info()` as selecting the nearest intersecting shape, while `cast_motion()` reports safe/unsafe movement fractions and `intersect_shape()` reports overlapping shapes. That supports carrying explicit swept-segment context into a second, bounded part-selection step; it does not prescribe this game’s weakpoint policy: [PhysicsDirectSpaceState2D](https://docs.godotengine.org/en/4.7/classes/class_physicsdirectspacestate2d.html).



