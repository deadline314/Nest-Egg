# NE261 final stage5 — original public WAV names retained

Final entry: `canonical-7-manifest.json` (five source files plus two actual
Godot-generated UID metadata files, individually hashed). Actual canonical
files are directly under `tools/` in this directory. C/pm/Git index and all
existing protected D runtime files were not modified.

Only `tools/audio/melee_pcm_clock.gd` changed from stage4: after successful
bus-Master/SFX WAV saves, `DirAccess.copy_absolute` also saves the original
public `melee-master.wav` / `melee-sfx.wav`. Copy failure records bus/source/
target/error and makes the producer exit nonzero. Four-bus sample clocks,
segments, actions, damage, target distances, metrics and limits are unchanged.
Other four sources and both previously imported UID bytes remain identical.

The one new complete published8c headless/WASAPI run is
`runs/1794468251143191900`: engine exit0, no diagnostics/GPU, 1506 published
context hashes stable, four buses each2,252,800 frames at48kHz. Actual PCM
sample/content readers accept24 segments and18 real damage events; original
loudness report problems0. Both public WAVs are9,011,244 bytes and byte-exact
copies of their bus files. No native rendering, performance or new human
listening is claimed; armor target only, not all-material or held-mode scope.

The only additional small audio control is
`runs/1794468143021993100`: an actual directory at `melee-master.wav` makes
copy fail with a real error, contextual path and engine exit1. Other artifacts
are retained unchanged. Existing29 counter/action/compatibility controls pass.
Stage4 and its v1/v2 source/results/raw archives remain untouched; its complete
old red-green archive is still at D:/NestEggDeliveries/NE261-20261112/ with
its original SHA/CRC index. No raw was cut or silently reconstructed.

The retained detached validation tree is
C:/Users/stanl/.codex/worktrees/ne261-audio-validation-20261112/Nest-Egg,
published base896d3e8a7fb1b0018df0aec47ed8c5a37bb881c0. Only this final
clock helper was overlaid onto its prior five-source/two-UID candidate;
no reimport. Its original selector and `run_tests_changed.sh` again selected
**0 groups**, exited0, no SCRIPT ERROR, and all3871 source/context hashes
stayed fixed. Zero suite checks are claimed;29 controls and24 actual audio
segments are separate scopes. Raw commands/output are in
`work/ne261-official-stage5` and delivery/official-raw.zip.

`delivery/index.json` hashes every original ZIP member. Both accepted and
requested legacy-directory-negative original bytes are in accepted-raw.zip;
source.zip is the final seven files/readers, not another tool format.

Portable, read-only recomputation (no engine, no input changes):

```powershell
python -X utf8 verify_delivery.py
# Or supply an exact copy of the delivered accepted ZIP:
python -X utf8 verify_delivery.py --raw-root <accepted-raw.zip>
```

This validates original engine exit/log/source guards, all deployed-source
path mappings, four-bus counter/PCM samples, real actions, both public aliases,
the genuine directory rejection and unchanged loudness rules. Python requires
the existing NumPy/Pillow dependencies. Ordinary probe/report use continues
to allow no external wrapper sidecar; formal delivery verifier always requires
the original actual wrapper receipts. The earlier published8c-vs-a4 source
differences and all historic acceptance limits remain documented in stage4.
