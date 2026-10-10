#!/usr/bin/env python3
"""Verify the published NE-90 single-boot evidence packet and optional raw frames."""
import argparse, hashlib, json
from pathlib import Path
from PIL import Image

HERE = Path(__file__).resolve()
ROOT = HERE.parents[4]
PACKET = HERE.parent

def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--native-source', type=Path, help='Optional original raw ankle-120 directory for all 1,920 file checks')
    args = ap.parse_args()
    manifest = json.loads((PACKET / 'manifest.json').read_text(encoding='utf8'))
    for rel, expected in manifest['packet_files'].items():
        path = ROOT / rel
        assert path.is_file(), f'missing packet file: {rel}'
        assert sha(path) == expected, f'packet SHA mismatch: {rel}'
    audit = json.loads((PACKET / 'source/audit.json').read_text(encoding='utf8'))
    assert audit['source_hashes_unchanged'] is True
    assert audit['owner_mask']['candidate_equals_registered_override_pixels'] is True
    assert audit['owner_mask']['repeat_bytes_identical'] is True
    assert audit['owner_mask']['scratch_replay_png_sha256'][0] == audit['owner_mask']['scratch_replay_png_sha256'][1]
    assert all(v['detected'] for v in audit['one_pixel_negative_controls'].values())
    assert all(v['pixel_exact'] for v in audit['official_texture_replay']['parts'].values())
    frames = json.loads((PACKET / 'native/ankle-120/frames.json').read_text(encoding='utf8'))
    samples = [s for group in frames for s in group['samples']]
    raw = json.loads((PACKET / 'native/ankle-120/raw-frame-sha256.json').read_text(encoding='utf8'))
    assert len(frames) == 16 and len(samples) == 1920 and raw['raw_png_count'] == 1920
    assert {s['file'] for s in samples} == {Path(row['path']).name for row in raw['frames']}
    assert len({row['sha256'] for row in raw['frames']}) > 1
    report = json.loads((PACKET / 'native/ankle-120/report.json').read_text(encoding='utf8'))
    assert report['samples'] == 7680 and report['failed_samples'] == 0 and not report['failures']
    native_root = args.native_source
    default_raw = Path(raw['source_scratch'])
    if native_root is None and default_raw.is_dir():
        native_root = default_raw
    checked = 0
    if native_root is not None:
        for row in raw['frames']:
            path = native_root / Path(row['path']).name
            assert path.is_file(), f'missing raw native frame: {path}'
            assert sha(path) == row['sha256'], f'raw frame SHA mismatch: {path.name}'
            checked += 1
    selected = manifest['selected_native_frames']
    for row in selected.values():
        published = ROOT / row['published_file']
        source = next(x for x in raw['frames'] if Path(x['path']).name == Path(row['source_file']).name)
        assert sha(published) == source['sha256'] == row['sha256']
        with Image.open(published) as im:
            assert list(im.size) == row['size_px'] and im.mode == row['mode']
    gait = manifest['gait_capture']
    assert sha(ROOT / gait['published_file']) == gait['sha256']
    print(json.dumps({'status':'PASS','packet_files_verified':len(manifest['packet_files']),'source_negative_controls':2,'source_rebuilds':2,'native_samples':report['samples'],'native_failures':report['failed_samples'],'raw_frames_listed':len(raw['frames']),'raw_frames_hash_checked':checked,'representative_frames':len(selected)},indent=2))

if __name__ == '__main__':
    main()
