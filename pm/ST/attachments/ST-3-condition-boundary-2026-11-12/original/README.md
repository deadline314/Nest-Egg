# ST-3 runtime condition boundary — isolated delivery

Base: `f80d0d9fe30732981d0d657e4ba3a983c820f427`; branch `codex/st3-condition-boundary-20261112`.
Only `core/story_rules.gd` and the existing `tests/suite/test_cutscene.gd` extension are candidate changes. Nothing was adopted into primary C, PM or Git index; no commit/push was made.

`holds()` preflights the complete bounded structural schema once, then evaluates through the original private recursion. Unknown/malformed children cannot pass through `not`, `any` or false-first `all`; errors contain the nested path. Valid empty conditions, omitted flag `equals=true`, StringName compatibility, original `same_value`, caller-provided candidate facts, legacy requires/custody, and generic later-chapter receipt/account IDs remain supported.

This is a structural boundary subdelivery. It does **not** claim that strict declared-facts / locked-ledger snapshot validation has been connected to all runtime callers, nor that the entire ST-3 mother ticket is complete. No death sequence content or other chapter schema was changed.

Literal `equals:null` is invalid (existing STORY_CONDITION_CONTRACT.md explicitly excludes null). This differs from a facts reader returning null: its original comparisons with false / empty string / 0 / 0.0 / unset remain valid. The new tests cover both literal-null rejection, including under `not`, and all five fact-null defaults. Runtime StringName and omitted-equals compatibility are intentionally broader than the pure StoryConditionTree contract. Shared bounds come from that class, without borrowing its chapter-one receipt/account whitelist.

## Evidence

- Clean original: unchanged 13-case probe, 6 actual failures, exit1, no SCRIPT ERROR; original source is byte-identical between 6fb and f80. The earlier import-overlap/resource-error run is retained and explicitly invalid, not the accepted red.
- Final f80 candidate: 74 new checks / 0 failures, exit0. Original CutsceneSuite assertions are retained. Expected `test_bad_cutscene` errors use the unchanged original filter.
- All 524 formal `data/story/*.json` when nodes × live facts plus nine alternate scalar/held/receipt/account strategies = 5240 comparisons / 0 mismatches. Both result and reader-call count match; input and actual State snapshots unchanged. This is sampled equivalence, not every possible world state or a natural playthrough. Legacy body differs only by replacing its global class_name line to permit loading both scripts together; this is not a full historical checkout.
- Original `tools/run_tests_changed.sh f80d0d9fe30732981d0d657e4ba3a983c820f427`, SHARDS=2, original console executable, default `--headless` (no audio driver adapter), five isolated user-data environment variables: **22 groups, 45500 checks / 0 new / 0 known, runner exit0**. Original runner wall831s; wrapper884.3381717s includes post-run hashes. 13157 tracked source/resource files fixed before/after; generated GD UID context recorded separately. Exact argv/env/filters/known-failures/commands and both original shard logs are in the archive. No concurrent import was used in the final run. Wrapper records the original runner exit; it does not invent per-child exit receipts.
- 0 SCRIPT ERROR. Do not claim zero ERROR or zero leaks: original filter permits shutdown diagnostics. Shard0 reports 6 AreaRID / 6 CanvasItem / 16 ObjectDB / 8 resources; shard1 reports 1 CanvasItem / 9 ObjectDB / 5 resources. All original messages remain.

## Read-only verification

Run `python verify.py` from any directory (script resolves this packet). It verifies original ZIP member SHA/CRC, clean red, final short and equivalence results, final two sources and original affected receipts. No engine or worktree is required. `candidate.json` gives the exact two source SHA values; their LF files are available under `source/`. The ZIP keeps raw bytes, including original CRLF logs. Test user-data caches are omitted; command/source/log/result evidence is retained.

For an engine rerun, start from the exact base, apply only these two source files, import serially if needed, then use the archived original command/environment. The original `run_official.py`, runners, filters and known failures are preserved inside the raw archive. No rendering, GPU, audio capture or performance claim is made here.
