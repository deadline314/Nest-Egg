# NE-222 06c Melee failure reproduction

This is a CPU/headless test reproduction record on the clean primary checkout, not a code change. The tested checkout was `06c440760b91f882a8da2d1aedced1f7c04fcc50`; tracked status was clean. Godot was 4.7.2 stable (`ed1daf0bf`).

The requested six suites ran in four shards: 7,921 checks, zero new or known failures, 23 seconds wall time. A separate one-shard `MeleeSuite` run also passed all 25 checks. The three Melee failures from the earlier root comparison did not reproduce. Raw per-shard logs, hashes, exact commands, executable hash, and source-file hashes are in [report.json](report.json).

The earlier root comparison reported 8,020 checks with three Melee failures: buffered press did not chain to swing two; hit cancellation took 41 frames against a limit of 9; and swing three was not heavy. Its summary header says six nominal processes, while only four process IDs (0–3) have assignments; root confirmed the effective run used four processes. That run was in a different, modified verification checkout with concurrent capture/load, so these results do not isolate load as the cause.

A plausible timing race exists but is not proven: the command buffer expires against monotonic wall time (`melee_buffer = 0.22s`), while recovery and cancel eligibility advance in physics ticks. The first light attack has 0.16s recovery, 0.05s cancel threshold, and a 0.05s hit-freeze event. That leaves little margin under scheduling delay, and the buffer continues ticking during freeze. No threshold or test changes were made.

The prior failure run and this clean run together support “intermittent and unreproduced,” not “fixed” or “load-caused.” No tracked files were modified; no GPU work was performed for this task.
