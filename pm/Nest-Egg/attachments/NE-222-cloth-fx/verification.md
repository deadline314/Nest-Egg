# NE-222 cloth tear FX verification

## Scope

Headless CPU-only verification of the cloth tear helper and its damage trigger. No GPU capture or editor import was run. Production changes are limited to `autoload/fx.gd`, `game/rig/character_rig.gd`, and `tests/suite/test_hit_reaction.gd`.

## Test results

- `HitReactionSuite`: 216 checks, 0 failures. Covers four facing/hit-side combinations, real health loss that stays within one armor step, no emission on setup/heal/non-finite origin, chest/thigh/calf anchors, a skeleton-origin pose-mesh anchor control, expiry, bounded pool use, and enemy debris regression.
- `EnemyVfxSuite,FxUpgradesSuite,FxMeleePickupsSuite`: 443 checks, 0 failures.
- Both commands used Godot 4.7.2 console with `--headless --audio-driver Dummy --path . res://tests/smoke_test.tscn -- --only=...` in the worktree.
- No `SCRIPT ERROR` in either final log. Existing expected negative-fixture `ERROR` logs appear in the FX run, followed by exit leak diagnostics.

## Clean-checkout comparison

Ran the same three-suite FX command against `D:/NestEggVerification/ne221-spring-bdd4` at HEAD `8b61faef5561211275d8341f7ef3c10a64442638`; the three owned files were clean there before running. It also passed 443 checks with exit code 0. Its exit diagnostics exactly match the worktree run: 6 `GodotArea2D` RIDs, 6 CanvasItem RIDs, 16 ObjectDB instances, and 8 resources still in use. The three logged `ERROR` entries are the same intentional missing-data fixtures. The clean checkout had no tracked file changes after the run. This comparison establishes those diagnostics were present at baseline; it does not classify them as benign beyond their exact match.

## Logs and SHA-256

- Current HitReaction log: `hit-reaction-final.log`, SHA-256 `ABD3F5F536882182AE67B75D78EE15B58A2F7B514BB7CA67188F6CEA236EE1A0`.
- Current FX suites log: `fx-related-final.log`, SHA-256 `5E8B0745F4AB02E86D824C578A1421A2EE3BEF17256AE8C2E1801FB5100F7F5D`.
- Clean-checkout FX log: `fx-related-baseline-8b61faef.log`, SHA-256 `61A17BEA1EBE160D4A16949A98B8B3C2A66502C8F1942E489CFC6109A7B0CBC8`.
- `autoload/fx.gd`: `F610B95735470417C15FFD6A8CA7DF0E0B5F41EA89C527DC0B8ECD5831CF84A3`.
- `game/rig/character_rig.gd`: `E599B255DD58F5709E6990839E53CB7D1C8337C426354271E66BA6979F2AE2DD`.
- `tests/suite/test_hit_reaction.gd`: `E2A9CAE5182B0B503469FBF1FAE3ECE63E62B101612C46CEE234B38607D85B3D`.
