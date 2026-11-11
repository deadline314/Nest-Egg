# NE-292 — encoded final override integrity

Pure published base: `64905fba7ce1aaf03e235331d7ced1e4e711d106`. All baseline tools and fixed Rin inputs were materialized from this Git object, never from C's unpublished guest/source-record/crop-phase changes. C product and pm files were not changed by this delivery. The original NE255 CPU review remains in its original work directory; NE292 is the independent fault-tolerance fix opened by Root.

The candidate validates actual PNG format, RGBA mode, exact dimensions, PNG CRC/structure and full pixel decoding. Context managers close both header and decoded image handles. The cutter validates every final override before replacing parts/rig/character. Build uses the same helper and retains its existing failure exit behavior. Valid override PNG bytes are copied without re-encoding. Failed runs may leave the existing private `parts.tmp` staging folder; accepted outputs and all source originals remain unchanged. No foreign temporary directory is cleaned.

## Exact candidate

`candidate.json` and `candidate.patch` contain only:

1. `tools/comfyui/cut_layers.py`: one `validate_final_override` helper and replacement of the final three-line header-only guard.
2. `tools/comfyui/build_character.py`: replace the final override header guard with the same helper, preserving SystemExit behavior.
3. `tools/comfyui/test_final_overrides.py`: eight permanent synthetic CPU regressions. Real constructor, complete schema, real check_spec subprocess and real cutter are used; only the output folder is redirected to the test temporary directory. No source_rebuilds, guest art, model or Godot dependency.
4. `.github/workflows/art-cuts.yml`: append exactly `python tools/comfyui/test_final_overrides.py` after the existing eight CPU script calls. The original final call is `python tools/comfyui/test_hand_attachments.py`; no other CI configuration changes.

Do not stage whole C build_character/cut_layers files: their separate retained-source/crop-phase WIP must remain. Use the published candidate blobs for staging and apply these same narrow changes to the C union separately.

## Validation

| Check | Actual result |
|---|---|
| First focused override probe | 6 tests / 2 failures on original; candidate 6/0. Original logs remain in raw |
| Final complete-schema permanent test | **Original 8 tests / 4 expected failures → candidate 8/0** |
| Final failures | Truncated PNG; RGBA TIFF named .png; PNG with valid CRC but broken IDAT; second corrupt override after a valid first override |
| Existing published CPU pipeline | All original **8 scripts pass**: source alpha, joint caps, mask delivery, point mask cache, point validation, cache options, registered layers, hand attachments |
| Independent read-only reader | All 687 ZIP members verified by SHA/size/CRC; eight old/new fixture sets independently compared; all sources unchanged; refused candidate deliveries unchanged; legal PNG original bytes identical |
| Reader adversarial controls | Raw one-byte corruption rejected; changed delivery with recomputed ZIP/member hashes still rejected |
| Godot/native/model/performance | Not run or claimed for this CPU integrity fix |

The first D-only legacy mask test was rejected for lock-root metadata/missing published enforcer rebuild input; both rejected logs remain. The initial hand regression lacked published Rin character.json, then its published near-hand PNG; both rejected logs remain. Only after these exact `64905fba` dependencies were added did `ne292-pipeline-test_hand_attachments-v3` pass. No test, expected hash or approved asset was altered to get that pass. Existing source replay itself remains CPU-only; its approved PNG assets are already published and the D copy retains them.

Reader v1 correctly verified raw members but its final `OK` log check assumed LF and rejected original Windows CRLF. Its source/log remain outside raw as `reader-v1.*`; v2 parses log lines without rewriting original bytes. `reader-v2.stdout.json` and `reader-controls.stdout.json` are the successful receipts.

## Reproduce / verify

```powershell
python -B -X utf8 verify_ne292.py --raw-root C:/absolute/NE292-evidence
python -B -X utf8 reader_controls.py
```

The reader uses the sealed index/raw archive and Pillow, makes no filesystem changes and does not consult current C images. The `--raw-root` folder holds index.json and raw.zip. Full original synthetic before/after PNGs, malformed encoded files, source/accepted-delivery snapshots, logs, receipts and published tool/recipe source snapshots are in raw. It is a small 850,222-byte packet, not an RGBA frame extraction or rewritten log summary.

To rerun the permanent regression, start from the exact published base in a separate checkout, apply candidate.patch, install the existing offline CPU dependencies, and run the new script plus the original eight workflow calls. C's WIP is unnecessary. The unchanged affected-range engine selector remains for Root's adoption step; no Godot group is claimed by this Python-only review.

NE255's final fresh-session/new-character acceptance is **not** satisfied by NE292. NE267 art, new NPC gait and S18 material acceptance remain independent.
