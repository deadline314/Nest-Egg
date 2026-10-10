# NE-222 seated-source hip shading correction

This source candidate corrects the long internal dark stripe identified in the user's marked image. It is **not adopted into the game** and does not establish seated/kneeling anatomy, correct part ownership, rig binding, or animation acceptance.

The marked 651×497 image is a near-1:1 crop of the retained IG01 candidate. Feature matching found 408 inliers from 444 matches, with approximately +159 source pixels in Y; the red annotation corresponds approximately to `[85,284,224,568]` in the 1037×1516 source. The stripe is authored in those raw source pixels, rather than caused by a game mesh in this particular image. This finding does not attribute every existing in-game hip defect to the same cause.

IG02 removes that internal stripe and the large bright arc while retaining a connected seated hip/thigh silhouette. The generation request targets local shading; it does **not** guarantee byte-identical pixels outside the requested area. Preserve both raw sources, prompts and receipts for comparison. Neither source replaces the approved standing s33 illustration.

- Rejected source: `../rin_sit_lower_ig01/raw/source.png`, SHA-256 `8115265f8ca9e0dbb554c172a8a39f70148b5ab700b3cfd639f4abb690ea9550`.
- Corrected source candidate: `raw/source.png`, SHA-256 `4d6f40cabb7854071d5b7be71bf2185089e425043c1da0adbc7e1cf29bffc520`.
- User's unchanged marked image: `../../../pm/Nest-Egg/images/NE-222-user-hip-shadow-line.png`, SHA-256 `63477fef23668361c7352cf7df1cbbbf932e35e5a7689d157767e8692471b232`.
- `prompt.txt` preserves the exact image-edit request. `source.json` records the returned native PNG and references; the provider exposed no model identifier, seed, or node graph, so those fields are null. This is a builtin image-edit result, not a Qwen/ComfyUI job.

Before production use, resolve near/far limb ownership and hidden material, source landmarks and fixed-bone registration, boot perspective and alpha fringes, matching damage/normal/glow, whole-body composition, and all required native pose/transition tests. No new source candidate may be accepted merely because this one stripe is absent.

## Pixel review and replay

The [source-only review](review/REVIEW.md) retains native-size crops and exact counters. IG02 changes 487,597 pixels overall, including 451,667 outside the marked target; 143,109 outside-target alpha values change. The `alpha >= 128` silhouette gains 7,301 pixels and loses 81. Consequently this whole output fails any promise of an exact local edit. Its boots still have unaccepted three-quarter projection, and the remaining diagonal thigh crease requires visual review. No source-alpha threshold or anatomy/animation criterion was relaxed.

Use the existing Python environment to replay the pinned input comparison without changing either source:

```powershell
D:/ComfyUI/.venv/Scripts/python.exe art_src/characters/rin_sit_lower_ig02/compare_sources.py D:/NestEggVerification/ne222-sit-shadow-replay
```

The output is a source diagnostic, not a game screenshot. The script verifies both source SHA-256 values before sampling, crops at native resolution and reports both half-open and inclusive ROI conventions. It has no path to the formal character, rig or animation files.

The method follows the [Spine pose-specific asset workflow](https://esotericsoftware.com/blog/Rigging-new-poses-tutorial): create the required art, bind it deliberately to the existing rig, then test its weights and transitions. Here the project keeps its fixed bone lengths and established quality limits.
