# Enforcer wrist source replay

This folder records the source ownership for the reviewed forearm and glove selection. Root adopted the two diffuse/normal texture pairs and their two `character.json` metadata entries, and registered the source rebuild hook. This is a bounded wrist repair, not full animation acceptance.

The source canvas is RGBA 832×1216. The exact candidate arm_lower foreground has 21,735 pixels assigned to mutually exclusive source masks:

| Owner | Source | Pixels |
|---|---|---:|
| arm_lower_base.png | base_rgba.png | 2,743 |
| arm_lower_stage_P.png | 04_stages/P.png | 18,919 |
| arm_lower_existing_07_refined.png | 07_refined/arm_lower.png | 73 |

The hand has 9,154 pixels copied byte-for-byte from base_rgba.png under the root-reviewed hand-union mask. seam_clear_overlap.png is a separate non-owner mask for the 14 reviewed cuff/hand overlap pixels; it clears duplicate pixels from the arm layer. The builder starts from the existing arm RGBA to retain transparent RGB, clears alpha outside the exclusive owners, then applies those 14 seam clears. The manifest pins inputs, owner masks, provenance and exact candidate decoded-RGBA hashes.

provenance/strap-segmentation/ retains the reviewed SAM 3.1 workflow, proposed points, job name, raw SAM output and selected mask. provenance/root-hand-selection/ retains the root-reviewed hand union and the prior glove mask. The prior glove source mask hash is pinned in owner-manifest.json.

Rebuild in an isolated copy of art_src/characters/enforcer:

~~~powershell
& 'D:/ComfyUI/.venv/Scripts/python.exe' 'art_src/characters/enforcer/wrist_repair/rebuild.py' --work '<isolated-enforcer-source-clone>'
~~~

The production builder is limited to source replay. It validates source and owner-mask hashes, native dimensions/modes, binary and exclusive pixel ownership, source alpha, connectedness/no enclosed holes, seam provenance, and the exact decoded RGBA candidate hashes before writing either override. It stages and validates both files first, then atomically replaces each target and restores prior files if installation fails. Without --work, it follows the normal source_rebuilds hook convention and targets art_src/characters/enforcer; do not use that mode for private validation.

The public CPU verifier is [NE-90 enforcer wrist verify.py](../../../../pm/Nest-Egg/attachments/NE-90-enforcer-wrist/verify.py). Run it from the repository root with the configured Python environment:

~~~powershell
$env:PYTHONUTF8 = '1'
& 'D:/ComfyUI/.venv/Scripts/python.exe' 'pm/Nest-Egg/attachments/NE-90-enforcer-wrist/verify.py'
~~~

It reconstructs the override in two temporary source clones using the pinned inputs and default owner masks, then compares the generated diffuse/normal cut PNGs and size/pivot metadata with the four adopted files and `character.json`. It also reruns five negative controls. It does not write to the formal source or art folders.

Native wrist checks passed in all seven non-dead poses, with zero failures across 6,720 samples; all eight poses total 7,680 samples. The dead-pose wrist check has 256 failed samples, and elbow checks remain at the 208-sample baseline. The CPU replay does not resolve those remaining animation checks or constitute full pose acceptance.
