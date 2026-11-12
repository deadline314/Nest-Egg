# NE294 generator foundation — exact CPU delivery

Base: `78c367b1efc2f7945196d9373b24c3d8377394ba`. All changes live only in the owned linked worktree. Six LF source files are frozen in candidate-manifest.json / candidate-source.zip; no primary, PM, index, product geometry, player, save or navigation changes.

- Area owns h (default24), including bounds, checks, slice, overview/render, text report, LevelData output and all three main loops. Grid rejects negative/outside coordinates before writing.
- Explicit RouteState + Area.route_gate/route_platform bind boolean flag/mechanism/ability facts to actual grid rectangles. Missing facts/state fail. Multiple standing nodes per column, rise/horizontal/landing clearance and one-way-platform drops are checked. Caller-supplied movement bounds are a grid approximation, **not** player physics, trusted permission or automatic air-jump simulation.
- Existing three generator main paths deliberately retain the clearly labelled legacy all-open geometry check so this foundation does not silently change published geometry. NE298+ must declare actual progress states/gates; legacy successful geometry is not progression-lock evidence.

Evidence in raw.zip:

1. Exact original modules: before-source.zip. Original height48 actually24, negative coordinate silently wraps, closed gate is ignored by old all-open route: three retained red assertions / expected exit1.
2. Final new unit: 10 tests/0, including height48/16/default24 isolation, negative/missing/malformed state, gated flags/mechanisms/abilities, absent raft, actual multilayer nodes and solid-floor versus drop-through. Standard-library mocks verify optional Pillow's call dimensions without a new CI dependency. Additional real CPU Pillow PNGs height48/16 read back as144x316 /144x124; no native image claim.
3. Original check_channel_generation.py: 10+10+9 =29 checks/0, unchanged tool. No engine.
4. Old→candidate three generators, each exit0: all216 inventoried data files byte-identical on the same Windows/PYTHONUTF8=1 execution. Baseline-generated.zip retains the actual baseline bytes. Published→old generator already differs in3 non-EOL files (ch1_stall_map.json/ch1_warehouse.tres/ch2_market_gate.tres), plus Windows EOL differences: explicitly retained, not fixed/shipped. All216 current data files restored to their exact before hashes.
5. Five Python files: original select + changed.sh exit0, actual0 Godot groups. No existing discovery covers tools/level/test_level_kit.py, so the allowed sixth workflow file adds one explicit adjacent Python command. Final six-file select and original changed.sh also actually select0, not ALL. Both phases/logs are separate; this does not claim the remote full CI already passed.
6. First old Windows-cp950 JSON self-read failed; preserved baseline-first-encoding-red.* and stderr. Accepted baseline declares PYTHONUTF8=1. Grid.write now explicitly reads its own UTF8 file with UTF8.

Read-only portable verification (no Godot): `python verify.py`. Root can take the exact six candidate paths from the source ZIP; the new test and workflow line belong together. No further engine work or source changes are pending for this foundation.
