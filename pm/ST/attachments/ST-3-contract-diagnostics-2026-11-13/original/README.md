# ST3 CI intentional-contract diagnostic repair

This packet is ready for source adoption; it does **not** claim the local full CI matrix passed.

Base: `b2abac978cf6a14feaf254bb608b3779299fa89f`. Only the seven Python files in `candidate.json` change. All seven were read-only checked to contain LF, with no CRLF rewriting after the test epoch. No GD/data/catalog product, primary workspace, PM, Git index, commit or push was changed.

The original published patroller `contract` fixture deliberately changes the true gate result. Its ten assertions passed and engine exited 0, but the newly correct Catalog error made the old strict runner fail. The repair permits only a trusted caller's fixed tuple of complete diagnostic lines, with exact occurrence counts. Matching uses whole lines after `str.strip()` leading/trailing whitespace normalization; it is not raw-byte matching. Full raw logs/counts survive; the bounded 32-line/512-character summary never authorizes output. Missing, duplicate, wrong-path, extra ERROR/SCRIPT/leak diagnostics still fail. Probe result self-report cannot authorize errors. Default remains strict zero.

Five callers declare 22 deliberate mutation cases. Their original complete flow has 98 child processes (including marker audit); other owners' callers retain the zero-diagnostic default. Each changed caller's existing source list now additionally records the Catalog module and its catalog/ch1/ch2/migration JSON inputs.

## Actual checks

- Original local patroller contract red: engine 0, ten assertions / zero assertion failures, one Catalog error, old runner rejects. It reproduces the original GitHub failure.
- Windows unit run: 11 executed PASS, nine original POSIX fixtures skipped by their unchanged condition. Actual existing Ubuntu/WSL run: all 20 tests executed PASS, zero skips, including all original POSIX process/timeout tests.
- Original selector `--base b2ab --explain` and original `tools/run_tests_changed.sh b2ab`: both exit 0, zero Godot suites. These are Python-tool changes; real completion probes are a separate scope.
- Original 4.7.2 Windows console executable, original headless Dummy caller commands, no adapter/GPU: patroller 8/8 PASS (150.721s), evidence 14/14 PASS (242.280s), reading seven PASS then `rumor--accepted` RED (136.982s for partial reading CLI). **29 green / one red; 98 not completed.** That last case has 26 assertions / zero assertion failures and engine exit 0, but one DummyTexture RID, one Image and one ObjectDB shutdown diagnostic. All three are unexpected and remain rejected. Fail-fast stopped the rest of reading plus marker/voice.
- Single bounded original-helper `rumor--accepted` control: 26 assertions / zero failures, zero diagnostics, PASS (19.724s). This does not erase the preceding red, prove a fix, or establish an engine root cause. That invocation used tool-call stdin and the saved original helper; no pre-execution disk runner/hash is claimed. Its actual child command/PID/log/exit/result remain preserved.
- The 4,057-entry tracked runtime/test/author/config source projection was byte-stable before/after the partial batch; it is not whole-repo raw-asset prehashing. Seven candidate bytes match that frozen projection.

The actual GitHub job used a different safe Linux engine, SHA256 `2a6aae0314b37ecf1f2dbd29f665f2970391e82a1b53ffb4520af3bf07a2b464`. The existing published recipe includes `dummy-texture-threads.patch`; stock Windows is not claimed equivalent. No matching local safe binary/receipt was found in the documented bounded locations; no new engine was downloaded/built. Root will adopt the seven files and require the original safe CI to finish all 98 cases and the original workflow. No shutdown diagnostic is ignored here.

## Portable contents and commands

`source.zip`: seven exact candidate sources plus seven original baseline sources. `raw.zip`: all local commands, source projection, raw logs, process/exit/result/slot files, first red, single original-helper control, unit and selector logs; plus the byte-exact downloaded original GitHub artifact and clearly labelled decoded connector job log. Machine Python caches are excluded. `archive-index.json` checks every member's size/SHA256/CRC. Neither ZIP needs either worktree, engine or network to verify.

Run after relocating this directory: `python verify.py`. It reports packet integrity PASS **and** the preserved local 29/1 RED/incomplete scope. It does not run an engine. Exact original CLI/working-directory/environment records are in `raw.zip` (`*-command.json` and per-case `*-process.json`). Candidate files may be extracted at their original `tools/` paths; source adoption belongs to Root.

Root's additional independent self-report-injection four-control proof is separate and can be attached by Root; it is not retroactively part of these frozen 20 unit tests.
