# NE-222 walk source IG01 review

This is an immutable source candidate and actual segmentation evidence, not a deployed walk fix. The approved standing source, production textures, rig, motion and input data are unchanged. The ticket remains in progress.

The new drawing makes the jacket worn on both shoulders and explores a less arched trunk. The source is [raw RGBA](../../../../art_src/characters/rin_walk_source_ig01/raw/source.png), with its prompt, generation metadata, 70-point model proposal and 14 SAM masks alongside it. The built-in generator does not expose a seed or Comfy generation graph; the subsequent actual SAM graph and checkpoint hash are preserved. Never label this a Qwen-generated source.

Actual Godot 4.7.2, RTX4070SUPER, Forward+ and HDR2D captured the [1920×1600 source comparison](../../images/NE-222-walk-source-ig01.png) under the shared GPU lock after ComfyUI was stopped. It draws the two complete source images at comparable display height, without rigging, normal maps, gameplay or animation. The capture's successful execution is not an anatomy, seam or movement pass.

## Rejected and unresolved controls

- 501 known detached black alpha=1 pixels are recorded in the exact cleanup-mask proposal and source audit; the raw source is unchanged. Other fringe/fragment ownership still needs review. No global alpha cutoff or acceptance threshold was changed.
- Two SAM3D points hit transparent pixels. Clothing/boots conceal joint centers; model output is a proposal, not an approved skeleton.
- All 14 masks include their positive seeds and exclude their negative seeds. Their original-alpha ownership still leaves 123,256 pixels unassigned and 9,886 multiply assigned. Jacket/body sleeve overlap is 6,496 pixels; metal forearm/hand overlap is 2,264. The near-boot mask also captures upper-body fragments. These numbers expose failed ownership; they are not acceptable cut parts.
- The new coat construction must use a matched body, hem, sleeves and damage/material-map set. It cannot be mixed with old coat pieces simply because texture sizes or seeds pass.
- [Spine's new-pose workflow](https://esotericsoftware.com/blog/Rigging-new-poses-tutorial), [skin attachments](https://esotericsoftware.com/spine-skins) and [weights](https://esotericsoftware.com/spine-weights) support separate authored attachments and validated weights. This project uses its existing Godot pose-part API; no Spine dependency is added. A drawn source pose needs correct source-to-bind registration, not a forced canonical bind or a changed bone length.

`art_src/characters/rin_walk_source_ig01/verify.py --self-test` checks delivered hashes, native dimensions, original-source preservation, actual mask seed responses, the executed 14-node graph and three corruption/size/hash rejection controls. A passing evidence check deliberately retains the source/mask failures above. Full rendered joints, all motions, pose switching, armor changes, feel and hardware performance remain outside this source-only review.

Reproduce the source comparison after stopping ComfyUI through the existing shared lock:

```powershell
& '<Python>' tools/comfyui/gpu_lock.py -- '<Godot 4.7.2 console>' --path pm/Nest-Egg/attachments/NE-222-walk-source-ig01/capture --resolution 1920x1600 -- --root=<absolute repository> --out=<absolute PNG>
```

The fixed `aeb45f77` isolated-checkout changed-test selector selected zero Godot suites, exit0: this delivery adds unregistered source/evidence, not production game behavior. The source verifier also passed independently in that checkout. Complete tests remain with CI; no game test pass is claimed here.
