# NE-255 new-reader character evidence

The 123 production paths in `production-v12-freeze-123.json` are the frozen v12 authoring/runtime/preview source. Original design, transparent source, source parts, spec, recipe and rebuild helpers remain ordinary files outside these archives. This is an isolated adult noncombat NPC demonstration, not new story content.

Read `REVIEW-v12.md` for the actual verdict and limitations. The original final joint checker records **358 failures / 120960 samples in each pair-only and as-worn matrix**; automatic acceptance remains false. Manual source/geometry/native-image review is recorded separately. A successful archive verifier or game test does not turn those failures into zero.

## Verify the complete raw history

Use ordinary Python 3.11+ with its standard library, from this directory:

```powershell
python verify_raw_archives.py
```

Or pass `--index <absolute-path-to-raw-archives/index.json>`. Verification streams every tar member without extracting it or touching source files. It checks archive and member-manifest SHA256, archive size below 50,000,000 bytes, every original member SHA256/size, unique safe member names and complete counts. The included small positive/negative controls demonstrate rejection of an incorrect inner member hash even when the archive and sidecar hashes are correct.

`raw-archives/index.json` lists each independently readable `.raw.tar.xz` volume and its sidecar. Volumes group explicit vN labels from the original paths, with unversioned records and frozen authoring separated; this grouping does not invent dates for unlabelled diagnostics. The sidecars preserve repository-relative original paths, SHA256, byte sizes and original modification times. Tar member times are normalized for reproducibility. All original files remain locally retained; the delivery avoids staging the same thousands of images and reports again as loose files.

The history includes original failures, rejected variants, final matrix frames/reports/geometry, source snapshots, native captures, generation logs, official test logs and independent review. Early normal-on/off diagnostic controls did not freeze all their original spec/parts: those images remain diagnostic evidence, not a replayable final character source claim. The frozen v12 snapshot and normal authoring source are kept distinct.

Representative original native PNGs live in `pm/Nest-Egg/images/NE-255-fresh-character/`; marker/locator composites are explicitly diagnostic and do not replace their raw 128px crops. The official source guard compares every tracked runtime/art/authoring/data/test/tool/CI source plus the exact 123 frozen paths before and after the original test runner. Test times under shared load are not isolated performance acceptance.

## Restore an original path

After verification, each tar volume can be read with standard tar. To restore the frozen 123 source paths into an empty scratch directory on D, extract `authoring-v12-01.raw.tar.xz` there; it retains the original repository-relative layout. To restore all historical paths, extract every listed volume into that same empty scratch directory. This requires the original uncompressed byte capacity and is separate from no-extraction verification. Use the complete repository at the recorded baseline for common game/tools, then overlay the frozen ordinary authoring/runtime/preview paths; the evidence volumes are not a complete Git checkout or model installation.

The separate performance volume, when present, adds only later original probe logs/metadata. Existing historical archives are preserved byte for byte rather than recompressed. An updated index counts both the original history and the added volume.

Current review and ledger documents beside the archives supersede earlier document copies retained within the raw history. Archived artifact hashes refer to their captured original bytes; final review metadata is separately versioned.

The verifier also reads the versioned `git-canonical-production-v12.json` beside it. It verifies all 123 tested raw archive members, their expected Git canonical SHA256 and Git blob IDs, without extracting source or requiring Git. Of 123 files, 23 text files change only CRLF to LF under the repository attributes; all 58 PNGs keep their exact raw bytes. Root separately checks actual staged bytes. The small control fixtures use explicit `--skip-production-mapping` because they contain only two synthetic members.

Delivery index/member sidecars are fixed LF bytes so Git normalization cannot invalidate their SHA256 links. The first 65 CRLF metadata files remain intact inside the later performance supplement under `original-metadata-crlf/`; all first 64 archive payloads are unchanged. This metadata repair does not normalize or replace any tested source, frame, PNG or archive payload.
