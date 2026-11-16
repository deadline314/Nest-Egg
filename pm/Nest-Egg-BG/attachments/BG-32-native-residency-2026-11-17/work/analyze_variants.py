from pathlib import Path
import json

root = Path('C:/NE/evidence-20261117/bg32')
summary = {}
for label in ['A1', 'B1', 'C1', 'A2', 'C2', 'D1', 'D2', 'D3', 'D4', 'A3', 'E1', 'A4', 'E2']:
    path = root / ('isolated-' + label) / 'report.json'
    if not path.is_file(): continue
    report = json.loads(path.read_text(encoding='utf-8'))
    records = report['records']
    enter = [r['enter_max_ms'] for r in records[1:]]
    stages = [s for r in records for s in r['stage_timings']]
    row = {'ratio': report['ratio'], 'first_payload': records[0]['payload_bytes'],
           'last_payload': records[-1]['payload_bytes'], 'failures': report['failures'],
           'actual_engine_errors': report['observer']['count'],
           'first_prefetch_cached': records[0]['prefetch']['cached'],
           'last_prefetch_cached': records[-1]['prefetch']['cached'],
           'first_neighbor_misses': len(records[0].get('neighbor_requests',{}).get('missing_from_prefetch',[])),
           'last_neighbor_misses': len(records[-1].get('neighbor_requests',{}).get('missing_from_prefetch',[])),
           'stages_built': sum(len(r['built_stages']) for r in records),
           'stage_resident_count': sum(len(r['stage_residents']) for r in records),
           'unexpected_backdrop_count': sum(len(r.get('unexpected_backdrop',[])) for r in records) if 'unexpected_backdrop' in records[0] else None,
           'enter_max_mean_except_startup_ms': sum(enter)/len(enter),
           'enter_max_except_startup_ms': max(enter),
           'stage_sync_max_ms': max(s['sync_build_ms'] for s in stages),
           'stage_enter_max_ms': max(max(s['enter_frames_ms']) for s in stages),
           'stage_exit_max_ms': max(max(s['exit_release_frames_ms']) for s in stages),
           'owners': [{'cancelled': r['cancelled'], 'finished': r['finished_signal'],
                       'max_frame_ms': max(r['frames_ms']),
                       'release_max_ms': max(r['exit_release_frames_ms']),
                       'after_stage_count': len(r['after']['stage_residents'])} for r in report.get('owner_runs',[])],
           'tool_sha': report['tool_sha256'], 'source_shas': report.get('source_shas')}
    summary[label] = row
    print(label, json.dumps(row, ensure_ascii=False))
Path(__file__).with_name('variant-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
