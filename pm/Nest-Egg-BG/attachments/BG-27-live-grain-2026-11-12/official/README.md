# BG27 live grain: isolated original-selector receipt

Official immutable base: `896d3e8a7fb1b0018df0aec47ed8c5a37bb881c0`.
Tree: `C:/Users/stanl/.codex/worktrees/bg27-live-grain-validation-20261112/Nest-Egg`.
Only the canonical three candidate files were copied; original candidate manifest
base a4f2 is retained unchanged inside the receipt. A real cold editor import
generated the new grain helper UID. C products/PM/index were not changed.

Import:72.2065 seconds, exit0, no script/error/exit-leak diagnostics. Original
`tools/run_tests_changed.sh 896...` with `SHARDS=1` selected26 groups and completed
51,928 checks /0 new /0 known; entry exit0,1486.9219 seconds (shell wall1484s).
All27,674 actual source bytes remain identical before/import/after; generated UID
also unchanged. This is functionality under concurrent machine activity, not
a performance result.

The original filters are retained byte for byte. The complete suite raw output
contains deliberately expected error fixtures and four historical-filter-allowed
exit lines:6 GodotArea2D RIDs,7 CanvasItem RIDs,25 ObjectDB instances,13 resources.
There are zero SCRIPT ERROR lines. Original-entry success must **not** be described
as a strict zero-diagnostic exit or as proof those exit leaks predated this change.
An independent CutsceneSuite baseline/candidate comparison follows separately;
this original26-group epoch is sealed and will not be rewritten.

Compact review packet, excluding immutable published assets and duplicate working
copies:

- `raw-minimal.zip` + `raw-minimal-index.json`:18 original logs/commands/process
  exits/full before-after SHA manifests/filter receipt members,3,792,449 bytes.
- `sources.zip` + `sources-index.json`:actual candidate3, generated UID, unmodified
  original test runners/filter/known failures and orchestration,38,891 bytes.
- `read_packet.py`:read-only SHA/member/CRC/receipt verification directly from ZIPs.
- `reader-correction.txt` + `read_packet-rejected-v1.py.txt`:first reader path-key
  mismatch and its original source. Original Windows-path UID metadata was
  preserved; only the reader ZIP lookup normalizes the separator.

Run `python read_packet.py`. It passed and explicitly prints the preserved raw
exit diagnostics. The older broader `raw.zip` and loose originals remain local
but should not be staged alongside the recommended compact packet.
