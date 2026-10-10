# NE-246 original cloud ALL run evidence

This bundle records the original run at source checkpoint `a5f2a1ba9eb64233b56108c3e930c68bffa52158` (parent `2dab08d7a433d49af5ae8419ddcc794a16c83994`) against `origin/main` `7e3289808d00e339c0662f26d1ab61c02de0f9d6`. No engine was rerun to prepare this evidence.

The original `SHARDS=1 tools/run_tests_changed.sh origin/main` selected all 83 groups, reached natural EOF, and exited 1 after 1,390 seconds: 86,162 checks, 126 new failures, 0 known failures, and 3 script errors. `raw/shard_0.log` is the complete unmodified shard output; `raw/runner.console.raw.log` is the complete runner console. Import and preflight logs are included byte-for-byte. Their SHA-256 values are in `run-manifest.json`.

`failures.csv` enumerates all 126 original `FAIL:` entries. `raw_log_line` points into `raw/shard_0.log`; `suite` gives the runner suite name; `suite_source` identifies the corresponding assertion source line. The classifications group 87 failures with the authored story-owner migration or the old test contract, and 39 with independent product behavior: 37 failures downstream of formal flag parsing plus one atomic request cancellation invariant. None of the 126 is supported by evidence as environment-caused. The 3 script-error locations and raw messages are recorded in `run-manifest.json`. Expected negative-fixture `ERROR:` output is retained in raw logs and is distinct from script errors.

The owner-migration group includes old test assumptions for `ch1_c01_open`, `ch1_c09_wake`, `ch1_c14_home`, and the former `ch1_b_dinner` scene, along with old scene-length, route, budget, and death-flow expectations. Root's local review identified `data/story/ch1_kasa` as the authoritative replacement source. The formal-flag product errors include the runtime String-vs-bool error at `autoload/story.gd:570`.

`source-manifest.json` lists all 148 changed paths from the tested parent to the tested source HEAD with Git blob IDs and LF-normalized SHA-256. This is evidence for the failed checkpoint only; it does not indicate ticket completion or chapter readiness.
