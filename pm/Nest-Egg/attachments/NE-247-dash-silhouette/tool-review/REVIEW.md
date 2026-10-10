# P2 probe-only negative-X decomposition

Adopt the complete native9 tool from `candidate/tools/dash_silhouette_native_probe.gd`, LF SHA256 `870ec89318be0fdf04b3507a3924f7f448e2de60452b8325ba5d8b98eb23bc48`. `alignment-only.diff` adds this correction to the independently preserved GUI-host candidate (`19171059051b8b92f382bbcf2064646fd0d5b5585c7d0050d72b65492a366e51`). `combined-native9.diff` applies both tool corrections to native8's exact `71a436...` preimage. Neither older freeze directory was modified.

## Source and failure mechanism

Native8 `_alignment` stores a local Transform2D, reparents the actual formal Rig into its existing diagnostic SubViewport, sets the world matrix, then reparents back and sets the saved local matrix. It restores the matrix but not Node2D's original position/rotation/scale/skew representation. Godot documents that negative X scale decomposes into a negative Y scale and 180-degree rotation. The existing `CharacterRig.facing` setter (`game/rig/character_rig.gd:29–32`) then assigns scale on each genuine animate call while leaving rotation unchanged. Matrix equivalence at the end of the diagnostic therefore does not guarantee equivalent subsequent gameplay.

[Official Godot Node2D scale contract](https://docs.godotengine.org/en/stable/classes/class_node2d.html#class-node2d-property-scale) supports this diagnosis. The untouched product setter is correct for its normal authored root representation; the diagnostic tool introduced the alternate representation.

Actual native8 raw formal source world matrix: `[-1.18941199779511, 0, 0, 1.12241160869598, 918, 319.997741699219]`. Its synthetic source world matrix is `[-1.19151735305786, 9.79954961621843e-08, 1.04165756908969e-07, 1.12093782424927, 871.777770996094, 319.925262451172]`. Both source/snapshot alpha comparisons report zero pixels differing by more than two, which does not prove post-diagnostic animation restoration. The earlier report did not record rig component pre/post values; none are fabricated here. Root's native8 visual observation of inverted Rin in normal10/11 and the rejected settings world image is preserved in `native8-alignment-evidence.json` with the raw report hash.

CPU negative control: `R(0)·diag(-1,+1)` and `R(PI)·diag(+1,-1)` describe the same matrix. Applying the real facing setter's scale `(-1,+1)` to the second representation produces `diag(+1,-1)` instead, a vertical inversion. This arithmetic is a source-supported CPU model, not an engine reproduction.

## Narrow repair and genuine observation

Before any diagnostic movement, capture the actual local matrix and all four components. After moving the same source Rig back to its exact original parent/index, restore those exact saved component values and check both the matrix and components for equality. Do not assign zero rotation, select an authored pose or reconstruct a player stance. Player/Visual are never restored or posed; their saved matrix/components are read-only controls checked unchanged while gameplay is paused.

The synthetic fixture creation also copies the exact original components instead of assigning a reflected matrix before its existing facing setter. Otherwise fixing formal restoration would expose the same decomposition bug in the fixture itself. This remains a clearly synthetic existing PoseMesh fixture, never an assertion that formal Rin currently uses pose_parts.

After fixture/material/visibility restoration, assert that the exact original formal Rig and saved component representation were returned. Then unpause and observe two real physics/process frames. Check actual animation retains the original local rotation/skew/origin, uses the real facing setter's base-scale/facing relation, and keeps its local Y basis aligned with the pre-diagnostic basis. No post-resume transform or pose assignment occurs. Genuine report rows record source/formal local and global matrices/components before restoration, immediately after restoration, and after those actual resumed frames, plus untouched Player/Visual observation data.

All prior ninety static assertion calls remain, including the original eighty, world timing, GUI reading and real host/readiness checks; five restoration assertions are added. The real dash control/world timing and GUI host/readiness code are byte-identical to the preserved prior candidate. No image is added and existing counts remain unchanged. CPU gdparse and Counter/predicate checks pass. No repo/Git/PM/product/engine mutation occurred here.

Root must generate a fresh native9 manifest and run one complete engine probe. Native8's functional result does not approve its inverted pause world images or invisible settings GUI. Native9 must supply the actual component rows and Root must inspect the resulting images. No product CharacterRig/Player/PlayerVisual correction is proposed from this probe pollution.
