# Separate CutsceneSuite baseline/candidate isolation

Immutable baseline896, same private project, separate Godot process and freshly
created user directory for each run. Baseline replaces only StageLayers and
test_cutscene with exact immutable Git bytes; the new helper/UID remain on disk
but are not referenced by baseline test_cutscene. Candidate restores the canonical
three files and the actual imported UID. No source/failure filters are changed.

- A baseline:1821 checks,0 failures, process exit0.
- B candidate:1829 checks,0 failures, process exit0; exactly8 added checks.
- Both:0 SCRIPT ERROR,0 ObjectDB/RID/resource exit leak lines. The same25 deliberate
  fixture ERROR texts and occurrence counts remain in both original logs.
- Each source-before/source-after27,674-member dictionary is exact. A/B differ in
  only the two requested baseline files. Candidate3+UID and full source dictionary
  are restored exactly after B; old official26-group receipts are never rewritten.

Process receipt `seconds` includes the run and immediately following full source
SHA audit: A134.8588s, B114.4584s. This is not performance or pure Godot wall time.

`raw.zip`(5,002,475bytes,14 members) contains original logs, commands/exits,
before-after manifests, comparison/restore receipts, actual wrapper, and both
immutable baseline source files. `raw-index.json` preserves exact SHA/member bytes.
`read_packet.py` verifies ZIP SHA/CRC/all members, counts, unchanged intentional
diagnostics, isolated source epochs and final restoration without an engine or
extraction. It completed exit0.

This direct-scope control rules out a new exit leak in these CutsceneSuite runs.
It does not assign a cause to, suppress, or erase the four preserved original
26-group filter-allowed exit diagnostics.
