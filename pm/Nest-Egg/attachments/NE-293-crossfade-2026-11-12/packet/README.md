# NE293: amplitude-domain crossfade candidate

Only two candidate paths belong to this delivery: `core/audio/crossfade_player.gd` and appended regression checks in `tests/suite/test_audio.gd`. Primary C sources, protected D trees, PM, index and commits are untouched. The independent detached verification tree is `D:/NestEggVerification/ne293-crossfade-20261112`, advanced from historical cb2f0874 to published `4a2f9ecfaf3d98db102e79b37420821f714549ca` before final verification. Candidate bytes did not change during that advance. See `published-candidate-2-manifest.json`.

## Intent and exact curve change

Public volume targets and `_targets` remain dB. Each voice's existing fade duration and endpoint remain unchanged; `_rates` now means amplitude per second. Initial fade and `_fade_to` compute the absolute distance between linear amplitudes, and `_process` moves `volume_linear` toward `db_to_linear(target)`. This intentionally changes the old linear-in-dB curve. It does not claim preservation of that old interpolation or constant energy for arbitrary musical content.

The original dB `is_equal_approx` check and `SILENT_DB + 0.01` inactive-voice stopping threshold remain. Only gain updates require positive delta; the stop check still runs at zero delta. No Tween, mode, dependency, extra voice, gain boost, background layer, target-volume adjustment or Music/NE154 duck-envelope/clock modification was added.

## Narrow causal results

`probe.gd` uses the actual product CrossfadePlayer. 26 state checks cover first/same stream, fade0, midpoint, unequal durations/volumes and their endpoints, rapid midfade reentry, zero delta, initial/set-volume targets below −60 dB, small-gain stop, seek, real tree pause eligibility, null stream and free during playback. It preserves the first 25 checks and adds the zero-delta inactive/fade0 release counterexample.

| Source epoch | State checks | Raw result |
| --- | --- | --- |
| Published original | 26 / 4 failed | `runs/1794473416764590300-baseline-state` |
| Rejected whole-_process early return | 26 / 1 failed | `runs/1794473435109872200-candidate-state` |
| Final gain-only delta guard | 26 / 0 failed | `runs/1794473446128261000-candidate-state` |

Earlier 25-check snapshots and the initial zero-delta roundtrip failure are also retained. All narrow runs used actual headless/WASAPI, null RenderingDevice and empty adapter, no engine diagnostics. These are API/state and audio checks, not rendered/native Forward+ or performance acceptance. Pause checks explicitly disclose manual fade stepping with an ALWAYS fader in a genuinely paused tree; the later original MusicSuite checks the separate pause/duck integration.

Two independent WAV resources contain exactly the same fixed coherent PCM: signed16 3276, stereo, 48 kHz, two seconds. The actual Capture effect records its own isolated bus before Master, with pushed-frame anchors, zero discards and exact raw float count. Muting Master only prevents the synthetic DC test reaching speakers; its pre-Master captured bus is unchanged.

| Product source | Actual frames | Lowest middle 50 ms RMS relative to its own steady input |
| --- | ---: | ---: |
| Original | 82,432 | −23.870977 dB |
| Final | 82,432 | +0.008686 dB |

`verify_pcm.py` independently recomputes the actual raw floats, unchanged fixture hashes and the only runtime-source difference. The eight middle 50 ms windows remain within ±0.25 dB for the new algorithm; this tolerance allows AudioServer property/mix publication quantization. Original windows fail clearly. The +0.0087 dB offset is consistent with retaining the original −60 dB endpoint rather than changing it to zero amplitude. This fixed coherent input proves removal of the algorithmic trough; it does not prove music has constant energy or close the original hold loudness requirement.

The additional real unequal pair in `unequal-pcm/runs` uses old0dB→new-6dB, outgoing0.4s/incoming0.8s and identical fixed PCM. Each records75,264 frames with zero discards and no diagnostics. Both retain original endpoints/deadlines: actual process-delta sums0.402778s and0.805556s, bounded by one measured0.006944s step. The final per-process amplitude curve matches within1.4e-6; actual50ms PCM errors versus the correct unequal curve are at most0.008246 of the initial reference RMS, versus old0.585160. `unequal-pcm/verify.py` derives its PCM publication bound from the observed512-frame mix quantum plus one measured process step, multiplied by the maximum source gain slope. Different durations naturally permit a trough, so the equal-level flat gate is deliberately not used. Only the global class declaration is omitted from the two isolated original-body copies; both product files remain unchanged throughout these captures.

## Regression scopes, kept separate

Original AudioSuite and MusicSuite smoke-runner specialization: 27,821 checks / zero failures, 14 original intentional error lines, no SCRIPT ERROR, original filter accepted. All original assertions remain; nine permanent crossfade checks were appended. No permanent test depends on the new PCM tools or a physical audio driver.

`published-official-1794474159874263500` is explicitly **WASAPI enhanced30**, not the CI/default entry: 47,507 checks / zero new or known failures, script exit0, 755.290 s wrapper time / 750 s original-script wall time, 4,052 frozen inputs unchanged. Two actual child exits are zero. 136 raw intentional ERROR lines remain; original filter reports no unexpected error, no SCRIPT ERROR or shutdown leak lines. The complete original wrapper/commands/logs are retained, because changing the audio driver is a different configuration.

The separate `published-default-official-1794475000448228800` run uses the original Godot executable directly, original headless/default-audio flags, original `tools/run_tests_changed.sh` at base4a2f9ecf, SHARDS=2 and original selector/filter. It completed 30 groups, 47,507 checks / zero new or known failures, original script exit0, 616.856 s outer time / 600 s original-script wall time. 4,052 frozen inputs were unchanged. Raw ERROR lines are 44+93=137, all accepted by the original filter; no SCRIPT ERROR or shutdown leak diagnostic occurred. The additional passive Windows observer failed to retain individual child exits (`children=[]`); its original output and strict reader failure are retained, and no child exit code is invented. The original affected entry waits and checks complete results/filter output; that original entry result is verified independently of the failed extra observer. Both imports retain original logs/commands/exits and seven generated existing-script UIDs as separate metadata, not candidate product files.

## Actual-track hold replay

`hold-replay` retains the original `ne261-published-five-holds-v1` 34-row schema. Its public inputs, distances, natural recovery, charge/repeat/sustain readiness, original times/volumes, true damage/material/physics-space and hum/event observation remain unchanged. Only deployment URLs and the explicit source label changed; `contract-before-replay.json` records byte/AST/data checks. Content, metric and 6/10 dB limit functions are AST-identical to the original reader. Source is now published4a2f9ecf plus only these two candidates, with no primary C26 geometry or NPC WIP.

The two original NE261 maul idle/bed failures stay preserved in their original delivery. The new run `1794475671530991700` completed in69.606 s, engine exit0, no diagnostics, actual headless/WASAPI/no GPU, with4,052 frozen inputs unchanged. Four buses each contain2,489,856 real frames at48kHz, no drops;34 rows /10 hold rows /312 original hit-pass calls /32 true hold damage events satisfy the unchanged reader. All original loudness rules pass (`problems=[]`). Maul idle remains exactly-43.717873dB, while its actual bed is-27.995607dB (15.722266dB separation); hum volume and all cue endpoints are unchanged. Ambience remains zero/neutral. The source repair improves the transition, rather than raising a configured background or lowering a weapon. A live track/fade/hum state is captured at each row boundary. This is actual software-input game audio, not human listening, physical controller or rendered Forward+ acceptance.

## Public portable packet

`delivery/packet293/verify_delivery.py --raw-root D:/NestEggDeliveries/NE293-20261112` verifies the local source/proof ZIPs and the separately stored large before/after PCM ZIPs by SHA, member SHA/size/CRC; it then extracts to an owned temporary directory and runs state, fixed-PCM, default affected-scope, original hold-RED and new hold-GREEN readers in fresh Python processes. It accepts an external folder through `--raw-root`; no absolute source-repo location is required after copying the packet. NumPy and Pillow are the existing audio-report dependencies. No Godot, GPU, download or human listening is invoked. The original red ZIP is a byte-exact copy of the already retained NE261 metadata capture; it is never rewritten as green.
