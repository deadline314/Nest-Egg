# Native material-axis control

This is a diagnostic of one new mechanical-hand source, **not** an adopted pose or complete walking rig. The original standing illustration and production character/rig/motion files are unchanged.

The 95×130 RGBA comes from the reviewed native source crop `[341,711,436,841)`. The fixture uses four UV corners, two triangles and one bone influence; no extra geometry budget or new animation framework is introduced. It creates the production Rin skeleton, hides its existing art, installs each candidate bind and uses the production mesh parser and Skeleton2D bone-path configuration. It reads the target material vector from the real formal hand pivot, rather than guessing the pivot or treating local +Y as finger direction.

The three panels show authored current=bind, the rejected +Y assumption, and corrected terminal material orientation. Native Forward+ / HDR 2D on Godot 4.7.2 and RTX 4070 SUPER measured 88.203540 degrees for the rejected panel and 0.000000799 degrees for the corrected panel. The original source render and corrected hand remain readable at native density. ComfyUI was stopped and the shared GPU lock held. The initial fixture's guessed pivot failed an assertion; its raw log is retained, and the final fixture reads the actual character metadata.

Rebuild the source calibration before running this fixture:

```powershell
python art_src/characters/rin_walk_source_ig01/registration/build.py
python tools/comfyui/gpu_lock.py -- <godot-console> --path . --resolution 1200x700 --quit-after 90 res://pm/Nest-Egg/attachments/NE-222-material-axis/preview.tscn -- --out=<absolute-output.png>
```

The actual PNG is [NE-222-material-axis.png](../../images/NE-222-material-axis.png). Check both the process exit code and the complete log for `SCRIPT ERROR`/`ERROR`; `--quit-after` can return zero after a script assertion and is not proof of success. Final `native-control.log` contains the measured result and no error. CPU reconstruction, repeated-build and fixed-base changed-test logs are recorded separately.

This control does not validate a production pose loader, all source ownership, wrist/cuff closure, head/neck/torso joins, whole-body anatomy, normal/glow, all walk frames or input feel. The source's unresolved shoulder/hip/coat branch geometry remains in its JSON; no acceptance checkbox is marked by this packet.
