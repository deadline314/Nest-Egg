# NE-255 — source coverage during offline cuts

Base: `dbce3fa44ccec6d3bef4c87b4e82d19eb3c3501a`.

`preserve_source_alpha: true` separates binary part ownership from source coverage. Visible parts retain source RGBA; stage completions retain the stage alpha; generated crops retain their premultiplied-resampled alpha; caps multiply coverage. Legacy defaults and source cleanup policy are unchanged. Completion cache keys for this opt-in mode include source/stage RGBA and reject unkeyed legacy completions. Explicit selective exports preserve unselected outputs. Invalid option types stop before output creation. The old empty-parts export fixture also exposed an unconditional depth reduction; empty depth now defaults to zero, with existing nonempty exports unchanged.

## Reproduction and results

- `python tools/comfyui/test_source_alpha.py`: 11 tests pass. Exact same final test against the frozen baseline cutter: 10 failures, including loss of soft edges, original/source alpha, cache invalidation and selective alpha export. `check_spec` in that negative run is current, so schema validation is not counted as a baseline failure.
- Six offline programs run by the new independent `art-cuts.yml` workflow: source alpha, joint caps, mask delivery, point cache, point validation, cache options. All pass locally, 2.204 seconds total; this is CPU fixture time, not game performance.
- Unchanged `tools/run_tests_changed.sh`, explicit pinned engine, six shards: no affected Godot suites. No engine tests are claimed from this result.
- `actual_source.py`: original Hong 1024×1536 reference, unchanged source SHA. Only in a disposable reference, existing alpha-floor 40 cleanup removes 12,122 faint pixels; RGB and retained coverage remain unchanged. This is not a new approved body or replacement portrait. Frozen old vs current default cut, diffuse, normal, character and rig exports are byte-identical. Opt-in full-canvas RGBA equals the cleaned input exactly. Two rebuilds have identical receipts and hashes. Native-size black/gray/white composites were viewed; the attached image uses a native crop, no enlargement.
- Source/portrait/canonical runtime assets are untouched. No model generation, native actor, pose anatomy, animation, GPU performance or human acceptance is claimed.

## Retained failures

The first texture assertion incorrectly sliced a cropped output as if its transparent canvas padding had been retained; it was replaced with the actual inverse source transform. The first generated-crop assertion incorrectly expected the prior floating premultiplication/uint8 conversion to reproduce every generated RGB byte; the final test compares generated alpha and preserved original pixels exactly and compares completion RGB to the existing path. These failed logs are retained.

Broader hand-attachment validation also fails on the unchanged baseline: approved PNG compression hashes differ after re-encoding in this environment. A read-only diagnostic found byte-identical decoded RGBA for the derived layers; no approved assets or expected hashes were replaced. This is a separate source-rebuild portability issue, not counted as a passing regression. Raw baseline/final logs and pixel diagnostics are retained for the follow-up.

Archive contains frozen baseline modules, final/failed test logs, actual source probe, disposable cut inputs/outputs and environment versions. Comfy/SAM models and generated hidden-layer candidates are not used by this delivery.
