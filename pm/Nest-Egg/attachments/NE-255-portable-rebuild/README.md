# NE-255 — portable registered source reconstruction

Base: `2cc1bbbc5d14938fc8449a3688d8d9e5bca2954c`.

The prior broad hand-source regression failed in this environment even before the alpha-mode delivery: re-encoding unchanged approved RGBA produced different PNG bytes. Read-only derivation verified every pixel against the pre-existing approved PNGs, including transparent RGB. Their old encoded SHA-256 values are unchanged.

## Contracts

- Twelve approved hand/coat PNGs and two native support-hand PNGs are frozen under each source packet's `source/approved_outputs`. The copies are checked against existing approved hashes and original source provenance before registering; no new image was generated or approved. Existing source hashes and expected output hashes remain unchanged.
- `registered_layers.py` validates the complete derived layer set, input PNG integrity, RGBA mode/size, and every decoded RGBA byte before returning any output payload. It then publishes the original approved PNG bytes, not current encoder output. Identical files retain their timestamps; changed files stage/flush/sync then replace atomically. Write/sync failures preserve the previous file and clean temporary files. This is per-file atomic publication after whole-set validation, not a multi-file filesystem transaction.
- The retained `rin_s33.json` recipe owns these sources. The current game Rin recipe is `rin.json`; its character/art/rig/animation is unchanged. Source documentation now points at the correct retained recipe.
- The support-hand replay was already broken by an older whole-file cutter pin. Git history located its exact pinned revision `0a09e1bdd97c32d947e9224267fffc8f26c63c6e`, SHA `5c662add546e3ccc0b23f1e0e8a817f8d86608a4e53dc923cf47e8b7cdf64154`. Both the AST and exact function source of `make_normal_map` match the current implementation. Replay now pins that exact function source (SHA `e31b1bb62da3941e618aca6554445432ff5eb91bcb93edc94eb284395f448444`), rejects duplicate/decorated definitions, and still validates all produced normal pixels and original encoded bytes. Algorithm changes fail; unrelated exporter changes pass. The old whole-file pin and processing proof are retained as provenance, not silently replaced by a new whole-file hash.

## Verification

- Eight CPU offline programs pass; delivery log records the duration. New registration/source suite: 16 tests. Includes compression differences, malformed layer set/format/dimensions, path escape, visible/hidden one-byte corruption, late failure before publication, no-op writes, replace/sync failures, actual support-hand rebuild, altered normal algorithm/decorator/duplicate, corrupt frozen source and runtime normal corruption preserving previous output.
- Existing hand-attachment regression now passes for both complete source packets in fresh sandboxes. It checks original encoded output hashes, two identical replays without timestamp changes, all 50 repaired source metal-reflection pixels, reencoded-input rejection and one-byte derived-error refusal before replacing output.
- Actual registered hand and coat sources run twice against 20 existing source destinations. All original PNG hashes and timestamps remain unchanged. Native support-hand diffuse/normal replay has exactly the original two PNG hashes. The static graphic compares native source crops of all 14 outputs; every complete image is byte-identical, not merely visually similar.
- Required unchanged affected-range runner, explicit pinned Godot and six shards: no affected Godot suites. No game/native/hardware performance or full rig acceptance is inferred from CPU source checks.
- New independent offline CI job includes these checks and source folders. Prior alpha-only offline CI was green; this delivery's remote result must be observed after push.

Archive includes old source scripts/manifests, old pinned cutter, before-failure logs, final test/fault-injection logs, actual source replay receipts, output hashes, source graphics and replay scripts. The prior broad-regression PNG-hash failure is retained in `hand-before.log`; the old support replay pin failure is retained in `support-before.log`. The approved source and runtime assets are not re-generated or switched.
