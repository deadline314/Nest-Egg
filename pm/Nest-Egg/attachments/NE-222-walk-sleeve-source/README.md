# NE-222 native sleeve source evidence

This is one separate clothing attachment for the walk-source work, not a production
walk, outfit or rig acceptance. The original approved standing source and runtime
torso are protected by SHA checks. [Source and repeatable build](../../../../art_src/characters/rin_walk_sleeve_22322/README.md).

Actual Qwen and SAM execution logs are retained alongside the unmodified PNGs,
executed graphs and prompts in the source directory. The narrow SAM mask clips
524 core edge pixels (`mask-missing-material-native.png`); the reviewed material
mask preserves the whole single sleeve. `outside-mask2-contexts.png` records the
four retained cuff-edge pixels and five discarded outer-canvas background pixels.

The first actual Forward+ capture exposed unexpected cuff transparency:
`cuff-alpha-rejected-native.png`. The final source capture repairs opacity only
inside the reviewed cuff material polygon, retaining all RGB and outer alpha.
The raw generation stays intact. Thirteen negative controls, two same-output
builds and a clean imported-checkout replay pass. See `build.log`,
`isolated-build.log` and `determinism.json`.

The standalone source-preview project uses the existing HDR readback helper;
it loads PNG pixels directly at 1:1 and does not load or alter production rigs.
The 1440×760 black/gray/white capture is Forward+ / HDR 2D on RTX 4070 SUPER,
with the shared GPU lock held and ComfyUI stopped. `capture.log` contains the
actual renderer, exit-success output and no errors. Native image:
`../../images/NE-222-walk-sleeve-source.png`.

```powershell
python tools/comfyui/gpu_lock.py -- godot --path pm/Nest-Egg/attachments/NE-222-walk-sleeve-source/native --quit-after 120 -- --root=<absolute repo> --out=<absolute PNG>
```

`affected-tests.log` is the actual `run_tests_changed.sh` selection against the
fixed pre-change 5dd1a3f9 baseline in the isolated checkout: zero Godot suites,
because this source is unregistered. Source assertions and native preview are
reported separately, not as gameplay tests. The independent EncounterSuite CI
failure is tracked in NE-249; no known-failure exception is added.
