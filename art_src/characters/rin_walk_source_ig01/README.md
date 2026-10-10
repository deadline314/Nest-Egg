# Rin walk source IG01 — candidate, not adopted

The approved s33 standing source and all production Rin parts remain unchanged. This separate 1037×1516 RGBA walk source explores a relaxed trunk and a normally worn navy jacket, retaining the original face, body type, white/pink ponytail and cyberpunk palette. It is not registered in a character recipe or pose set.

`raw/source.png` is the unmodified built-in image-generation output. `prompt.txt` and `generation.json` retain the request and reference SHA. This tool does not expose a seed, model checkpoint or executable Comfy generation graph; those values are not invented. The stored source bytes are reproducible inputs for subsequent segmentation, not a promise that image generation can reproduce them.

`keypoints-proposal.json/png` came from the actual local SAM3D Body model. Coordinates are native source pixels; clothing-obscured joints remain estimates. The proposed right toe and one hand point land on transparency and are rejected. Anatomical model labels must be reconciled with visible near/far ownership.

`sam/` contains 14 actual SAM3.1 point-mask outputs, the executed graph and input/model hashes. The semantic input was the original RGBA composited over gray128 at native size. Pixels for future parts must come from the raw RGBA, not that RGB input. Positive-point inclusion and negative-point exclusion all pass, but semantic ownership does not: the jacket/sleeve masks overlap, the metal-hand mask includes forearm pixels, and the near-boot mask contains upper-body fragments. No priority fill, nearest-owner assignment, hidden anatomy or production replacement was applied.

The source has detached low-alpha black artifacts and a fringe requiring review. A proposed exact 501-pixel cleanup mask is evidence only; it has not been applied. Neither source alpha nor the one-pixel acceptance gate was weakened. Coat, sleeves, hem, torso/damage counterpart, normals/glow and any adjoining arm/pelvis parts must form a matched tuple before binding. Preserve the original standing set; do not paste this torso into the old coat.

Verify the delivered bytes and negative controls:

```powershell
& '<Python with Pillow>' art_src/characters/rin_walk_source_ig01/verify.py --self-test
```

Source review and native **source-only** comparison: [NE-222 evidence](../../../pm/Nest-Egg/attachments/NE-222-walk-source-ig01/README.md). This source has not passed rigging, animation, transitions, gameplay feel or hardware performance acceptance.
