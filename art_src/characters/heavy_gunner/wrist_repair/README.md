# Heavy Gunner elbow source replay

This folder contains a source-only replay for the reviewed band18 `arm_lower` candidate. It changes no source artwork, formal texture, upper-arm part, rig, or spec. The replay keeps the existing lower-arm transparent RGB and reconstructs every visible output pixel from pinned same-coordinate RGBA source pixels.

The source ledger records four disjoint owners on the native 832×1216 canvas:

| Owner | Source | Pixels |
|---|---|---:|
| `base.png` | `base_rgba.png` | 10 |
| `stage_P.png` | `04_stages/P.png` | 18,687 |
| `lower_07.png` | `07_refined/arm_lower.png` | 11 |
| `upper_band18.png` | `07_refined/arm_upper.png` | 3,400 |

The first three masks retain the first exact source match for the v3 underlay in base → stage P → existing lower-arm order. The last mask is the connected, reviewed ±18 source-pixel band along the elbow-to-palm axis; its selected RGBA comes directly from the existing upper arm. The four masks are disjoint, cover the candidate's 22,108 alpha pixels, and leave zero unmatched pixels. `owner-manifest.json` pins source, mask, and candidate hashes.

Run the production-compatible source hook in an isolated copy of `art_src/characters/heavy_gunner`:

~~~powershell
& 'D:/ComfyUI/.venv/Scripts/python.exe' 'art_src/characters/heavy_gunner/wrist_repair/rebuild.py' --work '<isolated-heavy-gunner-source-clone>'
~~~

The public CPU replay is [NE-90 Heavy Gunner verify.py](../../../../pm/Nest-Egg/attachments/NE-90-heavy-wrist/verify.py). It rebuilds two temporary source clones, checks the decoded full-canvas pixels, and compares cut diffuse/normal hashes, dimensions and pivot with the formal texture and `character.json`. Five negative controls cover source corruption, owner omission, an extra owner pixel, a one-pixel hole and band-mask corruption. The run does not read private `.godot` candidate artifacts or write to formal art.

The source replay is now adopted for the single formal forearm part. Root's full fourteen-joint Forward+ audit reports 827/53,760 failures versus 9,694 baseline failures (8,867 resolved, zero new); neck 392, wrists 24, front elbow 333, knees 54 and shoulders 24 remain rejected. The other textures and skeleton are unchanged. See the public packet for exact native results; this source replay is not full pose or animation acceptance.
